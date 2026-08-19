import 'package:cobalto_mobile/services/aegis_early_warning_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Algoritmo P/S (ondas sísmicas)', () {
    test('a distancia 0 las ondas llegan al instante', () {
      final r = AegisEarlyWarningService.computeArrivals(0);
      expect(r.pArrivalS, 0);
      expect(r.sArrivalS, 0);
    });

    test('la onda S llega después que la P (la fuerte viaja mas lento)', () {
      final r = AegisEarlyWarningService.computeArrivals(210);
      expect(r.sArrivalS, greaterThan(r.pArrivalS));
      // P ~ 210/6 = 35s ; S ~ 210/3.5 = 60s
      expect(r.pArrivalS, 35);
      expect(r.sArrivalS, 60);
    });

    test('la ventana de anticipación crece con la distancia', () {
      final near = AegisEarlyWarningService.computeArrivals(60).sArrivalS;
      final far = AegisEarlyWarningService.computeArrivals(240).sArrivalS;
      expect(far, greaterThan(near));
    });
  });

  group('Clasificación de amenaza por escala', () {
    test('M6.5 a 100 km es CRÍTICA', () {
      expect(AegisEarlyWarningService.classifyThreat(6.5, 100), 'CRÍTICA');
    });

    test('M7.2 a 500 km queda fuera de umbral (INFO)', () {
      expect(AegisEarlyWarningService.classifyThreat(7.2, 500), 'INFO');
    });

    test('M5.5 a 200 km es MEDIA', () {
      expect(AegisEarlyWarningService.classifyThreat(5.5, 200), 'MEDIA');
    });

    test('M3.9 cerca es INFO (debajo del umbral táctico)', () {
      expect(AegisEarlyWarningService.classifyThreat(3.9, 50), 'INFO');
    });

    test('M6.1 a 300 km es INFO (demasiado lejos para alarma)', () {
      expect(AegisEarlyWarningService.classifyThreat(6.1, 300), 'INFO');
    });
  });

  group('Geocerca automática', () {
    test('dentro del radio y sobre la magnitud mínima dispara', () {
      final inside = AegisEarlyWarningService.withinFence(
        distanceKm: 50,
        radiusKm: 200,
        mag: 5.0,
        minMag: 4.0,
      );
      expect(inside, isTrue);
    });

    test('fuera del radio no dispara', () {
      final outside = AegisEarlyWarningService.withinFence(
        distanceKm: 250,
        radiusKm: 200,
        mag: 5.0,
        minMag: 4.0,
      );
      expect(outside, isFalse);
    });

    test('bajo la magnitud mínima no dispara aunque esté cerca', () {
      final weak = AegisEarlyWarningService.withinFence(
        distanceKm: 30,
        radiusKm: 200,
        mag: 3.0,
        minMag: 4.0,
      );
      expect(weak, isFalse);
    });
  });
}