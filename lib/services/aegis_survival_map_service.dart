import 'dart:convert';

import 'app_logger.dart';
import 'gps_service.dart';
import 'local_db_service.dart';

/// Tipo de POI colaborativo de supervivencia.
enum SurvivalPoiType {
  hospital,
  agua,
  // ignore: constant_identifier_names — nombre persistido en SQLite/CRDT
  carretera_bloqueada,
  escombros,
  refugio,
  suministros,
  peligro,
  otro,
}

extension SurvivalPoiTypeX on SurvivalPoiType {
  String get label {
    switch (this) {
      case SurvivalPoiType.hospital:
        return 'Hospital / Atención Médica';
      case SurvivalPoiType.agua:
        return 'Agua Potable';
      case SurvivalPoiType.carretera_bloqueada:
        return 'Carretera Bloqueada';
      case SurvivalPoiType.escombros:
        return 'Escombros / Zona de Derrumbe';
      case SurvivalPoiType.refugio:
        return 'Refugio / Punto de Encuentro';
      case SurvivalPoiType.suministros:
        return 'Suministros / Comida';
      case SurvivalPoiType.peligro:
        return 'Zona de Peligro';
      case SurvivalPoiType.otro:
        return 'Otro';
    }
  }

  String get emoji {
    switch (this) {
      case SurvivalPoiType.hospital:
        return '🏥';
      case SurvivalPoiType.agua:
        return '💧';
      case SurvivalPoiType.carretera_bloqueada:
        return '🚧';
      case SurvivalPoiType.escombros:
        return '🪨';
      case SurvivalPoiType.refugio:
        return '🏠';
      case SurvivalPoiType.suministros:
        return '📦';
      case SurvivalPoiType.peligro:
        return '⚠️';
      case SurvivalPoiType.otro:
        return '📍';
    }
  }

  String get color {
    switch (this) {
      case SurvivalPoiType.hospital:
        return '#FF2D55';
      case SurvivalPoiType.agua:
        return '#00E5FF';
      case SurvivalPoiType.carretera_bloqueada:
        return '#FF9500';
      case SurvivalPoiType.escombros:
        return '#8E8E93';
      case SurvivalPoiType.refugio:
        return '#00FFAA';
      case SurvivalPoiType.suministros:
        return '#B388FF';
      case SurvivalPoiType.peligro:
        return '#FF3B30';
      case SurvivalPoiType.otro:
        return '#FFFFFF';
    }
  }

  String get dbName => name;

  static SurvivalPoiType fromDb(String s) {
    return SurvivalPoiType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => SurvivalPoiType.otro,
    );
  }
}

/// Marcador de supervivencia colaborativo (CRDT/LWW).
class SurvivalMarker {
  final String id;
  final SurvivalPoiType type;
  final double lat;
  final double lon;
  final String status; // 'activo' | 'inactivo' | 'desconocido'
  final String nodeId;
  final String hlc; // %013d-%03d-%s (HLC de ancho fijo, crítico para LWW)
  final bool tombstone;
  final String? notes;

  const SurvivalMarker({
    required this.id,
    required this.type,
    required this.lat,
    required this.lon,
    required this.status,
    required this.nodeId,
    required this.hlc,
    required this.tombstone,
    this.notes,
  });

  Map<String, dynamic> toDb() => {
        'id': id,
        'type': type.dbName,
        'lat': lat,
        'lon': lon,
        'status': status,
        'node_id': nodeId,
        'hlc': hlc,
        'tombstone': tombstone ? 1 : 0,
        'notes': notes ?? '',
      };

  factory SurvivalMarker.fromDb(Map<String, dynamic> row) => SurvivalMarker(
        id: row['id'] as String,
        type: SurvivalPoiTypeX.fromDb(row['type'] as String? ?? ''),
        lat: (row['lat'] as num).toDouble(),
        lon: (row['lon'] as num).toDouble(),
        status: row['status'] as String? ?? 'activo',
        nodeId: row['node_id'] as String? ?? '',
        hlc: row['hlc'] as String? ?? '',
        tombstone: (row['tombstone'] as int? ?? 0) == 1,
        notes: row['notes'] as String?,
      );

