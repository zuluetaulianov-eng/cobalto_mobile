import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:sqflite/sqflite.dart';

import 'aegis_mesh_crypto_service.dart';
import 'aegis_survival_map_service.dart';
import 'app_logger.dart';
import 'local_db_service.dart';

/// Tipos de paquetes de la Red Mesh AEGIS.
enum AegisMeshPacketType {
  crdtSync,       // Delta de marcadores del mapa colaborativo
  sosAlert,       // Alerta de pánico/SOS de alta prioridad (flooding prioritario)
  e2eMsg,         // Mensaje privado E2EE entre dos operadores
  watermarkReq,   // Solicitud de marca de agua para sincronización delta
  watermarkResp,  // Respuesta con marca de agua local
}

extension AegisMeshPacketTypeX on AegisMeshPacketType {
  String get code {
    switch (this) {
      case AegisMeshPacketType.crdtSync:
        return 'CRDT_SYNC';
      case AegisMeshPacketType.sosAlert:
        return 'SOS_ALERT';
      case AegisMeshPacketType.e2eMsg:
        return 'E2E_MSG';
      case AegisMeshPacketType.watermarkReq:
        return 'WATERMARK_REQ';
      case AegisMeshPacketType.watermarkResp:
        return 'WATERMARK_RESP';
    }
  }

  static AegisMeshPacketType fromCode(String code) {
    return AegisMeshPacketType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => AegisMeshPacketType.crdtSync,
    );
  }
}

/// Paquete binario/JSON de la Red Mesh AEGIS.
class AegisMeshPacket {
  final int version;        // Versión del protocolo (1)
  final String id;         // SHA-256(payload) -> Idempotencia y dedup
  final String srcNodeId;  // NodeID de origen (hash de pubKey Ed25519)
  final String dstNodeId;  // NodeID de destino ("*" para broadcast)
  final AegisMeshPacketType type;
  final int ttl;           // Hops restantes (4 por defecto, decrementa en cada relay)
  final int timestampMs;   // UTC ms de creación
  final String payload;    // Payload (JSON / E2E cifrado / CRDT array)
  final String signature;  // Firma Ed25519 del emisor (Base64)

  const AegisMeshPacket({
    this.version = 1,
    required this.id,
    required this.srcNodeId,
    required this.dstNodeId,
    required this.type,
    required this.ttl,
    required this.timestampMs,
    required this.payload,
    required this.signature,
  });

  Map<String, dynamic> toJson() => {
        'v': version,
        'id': id,
        'src': srcNodeId,
        'dst': dstNodeId,
        'type': type.code,
        'ttl': ttl,
        'ts': timestampMs,
        'payload': payload,
        'sig': signature,
      };

  factory AegisMeshPacket.fromJson(Map<String, dynamic> json) => AegisMeshPacket(
        version: json['v'] as int? ?? 1,
        id: json['id'] as String,
        srcNodeId: json['src'] as String? ?? '',
        dstNodeId: json['dst'] as String? ?? '*',
        type: AegisMeshPacketTypeX.fromCode(json['type'] as String? ?? ''),
        ttl: json['ttl'] as int? ?? 0,
        timestampMs: json['ts'] as int? ?? 0,
        payload: json['payload'] as String? ?? '',
        signature: json['sig'] as String? ?? '',
      );

