import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'app_logger.dart';
import 'cobalto_api_service.dart';
import 'local_db_service.dart';

/// Sincronización de evidencia fotográfica con telemetría al nodo central.
/// Sube la fotografía + sidecar forense vía multipart. Si no hay enlace,
/// la cola queda persistida en el dispositivo y se reintenta en el próximo
/// arranque o de forma manual.
class TelemetrySyncService {
  static final http.Client _client = http.Client();

  static const String _pendingQueueKey = 'pending_photo_uploads';
  static const String _pendingSosKey = 'pending_sos_signals';

  static Map<String, String> get _authHeaders => {
        'Accept': 'application/json',
        if (ApiConfig.authToken != null)
          'Authorization': 'Bearer ${ApiConfig.authToken}',
      };

  /// Envía un reporte de campo con imagen y sidecar forense al servidor central.
  static Future<bool> uploadPhotoReport({
    required Map<String, dynamic> report,
    required String imagePath,
    required String sidecarPath,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/api/humint/report'),
      )..headers.addAll(_authHeaders)
        ..fields['report'] = json.encode(report);

      final imageFile = File(imagePath);
      if (imageFile.existsSync()) {
        request.files.add(await http.MultipartFile.fromPath('photo_file', imagePath));
      }
      final sidecarFile = File(sidecarPath);
      if (sidecarFile.existsSync()) {
        request.files.add(await http.MultipartFile.fromPath('sidecar_file', sidecarPath));
      }

      final response =
          await _client.send(request).timeout(const Duration(seconds: 25));
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      AppLogger.warn('Fallo la subida de telemetría fotográfica.', tag: 'Telemetry', error: e);
      return false;
    }
  }

  /// Intenta subir la evidencia justo después de la captura. Si no hay enlace,
  /// la encola localmente para reintento posterior.
  static Future<void> enqueueAndUpload({
    required Map<String, dynamic> report,
    required String imagePath,
    required String sidecarPath,
  }) async {
    final ok = await uploadPhotoReport(
      report: report,
      imagePath: imagePath,
      sidecarPath: sidecarPath,
    );

    if (ok) {
      _markSynced(report['id']?.toString());
    } else {
      await _enqueue(imagePath, sidecarPath, report);
    }
  }

  /// Reintenta las subidas pendientes persistidas (se invoca al arrancar).
  static Future<void> retryPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingQueueKey);
    if (raw == null || raw.isEmpty) return;

    final List<dynamic> queue;
    try {
      queue = json.decode(raw);
    } catch (e) {
      AppLogger.warn('Cola de subida pendiente corrupta.', tag: 'Telemetry', error: e);
      await prefs.remove(_pendingQueueKey);
      return;
    }
    if (queue.isEmpty) return;

    final List<dynamic> remaining = [];

    for (final item in queue) {
      if (item is! Map) continue;
      final String imagePath = item['imagePath']?.toString() ?? '';
      final String sidecarPath = item['sidecarPath']?.toString() ?? '';
      final report = _coerceReport(item['report']);

      if (imagePath.isEmpty || !File(imagePath).existsSync()) continue;

      final ok = await uploadPhotoReport(
        report: report,
        imagePath: imagePath,
        sidecarPath: sidecarPath,
      );
      if (ok) {
        _markSynced(report['id']?.toString());
      } else {
        remaining.add(item);
      }
    }

    await prefs.setString(_pendingQueueKey, json.encode(remaining));
  }

  static Map<String, dynamic> _coerceReport(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  static Future<void> _enqueue(
    String imagePath,
    String sidecarPath,
    Map<String, dynamic> report,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingQueueKey);
      List<dynamic> queue = [];
      if (raw != null && raw.isNotEmpty) {
        try {
          queue = json.decode(raw);
        } catch (e) {
          // Reiniciar cola si está corrupta
        }
      }
      queue.add({
        'imagePath': imagePath,
        'sidecarPath': sidecarPath,
        'report': report,
      });
      await prefs.setString(_pendingQueueKey, json.encode(queue));
    } catch (e) {
      AppLogger.warn('No se pudo encolar subida de telemetría.', tag: 'Telemetry', error: e);
    }
  }

  /// Marca el FieldReport como sincronizado en la base local.
  static Future<void> _markSynced(String? id) async {
    if (id == null || id.isEmpty) return;
    try {
      final reports = await LocalDbService.getFieldReports();
      final target = reports.where((r) => r['id']?.toString() == id).toList();
      if (target.isNotEmpty) {
        final synced = Map<String, dynamic>.from(target.first)..['synced'] = true;
        // saveFieldReport usará ConflictAlgorithm.replace por id.
        await LocalDbService.saveFieldReport(synced);
      }
    } catch (e) {
      AppLogger.warn('No se pudo marcar el reporte como sincronizado.', tag: 'Telemetry', error: e);
    }
  }

  // ── COLA DE SEÑALES SOS (Dead Man's Switch) ──

  /// Intenta transmitir la señal SOS a la base. Si no hay enlace, la encola
  /// localmente para reintento en el próximo arranque.
  /// Devuelve `true` si el servidor confirmó (ACK) y `false` si quedó en cola.
  static Future<bool> enqueueAndSendSos(Map<String, dynamic> sosData) async {
    final res = await CobaltoApiService.sendSosSignal(sosData);
    if (res['success'] == true) {
      AppLogger.info('Señal SOS transmitida a la base.', tag: 'SOS');
      return true;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingSosKey);
      List<dynamic> queue = [];
      if (raw != null && raw.isNotEmpty) {
        try {
          queue = json.decode(raw);
        } catch (e) {
          // Reiniciar cola si está corrupta
        }
      }
      queue.add(sosData);
      await prefs.setString(_pendingSosKey, json.encode(queue));
      AppLogger.warn('SOS sin enlace: señal encolada para reintento.', tag: 'SOS');
    } catch (e) {
      AppLogger.warn('No se pudo encolar la señal SOS.', tag: 'SOS', error: e);
    }
    return false;
  }

  /// Reintenta las señales SOS pendientes persistidas (se invoca al arrancar).
  static Future<void> retryPendingSos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingSosKey);
    if (raw == null || raw.isEmpty) return;

    final List<dynamic> queue;
    try {
      queue = json.decode(raw);
    } catch (e) {
      AppLogger.warn('Cola SOS pendiente corrupta.', tag: 'SOS', error: e);
      await prefs.remove(_pendingSosKey);
      return;
    }
    if (queue.isEmpty) return;

    final List<dynamic> remaining = [];
    for (final item in queue) {
      if (item is! Map) continue;
      final res = await CobaltoApiService.sendSosSignal(Map<String, dynamic>.from(item));
      if (res['success'] != true) {
        remaining.add(item);
      }
    }

    await prefs.setString(_pendingSosKey, json.encode(remaining));
  }
}