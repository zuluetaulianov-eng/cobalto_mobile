/// HTML embebido del Mapa Táctico COBALTO (Leaflet). Contenido estático que se
/// inyecta en el WebView de la pestaña de mapa.
const String kMapHtmlContent = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>COBALTO Map</title>
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    html, body, #map {
      margin: 0; padding: 0; width: 100%; height: 100%;
      background-color: #0A0B10; font-family: monospace; color: #fff;
    }
    .leaflet-popup-content-wrapper {
      background: #141824; color: #fff; border: 1px solid #00E5FF;
      border-radius: 8px; font-family: monospace; font-size: 11px;
      box-shadow: 0 4px 15px rgba(0, 229, 255, 0.25);
      padding: 4px;
    }
    .leaflet-popup-tip { background: #141824; }
    
    /* Animación de Radar Pulsante en CSS */
    @keyframes pulseRing {
      0% { transform: scale(0.3); opacity: 0.9; }
      80% { transform: scale(1.8); opacity: 0.1; }
      100% { transform: scale(2.2); opacity: 0; }
    }
    .pulse-marker-critical {
      width: 24px; height: 24px;
      border-radius: 50%;
      background: rgba(255, 45, 85, 0.4);
      border: 2px solid #FF2D55;
      animation: pulseRing 1.8s infinite ease-out;
    }
    .pulse-marker-quake {
      width: 24px; height: 24px;
      border-radius: 50%;
      background: rgba(255, 149, 0, 0.4);
      border: 2px solid #FF9500;
      animation: pulseRing 2s infinite ease-out;
    }
    .pulse-marker-operator {
      width: 28px; height: 28px;
      border-radius: 50%;
      background: rgba(0, 255, 170, 0.4);
      border: 2px solid #00FFAA;
      animation: pulseRing 1.4s infinite ease-out;
    }
    .pulse-marker-cctv {
      width: 24px; height: 24px;
      border-radius: 50%;
      background: rgba(255, 214, 10, 0.35);
      border: 2px solid #FFD60A;
      animation: pulseRing 2.2s infinite ease-out;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map', { zoomControl: false }).setView([10.4806, -66.9036], 5);
    
    // Capa 1: Modo Oscuro Vectorial (CartoDB Dark)
    var darkTileLayer = L.tileLayer('https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png', {
      maxZoom: 18,
      subdomains: 'abcd',
      attribution: 'CartoDB Dark | COBALTO C4I'
    });

    // Capa 2: Modo Satelital HD (Esri World Imagery)
    var satTileLayer = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
      maxZoom: 18,
      attribution: 'Esri Satellite | COBALTO C4I'
    });

    darkTileLayer.addTo(map);
    L.control.zoom({ position: 'bottomright' }).addTo(map);

    var markersGroup = L.layerGroup().addTo(map);
    var pulsesGroup = L.layerGroup().addTo(map);
    var geofenceGroup = L.layerGroup().addTo(map);
    var currentFilter = 'ALL';

    var allPoints = [];

    function centerMap(lat, lon, zoom) {
      map.flyTo([lat, lon], zoom || 14);
    }

    function setTileMode(isSat) {
      if (isSat) {
        map.removeLayer(darkTileLayer);
        satTileLayer.addTo(map);
      } else {
        map.removeLayer(satTileLayer);
        darkTileLayer.addTo(map);
      }
    }

    function filterPoints(type) {
      currentFilter = type;
      markersGroup.clearLayers();
      pulsesGroup.clearLayers();

      allPoints.forEach(function(p) {
        if (type === 'ALL' || p.type === type) {
          // Anillos pulsantes para Alerta, Sismo, CCTV u Operador GPS
          if (p.type === 'ALERT' || p.type === 'QUAKE' || p.type === 'OPERATOR' || p.type === 'CCTV') {
            var pulseClass = 'pulse-marker-critical';
            if (p.type === 'QUAKE') pulseClass = 'pulse-marker-quake';
            if (p.type === 'OPERATOR') pulseClass = 'pulse-marker-operator';
            if (p.type === 'CCTV') pulseClass = 'pulse-marker-cctv';

            var pulseIcon = L.divIcon({
              className: pulseClass,
              iconSize: [28, 28],
              iconAnchor: [14, 14]
            });
            var pulseMarker = L.marker([p.lat, p.lon], { icon: pulseIcon, interactive: false });
            pulsesGroup.addLayer(pulseMarker);
          }

          var marker = L.circleMarker([p.lat, p.lon], {
            radius: p.type === 'BASE' ? 10 : 7,
            fillColor: p.color || '#00E5FF',
            color: '#ffffff',
            weight: 2,
            opacity: 1,
            fillOpacity: 0.9
          });

          marker.pointData = p;

          var html = "<div style='padding:4px;'>" +
                     "<strong style='color:" + (p.color || '#00E5FF') + "; font-size:12px;'>" + p.title + "</strong><br/>" +
                     "<div style='color:#ddd; margin-top:4px; margin-bottom:6px; line-height:1.3;'>" + p.desc + "</div>" +
                     "<div style='border-top:1px solid #333; padding-top:4px; color:#888; font-size:9px; display:flex; justify-content:space-between;'>" +
                       "<span>📍 " + p.lat.toFixed(4) + ", " + p.lon.toFixed(4) + "</span>" +
                       "<span style='color:#00E5FF; font-weight:bold;'>TOCA PARA ABRIR</span>" +
                     "</div>" +
                     "</div>";

          marker.bindPopup(html, { maxWidth: 260 });

          marker.on('click', function(e) {
            if (window.FlutterBridge && e.target.pointData) {
              window.FlutterBridge.postMessage(JSON.stringify(e.target.pointData));
            }
          });

          markersGroup.addLayer(marker);
        }
      });
    }

    function updatePoints(newPoints) {
      if (Array.isArray(newPoints)) {
        allPoints = newPoints;
        filterPoints(currentFilter);
      }
    }

    function updateGeofences(zones) {
      geofenceGroup.clearLayers();
      if (!Array.isArray(zones)) return;
      zones.forEach(function(z) {
        var zoneColor = z.threatLevel === 'CRÍTICA' ? '#FF2D55'
          : z.threatLevel === 'ALTA' ? '#FF9500'
          : '#00E5FF';
        var circle = L.circle([z.lat, z.lng], {
          radius: z.radiusKm * 1000,
          color: zoneColor,
          weight: 2,
          dashArray: '6 4',
          fillColor: zoneColor,
          fillOpacity: 0.12,
          interactive: false
        });
        geofenceGroup.addLayer(circle);
      });
    }
  </script>
</body>
</html>
''';