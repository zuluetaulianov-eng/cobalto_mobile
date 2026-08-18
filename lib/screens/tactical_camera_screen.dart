import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/gps_service.dart';
import '../services/tactical_camera_service.dart';

/// Vista frontal del sensor de cámara con HUD táctico: previsualización en
/// vivo, overlay de telemetría GPS (coordenadas, altitud, velocidad, rumbo y
/// precisión) y controles de flash/sensor. Al capturar devuelve el mapa con
/// la ruta de la evidencia, sidecar forense y hash SHA-256.
class TacticalCameraScreen extends StatefulWidget {
  const TacticalCameraScreen({super.key});

  @override
  State<TacticalCameraScreen> createState() => _TacticalCameraScreenState();
}

class _TacticalCameraScreenState extends State<TacticalCameraScreen>
    with WidgetsBindingObserver {
  bool _ready = false;
  bool _capturing = false;
  bool _flashOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final ok = await TacticalCameraService.initCamera();
    if (mounted) setState(() => _ready = ok);
  }

  Future<void> _toggleFlash() async {
    await TacticalCameraService.toggleFlash();
    if (mounted) setState(() => _flashOn = !_flashOn);
  }

  Future<void> _switchCamera() async {
    final next = await TacticalCameraService.switchCamera();
    if (mounted) {
      setState(() {
        _ready = next != null;
      });
    }
  }

  Future<void> _capture() async {
    if (_capturing) return;
    setState(() => _capturing = true);

    final result = await TacticalCameraService.captureTelemetryPhoto(
      telemetry: GpsService.lastSnapshot,
      classification: 'CONFIDENCIAL // COBALTO C4I',
    );

    if (!mounted) return;
    setState(() => _capturing = false);

    if (result != null) {
      Navigator.pop(context, result);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No se pudo capturar la evidencia. Verifique permisos o sensor.'),
          backgroundColor: Color(0xFFFF2D55),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TacticalCameraService.disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _ready ? _buildViewfinder() : _buildLoading(),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Color(0xFF00E5FF)),
          SizedBox(height: 12),
          Text(
            'INICIALIZANDO SENSOR DE CÁMARA...',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildViewfinder() {
    final controller = TacticalCameraService.controller;
    if (controller == null || !controller.value.isInitialized) {
      return _buildLoading();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        // ── HUD de telemetría en vivo ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            color: const Color(0xCC0A0B10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: ValueListenableBuilder<TacticalSnapshot?>(
              valueListenable: GpsService.telemetry,
              builder: (context, snapshot, _) {
                final bool fixed =
                    snapshot != null && (snapshot.lat != 0.0 || snapshot.lon != 0.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          fixed ? Icons.gps_fixed : Icons.gps_off,
                          color: fixed ? const Color(0xFF00FFAA) : const Color(0xFFFF2D55),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          fixed ? 'FIX GPS CONFIRMADO' : 'SIN FIJACIÓN GPS',
                          style: TextStyle(
                            color: fixed ? const Color(0xFF00FFAA) : const Color(0xFFFF2D55),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '📷 TELECAM',
                          style: TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _hudLine('LAT',
                        fixed ? snapshot.lat.toStringAsFixed(5) : 'N/D',
                        fixed ? const Color(0xFF00FFAA) : const Color(0xFFFF2D55)),
                    _hudLine('LON',
                        fixed ? snapshot.lon.toStringAsFixed(5) : 'N/D',
                        fixed ? const Color(0xFF00FFAA) : const Color(0xFFFF2D55)),
                    _hudLine('ALT',
                        snapshot?.altitudeM != null ? '${snapshot!.altitudeM!.round()} m' : 'N/D',
                        fixed ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55)),
                    _hudLine('VEL',
                        snapshot?.speedMps != null ? snapshot!.speedKtsLabel : 'N/D',
                        fixed ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55)),
                    _hudLine('RUMBO',
                        snapshot?.headingDeg != null ? snapshot!.headingLabel : 'N/D',
                        fixed ? const Color(0xFF00E5FF) : const Color(0xFFFF2D55)),
                    if (snapshot?.accuracyM != null)
                      _hudLine('PREC',
                          '±${snapshot!.accuracyM!.round()} m',
                          const Color(0xFFB388FF)),
                  ],
                );
              },
            ),
          ),
        ),
        // ── Controles superiores: flash y sensor ──
        Positioned(
          top: 0,
          right: 0,
          child: Column(
            children: [
              IconButton(
                onPressed: _toggleFlash,
                icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off,
                    color: _flashOn ? const Color(0xFFFFFF00) : Colors.white70),
                tooltip: 'Conmutar Flash',
              ),
              IconButton(
                onPressed: _switchCamera,
                icon: const Icon(Icons.cameraswitch, color: Colors.white70),
                tooltip: 'Cambiar sensor de cámara',
              ),
            ],
          ),
        ),
        // ── Botón de captura ──
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: GestureDetector(
                onTap: _capture,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF00E5FF), width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00E5FF),
                      ),
                      child: _capturing
                          ? const Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.camera_alt, color: Colors.black, size: 24),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // ── Botón cerrar ──
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white70),
              tooltip: 'Cerrar cámara táctica',
            ),
          ),
        ),
      ],
    );
  }

  Widget _hudLine(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}