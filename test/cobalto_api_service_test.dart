import 'dart:convert';

import 'package:cobalto_mobile/config/api_config.dart';
import 'package:cobalto_mobile/services/cobalto_api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    ApiConfig.baseUrl = 'http://127.0.0.1:8083';
    ApiConfig.authToken = null;
  });

  tearDown(() {
    CobaltoApiService.restoreDefaultClient();
  });

  test('login exitoso almacena el token JWT', () async {
    CobaltoApiService.client = MockClient((request) async {
      expect(request.url.path, '/api/login');
      return http.Response(
        json.encode({'token': 'test-jwt-token'}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final res = await CobaltoApiService.login('admin', 'secreto');

    expect(res['success'], isTrue);
    expect(res['token'], 'test-jwt-token');
    expect(ApiConfig.authToken, 'test-jwt-token');
  });

  test('login rechaza credenciales inválidas sin otorgar token', () async {
    CobaltoApiService.client =
        MockClient((request) async => http.Response('denied', 401));

    final res = await CobaltoApiService.login('intruso', 'malapass');

    expect(res['success'], isFalse);
    expect(ApiConfig.authToken, isNull);
  });

  test('login no otorga acceso ante 404 del servidor (sin bypass)', () async {
    CobaltoApiService.client =
        MockClient((request) async => http.Response('no auth', 404));

    // Antes del endurecimiento estas credenciales producían 'open-access-token'.
    final res = await CobaltoApiService.login('admin', '..21Bishamonten21..');

    expect(res['success'], isFalse);
    expect(ApiConfig.authToken, isNull);
  });

  test('login no otorga acceso ante error de conexión (sin bypass offline)',
      () async {
    CobaltoApiService.client = MockClient(
        (request) async => throw http.ClientException('unreachable'));

    final res = await CobaltoApiService.login('admin', '..21Bishamonten21..');

    expect(res['success'], isFalse);
    expect(ApiConfig.authToken, isNull);
  });

  test('sendSosSignal publica la señal SOS a /api/sos', () async {
    CobaltoApiService.client = MockClient((request) async {
      expect(request.url.path, '/api/sos');
      return http.Response('{}', 201);
    });

    final res =
        await CobaltoApiService.sendSosSignal({'type': 'sos', 'severity': 'CRITICAL'});

    expect(res['success'], isTrue);
  });
}