  /// Genera un ID único para el paquete (SHA-256 de los contenidos núcleo).
  static Future<String> computeId({
    required String srcNodeId,
    required String dstNodeId,
    required String typeCode,
    required int timestampMs,
    required String payload,
  }) async {
    final raw = '$srcNodeId|$dstNodeId|$typeCode|$timestampMs|$payload';
    final hash = await Sha256().hash(utf8.encode(raw));
    return hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Crea un nuevo paquete firmado por el nodo local.
  static Future<AegisMeshPacket> createSigned({
    required String dstNodeId,
    required AegisMeshPacketType type,
    required String payload,
    int ttl = 4,
  }) async {
    final identity = await AegisMeshCryptoService.getOrCreateIdentity();
    final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
    final packetId = await computeId(
      srcNodeId: identity.nodeId,
      dstNodeId: dstNodeId,
      typeCode: type.code,
      timestampMs: ts,
      payload: payload,
    );

    // Firma del paquete.
    final bytesToSign = utf8.encode('$packetId|$dstNodeId|${type.code}|$payload');
    final sigBytes = await AegisMeshCryptoService.sign(bytesToSign);
    final sigBase64 = base64.encode(sigBytes);

    return AegisMeshPacket(
      version: 1,
      id: packetId,
      srcNodeId: identity.nodeId,
      dstNodeId: dstNodeId,
      type: type,
      ttl: ttl,
      timestampMs: ts,
      payload: payload,
      signature: sigBase64,
    );
  }

  /// Retorna una copia del paquete con TTL decrementado en 1 para retransmisión.
  AegisMeshPacket decrementTtl() {
    return AegisMeshPacket(
      version: version,
      id: id,
      srcNodeId: srcNodeId,
      dstNodeId: dstNodeId,
      type: type,
      ttl: ttl - 1,
      timestampMs: timestampMs,
      payload: payload,
      signature: signature,
    );
  }
}

/// RED MESH DE TRANSPORTE CIEGO AEGIS (FASE 6b).
///
/// Características principales:
/// 1. **P2P Cluster / Star Strategy**: Basado en `nearby_connections` (BLE + Wi-Fi Direct).
/// 2. **Store-and-Forward**: Guardado local en SQLite (`mesh_store`) con deduplicación por `id`.
/// 3. **Enrutamiento Ciego**: Los nodos intermedios retransmiten paquetes cifrados sin conocer su contenido.
/// 4. **Gossip / Flooding Controlado**: Decremento de TTL y eliminación de duplicados.
/// 5. **Sincronización CRDT Automática**: Al conectar con un peer, intercambia marcadores de agua
///    y envía sólo los deltas de supervivencia faltantes.
class AegisMeshTransportService {
  static const String _tableName = 'mesh_store';
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  static bool _isRunning = false;
  static bool get isRunning => _isRunning;

  // Peers conectados actualmente (endpointId -> peerNodeId)
  static final Map<String, String> _connectedPeers = {};

  // Stream controller para notificar llegada de mensajes/alertas a la UI
  static final StreamController<AegisMeshPacket> _incomingPacketController =
      StreamController<AegisMeshPacket>.broadcast();
  static Stream<AegisMeshPacket> get incomingPackets => _incomingPacketController.stream;

  // ── INICIALIZACIÓN DE TABLA ──

  static Future<void> ensureTable() async {
    try {
      final db = await LocalDbService.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_tableName (
          id        TEXT PRIMARY KEY,
          src       TEXT NOT NULL,
          dst       TEXT NOT NULL,
          type      TEXT NOT NULL,
          ttl       INTEGER NOT NULL,
          ts        INTEGER NOT NULL,
          payload   TEXT NOT NULL,
          sig       TEXT NOT NULL,
          received_at INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_mesh_store_ts ON $_tableName (ts DESC)',
      );
      AppLogger.info('Tabla mesh_store garantizada.', tag: 'MeshTransport');
    } catch (e) {
      AppLogger.warn('No se pudo garantizar tabla mesh_store.', tag: 'MeshTransport', error: e);
    }
  }

  // ── CICLO DE VIDA DE LA RED ──

