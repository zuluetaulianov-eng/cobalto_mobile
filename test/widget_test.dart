import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cobalto_mobile/screens/login_screen.dart';

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('LoginScreen renders creation form when no local user', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('COBALTO HUB'), findsOneWidget);
    expect(find.text('USUARIO OPERADOR'), findsOneWidget);
    expect(find.text('CONTRASEÑA DE ACCESO'), findsOneWidget);
    expect(find.text('CONFIRMAR CONTRASEÑA'), findsOneWidget);
    expect(find.text('CREAR OPERADOR Y INGRESAR'), findsOneWidget);
  });

  testWidgets('LoginScreen renders login form when a local user exists', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'local_operator_username': 'operador',
      'local_operator_salt': 'c2FsdA==',
      'local_operator_hash': 'aGFzaA==',
    });

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('COBALTO HUB'), findsOneWidget);
    expect(find.text('USUARIO OPERADOR'), findsOneWidget);
    expect(find.text('CONTRASEÑA DE ACCESO'), findsOneWidget);
    expect(find.text('INGRESAR AL SISTEMA'), findsOneWidget);
    expect(find.text('CONFIRMAR CONTRASEÑA'), findsNothing);
  });
}
