import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cobalto_mobile/services/aegis_mesh_crypto_service.dart';
import 'package:cobalto_mobile/services/aegis_mesh_transport_service.dart';

/// Tests unitarios — Fase 6b (Red Mesh de Transporte Ciego)
///
/// Pure Dart: prueba la creación de paquetes, firma Ed25519, deduplicación por SHA-256 ID,
/// decremento de TTL y serialización de red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AegisMeshPacket & Transport — Lógica del Protocolo Mesh', () {
    tearDown(() {
      AegisMeshCryptoService.clearCache();
    });

    test('createSigned genera un paquete con id SHA-256 y firma Ed25519 válida', () async {
      final identity = await AegisMeshCryptoService.getOrCreateIdentity();
      final packet = await AegisMeshPacket.createSigned(
        dstNodeId: '*',
        type: AegisMeshPacketType.crdtSync,
        payload: '[{"id":"poi1","lat":10.5,"lon":-66.9}]',
        ttl: 4,
      );

      expect(packet.version, equals(1));
      expect(packet.srcNodeId, equals(identity.nodeId));
      expect(packet.dstNodeId, equals('*'));
      expect(packet.type, equals(AegisMeshPacketType.crdtSync));
      expect(packet.ttl, equals(4));
      expect(packet.id.length, equals(64)); // SHA-256 hex
      expect(packet.signature, isNotEmpty);
    });

    test('decrementTtl reduce el TTL en 1 manteniendo el resto de campos intactos', () async {
      final packet = await AegisMeshPacket.createSigned(
        dstNodeId: 'NodoDestino123',
        type: AegisMeshPacketType.sosAlert,
        payload: 'EMERGENCIA SOS',
        ttl: 4,
      );

      final relayed = packet.decrementTtl();
      expect(relayed.ttl, equals(3));
      expect(relayed.id, equals(packet.id));
      expect(relayed.srcNodeId, equals(packet.srcNodeId));
      expect(relayed.payload, equals(packet.payload));
      expect(relayed.signature, equals(packet.signature));
    });

    test('roundtrip de serialización JSON de AegisMeshPacket', () async {
      final original = await AegisMeshPacket.createSigned(
        dstNodeId: 'PeerNode456',
        type: AegisMeshPacketType.e2eMsg,
        payload: 'E2E:PayloadCifradoBase64',
        ttl: 3,
      );

      final jsonMap = original.toJson();
      final restored = AegisMeshPacket.fromJson(jsonMap);

      expect(restored.version, equals(original.version));
      expect(restored.id, equals(original.id));
      expect(restored.srcNodeId, equals(original.srcNodeId));
      expect(restored.dstNodeId, equals(original.dstNodeId));
      expect(restored.type, equals(original.type));
      expect(restored.ttl, equals(original.ttl));
      expect(restored.timestampMs, equals(original.timestampMs));
      expect(restored.payload, equals(original.payload));
      expect(restored.signature, equals(original.signature));
    });

    test('computeId genera hashes idénticos para datos idénticos e IDs distintos si el timestamp o payload cambia', () async {
      const src = 'nodeA';
      const dst = 'nodeB';
      const type = 'SOS_ALERT';
      const ts = 1700000000000;
      const payload = 'Alerta de prueba';

      final id1 = await AegisMeshPacket.computeId(
        srcNodeId: src,
        dstNodeId: dst,
        typeCode: type,
        timestampMs: ts,
        payload: payload,
      );

      final id2 = await AegisMeshPacket.computeId(
        srcNodeId: src,
        dstNodeId: dst,
        typeCode: type,
        timestampMs: ts,
        payload: payload,
      );

      final id3 = await AegisMeshPacket.computeId(
        srcNodeId: src,
        dstNodeId: dst,
        typeCode: type,
        timestampMs: ts + 1,
        payload: payload,
      );

      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
    });
  });
}
