import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// Kit de Emergencia AEGIS: inventario de supervivencia con ciclo de
/// mantenimiento programado.
///
/// Recordatorio de renovación: el agua y las baterías de la mochila de
/// emergencia deben reemplazarse periódicamente (por defecto cada 6 meses).
/// COBALTO lo verifica al arrancar y al volver a primer plano; si venció la
/// fecha, emite una alerta de mantenimiento y reprograma el ciclo.
class AegisEmergencyKitService {
  static const String _inventoryKey = 'aegis_kit_inventory';
  static const String _nextReminderKey = 'aegis_kit_next_reminder';
  static const String _intervalMonthsKey = 'aegis_kit_interval_months';
  static const int _defaultIntervalMonths = 6;

  static const List<String> _defaultItems = [
    'Agua potable (3 L x persona)',
    'Baterías de repuesto',
    'Linterna + pilas',
    'Radio de batería/crank',
    'Botiquín de primeros auxilios',
    'Medicamentos personales',
    'Silbato de emergencia',
    'Cargador portátil (powerbank)',
    'Documentos de identidad en bolsa hermética',
    'Copia de claves/llaves de vehiculo',
    'Manta térmica',
    'Dinero en efectivo de reserva',
  ];

  /// Lista de inventario [valor]-[estado].
  static Future<List<Map<String, dynamic>>> getInventory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_inventoryKey);
    if (raw == null || raw.isEmpty) {
      return _defaultItems
          .map((item) => {'label': item, 'checked': false})
          .toList();
    }
    return raw.map((line) {
      final idx = line.indexOf('|');
      if (idx < 0) return {'label': line, 'checked': false};
      final label = line.substring(0, idx);
      final checked = line.substring(idx + 1) == '1';
      return {'label': label, 'checked': checked};
    }).toList();
  }

  static Future<String> getInventoryLine(Map<String, dynamic> item) =>
      Future.value('${item['label']}|${item['checked'] == true ? '1' : '0'}');

  static Future<void> saveInventory(List<Map<String, dynamic>> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _inventoryKey,
      items.map((item) => '${item['label']}|${item['checked'] == true ? '1' : '0'}').toList(),
    );
  }

  static Future<void> setItemChecked(dynamic label, bool checked) async {
    final items = await getInventory();
    for (final item in items) {
      if (item['label'] == label) item['checked'] = checked;
    }
    await saveInventory(items);
  }

  static Future<void> resetInventory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_inventoryKey);
  }

  // ── CICLO DE MANTENIMIENTO ──

  static Future<int> reminderIntervalMonths() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_intervalMonthsKey) ?? _defaultIntervalMonths;
  }

  static Future<void> setReminderIntervalMonths(int months) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_intervalMonthsKey, months);
  }

  static Future<DateTime?> nextReminderDate() async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_nextReminderKey);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<void> _scheduleNext() async {
    final interval = await reminderIntervalMonths();
    final next = DateTime.now()
        .add(Duration(days: 30 * interval))
        .millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_nextReminderKey, next);
  }

  static String _humanize(DateTime date) {
    const months = ['ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', 'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC'];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  /// Verifica si el mantenimiento del kit está vencido y, si es así,
  /// emite la alerta y reprograma el ciclo. Devolverá cadena de estado
  /// legible (próxima revisión) para mostrar en la UI.
  static Future<String> checkAndSchedule() async {
    final next = await nextReminderDate();
    final due = next == null || !DateTime.now().isBefore(next);

    if (due) {
      await NotificationService.showAlertNotification(
        title: '🎒 MANTENIMIENTO DEL KIT DE EMERGENCIA',
        body: 'Han pasado ${await reminderIntervalMonths()} meses '
            'desde la última revisión. Reemplace el agua y las baterías '
            'del kit de supervivencia.',
        level: 'MEDIA',
        deduplicationKey: 'aegis|kit|reminder',
      );
      await _scheduleNext();
    }

    final after = await nextReminderDate();
    return _humanize(after ?? DateTime.now());
  }

  static Future<void> resetReminderTimer() async {
    await _scheduleNext();
    debugPrint('🎒 Recordatorio de kit reprogramado.');
  }
}