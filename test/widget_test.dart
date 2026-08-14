import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cobalto_mobile/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen renders and exposes login form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('COBALTO HUB'), findsOneWidget);
    expect(find.text('USUARIO OPERADOR'), findsOneWidget);
    expect(find.text('CONTRASEÑA DE ACCESO'), findsOneWidget);
    expect(find.text('INGRESAR AL SISTEMA'), findsOneWidget);
  });
}