import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String presetLanUrl = 'http://192.168.1.102:8083';
  static const String presetLocalhostUrl = 'http://127.0.0.1:8083';
  static const String presetEmulatorUrl = 'http://10.0.2.2:8083';
  static const String presetZrokUrl = 'https://commandereliminatedextraction.share.zrok.io';

  static const String defaultBaseUrl = presetLanUrl;
  static const String defaultUsername = 'admin';
  static const String defaultPassword = '..21Bishamonten21..';

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
    baseUrl = prefs.getString('base_url') ?? defaultBaseUrl;
    username = prefs.getString('username') ?? defaultUsername;
    password = prefs.getString('password') ?? defaultPassword;
    authToken = prefs.getString('auth_token');
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
      await prefs.setString('auth_token', token);
    }
    await prefs.setString('base_url', baseUrl);
    await prefs.setString('username', username);
    await prefs.setString('password', password);
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
    if (token != null && token.isNotEmpty) {
      await prefs.setString('auth_token', token);
    } else {
      await prefs.remove('auth_token');
    }
  }
}