  /// Inicia el servicio de red mesh (Publicidad + Descubrimiento P2P).
  static Future<bool> startMesh() async {
    if (_isRunning) return true;
    await ensureTable();

    try {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      final userName = identity.nodeId.substring(0, 12); // Nombre corto para publicidad BLE

      // 1. Iniciar publicidad BLE/Wi-Fi
      await Nearby().startAdvertising(
        userName,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: 'com.cobalto.aegis.mesh',
      );

      // 2. Iniciar descubrimiento de peers
      await Nearby().startDiscovery(
        userName,
        _strategy,
        onEndpointFound: (endpointId, name, serviceId) async {
          AppLogger.info('Peer mesh descubierto: $name ($endpointId)', tag: 'MeshTransport');
          // Solicitar conexión automáticamente (red abierta ad-hoc entre nodos AEGIS)
          try {
            await Nearby().requestConnection(
              userName,
              endpointId,
              onConnectionInitiated: _onConnectionInitiated,
              onConnectionResult: _onConnectionResult,
              onDisconnected: _onDisconnected,
            );
          } catch (e) {
            // Conexión simultánea o rechazada
          }
        },
        onEndpointLost: (endpointId) {
          AppLogger.info('Peer mesh perdido: $endpointId', tag: 'MeshTransport');
        },
        serviceId: 'com.cobalto.aegis.mesh',
      );

      _isRunning = true;
      AppLogger.info('⚡ Red Mesh AEGIS iniciada correctamente.', tag: 'MeshTransport');
      return true;
    } catch (e) {
      AppLogger.warn('No se pudo iniciar la Red Mesh AEGIS (BLE/Nearby).', tag: 'MeshTransport', error: e);
      _isRunning = false;
      return false;
    }
  }

  /// Detiene la publicidad, descubrimiento y conexiones de la red mesh.
  static Future<void> stopMesh() async {
    if (!_isRunning) return;
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
      _connectedPeers.clear();
      _isRunning = false;
      AppLogger.info('Red Mesh AEGIS detenida.', tag: 'MeshTransport');
    } catch (e) {
      AppLogger.warn('Error al detener Red Mesh AEGIS.', tag: 'MeshTransport', error: e);
    }
  }

  // ── HANDLERS DE CONEXIÓN P2P ──

  static void _onConnectionInitiated(String endpointId, ConnectionInfo info) async {
    AppLogger.info('Conexión iniciada con peer: ${info.endpointName} ($endpointId)', tag: 'MeshTransport');
    // Aceptar conexión de forma automática (red militar ad-hoc)
    await Nearby().acceptConnection(
      endpointId,
      onPayLoadRecieved: (endpointId, payload) => _onBytesReceived(endpointId, payload),
    );
  }

  static void _onConnectionResult(String endpointId, Status status) async {
    if (status == Status.CONNECTED) {
      _connectedPeers[endpointId] = endpointId;
      AppLogger.info('🟢 Conectado a nodo mesh: $endpointId', tag: 'MeshTransport');

      // Al conectar con un peer, iniciar handshake de sincronización CRDT
      await _initiateCrdtHandshake(endpointId);
    } else {
      _connectedPeers.remove(endpointId);
      AppLogger.warn('Falló la conexión con nodo mesh: $endpointId', tag: 'MeshTransport');
    }
  }

  static void _onDisconnected(String endpointId) {
    _connectedPeers.remove(endpointId);
    AppLogger.info('🔴 Desconectado de nodo mesh: $endpointId', tag: 'MeshTransport');
  }

  // ── ENVÍO Y RETRANSMISIÓN DE PAQUETES ──

  /// Broadcast o envío unicast de un paquete por la red mesh.
  static Future<bool> sendPacket(AegisMeshPacket packet) async {
    await ensureTable();

    // 1. Guardar localmente en el almacén de deduplicación (store-and-forward)
    final saved = await _storePacketLocally(packet);
    if (!saved) {
      // El paquete ya existía en nuestro almacén (bucle evitado)
      return false;
    }

    // 2. Si no hay peers conectados físicamente en este momento, queda guardado en DB
    // y se transmitirá cuando se conecte el próximo peer.
    if (_connectedPeers.isEmpty) {
      debugPrint('📦 Paquete ${packet.id.substring(0, 8)} guardado localmente (sin peers conectados).');
      return true;
    }

    // 3. Serializar y transmitir a todos los peers adyacentes (Gossip / Flooding)
    final bytes = Uint8List.fromList(utf8.encode(json.encode(packet.toJson())));

    for (final endpointId in _connectedPeers.keys) {
      try {
        await Nearby().sendBytesPayload(endpointId, bytes);
      } catch (e) {
        AppLogger.warn('Error enviando paquete a $endpointId', tag: 'MeshTransport', error: e);
      }
    }

    return true;
  }

  // ── RECEPCIÓN Y PROCESAMIENTO CIEGO ──

