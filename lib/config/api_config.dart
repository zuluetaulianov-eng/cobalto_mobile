import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String presetLanUrl = 'http://192.168.1.102:8083';
  static const String presetLocalhostUrl = 'http://127.0.0.1:8083';
  static const String presetEmulatorUrl = 'http://10.0.2.2:8083';

  static const String defaultBaseUrl = presetLanUrl;

  // Credenciales de arranque provistas únicamente en tiempo de build
  // (--dart-define=COBALTO_DEFAULT_USERNAME=... COBALTO_DEFAULT_PASSWORD=...).
  // Sin valores embebidos en el repositorio.
  static const String defaultUsername =
      String.fromEnvironment('COBALTO_DEFAULT_USERNAME', defaultValue: '');
  static const String defaultPassword =
      String.fromEnvironment('COBALTO_DEFAULT_PASSWORD', defaultValue: '');

  static final _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      migrateWithBackup: true,
    ),
  );

  static String baseUrl = defaultBaseUrl;
  static String username = defaultUsername;
  static String password = defaultPassword;
  static String? authToken;

  static bool backgroundSync = true;
  static bool wifiOnly = false;
  static int syncInterval = 15;

  static String ollamaHost = 'http://192.168.1.50:11434';
  static String ollamaModel = 'llama3.2';

  static Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();

    // Migración: extraer credenciales legadas guardadas en claro hacia Secure Storage.
    final legacyPass = prefs.getString('password');
    if (legacyPass != null && legacyPass.isNotEmpty) {
      await _storage.write(key: 'password', value: legacyPass);
      await prefs.remove('password');
    }

    // Migración: JWT desde prefs en claro hacia Secure Storage.
    final legacyToken = prefs.getString('auth_token');
    if (legacyToken != null && legacyToken.isNotEmpty) {
      await _storage.write(key: 'auth_token', value: legacyToken);
      await prefs.remove('auth_token');
    }

    baseUrl = prefs.getString('base_url') ?? defaultBaseUrl;
    username = prefs.getString('username') ?? defaultUsername;
    password = await _storage.read(key: 'password') ?? defaultPassword;
    authToken = await _storage.read(key: 'auth_token');
    backgroundSync = prefs.getBool('background_sync') ?? true;
    wifiOnly = prefs.getBool('wifi_only') ?? false;
    syncInterval = prefs.getInt('sync_interval') ?? 15;
    ollamaHost = prefs.getString('ollama_host') ?? 'http://192.168.1.50:11434';
    ollamaModel = prefs.getString('ollama_model') ?? 'llama3.2';
  }

  static Future<void> saveConfig(String newBaseUrl, String newUsername, String newPassword, {String? token}) async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = newBaseUrl.endsWith('/') ? newBaseUrl.substring(0, newBaseUrl.length - 1) : newBaseUrl;
    username = newUsername;
    password = newPassword;
    if (token != null) {
      authToken = token;
      if (token.isNotEmpty) {
        await _storage.write(key: 'auth_token', value: token);
      } else {
        await _storage.delete(key: 'auth_token');
      }
      await prefs.remove('auth_token');
    }
    await prefs.setString('base_url', baseUrl);
    await prefs.setString('username', username);
    if (newPassword.isNotEmpty) {
      await _storage.write(key: 'password', value: newPassword);
    } else {
      await _storage.delete(key: 'password');
    }
  }

  static Future<void> saveOllamaConfig(String host, String model) async {
    final prefs = await SharedPreferences.getInstance();
    ollamaHost = host;
    ollamaModel = model;
    await prefs.setString('ollama_host', host);
    await prefs.setString('ollama_model', model);
  }

  static Future<void> saveBackgroundSettings(bool bgSync, bool wifiOnlyMode, int interval) async {
    final prefs = await SharedPreferences.getInstance();
    backgroundSync = bgSync;
    wifiOnly = wifiOnlyMode;
    syncInterval = interval;
    await prefs.setBool('background_sync', bgSync);
    await prefs.setBool('wifi_only', wifiOnlyMode);
    await prefs.setInt('sync_interval', interval);
  }

  static Future<void> setAuthToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    authToken = token;
    // JWT solo en Secure Storage (nunca en prefs en claro).
    await prefs.remove('auth_token');
    if (token != null && token.isNotEmpty) {
      await _storage.write(key: 'auth_token', value: token);
    } else {
      await _storage.delete(key: 'auth_token');
    }
  }
}