  Map<String, dynamic> toMapPoint() => {
        'lat': lat,
        'lon': lon,
        'title': '${type.emoji} ${type.label}',
        'type': 'SURVIVAL_POI',
        'desc': notes != null && notes!.isNotEmpty
            ? notes!
            : '${type.label} · $status',
        'color': type.color,
        'poi_id': id,
        'poi_type': type.dbName,
      };
}

/// Mapa colaborativo de supervivencia AEGIS (FASE 4).
///
/// Implementa CRDT "Último Escritor Gana" (LWW) sobre SQLite usando:
///   - HLC (Hybrid Logical Clock) con formato fijo `%013d-%03d-%s`
///     → CRÍTICO: el ancho fijo permite comparación lexicográfica correcta en SQLite.
///   - UPSERT `ON CONFLICT(id) DO UPDATE WHERE excluded.hlc > map_markers.hlc`
///     → Converge correctamente en split-brain sin DELETE.
///   - Tombstones inmortales: borrado lógico, nunca físico.
///   - Dedup de sincronización por marca de agua (watermark) por peer.
///
/// **No** depende de la red mesh (Fase 6): los marcadores se persisten localmente
/// y se expondrán al mesh en la Fase 6b.
class AegisSurvivalMapService {
  static const String _table = 'map_markers';
  // Watermarks por peer se manejan vía localWatermark()/getDeltaSince (sin prefs legacy).

  // ── HLC (Hybrid Logical Clock) ──

  /// Genera un HLC con formato fijo CRÍTICO para LWW correcto en SQLite.
  ///
  /// Formato: `%013d-%03d-%s`
  /// Ejemplo: `1692384759000-001-NodoA`
  ///
  /// El padding de 13 dígitos para ms y 3 para el contador asegura que la
  /// comparación lexicográfica SQLite sea equivalente a la comparación numérica.
  static String _generateHlc(String nodeId, {int? overrideMs}) {
    final int ms = overrideMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    // Sanidad: rechazar ms que exceda UTC+24h del reloj local (clock poison).
    final int maxMs = DateTime.now().toUtc().millisecondsSinceEpoch + 86400000;
    final int safeMs = ms > maxMs ? maxMs : ms;
    // Contador simple: en el primer POI del ms siempre es 001.
    // El mesh lo incrementará si hay colisión; aquí generamos el ancla.
    return '${safeMs.toString().padLeft(13, '0')}-001-$nodeId';
  }

  /// Parsea un HLC a sus componentes.
  static ({int ms, int counter, String node}) parseHlc(String hlc) {
    final parts = hlc.split('-');
    if (parts.length < 3) return (ms: 0, counter: 0, node: '');
    final ms = int.tryParse(parts[0]) ?? 0;
    final counter = int.tryParse(parts[1]) ?? 0;
    final node = parts.sublist(2).join('-');
    return (ms: ms, counter: counter, node: node);
  }

  /// Compara dos HLCs; retorna >0 si a > b, <0 si a < b, 0 si iguales.
  static int compareHlc(String a, String b) => a.compareTo(b);

  // ── GARANTÍA DE TABLA ──

