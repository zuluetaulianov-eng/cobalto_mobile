# 🛰️ COBALTO MOBILE — Autonomous Tactical Intelligence Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-APK-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com)
[![OSINT](https://img.shields.io/badge/Capability-OSINT%20%26%20C4I-00E5FF?style=for-the-badge)](https://github.com)
[![Security](https://img.shields.io/badge/Security-AES--256%20KEYSTORE-30D158?style=for-the-badge)](https://github.com)
[![Status](https://img.shields.io/badge/Status-ESTABLE%20%26%20OPTIMIZADO-00FFAA?style=for-the-badge)](https://github.com)

**COBALTO MOBILE** es una plataforma autónoma de inteligencia táctica, OSINT y monitoreo situacional diseñada para dispositivos Android. Permite operar **independiente en el dispositivo (Offline / Air-Gapped)** realizando scraping e ingesta local de noticias, o en modo **Enlace Estación Base** sincronizándose con el ecosistema central de COBALTO HUB.

---

## 🚀 Evolución Táctica Implementada & Optimizaciones de Rendimiento

```mermaid
graph TD
    A["✅ Fase 1: GPS & Geofencing Táctico"] --> B["✅ Fase 2: Voz Táctica STT / TTS"]
    B --> C["✅ Fase 3: Bóveda Cifrada AES-256-GCM"]
    C --> D["✅ Fase 4: Cámara Telemetría Isolate"]
    D --> E["✅ Fase 5: Widget Nativo Pantalla Inicio"]
    E --> F["✅ Capacidad Táctica: Modo Sigilo (NVG)"]
    F --> G["✅ Capacidad Táctica: Escáner OCR Offline"]
    G --> H["✅ Capacidad Táctica: Dead Man's Switch (SOS)"]
    H --> I["⚡ Estabilización: Multi-Isolates & Anti-ANR"]
```

### 1. 👁️ Modo Sigilo / Visión Nocturna (NVG) (`StealthService`)
- Interfaz táctica de **bajo perfil fotónico** con tonos rojos/negros monocromáticos (`0xFF080000`) para minimizar la firma de luz del operador en ambientes oscuros.
- Retroalimentación háptica silenciosa en patrones de código Morse según el nivel de alerta.

### 2. 🔤 Escáner OCR Táctico 100% Offline (`TacticalOcrService`)
- Procesamiento en el dispositivo utilizando Google MLKit para extraer instantáneamente texto, matrículas/placas, códigos de serie y coordenadas GPS desde fotografías o la galería de imágenes sin conexión a internet.

### 3. 🚨 Monitor de Hombre Muerto / Inmovilidad (`DeadManSwitchService`)
- Muestreo optimizado a 10Hz del acelerómetro para detectar impactos bruscos (>2.8G libre + gravedad) o caídas del operador.
- Desencadena una cuenta regresiva de emergencia de **30 segundos** con opción de cancelación manual antes de transmitir la señal de SOS a la estación base (endpoint `/api/sos`, con fallback al reporte HUMINT) y registro local cifrado del evento.

### 4. ⚡ Estabilización del Sistema & Aislamiento de Hilos (Isolates)
- **Procesamiento de Imágenes en Isolates (`compute`)**: La decodificación y estampado de telemetría GPS/UTC en fotos de cámara se ejecuta en Isolates secundarios, previniendo bloqueos del hilo principal (ANR).
- **Gestión de Memoria RAM**: Activación de `android:largeHeap="true"` y optimización de renderizado PNG (`pixelRatio: 2.0`) en el generador de fichas infográficas.
- **Android 14+ Foreground Service Compliance**: Declaración explícita de permisos de servicio en segundo plano (`FOREGROUND_SERVICE_DATA_SYNC`, `FOREGROUND_SERVICE_LOCATION`) para evitar terminaciones por el SO.

### 5. 📱 Widget Nativo para Pantalla de Inicio en Android (`WidgetService`)
- Transmisión en tiempo real del nivel **DEFCON**, conteo de **alertas activas** y el **titular SitRep más reciente** a la pantalla de inicio del teléfono (`cobalto_widget_layout.xml`).

---

## 🏛️ Arquitectura de la Interfaz (9 Pestañas Tácticas)

| Icono | Pestaña | Propósito Táctico |
|---|---|---|
| 📰 | **SitRep** | Feed de novedades con filtrado por relevancia, persistencia SQLite `cobalto_edge.db` y exportación de tarjetas PNG HD optimizadas. |
| 🗺️ | **Mapa** | Cartografía interactiva Leaflet (Modo Vectorial Oscuro / Satelital HD) con radar GPS del operador en vivo. |
| ⚠️ | **Alertas** | Sistema de criticidad de incidentes con avisos de geocerca, notificaciones Android y lectura por voz sintetizada (TTS). |
| 🎯 | **HUMINT** | Captura de reportes de campo cifrados con dictado por voz (STT), coordenadas GPS y sincronización de servidor. |
| 🛠️ | **Recon** | Kit OSINT (WHOIS, DNS, IP Geoloc, CVEs), Escáner OCR Offline y Cámara Táctica con telemetría en Isolate. |
| 🔍 | **OFAC** | Verificador de sanciones globales, listas SDN y trazabilidad Blockchain en tiempo real. |
| 🤖 | **IA Chat** | Consola táctica interactiva con selección de personas (`GENERAL`, `ARES`, `MINERVA`, `NEXUS`) y motor autónomo local. |
| 📡 | **Vivo** | Telemetría de vuelos comerciales/militares y sensores telúricos/térmicos en tiempo real (USGS / FIRMS). |
| ⚙️ | **Ajustes** | Centro de control de parámetros con conmutador NVG, probador SOS de Hombre Muerto y limpiador de caché. |

---

## 🛡️ Seguridad

- **Cifrado de datos en reposo:** bóveda **AES-256-GCM** (autenticación AEAD) con clave maestra de 32 bytes generada aleatoriamente y custodiada en el Android Keystore / Secure Storage. Los datos cifrados usan formato versionado `ENCv2:`; los registros legacy se migran automáticamente.
- **Credenciales de operador:** se inyectan en tiempo de build mediante `--dart-define` (nunca embebidas en el repositorio) y la contraseña se persiste únicamente en Secure Storage, no en SharedPreferences en claro.
- **Autenticación:** el acceso exige un JWT emitido por `/api/login`. No existen tokens de override ni bypass para credenciales por defecto.
- **Transporte:** en builds de producción el tráfico en claro (HTTP) está prohibido por `network_security_config`; solo el build de DEBUG permite cleartext hacia la LAN de desarrollo y Ollama. Para despliegues productivos use TLS/HTTPS.

## 📋 Requisitos de Sistema

- **SDK de Flutter:** 3.19.0 o superior
- **Dart SDK:** 3.3.0 o superior
- **SO Objetivo:** Android 8.0 (API 26) en adelante
- **Herramientas de Compilación:** Java JDK 17, Android Studio / Gradle

---

## ⚙️ Instalación y Compilación

### 1. Clonar el repositorio del cliente móvil
```bash
git clone https://github.com/tu-usuario/cobalto-mobile.git
cd cobalto-mobile
```

### 2. Obtener dependencias de Flutter
```bash
flutter pub get
```

### 3. (Opcional) Inyectar credenciales por defecto en tiempo de build
```bash
flutter build apk --release \
  --dart-define=COBALTO_DEFAULT_USERNAME=operador \
  --dart-define=COBALTO_DEFAULT_PASSWORD=tusecreto
```
Sin estos define, los campos de credenciales inician vacíos.

### 3. Verificar sintaxis
```bash
flutter analyze
```

### 4. Compilar APK de Producción
```bash
flutter build apk --release
```
El instalador APK generado se ubicará en:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 📄 Licencia y Seguridad
Uso reservado para investigación OSINT, análisis situacional y gestión de inteligencia operacional.  
**Desarrollado por el Ecosistema COBALTO HUB.**
