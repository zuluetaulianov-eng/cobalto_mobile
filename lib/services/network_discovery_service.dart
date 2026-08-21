import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'app_logger.dart';

/// Resultado del proceso de autodescubrimiento de red.
class HubDiscoveryResult {
  final bool success;
  final String? hubUrl;
  final String? hubIp;
  final int port;
  final String discoveryMethod;
  final String hubName;
  final String errorMessage;

  const HubDiscoveryResult({
    required this.success,
    this.hubUrl,
    this.hubIp,
    this.port = 8083,
    this.discoveryMethod = 'NONE',
    this.hubName = 'COBALTO-HUB',
    this.errorMessage = '',
  });

  @override
  String toString() => success
      ? 'HubDiscoveryResult(OK: $hubUrl via $discoveryMethod [$hubName])'
      : 'HubDiscoveryResult(FAIL: $errorMessage)';
}

/// Servicio de Autodescubrimiento Táctico Cero-Configuración para COBALTO.
///
/// Permite al dispositivo móvil localizar automáticamente el servidor COBALTO HUB (PC)
/// en la red Wi-Fi / LAN / Hotspot sin necesidad de ingresar la IP manualmente.
///
/// Estrategia de descubrimiento de 2 capas:
///  1. **UDP Broadcast Probe (Puerto 8084)**: Emite un ping de broadcast UDP táctico
///     y espera la respuesta del demonio de descubrimiento del HUB PC en < 1.5s.
///  2. **Subnet Fast Probe (Escaneo de Subred HTTP)**: Si los paquetes broadcast
///     son filtrados por el AP/Router, escanea en paralelo la subred local buscando
///     el endpoint activo de COBALTO HUB en el puerto 8083.
class NetworkDiscoveryService {
  static const int udpDiscoveryPort = 8084;
  static const int defaultHubPort = 8083;
  static const String discoveryProbePayload = 'COBALTO_DISCOVERY_PROBE_V1';

  /// Ejecuta el proceso completo de autodescubrimiento.
  /// Si [autoApply] es true, actualiza inmediatamente [ApiConfig.baseUrl].
  static Future<HubDiscoveryResult> discoverHub({bool autoApply = true}) async {
    AppLogger.info('📡 Iniciando autodescubrimiento táctico de COBALTO HUB...', tag: 'NetDiscovery');

    // 1. Probar vía UDP Broadcast (Más rápido y eficiente)
    final udpResult = await _discoverViaUdpBroadcast();
    if (udpResult.success) {
      if (autoApply && udpResult.hubUrl != null) {
        await ApiConfig.saveConfig(
          udpResult.hubUrl!,
          ApiConfig.username,
          ApiConfig.password,
        );
      }
      return udpResult;
    }

    // 2. Fallback a Escaneo de Subred HTTP (Resiliente a bloqueos de UDP)
    AppLogger.info('UDP Broadcast sin respuesta. Iniciando escaneo directo de subred LAN...', tag: 'NetDiscovery');
    final subnetResult = await _discoverViaSubnetScan();
    if (subnetResult.success && autoApply && subnetResult.hubUrl != null) {
      await ApiConfig.saveConfig(
        subnetResult.hubUrl!,
        ApiConfig.username,
        ApiConfig.password,
      );
    }

    return subnetResult;
  }

  // ── 1. UDP BROADCAST PROBE ──

  static Future<HubDiscoveryResult> _discoverViaUdpBroadcast() async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      final completer = Completer<HubDiscoveryResult>();

