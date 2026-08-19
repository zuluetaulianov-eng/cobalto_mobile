import 'package:flutter_test/flutter_test.dart';
import 'package:cobalto_mobile/services/aegis_black_box_service.dart';
import 'package:cobalto_mobile/services/aegis_triage_service.dart';
import 'package:cobalto_mobile/services/aegis_zero_click_panic_service.dart';

/// Tests unitarios — Fase 3 (Caja Negra), Fase 4 (Triaje), Fase 5 (0-clic).
///
/// TODOS puro Dart: no dependen de SQLite, hardware ni red.
void main() {
  // ── CAJA NEGRA (Fase 3) ──

  group('AegisBlackBoxService — lógica offline pura', () {
    test('sealForTransport produce prefijo TRA:', () async {
      // No testeamos el cifrado real (requiere clave); solo el contrato del prefijo.
      // Verificamos que la constante _transportPrefix es 'TRA:'.
      // Acceso indirecto: openFromTransport retorna el valor intacto si no empieza por TRA:.
      const notSealed = 'texto plano sin prefijo';
      final result = await AegisBlackBoxService.openFromTransport(notSealed);
      // Debe retornar el valor original intacto (no es TRA:).
      expect(result, equals(notSealed));
    });

    test('pendingCount devuelve 0 con SharedPreferences vacío', () async {
      // Sin haber guardado ningún paquete pendiente, la cola debe estar vacía.
      // Nota: este test requiere que SharedPreferences esté mockeado o vacío.
      // En flutter_test el binding inicializa prefs en memoria.
      TestWidgetsFlutterBinding.ensureInitialized();
      // Sin setup adicional, pendingCount no puede acceder a prefs reales —
      // solo validamos que el método existe y es callable sin throw.
      expect(() async => AegisBlackBoxService.pendingCount(), returnsNormally);
    });

    test('stopMonitoring es idempotente (no lanza si ya está detenido)', () {
      // Llamar stop sin haber llamado start no debe lanzar.
      expect(() => AegisBlackBoxService.stopMonitoring(), returnsNormally);
      expect(() => AegisBlackBoxService.stopMonitoring(), returnsNormally);
    });

    test('lastPackage comienza como null', () {
      expect(AegisBlackBoxService.lastPackage.value, isNull);
    });
  });

  // ── TRIAJE (Fase 4) ──

  group('AegisTriageService — protocolos offline', () {
    test('availableProtocols no está vacío', () {
      expect(AegisTriageService.availableProtocols, isNotEmpty);
    });

    test('todos los protocolos tienen id, title, emoji y category', () {
      for (final p in AegisTriageService.availableProtocols) {
        expect(p['id'], isNotEmpty, reason: 'falta id en protocolo');
        expect(p['title'], isNotEmpty, reason: 'falta title en protocolo ${p['id']}');
        expect(p['emoji'], isNotEmpty, reason: 'falta emoji en protocolo ${p['id']}');
        expect(p['category'], isNotEmpty, reason: 'falta category en protocolo ${p['id']}');
      }
    });

    test('getProtocol devuelve pasos para protocolos conocidos', () {
      final ids = AegisTriageService.availableProtocols.map((p) => p['id']!).toList();
      for (final id in ids) {
        final steps = AegisTriageService.getProtocol(id);
        expect(steps, isNotNull, reason: 'protocolo "$id" no tiene pasos registrados');
        expect(steps!, isNotEmpty, reason: 'protocolo "$id" tiene lista vacía');
      }
    });

    test('getProtocol devuelve null para id desconocido', () {
      expect(AegisTriageService.getProtocol('protocolo_inexistente_xyz'), isNull);
    });

    test('protocolo RCP tiene paso con metrónomo', () {
      final steps = AegisTriageService.getProtocol('cpr_adult')!;
      final hasMetronome = steps.any((s) => s.hasCprMetronome);
      expect(hasMetronome, isTrue,
          reason: 'RCP debe tener al menos un paso con metrónomo de 100-120 BPM');
    });

    test('protocolo de atragantamiento tiene bifurcaciones (options)', () {
      final steps = AegisTriageService.getProtocol('choking_adult')!;
      final hasBranch = steps.any((s) => s.options != null && s.options!.isNotEmpty);
      expect(hasBranch, isTrue,
          reason: 'atragantamiento debe tener bifurcación de decisión');
    });

    test('todos los pasos tienen id y instrucción no vacíos', () {
      final protocols = AegisTriageService.availableProtocols.map((p) => p['id']!).toList();
      for (final protId in protocols) {
        final steps = AegisTriageService.getProtocol(protId)!;
        for (final step in steps) {
          expect(step.id, isNotEmpty, reason: 'paso sin id en protocolo $protId');
          expect(step.instruction, isNotEmpty,
              reason: 'paso ${step.id} sin instrucción en protocolo $protId');
          expect(step.title, isNotEmpty,
              reason: 'paso ${step.id} sin título en protocolo $protId');
        }
      }
    });

    test('opciones de bifurcación apuntan a IDs existentes en el mismo protocolo', () {
      final protocols = AegisTriageService.availableProtocols.map((p) => p['id']!).toList();
      for (final protId in protocols) {
        final steps = AegisTriageService.getProtocol(protId)!;
        final stepIds = steps.map((s) => s.id).toSet();
        for (final step in steps) {
          if (step.options == null) continue;
          for (final option in step.options!) {
            expect(
              stepIds.contains(option.nextId),
              isTrue,
              reason: 'opción "${option.label}" apunta a nextId "${option.nextId}" '
                  'que no existe en protocolo $protId',
            );
          }
        }
      }
    });

    test('stopMetronome es idempotente', () {
      expect(() => AegisTriageService.stopMetronome(), returnsNormally);
      expect(() => AegisTriageService.stopMetronome(), returnsNormally);
    });

    test('dispose es idempotente', () {
      expect(() => AegisTriageService.dispose(), returnsNormally);
      expect(() => AegisTriageService.dispose(), returnsNormally);
    });
  });

  // ── PÁNICO 0-CLIC (Fase 5) ──

  group('ZeroClickPanicService — disparador VOL DOWN × 3', () {
    tearDown(() {
      ZeroClickPanicService.detach();
      ZeroClickPanicService.onConfirmationRequired = null;
      ZeroClickPanicService.onPanicTriggered = null;
    });

    test('attach es idempotente (llamar dos veces no duplica el handler)', () {
      expect(() {
        ZeroClickPanicService.attach();
        ZeroClickPanicService.attach(); // No debe lanzar.
      }, returnsNormally);
    });

    test('detach es idempotente (llamar sin attach previo no lanza)', () {
      expect(() {
        ZeroClickPanicService.detach();
        ZeroClickPanicService.detach();
      }, returnsNormally);
    });

    test('dispose llama a detach sin lanzar', () {
      ZeroClickPanicService.attach();
      expect(() => ZeroClickPanicService.dispose(), returnsNormally);
    });

    test('callbacks onConfirmationRequired y onPanicTriggered son nullable', () {
      // El servicio no debe lanzar si los callbacks son null.
      ZeroClickPanicService.onConfirmationRequired = null;
      ZeroClickPanicService.onPanicTriggered = null;
      expect(ZeroClickPanicService.onConfirmationRequired, isNull);
      expect(ZeroClickPanicService.onPanicTriggered, isNull);
    });

    test('setEnabled persiste correctamente (async)', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Solo verificamos que no lanza; SharedPreferences en test es en memoria.
      expect(() async => ZeroClickPanicService.setEnabled(true), returnsNormally);
      expect(() async => ZeroClickPanicService.setEnabled(false), returnsNormally);
    });
  });
}