  /// Asegura que la tabla `map_markers` exista. Se llama al arrancar.
  /// La tabla principal (CRDT) es independiente del R-Tree (opcional).
  static Future<void> ensureTable() async {
    try {
      final db = await LocalDbService.database;
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $_table (
          id      TEXT    PRIMARY KEY,
          type    TEXT    NOT NULL,
          lat     REAL    NOT NULL,
          lon     REAL    NOT NULL,
          status  TEXT    NOT NULL DEFAULT 'activo',
          node_id TEXT    NOT NULL DEFAULT '',
          hlc     TEXT    NOT NULL DEFAULT '',
          tombstone INTEGER NOT NULL DEFAULT 0,
          notes   TEXT    DEFAULT ''
        )
      ''');
      // Índice compuesto (lat, lon) como fallback de búsqueda espacial.
      // El R-Tree opcional (P10) se añade por encima; el núcleo CRDT no depende de él.
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_markers_latlon ON $_table (lat, lon)',
      );
      AppLogger.info('Tabla map_markers garantizada.', tag: 'SurvivalMap');
    } catch (e) {
      AppLogger.warn('No se pudo garantizar la tabla map_markers.', tag: 'SurvivalMap', error: e);
    }
  }

  // ── ESCRITURA (UPSERT-LWW) ──

  /// Inserta o actualiza un marcador usando la regla LWW:
  /// solo actualiza si el HLC entrante es MAYOR al almacenado.
  ///
  /// NUNCA usa INSERT OR REPLACE (ConflictAlgorithm.replace):
  /// ese patrón borra+reinserta y puede cambiar el rowid, rompiendo
  /// cualquier índice R-Tree asociado.
  static Future<bool> upsertMarker(SurvivalMarker marker) async {
    try {
      final db = await LocalDbService.database;
      // Validar sanidad del HLC antes de insertar.
      if (!_isHlcSane(marker.hlc)) {
        AppLogger.warn(
          'HLC rechazado por sanidad de reloj: ${marker.hlc}',
          tag: 'SurvivalMap',
        );
        return false;
      }
      final row = marker.toDb();
      await db.rawInsert('''
        INSERT INTO $_table (id, type, lat, lon, status, node_id, hlc, tombstone, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          type      = excluded.type,
          lat       = excluded.lat,
          lon       = excluded.lon,
          status    = excluded.status,
          node_id   = excluded.node_id,
          hlc       = excluded.hlc,
          tombstone = excluded.tombstone,
          notes     = excluded.notes
        WHERE excluded.hlc > $_table.hlc
      ''', [
        row['id'],
        row['type'],
        row['lat'],
        row['lon'],
        row['status'],
        row['node_id'],
        row['hlc'],
        row['tombstone'],
        row['notes'],
      ]);
      return true;
    } catch (e) {
      AppLogger.warn('UPSERT de marcador fallido: ${marker.id}', tag: 'SurvivalMap', error: e);
      return false;
    }
  }

  /// Marca un marcador como eliminado (tombstone lógico) con un HLC nuevo.
  /// DELETE está PROHIBIDO: el núcleo CRDT requiere lapidas inmortales.
  static Future<void> deleteMarker(String id, String nodeId) async {
    try {
      final db = await LocalDbService.database;
      final existing = await db.query(_table, where: 'id = ?', whereArgs: [id], limit: 1);
      if (existing.isEmpty) return;
      final current = SurvivalMarker.fromDb(existing.first);
      final newHlc = _generateHlc(nodeId);
      // Solo entomba si el nuevo HLC > el actual (LWW correcto).
      if (compareHlc(newHlc, current.hlc) > 0) {
        await db.rawInsert('''
          INSERT INTO $_table (id, type, lat, lon, status, node_id, hlc, tombstone, notes)
          VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
          ON CONFLICT(id) DO UPDATE SET
            tombstone = 1,
            hlc       = excluded.hlc,
            node_id   = excluded.node_id
          WHERE excluded.hlc > $_table.hlc
        ''', [
          current.id,
          current.type.dbName,
          current.lat,
          current.lon,
          current.status,
          nodeId,
          newHlc,
          current.notes ?? '',
        ]);
      }
    } catch (e) {
      AppLogger.warn('Tombstone de marcador fallido: $id', tag: 'SurvivalMap', error: e);
    }
  }

  // ── LECTURA ──

  /// Retorna todos los marcadores activos (tombstone=0), ordenados por HLC desc.
  static Future<List<SurvivalMarker>> getActiveMarkers() async {
    try {
      final db = await LocalDbService.database;
      final rows = await db.query(
        _table,
        where: 'tombstone = 0',
        orderBy: 'hlc DESC',
      );
      return rows.map(SurvivalMarker.fromDb).toList();
    } catch (e) {
      AppLogger.warn('No se pudo leer marcadores activos.', tag: 'SurvivalMap', error: e);
      return [];
    }
  }

  /// Retorna marcadores dentro de un bounding box (viewport del mapa).
  /// Filtro de círculo exacto con Haversine en capa Dart (el bbox es cuadrado).
  static Future<List<SurvivalMarker>> getMarkersInBbox({
    required double minLat,
    required double maxLat,
    required double minLon,
    required double maxLon,
    double? radiusKm, // Si se pasa, filtra círculo exacto además del bbox.
    double? centerLat,
    double? centerLon,
  }) async {
    try {
      final db = await LocalDbService.database;
      final rows = await db.query(
        _table,
        where:
            'tombstone = 0 AND lat >= ? AND lat <= ? AND lon >= ? AND lon <= ?',
        whereArgs: [minLat, maxLat, minLon, maxLon],
        orderBy: 'hlc DESC',
      );
      final markers = rows.map(SurvivalMarker.fromDb).toList();
      // Refinamiento radial: si se pide radio exacto, filtrar con Haversine.
      if (radiusKm != null && centerLat != null && centerLon != null) {
        return markers.where((m) {
          final d = GpsService.calculateDistanceInKm(
            centerLat, centerLon, m.lat, m.lon,
          );
          return d <= radiusKm;
        }).toList();
      }
      return markers;
    } catch (e) {
      AppLogger.warn('No se pudo leer marcadores en bbox.', tag: 'SurvivalMap', error: e);
      return [];
    }
  }

  // ── CREACIÓN ASISTIDA ──

  /// Crea un marcador nuevo en la posición indicada con el nodeId del operador.
  static Future<SurvivalMarker?> createMarker({
    required double lat,
    required double lon,
    required SurvivalPoiType type,
    String status = 'activo',
    String? notes,
    required String nodeId,
  }) async {
    final id = '${type.dbName}_${lat.toStringAsFixed(6)}_${lon.toStringAsFixed(6)}_${DateTime.now().millisecondsSinceEpoch}';
    final hlc = _generateHlc(nodeId);
    final marker = SurvivalMarker(
      id: id,
      type: type,
      lat: lat,
      lon: lon,
      status: status,
      nodeId: nodeId,
      hlc: hlc,
      tombstone: false,
      notes: notes,
    );
    final ok = await upsertMarker(marker);
    if (!ok) return null;
    await LocalDbService.logEmergencyEvent('SURVIVAL_POI_CREADO', data: {
      'id': id,
      'type': type.dbName,
      'lat': lat,
      'lon': lon,
    });
    return marker;
  }

  // ── SINCRONIZACIÓN (DELTA / MARCA DE AGUA) ──

  /// Retorna los marcadores (vivos + lapidas) cuyo HLC es mayor al watermark
  /// del peer indicado. Se usa para construir el delta de sincronización mesh.
  ///
  /// CRÍTICO: la comparación es sobre el HLC COMPLETO (ms+counter+node),
  /// nunca solo el timestamp ms.
  static Future<List<SurvivalMarker>> getDeltaSince(String watermark) async {
    try {
      final db = await LocalDbService.database;
      final rows = await db.query(
        _table,
        where: 'hlc > ?',
        whereArgs: [watermark],
        orderBy: 'hlc ASC',
      );
      return rows.map(SurvivalMarker.fromDb).toList();
    } catch (e) {
      AppLogger.warn('No se pudo obtener delta de marcadores.', tag: 'SurvivalMap', error: e);
      return [];
    }
  }

  /// Retorna el HLC máximo actualmente en la tabla (marca de agua local).
  static Future<String> localWatermark() async {
    try {
      final db = await LocalDbService.database;
      final rows = await db.rawQuery('SELECT MAX(hlc) as max_hlc FROM $_table');
      return rows.first['max_hlc'] as String? ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Aplica un lote de marcadores recibidos de un peer (merge LWW batch).
  static Future<int> applyDelta(List<Map<String, dynamic>> rawMarkers) async {
    int applied = 0;
    try {
      final db = await LocalDbService.database;
      await db.transaction((txn) async {
        for (final raw in rawMarkers) {
          try {
            final marker = SurvivalMarker.fromDb(raw);
            if (!_isHlcSane(marker.hlc)) continue;
            await txn.rawInsert('''
              INSERT INTO $_table (id, type, lat, lon, status, node_id, hlc, tombstone, notes)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET
                type      = excluded.type,
                lat       = excluded.lat,
                lon       = excluded.lon,
                status    = excluded.status,
                node_id   = excluded.node_id,
                hlc       = excluded.hlc,
                tombstone = excluded.tombstone,
                notes     = excluded.notes
              WHERE excluded.hlc > $_table.hlc
            ''', [
              raw['id'],
              raw['type'],
              raw['lat'],
              raw['lon'],
              raw['status'] ?? 'activo',
              raw['node_id'] ?? '',
              raw['hlc'],
              (raw['tombstone'] ?? 0),
              raw['notes'] ?? '',
            ]);
            applied++;
          } catch (e) {
            // Marcador inválido: se ignora, no aborta el lote.
          }
        }
      });
    } catch (e) {
      AppLogger.warn('Delta apply fallido.', tag: 'SurvivalMap', error: e);
    }
    AppLogger.info('Delta CRDT aplicado: $applied marcadores.', tag: 'SurvivalMap');
    return applied;
  }

  // ── WATERMARKS POR PEER ──

  /// Recupera el HLC watermark registrado para un peer (para delta sync).
  static Future<String> getPeerWatermark(String peerId) async {
    try {
      final raw = await _loadWatermarks();
      return raw[peerId] ?? '';
    } catch (e) {
      return '';
    }
  }

  /// Actualiza el watermark de un peer tras una sincronización exitosa.
  static Future<void> savePeerWatermark(String peerId, String hlc) async {
    try {
      final raw = await _loadWatermarks();
      raw[peerId] = hlc;
      await _saveWatermarks(raw);
    } catch (e) {
      AppLogger.warn('No se pudo guardar watermark de peer.', tag: 'SurvivalMap', error: e);
    }
  }

  static Future<Map<String, String>> _loadWatermarks() async {
    // Persistido en SharedPreferences: no requiere cifrado (son HLCs públicos).
    try {
      final db = await LocalDbService.database;
      // Usar una tabla simple de clave-valor en SQLite para evitar deps adicionales.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS aegis_peer_watermarks (
          peer_id TEXT PRIMARY KEY,
          watermark TEXT NOT NULL DEFAULT ''
        )
      ''');
      final rows = await db.query('aegis_peer_watermarks');
      return {for (final r in rows) r['peer_id'] as String: r['watermark'] as String};
    } catch (e) {
      return {};
    }
  }