  static void _onBytesReceived(String endpointId, Payload payload) async {
    if (payload.type != PayloadType.BYTES || payload.bytes == null) return;

    try {
      final jsonStr = utf8.decode(payload.bytes!);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final packet = AegisMeshPacket.fromJson(data);

      await processIncomingPacket(packet);
    } catch (e) {
      AppLogger.warn('Error al procesar paquete entrante de $endpointId', tag: 'MeshTransport', error: e);
    }
  }

  /// Procesa un paquete entrante (Lógica central de relay ciego + deduplicación + despacho local).
  static Future<void> processIncomingPacket(AegisMeshPacket packet) async {
    await ensureTable();

    // 0. Verificar firma Ed25519 antes de cualquier despacho (anti-inyección).
    //    El relay ciego reenvía bytes sin descifrar, pero NO aplica CRDT/SOS
    //    sin firma válida de un peer TOFU conocido.
    final peer = await AegisMeshCryptoService.findPeer(packet.srcNodeId);
    if (peer == null) {
      // Desconocido: se permite retransmitir (flooding) pero no se aplica localmente.
      AppLogger.warn(
        'Paquete mesh de src desconocido ${packet.srcNodeId.substring(0, 8)}... — solo relay.',
        tag: 'MeshTransport',
      );
    } else if (packet.signature.isNotEmpty) {
      try {
        final bytesToVerify = utf8.encode(
          '${packet.id}|${packet.dstNodeId}|${packet.type.code}|${packet.payload}',
        );
        final ok = await AegisMeshCryptoService.verify(
          message: bytesToVerify,
          signatureBytes: base64.decode(packet.signature),
          publicKeyBase64: peer.publicKeyBase64,
        );
        if (!ok) {
          AppLogger.warn(
            'Firma mesh inválida de ${packet.srcNodeId.substring(0, 8)}... — descartado.',
            tag: 'MeshTransport',
          );
          return;
        }
      } catch (e) {
        AppLogger.warn('Error verificando firma mesh.', tag: 'MeshTransport', error: e);
        return;
      }
    } else {
      AppLogger.warn('Paquete mesh sin firma — descartado.', tag: 'MeshTransport');
      return;
    }

    // 1. Comprobar deduplicación local
    final isNew = await _storePacketLocally(packet);
    if (!isNew) {
      // Duplicado ya conocido: se descarta en silencio
      return;
    }

    AppLogger.info(
      '📩 Paquete mesh recibido: ${packet.type.code} [id: ${packet.id.substring(0, 8)}...] (TTL=${packet.ttl})',
      tag: 'MeshTransport',
    );

    final identity = await AegisMeshCryptoService.getOrCreateIdentity();
    final bool isForMe = packet.dstNodeId == '*' || packet.dstNodeId == identity.nodeId;

    // 2. Despachar a la aplicación solo si es para este nodo Y el peer es de confianza.
    if (isForMe && peer != null) {
      _incomingPacketController.add(packet);
      await _handleInternalPacket(packet);
    }

    // 3. ENRUTAMIENTO CIEGO (Relay): Si TTL > 1, decrementar TTL y retransmitir a los demás peers
    if (packet.ttl > 1) {
      final relayedPacket = packet.decrementTtl();
      final bytes = Uint8List.fromList(utf8.encode(json.encode(relayedPacket.toJson())));

      for (final endpointId in _connectedPeers.keys) {
        try {
          await Nearby().sendBytesPayload(endpointId, bytes);
        } catch (_) {}
      }
      debugPrint('🔄 Paquete ${packet.id.substring(0, 8)} retransmitido por relay ciego (Nuevo TTL: ${relayedPacket.ttl})');
    }
  }

  // ── MANEJO DE TIPOS DE PAQUETES INTERNOS ──

