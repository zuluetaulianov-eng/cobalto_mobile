import 'package:cobalto_mobile/services/local_auth_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('hasLocalUser es false sin cuenta configurada', () async {
    expect(await LocalAuthService.hasLocalUser(), isFalse);
    expect(await LocalAuthService.getUsername(), isNull);
  });

  test('createUser registra un operador y no guarda la contraseña en claro', () async {
    await LocalAuthService.createUser('operador', 'secreto123');

    expect(await LocalAuthService.hasLocalUser(), isTrue);
    expect(await LocalAuthService.getUsername(), 'operador');
    expect(await LocalAuthService.verifyLogin('operador', 'secreto123'), isTrue);

    final store = FlutterSecureStorage();
    final salt = await store.read(key: 'local_operator_salt');
    final hash = await store.read(key: 'local_operator_hash');
    expect(salt, isNotNull);
    expect(hash, isNotNull);
    expect(hash, isNot('secreto123'));
    expect(await store.read(key: 'local_operator_username'), 'operador');
  });

  test('verifyLogin rechaza contraseña incorrecta o usuario distinto', () async {
    await LocalAuthService.createUser('alfa', 'clave123');

    expect(await LocalAuthService.verifyLogin('alfa', 'clave-incorrecta'), isFalse);
    expect(await LocalAuthService.verifyLogin('beta', 'clave123'), isFalse);
    expect(await LocalAuthService.verifyLogin('', 'clave123'), isFalse);
  });

  test('createUser valida longitud mínima de usuario y contraseña', () async {
    expect(() => LocalAuthService.createUser('ab', 'clave123'), throwsArgumentError);
    expect(() => LocalAuthService.createUser('operador', 'abc'), throwsArgumentError);
    expect(await LocalAuthService.hasLocalUser(), isFalse);
  });

  test('createUser no permite sobreescribir un operador existente', () async {
    await LocalAuthService.createUser('uno', 'clave123');
    expect(
      () => LocalAuthService.createUser('dos', 'clave456'),
      throwsStateError,
    );
  });

  test('changeUsername exige la contraseña actual correcta', () async {
    await LocalAuthService.createUser('original', 'clave123');

    expect(() => LocalAuthService.changeUsername('nuevo', 'clave-incorrecta'), throwsStateError);

    await LocalAuthService.changeUsername('renombrado', 'clave123');
    expect(await LocalAuthService.getUsername(), 'renombrado');
    // Las credenciales siguen válidas con el nuevo nombre.
    expect(await LocalAuthService.verifyLogin('renombrado', 'clave123'), isTrue);
    expect(await LocalAuthService.verifyLogin('original', 'clave123'), isFalse);
  });

  test('changePassword exige la contraseña actual correcta', () async {
    await LocalAuthService.createUser('operador', 'clave123');

    expect(() => LocalAuthService.changePassword('nueva456', 'clave-incorrecta'), throwsStateError);

    await LocalAuthService.changePassword('nueva456', 'clave123');
    expect(await LocalAuthService.verifyLogin('operador', 'clave123'), isFalse);
    expect(await LocalAuthService.verifyLogin('operador', 'nueva456'), isTrue);
  });

  test('changeUsername/changePassword validan el formato del nuevo valor', () async {
    await LocalAuthService.createUser('operador', 'clave123');

    expect(() => LocalAuthService.changeUsername('ab', 'clave123'), throwsArgumentError);
    expect(() => LocalAuthService.changePassword('abc', 'clave123'), throwsArgumentError);
  });
}
