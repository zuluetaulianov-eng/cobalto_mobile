import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'app_logger.dart';

class CobaltoApiService {
  // Cliente HTTP inyectable para permitir mocks en pruebas unitarias.
  static http.Client _client = http.Client();

  @visibleForTesting
  static set client(http.Client value) => _client = value;

  @visibleForTesting
  static void restoreDefaultClient() {
    _client = http.Client();
  }

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (ApiConfig.authToken != null && ApiConfig.authToken!.isNotEmpty)
          'Authorization': 'Bearer ${ApiConfig.authToken}',
      };

  static Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('token') && data['token'].toString().isNotEmpty) {
          final token = data['token'].toString();
          await ApiConfig.setAuthToken(token);
          return {'success': true, 'token': token};
        }
      }

      return {
        'success': false,
        'error': 'Credenciales rechazadas por el servidor (HTTP ${response.statusCode}).',
      };
    } catch (e) {
      return {'success': false, 'error': 'Error de conexión con ${ApiConfig.baseUrl}: $e'};
    }
  }

  static Future<bool> testConnection() async {
    try {
      // 1. Probar salud pública (status, startup-progress o health)
      var healthResp = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/status'))
          .timeout(const Duration(seconds: 8));

      if (healthResp.statusCode != 200) {
        healthResp = await _client
            .get(Uri.parse('${ApiConfig.baseUrl}/api/startup-progress'))
            .timeout(const Duration(seconds: 8));
      }

      if (healthResp.statusCode != 200) {
        healthResp = await _client
            .get(Uri.parse('${ApiConfig.baseUrl}/api/health'))
            .timeout(const Duration(seconds: 8));
      }

      if (healthResp.statusCode != 200) return false;

      // 2. Intentar autenticar si no hay token o probar endpoint protegido /api/config
      var configResp = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/config'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (configResp.statusCode == 401) {
        // Autenticar automáticamente con credenciales configuradas
        final loginRes = await login(ApiConfig.username, ApiConfig.password);
        if (loginRes['success'] == true) {
          configResp = await _client
              .get(Uri.parse('${ApiConfig.baseUrl}/api/config'), headers: _headers)
              .timeout(const Duration(seconds: 8));
        }
      }

      return configResp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> fetchNews() async {
    try {
      var response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/news'), headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        response = await _client
            .get(Uri.parse('${ApiConfig.baseUrl}/api/dashboard'), headers: _headers)
            .timeout(const Duration(seconds: 12));
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        if (data is Map && data.containsKey('entries')) return data['entries'];
        if (data is Map && data.containsKey('all_entries')) return data['all_entries'];
      }
    } catch (e) {
      // Fallback
    }
    return [];
  }

  static Future<Map<String, dynamic>> triggerExtraction() async {
    try {
      final response = await _client
          .post(Uri.parse('${ApiConfig.baseUrl}/api/extractor/run'), headers: _headers)
          .timeout(const Duration(seconds: 120));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      return {'status': 'error', 'message': 'Timeout o error de conexión con el extractor: $e'};
    }
    return {'status': 'error', 'message': 'No se pudo iniciar la extracción.'};
  }

  static Future<Map<String, dynamic>> fetchConfig() async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/config'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      // Return empty map on error
    }
    return {};
  }

  static Future<bool> saveSystemConfig(Map<String, dynamic> configMap) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/config'),
            headers: _headers,
            body: json.encode(configMap),
          )
          .timeout(const Duration(seconds: 12));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> fetchFeedHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/health/sources'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      // Error fallback
    }
    return {};
  }

  static Future<List<dynamic>> fetchAlerts() async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/alerts'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is List) return data;
        if (data is Map && data.containsKey('alerts')) return data['alerts'];
      }
    } catch (e) {
      // Silent error
    }
    return [];
  }

  static Future<List<dynamic>> fetchCctv({double? lat, double? lng, double? radiusKm}) async {
    try {
      String url = '${ApiConfig.baseUrl}/api/osiris/data/cctv?region=all';
      if (lat != null && lng != null && radiusKm != null) {
        url += '&lat=$lat&lng=$lng&radius_km=$radiusKm';
      }
      var response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        response = await _client
            .get(Uri.parse('${ApiConfig.baseUrl}/api/cctv'), headers: _headers)
            .timeout(const Duration(seconds: 10));
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data.containsKey('cameras')) return data['cameras'];
        if (data is List) return data;
      }
    } catch (e) {
      AppLogger.warn('Error fetching CCTV feeds.', tag: 'Api', error: e);
    }
    return [];
  }

  static Future<Map<String, dynamic>> fetchRealtime() async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/realtime'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      // Silent error
    }
    return {};
  }

  static Future<String> sendAiQuery(String prompt, {String persona = 'GENERAL'}) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/chat'),
            headers: _headers,
            body: json.encode({'message': prompt, 'persona': persona}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response'] ?? data['reply'] ?? data['text'] ?? 'Sin respuesta.';
      }
    } catch (e) {
      AppLogger.warn('IA sin conexión; modo offline.', tag: 'Api', error: e);
      return 'OFFLINE_MODE';
    }
    return 'OFFLINE_MODE';
  }

  // ── MÉTODOS DE SUB-ROUTERS (HUMINT, FININT, PREDICTIVE, ENTITIES) ──

  static Future<Map<String, dynamic>> sendHumintReport(Map<String, dynamic> reportData) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/humint/report'),
            headers: _headers,
            body: json.encode(reportData),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true, 'data': json.decode(response.body)};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
    return {'success': false, 'error': 'No se pudo enviar el reporte HUMINT al servidor.'};
  }

  /// Transmite la señal SOS (Dead Man's Switch) a la estación base.
  /// No lanza excepciones: siempre devuelve un mapa de resultado para uso en
  /// fire-and-forget.
  static Future<Map<String, dynamic>> sendSosSignal(Map<String, dynamic> sosData) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/sos'),
            headers: _headers,
            body: json.encode(sosData),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      // Fallback: algunos despliegues ingieren SOS vía el endpoint HUMINT.
      if (response.statusCode == 404) {
        return sendHumintReport(sosData);
      }
      return {'success': false, 'error': 'SOS rechazado (HTTP ${response.statusCode}).'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Publica el latido de telemetría (beacon) del operador al nodo central.
  /// La base puede detectar pérdida del operador si deja de recibir latidos.
  static Future<Map<String, dynamic>> sendHeartbeat(Map<String, dynamic> heartbeatData) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/telemetry/heartbeat'),
            headers: _headers,
            body: json.encode(heartbeatData),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      return {'success': false, 'error': 'Heartbeat rechazado (HTTP ${response.statusCode}).'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Publica el Paquete de Caja Negra AEGIS (batería + GPS + perfil de
  /// sobreviviente) al nodo central. El payload va CIFRADO en origen
  /// (AES-256-GCM) y se envía como un solo blob; la base lo ingiere tal cual.
  static Future<Map<String, dynamic>> sendBlackBoxPackage(
      Map<String, dynamic> envelope) async {
    try {
      final response = await _client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/aegis/blackbox'),
            headers: _headers,
            body: json.encode(envelope),
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {'success': true};
      }
      return {
        'success': false,
        'error': 'BlackBox rechazado (HTTP ${response.statusCode}).',
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> fetchPredictiveScore() async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/predictive/score'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      AppLogger.warn('fetchPredictiveScore sin respuesta del servidor.', tag: 'Api', error: e);
    }
    return {};
  }

  static Future<Map<String, dynamic>> fetchEntityStats() async {
    try {
      final response = await _client
          .get(Uri.parse('${ApiConfig.baseUrl}/api/entities/stats'), headers: _headers)
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      AppLogger.warn('fetchEntityStats sin respuesta del servidor.', tag: 'Api', error: e);
    }
    return {};
  }

  /// Ingesta el catálogo de cámaras CCTV públicas/tácticas desde el motor OSIRIS.
  static Future<List<dynamic>> fetchCctv({double? lat, double? lng, double? radiusKm}) async {
    try {
      String url = '${ApiConfig.baseUrl}/api/osiris/data/cctv';
      if (lat != null && lng != null && radiusKm != null) {
        url += '?lat=$lat&lng=$lng&radius_km=$radiusKm';
      }
      final response = await _client
          .get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['cameras'] is List) {
          return data['cameras'];
        }
      }
    } catch (e) {
      AppLogger.warn('fetchCctv sin respuesta del servidor.', tag: 'Api', error: e);
    }
    return [];
  }
}

