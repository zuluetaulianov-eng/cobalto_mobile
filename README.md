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
    I --> J["✅ Fase 6: Telemetría GPS en Vivo & HUD Cámara"]
    J --> K["✅ Fase 7: Sistema de Emergencias Integral (Pánico/Duress/Heartbeat/Sirena)"]
    K --> L["⚡ Optimización: Ciclo de Vida & Navegación Responsiva"]
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

### 6. 🛰️ Telemetría GPS en Vivo & HUD de Cámara Táctica (`GpsService`, `TacticalCameraService`)
- **Snapshot táctico unificado** (`TacticalSnapshot`): lat/lon, altitud, rumbo, velocidad (KT), precisión y timestamp UTC expuesto como `ValueNotifier` en vivo compartido por mapa, HUD, geocercas y SOS — con `distanceFilter: 5 m` para ahorrar batería.
- **Cámara táctica con HUD en vivo**: overlay de telemetría GPS en tiempo real, flash, conmutación de sensor y **linterna de emergencia** (torch).
- **Forense fotográfico**: cada captura genera un sidecar JSON con SHA-256, coordenadas y UTC, registra un `FieldReport` y se sube a `/api/humint/report`; sin fix, muestra **"SIN FIJACIÓN"** (nunca estampa coordenadas falsas).

### 7. 🆘 Sistema de Emergencias Integral (`EmergencyService`)
- **Botón PÁNICO global** con retención de 3 s (anti-activación accidental) que transmite SOS con telemetría fresca (fallback a fijación puntual si el stream está obsoleto).
- **Coacción (Duress)**: contraseña camuflada en el login que entra con normalidad aparente mientras transmite un SOS silencioso.
- **Sirena de localización** (`EmergencyAlarmScreen`): estroboscopio rojo ~2.5 Hz, patrón háptico SOS, linterna, telemetría en vivo y cancelación explícita; el botón "atrás" del sistema queda **bloqueado** (PopScope).
- **Heartbeat de telemetría**: latido periódico (`/api/sos`) para que la base detecte la pérdida del operador; intervalo y activación configurables.
- **Escalada a contacto**: sin ACK del servidor, intenta SMS y llamada al contacto de emergencia configurado.
- **Timeline forense** (`emergency_log` en SQLite v3) con registro de pánico, coacción, escaladas y cancelaciones.
- **Dead Man's Switch mejorado**: detección de caída + inmovilización + **arrastre/transporte**, foto de contexto automática y cancelación por cualquier toque.

### 8. 🔋 Gestión de Poder & 🧭 Navegación Responsiva
- **Ciclo de vida** (`PowerManagementService`): al pasar a segundo plano se suspende el stream GPS continuo (el mayor consumo) y se restaura al volver; los servicios de seguridad (dead-man, heartbeat) permanecen activos.
- **Navegación responsiva**: la barra inferior reduce de 9 a **5 módulos esenciales** (SitRep, Mapa, Alertas, IA Chat, Ajustes) con tipografía 12 px legible; el resto (HUMINT, Recon, OFAC, Vivo) queda en un **cajón "MÓDULOS"**. En tabletas / apaisado (≥600 dp) se usa un **panel lateral** (`NavigationRail`).
- **AppBar compacto**: solo el botón de pánico; NVG y chip de identidad de red viven en una franja de estado táctica sin saturar la barra superior.

---

## 🏛️ Arquitectura de la Interfaz (Navegación Responsiva)

La app expone **9 módulos tácticos**. En teléfonos, la barra inferior muestra los **5 esenciales** (SitRep, Mapa, Alertas, IA Chat, Ajustes) y el resto se alcanza desde el **cajón "MÓDULOS COBALTO C4I"** (icono ☰); en tabletas / apaisado el cuerpo cambia a panel lateral.

| Icono | Módulo | Propósito Táctico |
|---|---|---|
| 📰 | **SitRep** | Feed de novedades con filtrado por relevancia, persistencia SQLite `cobalto_edge.db` y exportación de tarjetas PNG HD optimizadas. |
| 🗺️ | **Mapa** | Cartografía interactiva Leaflet (Modo Vectorial Oscuro / Satelital HD) con radar GPS del operador en vivo. |
| ⚠️ | **Alertas** | Sistema de criticidad de incidentes con avisos de geocerca, notificaciones Android y lectura por voz sintetizada (TTS). |
| 🎯 | **HUMINT** | Captura de reportes de campo cifrados con dictado por voz (STT), coordenadas GPS y sincronización de servidor. |
| 🛠️ | **Recon** | Kit OSINT (WHOIS, DNS, IP Geoloc, CVEs), Escáner OCR Offline y Cámara Táctica HUD con telemetría en vivo. |
| 🔍 | **OFAC** | Verificador de sanciones globales, listas SDN y trazabilidad Blockchain en tiempo real. |
| 🤖 | **IA Chat** | Consola táctica interactiva con selección de personas (`GENERAL`, `ARES`, `MINERVA`, `NEXUS`), dictado por voz y lectura de respuestas. |
| 📡 | **Vivo** | Telemetría de vuelos comerciales/militares y sensores telúricos/térmicos en tiempo real (USGS / FIRMS). |
| ⚙️ | **Ajustes** | Centro de control con conmutador NVG, calibración del monitor de hombre muerto, **plan de emergencia** (contacto, heartbeat, código de coacción) y limpiador de caché. |

> **Franja de estado táctica**: bajo el AppBar se muestra el conmutador de sigilo (NVG), el estado de red y, cuando aplica, la franja de vigilancia del dead-man y el banner de SOS.

---

## 🛡️ Seguridad

- **Cifrado de datos en reposo:** bóveda **AES-256-GCM** (autenticación AEAD) con clave maestra de 32 bytes generada aleatoriamente y custodiada en el Android Keystore / Secure Storage. Los datos cifrados usan formato versionado `ENCv2:`; los registros legacy se migran automáticamente.
- **Credenciales de operador:** se inyectan en tiempo de build mediante `--dart-define` (nunca embebidas en el repositorio) y la contraseña se persiste únicamente en Secure Storage, no en SharedPreferences en claro.
- **Autenticación:** el acceso exige un JWT emitido por `/api/login`. No existen tokens de override ni bypass para credenciales por defecto.
- **Transporte:** en builds de producción el tráfico en claro (HTTP) está prohibido por `network_security_config`; solo el build de DEBUG permite cleartext hacia la LAN de desarrollo y Ollama. Para despliegues productivos use TLS/HTTPS.

## 📋 Requisitos de Sistema

- **SDK de Flutter:** 3.22 o superior (probado en **3.44 stable**)
- **Dart SDK:** 3.6 o superior
- **SO Objetivo:** Android 8.0 (API 26) en adelante
- **Herramientas de Compilación:** Java JDK 17, Android Studio / Gradle

---

## ⚙️ Instalación y Compilación

### 1. Clonar el repositorio del cliente móvil
```bash
git clone https://github.com/zuluetaulianov-eng/cobalto_mobile.git
cd cobalto_mobile
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