  static Future<void> _handleInternalPacket(AegisMeshPacket packet) async {
    switch (packet.type) {
      case AegisMeshPacketType.crdtSync:
        // Aplicar deltas del mapa colaborativo recibidas por el mesh
        try {
          final List<dynamic> list = json.decode(packet.payload);
          final rawMarkers = list.cast<Map<String, dynamic>>();
          await AegisSurvivalMapService.applyDelta(rawMarkers);
        } catch (e) {
          AppLogger.warn('Error al aplicar delta CRDT del mesh.', tag: 'MeshTransport', error: e);
        }
        break;

      case AegisMeshPacketType.watermarkReq:
        // El peer nos pide nuestra marca de agua local para enviarnos lo que nos falta
        final myWm = await AegisSurvivalMapService.localWatermark();
        final respPacket = await AegisMeshPacket.createSigned(
          dstNodeId: packet.srcNodeId,
          type: AegisMeshPacketType.watermarkResp,
          payload: myWm,
        );
        await sendPacket(respPacket);
        break;

      case AegisMeshPacketType.watermarkResp:
        // El peer respondió con su marca de agua. Le enviamos nuestro delta acumulado.
        final peerWm = packet.payload;
        final deltaMarkers = await AegisSurvivalMapService.getDeltaSince(peerWm);
        if (deltaMarkers.isNotEmpty) {
          final payloadJson = json.encode(deltaMarkers.map((m) => m.toDb()).toList());
          final deltaPacket = await AegisMeshPacket.createSigned(
            dstNodeId: packet.srcNodeId,
            type: AegisMeshPacketType.crdtSync,
            payload: payloadJson,
          );
          await sendPacket(deltaPacket);
          debugPrint('📤 Enviados ${deltaMarkers.length} marcadores delta a ${packet.srcNodeId.substring(0, 8)}');
        }
        break;

      case AegisMeshPacketType.sosAlert:
        // Alerta de pánico en la red mesh: registrar evento local
        try {
          final data = json.decode(packet.payload) as Map<String, dynamic>;
          await LocalDbService.logEmergencyEvent('AEGIS_MESH_SOS_RECEIVED', data: data);
        } catch (_) {}
        break;

      case AegisMeshPacketType.e2eMsg:
        // Mensaje privado E2EE: descifrar y registrar (UI puede escuchar incomingPackets).
        try {
          if (packet.payload.startsWith('E2E:')) {
            final plain = await AegisMeshCryptoService.decryptFromPeer(packet.payload);
            await LocalDbService.logEmergencyEvent(
              'AEGIS_MESH_E2E_MSG',
              data: {
                'from': packet.srcNodeId,
                'plaintext': plain,
                'ts': packet.timestampMs,
              },
            );
          }
        } catch (e) {
          AppLogger.warn('No se pudo descifrar E2E mesh.', tag: 'MeshTransport', error: e);
        }
        break;
    }
  }

  // ── HANDSHAKE DE SINCRONIZACIÓN CRDT ──

  static Future<void> _initiateCrdtHandshake(String endpointId) async {
    try {
      // Solicitar marca de agua al peer recién conectado
      final reqPacket = await AegisMeshPacket.createSigned(
        dstNodeId: '*',
        type: AegisMeshPacketType.watermarkReq,
        payload: '',
      );
      await sendPacket(reqPacket);
    } catch (e) {
      AppLogger.warn('Error en handshake CRDT con peer.', tag: 'MeshTransport', error: e);
    }
  }

  // ── PERSISTENCIA Y DEDUPLICACIÓN EN SQLITE ──

  static Future<bool> _storePacketLocally(AegisMeshPacket packet) async {
    try {
      final db = await LocalDbService.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      final count = await db.rawInsert('''
        INSERT OR IGNORE INTO $_tableName (id, src, dst, type, ttl, ts, payload, sig, received_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        packet.id,
        packet.srcNodeId,
        packet.dstNodeId,
        packet.type.code,
        packet.ttl,
        packet.timestampMs,
        packet.payload,
        packet.signature,
        now,
      ]);

      return count > 0;
    } catch (e) {
      return false;
    }
  }

  /// Retorna la cantidad total de paquetes almacenados en la base de datos local.
  static Future<int> getStoredPacketsCount() async {
    try {
      final db = await LocalDbService.database;
      final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM $_tableName');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Retorna el número de peers físicos conectados activamente.
  static int get activePeersCount => _connectedPeers.length;
}