      // Escuchar respuestas UDP
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket?.receive();
          if (datagram != null) {
            final responseStr = utf8.decode(datagram.data).trim();
            final senderIp = datagram.address.address;

            debugPrint('📩 Respuesta UDP recibida desde $senderIp: $responseStr');

            if (responseStr.contains('COBALTO_HUB') || responseStr.contains('service')) {
              int port = defaultHubPort;
              String name = 'COBALTO-HUB-PC';

              // Intentar parsear JSON de respuesta del HUB PC
              try {
                final jsonMap = json.decode(responseStr) as Map<String, dynamic>;
                port = jsonMap['port'] as int? ?? defaultHubPort;
                name = jsonMap['name'] as String? ?? name;
              } catch (_) {
                // Formato legacy/simple: COBALTO_HUB_RESPONSE:8083
                if (responseStr.contains(':')) {
                  final parts = responseStr.split(':');
                  if (parts.length > 1) {
                    port = int.tryParse(parts[1]) ?? defaultHubPort;
                  }
                }
              }

              final hubUrl = 'http://$senderIp:$port';
              if (!completer.isCompleted) {
                completer.complete(
                  HubDiscoveryResult(
                    success: true,
                    hubUrl: hubUrl,
                    hubIp: senderIp,
                    port: port,
                    discoveryMethod: 'UDP Broadcast',
                    hubName: name,
                  ),
                );
              }
            }
          }
        }
      });

      // Transmitir ráfaga de broadcast UDP
      final payload = utf8.encode(discoveryProbePayload);
      final broadcastAddress = InternetAddress('255.255.255.255');
      socket.send(payload, broadcastAddress, udpDiscoveryPort);

      // Esperar hasta 1.5 segundos por respuesta
      return await completer.future.timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {
          return const HubDiscoveryResult(
            success: false,
            errorMessage: 'Timeout en UDP broadcast.',
          );
        },
      );
    } catch (e) {
      AppLogger.warn('Error durante UDP Broadcast Discovery', tag: 'NetDiscovery', error: e);
      return HubDiscoveryResult(
        success: false,
        errorMessage: 'Error UDP: $e',
      );
    } finally {
      socket?.close();
    }
  }

  // ── 2. ESCANEO RÁPIDO DE SUBRED HTTP ──

  static Future<HubDiscoveryResult> _discoverViaSubnetScan() async {
    try {
      final localIps = await _getLocalIpAddresses();
      if (localIps.isEmpty) {
        return const HubDiscoveryResult(
          success: false,
          errorMessage: 'Sin interfaz de red Wi-Fi/LAN activa.',
        );
      }

      for (final localIp in localIps) {
        final subnetPrefix = _extractSubnetPrefix(localIp);
        if (subnetPrefix == null) continue;

        debugPrint('🔍 Escaneando subred LAN $subnetPrefix.1-254 para COBALTO HUB...');

        // Escanear en lotes paralelos de 30 IPs para no saturar sockets
        final int port = defaultHubPort;
        final candidateIps = List<String>.generate(254, (i) => '$subnetPrefix.${i + 1}');

        for (int i = 0; i < candidateIps.length; i += 35) {
          final batch = candidateIps.sublist(i, (i + 35 > candidateIps.length) ? candidateIps.length : i + 35);
          final futures = batch.map((ip) => _probeHttpHost(ip, port));
          final results = await Future.wait(futures);

          for (final res in results) {
            if (res != null) {
              return HubDiscoveryResult(
                success: true,
                hubUrl: 'http://$res:$port',
                hubIp: res,
                port: port,
                discoveryMethod: 'Subnet HTTP Scan',
                hubName: 'COBALTO-HUB ($res)',
              );
            }
          }
        }
      }

      return const HubDiscoveryResult(
        success: false,
        errorMessage: 'No se encontró ningún COBALTO HUB activo en la subred local.',
      );
    } catch (e) {
      AppLogger.warn('Error durante escaneo de subred', tag: 'NetDiscovery', error: e);
      return HubDiscoveryResult(
        success: false,
        errorMessage: 'Error de escaneo: $e',
      );
    }
  }

  /// Prueba la presencia de COBALTO HUB en [ip]:[port] con timeout corto de 600ms.
  static Future<String?> _probeHttpHost(String ip, int port) async {
    try {
      final uri = Uri.parse('http://$ip:$port/api/v1/health');
      final client = http.Client();
      try {
        final response = await client.get(uri).timeout(const Duration(milliseconds: 650));
        // Aceptamos 200 OK, 401 Unauthorized (requiere auth), 403 o respuesta con firma COBALTO
        if (response.statusCode == 200 ||
            response.statusCode == 401 ||
            response.body.contains('cobalto') ||
            response.body.contains('status')) {
          return ip;
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Host inalcanzable o timeout
    }
    return null;
  }

  /// Obtiene la lista de IPs IPv4 locales (omitir 127.0.0.1 y interfaces virtuales/VPN).
  static Future<List<String>> _getLocalIpAddresses() async {
    final List<String> ips = [];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        // Filtrar interfaces virtuales de docker/vbox
        final lowerName = interface.name.toLowerCase();
        if (lowerName.contains('vbox') || lowerName.contains('docker') || lowerName.contains('vethernet')) {
          continue;
        }
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            ips.add(addr.address);
          }
        }
      }
    } catch (e) {
      AppLogger.warn('No se pudieron listar interfaces de red.', tag: 'NetDiscovery', error: e);
    }
    return ips;
  }

  /// Extrae el prefijo de subred IPv4 (ej. '192.168.1.45' -> '192.168.1')
  static String? _extractSubnetPrefix(String ip) {
    final parts = ip.split('.');
    if (parts.length == 4) {
      return '${parts[0]}.${parts[1]}.${parts[2]}';
    }
    return null;
  }
}
