# 🛰️ COBALTO MOBILE — Autonomous Tactical Intelligence Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Android](https://img.shields.io/badge/Android-APK-3DDC84?style=for-the-badge&logo=android&logoColor=white)](https://developer.android.com)
[![OSINT](https://img.shields.io/badge/Capability-OSINT%20%26%20C4I-00E5FF?style=for-the-badge)](https://github.com)
[![License](https://img.shields.io/badge/Security-TACTICAL-red?style=for-the-badge)](https://github.com)

**COBALTO MOBILE** es una plataforma autónoma de inteligencia táctica, OSINT y monitoreo situacional diseñada para dispositivos Android. Funciona de manera **100% independiente en el dispositivo (Air-Gapped / Offline)** realizando scraping e ingesta local de noticias, o en modo **Enlace Estación Base** sincronizándose con el ecosistema central de COBALTO HUB.

---

## 🚀 Características Principales

- **📱 Motor Autónomo de Extracción OSINT:** Scrapea directamente desde el teléfono más de 20 fuentes RSS internacionales/regionales y canales públicos de Telegram (`t.me/s/...`) sin depender de servidor externo.
- **🖼️ Tarjetas Visuales con Imágenes Destacadas:** Visualización táctica estilo COBALTO PC con renderizado adaptativo de fotografías en las noticias.
- **🗺️ Mapa Táctico Interactivo (Leaflet Dark Matter):** Visor cartográfico ciberpunk integrado con capas seleccionables (Alertas, Sismos USGS, Noticias, CCTV Caribe, Base Caracas) y popups interactivos.
- **🔍 Herramientas OSINT Recon:** Suite integrada para consultas WHOIS, DNS Lookup, Geolocalización IP y Búsqueda de Vulnerabilidades NVD (CVE).
- **🛡️ Módulo OFAC & Cripto-Inteligencia:** Verificación instantánea de entidades sancionadas OFAC SDN y balance de wallets Bitcoin (BTC) en tiempo real.
- **🤖 Motor de IA Conversacional & Asistente Local:** Chat conversacional con agentes especializados (General, ARES, MINERVA, NEXUS) que conmuta a un **Asistente Táctico Móvil Autónomo** en ausencia de conectividad.
- **⚙️ Panel de Configuración de 5 Sub-Pestañas:** Personalización de enlace, chips interactivos de palabras clave, gestión de fuentes de ingesta, host de Ollama local y limpieza de memoria.

---

## 🏛️ Arquitectura de la Interfaz (9 Pestañas Tácticas)

| Icono | Pestaña | Propósito Táctico |
|---|---|---|
| 📰 | **SitRep** | Feed de novedades con filtrado por relevancia, persistencia SQLite `cobalto_edge.db` e imágenes destacadas. |
| 🗺️ | **Mapa** | Cartografía interactiva Leaflet Dark Matter con capas filtrables. |
| ⚠️ | **Alertas** | Sistema de criticidad heurística local (🔴 Crítica, 🟠 Alta, 🟡 Urgente). |
| 🎯 | **HUMINT** | Captura de reportes de campo con coordenadas GPS, fotos, nivel de amenaza y sync híbrido. |
| 🛠️ | **Recon** | Kit OSINT de geolocalización, WHOIS, DNS y CVEs (Modo directo e integración OSIRIS). |
| 🔍 | **OFAC** | Verificador de sanciones globales y trazabilidad Blockchain. |
| 🤖 | **IA Chat** | Consola táctica interactiva conectada a Ollama / Asistente Local. |
| 📡 | **Vivo** | Telemetría de sismos USGS y sensores situacionales. |
| ⚙️ | **Ajustes** | Centro de control de 5 sub-pestañas para fuentes, palabras clave y enlace. |

---

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

## 🔒 Modos Operativos

1. **Modo Autónomo (Dispositivo):**  
   Ideal para operaciones de campo con conectividad limitada o restringida. La App ejecuta la ingesta RSS/Telegram, clasifica las alertas y responde consultas mediante el motor local sin requerir la PC.

2. **Modo Enlace Estación Base (PC):**  
   Conecta mediante HTTP/JSON con la instancia central de COBALTO HUB para sincronizar palabras clave, reportes consolidados y delegar consultas RAG avanzadas a Ollama/NVIDIA API.

---

## 📄 Licencia y Seguridad
Uso reservado para investigación OSINT, análisis situacional y gestión de inteligencia operacional.  
**Desarrollado por el Ecosistema COBALTO HUB.**
