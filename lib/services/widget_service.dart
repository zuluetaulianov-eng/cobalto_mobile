import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'local_db_service.dart';
import '../utils/text_sanitizer.dart';

class WidgetService {
  static const String _androidWidgetName = 'CobaltoWidgetProvider';

  /// Actualiza los campos de datos del Widget nativo de Android
  static Future<void> updateWidgetData({
    required String defcon,
    required int alertCount,
    required String headline,
  }) async {
    try {
      final cleanHeadline = TextSanitizer.clean(headline);
      await HomeWidget.saveWidgetData<String>('widget_defcon', 'DEFCON $defcon');
      await HomeWidget.saveWidgetData<String>('widget_alerts_count', 'ALERTAS ACTIVAS: $alertCount');
      await HomeWidget.saveWidgetData<String>('widget_headline', cleanHeadline);

      await HomeWidget.updateWidget(
        name: _androidWidgetName,
        androidName: _androidWidgetName,
      );
      debugPrint('📱 Widget nativo de Android actualizado con éxito.');
    } catch (e) {
      debugPrint('⚠️ Error actualizando Widget nativo: $e');
    }
  }

  /// Sincroniza automáticamente los datos locales de SQLite con el Widget
  static Future<void> syncWidgetFromLocalDb() async {
    try {
      final entries = await LocalDbService.getEntries(limit: 5);
      final reports = await LocalDbService.getFieldReports();

      final String headline = entries.isNotEmpty
          ? (entries.first['title'] ?? 'Sin noticias recientes')
          : (reports.isNotEmpty ? 'HUMINT: ${reports.first['title']}' : 'Sin alertas recientes');

      final int totalAlerts = reports.where((r) => r['threat_level'] == 'CRITICAL' || r['threat_level'] == 'ELEVATED').length;

      await updateWidgetData(
        defcon: '3',
        alertCount: totalAlerts,
        headline: headline,
      );
    } catch (e) {
      debugPrint('⚠️ Excepción al sincronizar datos para el Widget: $e');
    }
  }
}