  static Future<void> _saveWatermarks(Map<String, String> wm) async {
    try {
      final db = await LocalDbService.database;
      final batch = db.batch();
      for (final entry in wm.entries) {
        batch.rawInsert('''
          INSERT INTO aegis_peer_watermarks (peer_id, watermark)
          VALUES (?, ?)
          ON CONFLICT(peer_id) DO UPDATE SET watermark = excluded.watermark
        ''', [entry.key, entry.value]);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      AppLogger.warn('No se pudo persistir watermarks de peer.', tag: 'SurvivalMap', error: e);
    }
  }

  // ── SANIDAD DE RELOJ (ANTI-CLOCK-POISON) ──

  /// Rechaza HLCs cuyo timestamp excede UTC + 24 h del reloj local.
  static bool _isHlcSane(String hlc) {
    if (hlc.isEmpty) return false;
    final parsed = parseHlc(hlc);
    if (parsed.ms <= 0) return false;
    final maxMs = DateTime.now().toUtc().millisecondsSinceEpoch + 86400000;
    final ok = parsed.ms <= maxMs;
    if (!ok) {
      AppLogger.warn(
        'Clock poison detectado: HLC ms=${parsed.ms} > local+24h=$maxMs',
        tag: 'SurvivalMap',
      );
    }
    return ok;
  }

  // ── PUNTOS PARA EL MAPA LEAFLET ──

  /// Retorna los marcadores activos formateados como puntos para `MapPointsService`.
  static Future<List<Map<String, dynamic>>> buildSurvivalMapPoints() async {
    final markers = await getActiveMarkers();
    return markers.map((m) => m.toMapPoint()).toList();
  }

  // ── ESTADÍSTICAS ──

  /// Contadores por tipo de POI para el panel de capas.
  static Future<Map<String, int>> getStats() async {
    try {
      final db = await LocalDbService.database;
      final rows = await db.rawQuery('''
        SELECT type, COUNT(*) as cnt
        FROM $_table
        WHERE tombstone = 0
        GROUP BY type
      ''');
      final Map<String, int> stats = {};
      int total = 0;
      for (final row in rows) {
        final t = row['type'] as String;
        final c = (row['cnt'] as int? ?? 0);
        stats[t] = c;
        total += c;
      }
      stats['TOTAL'] = total;
      return stats;
    } catch (e) {
      return {'TOTAL': 0};
    }
  }

  /// Serializa los marcadores a JSON para exportación / debug.
  static Future<String> exportJson() async {
    final markers = await getActiveMarkers();
    return json.encode(markers.map((m) => m.toDb()).toList());
  }
}
