/**
 * BUS CONECTADO • APLICACIÓN DE ADMINISTRACIÓN DE PARADEROS (TACNA)
 * Gestión visual en mapa, reubicación directa con Drag & Drop, creación, edición y exportación a iOS.
 * Módulo colaborativo en tiempo real estilo Google Docs con WebSockets.
 */

// Administrador General Autenticado Oficial
const CURRENT_ADMIN = {
  id: 'USR-ADM-001',
  username: 'aron.quispe',
  name: 'Aron Quispe',
  role: 'Administrador General',
  dni: '70881234',
  avatar: 'AQ',
  color: '#2563EB'
};

const PROFILES = [CURRENT_ADMIN];

// Estado global de la aplicación
const state = {
  activeModule: 'stops',     // 'stops' | 'routes' | 'pos' | 'users' | 'stats'
  stops: [],
  routes: [],
  posTerminals: [],
  transactions: [],
  users: [],
  posFilterRoute: 'all',
  posFilterMethod: 'all',
  posSearchText: '',
  userFilterRole: 'all',
  userSearchText: '',
  selectedStopId: null,
  selectedRouteId: null,
  activeFilter: 'all',
  activeRouteFilter: 'all',
  searchQuery: '',
  routeSearchQuery: '',
  showAllRoutesOnMap: false,
  map: null,
  markersMap: new Map(),     // Map<stopId, L.Marker>
  routeLayersGroup: null,    // L.LayerGroup para polilíneas y nodos de secuencia de rutas
  activeTileLayer: null,
  tileLayers: {},
  pickingCoordsMode: false,
  relocatingStopId: null,    // ID del paradero actualmente en proceso de reubicación
  originalCoords: null,      // { lat, lng } para restaurar si el usuario cancela
  tempCoords: null,          // { lat, lng } posición en tiempo real mientras se mueve
  tracingRouteId: null,      // ID de la ruta actualmente en modo trazado interactivo en el mapa
  tempTraceNodes: [],        // Nodos de control [{ lat, lng, stopId, streetName }] alineados a calles
  tempTraceSegments: [],     // Tramos viales [[[lat, lng], ...]] entre cada par de nodos consecutivos
  tempTraceCoords: [],       // Polilínea densa [[lat, lng], ...] alineada a las calles de Tacna
  tempTraceStopIds: [],      // IDs de paraderos asociados durante el trazado
  tempTraceClosedLoop: false, // Indica si la ruta volvió al Nodo #1 (inicio/fin obligatorio)
  isRoutingStreet: false,    // Indicador de consulta activa al motor vial OSRM
  modalSelectedStopIds: [],  // IDs de paraderos seleccionados en orden dentro del modal de ruta
  currentUser: CURRENT_ADMIN, // Administrador General autenticado
  activeUsers: [],           // Usuarios conectados al WebSocket
  lockedStops: {},           // { [stopId]: user } paraderos bloqueados en tiempo real
  ws: null,                  // Instancia WebSocket
  lastDragBroadcastTime: 0
};

// ═══════════════════════════════════════════════════════════════════════
// INICIALIZACIÓN
// ═══════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', async () => {
  loadStoredProfile();

  // 1. Iniciar mapa, listeners y WebSocket en paralelo
  initLeafletMap();
  setupUIEventListeners();
  setupDialogLightDismiss();
  initCollaborationWebSocket();

  // 2. Validar con servidor (fuente de verdad) y cargar catálogo, usuarios y POS
  await Promise.all([loadStopsData(), loadRoutesData(), loadUsersData(), loadPosData()]);
  renderMapMarkers();
  renderMapRoutes();
  renderStopsList();
  renderRoutesList();
  updateStats();
  updateRouteStats();
});

// ═══════════════════════════════════════════════════════════════════════
// GESTIÓN DE PERFILES Y WEBSOCKETS EN TIEMPO REAL
// ═══════════════════════════════════════════════════════════════════════

function loadStoredProfile() {
  state.currentUser = CURRENT_ADMIN;
  updateProfileUI();
}

function updateProfileUI() {
  const avatarEl = document.getElementById('collab-my-avatar');
  const nameEl = document.getElementById('collab-my-name');
  const subEl = document.getElementById('collab-my-sub');
  if (avatarEl) {
    avatarEl.textContent = state.currentUser.avatar;
    avatarEl.style.backgroundColor = state.currentUser.color;
    avatarEl.style.boxShadow = `0 0 10px ${state.currentUser.color}`;
  }
  if (nameEl) {
    nameEl.textContent = state.currentUser.name;
  }
  if (subEl) {
    subEl.textContent = `${state.currentUser.role} • DNI ${state.currentUser.dni}`;
  }
}

function initCollaborationWebSocket() {
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  const host = window.location.host || 'localhost:8000';
  const wsUrl = `${protocol}//${host}/ws`;

  try {
    const ws = new WebSocket(wsUrl);
    state.ws = ws;

    ws.onopen = () => {
      console.log('⚡ [Collab] Conectado a canal en tiempo real estilo Google Docs');
      sendWsMessage({ type: 'join', user: state.currentUser });
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        handleCollabMessage(msg);
      } catch (err) {
        console.warn('[WS] Error parseando mensaje', err);
      }
    };

    ws.onclose = () => {
      setTimeout(initCollaborationWebSocket, 2500);
    };

    ws.onerror = () => {};
  } catch (err) {
    console.warn('[WS] Error inicializando WebSocket', err);
  }
}

function sendWsMessage(msg) {
  if (state.ws && state.ws.readyState === WebSocket.OPEN) {
    state.ws.send(JSON.stringify(msg));
  }
}

function handleCollabMessage(msg) {
  switch (msg.type) {
    case 'presence_update':
      state.activeUsers = msg.activeUsers || [];
      state.lockedStops = msg.lockedStops || {};
      renderPresenceStrip();
      updateStopLocksUI();
      break;

    case 'stop_locked':
      state.lockedStops[msg.stopId] = msg.user;
      updateStopLocksUI();
      if (msg.user && msg.user.id !== state.currentUser.id) {
        const stop = state.stops.find(s => s.id === msg.stopId);
        const name = stop ? (stop.shortName || stop.name) : 'Paradero';
        showRemoteBanner(`${msg.user.name} está reubicando "${name}"...`);
      }
      break;

    case 'stop_unlocked':
      delete state.lockedStops[msg.stopId];
      updateStopLocksUI();
      hideRemoteBanner();
      break;

    case 'stop_moving':
      if (msg.user && msg.user.id !== state.currentUser.id) {
        const remoteMarker = state.markersMap.get(msg.stopId);
        if (remoteMarker) {
          remoteMarker.setLatLng([msg.lat, msg.lng]);
        }
        const stop = state.stops.find(s => s.id === msg.stopId);
        const name = stop ? (stop.shortName || stop.name) : 'Paradero';
        showRemoteBanner(`${msg.user.name} moviendo "${name}" a [${msg.lat.toFixed(5)}, ${msg.lng.toFixed(5)}]`);
      }
      break;

    case 'stop_saved':
      const idx = state.stops.findIndex(s => s.id === msg.stop.id);
      if (idx >= 0) {
        state.stops[idx] = msg.stop;
      } else {
        state.stops.push(msg.stop);
      }
      delete state.lockedStops[msg.stop.id];
      hideRemoteBanner();
      renderMapMarkers();
      renderStopsList();
      updateStats();
      if (msg.user && msg.user.id !== state.currentUser.id) {
        showToast(`⚡ ${msg.user.name} guardó la nueva posición de "${msg.stop.name}"`);
      }
      break;

    case 'stop_deleted':
      state.stops = state.stops.filter(s => s.id !== msg.stopId);
      delete state.lockedStops[msg.stopId];
      const m = state.markersMap.get(msg.stopId);
      if (m) {
        state.map.removeLayer(m);
        state.markersMap.delete(msg.stopId);
      }
      renderStopsList();
      updateStats();
      if (msg.user && msg.user.id !== state.currentUser.id) {
        showToast(`⚡ ${msg.user.name} eliminó un paradero.`);
      }
      break;

    case 'stops_reloaded':
      if (msg.stops && Array.isArray(msg.stops)) {
        state.stops = msg.stops;
        renderMapMarkers();
        renderMapRoutes();
        renderStopsList();
        renderRoutesList();
        updateStats();
        updateRouteStats();
      }
      break;

    case 'route_saved':
    case 'route_deleted':
    case 'routes_reloaded':
      if (msg.routes && Array.isArray(msg.routes)) {
        state.routes = msg.routes;
        localStorage.setItem('bc_admin_routes', JSON.stringify(state.routes));
      }
      if (msg.stops && Array.isArray(msg.stops) && msg.stops.length > 0) {
        state.stops = msg.stops;
        localStorage.setItem('bc_admin_stops', JSON.stringify(state.stops));
      }
      renderMapMarkers();
      renderMapRoutes();
      renderStopsList();
      renderRoutesList();
      updateStats();
      updateRouteStats();
      if (msg.user && msg.user.id !== state.currentUser.id) {
        showToast(`⚡ ${msg.user.name} actualizó el catálogo de rutas.`);
      }
      break;
  }
}

function renderPresenceStrip() {
  const container = document.getElementById('collab-presence-pills');
  if (!container) return;

  if (state.activeUsers.length === 0) {
    container.innerHTML = `<span class="presence-pill"><span class="presence-dot"></span> ${escapeHtml(state.currentUser.name)} (Tú)</span>`;
    return;
  }

  const uniqueUsers = [];
  const seenIds = new Set();
  for (const u of state.activeUsers) {
    if (!seenIds.has(u.id)) {
      seenIds.add(u.id);
      uniqueUsers.push(u);
    }
  }

  container.innerHTML = uniqueUsers.map(u => {
    const isMe = u.id === state.currentUser.id;
    return `
      <span class="presence-pill" style="border-color: ${u.color || '#38BDF8'};">
        <span class="presence-dot" style="background: ${u.color || '#10B981'};"></span>
        ${escapeHtml(u.name)}${isMe ? ' (Tú)' : ''}
      </span>
    `;
  }).join('');
}

function updateStopLocksUI() {
  state.stops.forEach(stop => {
    const pinEl = document.getElementById(`pin-${stop.id}`);
    if (!pinEl) return;

    const lock = state.lockedStops[stop.id];
    const isLockedByOther = lock && lock.id !== state.currentUser.id;

    const oldRing = pinEl.querySelector('.marker-locked-ring');
    const oldBadge = pinEl.querySelector('.marker-locked-badge');
    if (oldRing) oldRing.remove();
    if (oldBadge) oldBadge.remove();

    if (isLockedByOther) {
      pinEl.classList.add('is-remote-locked');
      const ring = document.createElement('div');
      ring.className = 'marker-locked-ring';
      const badge = document.createElement('div');
      badge.className = 'marker-locked-badge';
      badge.textContent = `🔒 ${lock.name || 'Admin'}`;
      pinEl.appendChild(ring);
      pinEl.appendChild(badge);
    } else {
      pinEl.classList.remove('is-remote-locked');
    }
  });
}

function showRemoteBanner(text) {
  const banner = document.getElementById('collab-remote-banner');
  const textEl = document.getElementById('collab-remote-text');
  if (banner && textEl) {
    textEl.textContent = text;
    banner.style.display = 'flex';
  }
}

function hideRemoteBanner() {
  const banner = document.getElementById('collab-remote-banner');
  if (banner) {
    banner.style.display = 'none';
  }
}

// Obtener la URL base del backend dinámicamente según el host (local o cloud)
function getBackendBaseUrl() {
  if (window.location.protocol.startsWith('http')) {
    return window.location.origin;
  }
  return 'http://localhost:8000';
}

function hydrateStopsFromLocalCache() {
  const localSaved = localStorage.getItem('bc_admin_stops');
  if (!localSaved) return false;
  try {
    const localData = JSON.parse(localSaved);
    if (Array.isArray(localData) && localData.length > 0) {
      state.stops = localData;
      return true;
    }
  } catch (e) {
    console.warn('Error al leer caché local de paraderos', e);
  }
  return false;
}

function hydrateRoutesFromLocalCache() {
  const localSaved = localStorage.getItem('bc_admin_routes');
  if (!localSaved) return false;
  try {
    const localData = JSON.parse(localSaved);
    if (Array.isArray(localData) && localData.length > 0) {
      state.routes = localData;
      return true;
    }
  } catch (e) {
    console.warn('Error al leer caché local de rutas', e);
  }
  return false;
}

async function fetchWithTimeout(url, options = {}, timeoutMs = 8000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

// Cargar paraderos desde Backend local/cloud, localStorage o archivo JSON predeterminado
async function loadStopsData() {
  const backendBase = getBackendBaseUrl();

  // 1. Intentar cargar desde el Backend (aprovechando ETag 304 con cache: 'no-cache')
  try {
    const res = await fetchWithTimeout(`${backendBase}/api/v1/transit/stops`, { cache: 'no-cache' });
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data)) {
        state.stops = data;
        localStorage.setItem('bc_admin_stops', JSON.stringify(state.stops));
        const syncStatus = document.getElementById('sync-status');
        if (syncStatus) {
          const hostLabel = window.location.host || 'Cloud Backend';
          syncStatus.innerHTML = `<span class="status-dot"></span> Conectado a Servidor (${hostLabel})`;
        }
        return;
      }
    }
  } catch (e) {
    // Backend no activo o error de red, continuar con caché local
  }

  // 2. Si el backend no respondió, usar caché local si ya existe
  if (state.stops.length > 0 || hydrateStopsFromLocalCache()) {
    return;
  }

  // 3. Fallback estático a archivo paraderos_tacna.json
  try {
    const res = await fetchWithTimeout('paraderos_tacna.json', { cache: 'no-cache' });
    const fallback = await res.json();
    if (Array.isArray(fallback) && fallback.length > 0) {
      state.stops = fallback;
      saveToLocalStorage();
    }
  } catch (err) {
    console.error('Error cargando paraderos_tacna.json', err);
  }
}

function saveToLocalStorage() {
  localStorage.setItem('bc_admin_stops', JSON.stringify(state.stops));
  const syncStatus = document.getElementById('sync-status');
  if (syncStatus) {
    syncStatus.innerHTML = '<span class="status-dot"></span> Guardando cambios...';
  }
  syncWithBackendServer();
}

// Sincronización en vivo con el Servidor Backend (Cloud o Local)
async function syncWithBackendServer() {
  const syncStatus = document.getElementById('sync-status');
  const backendBase = getBackendBaseUrl();

  try {
    const res = await fetch(`${backendBase}/api/v1/transit/stops`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(state.stops)
    });
    if (res.ok) {
      if (syncStatus) {
        const hostLabel = window.location.host || 'Cloud Backend';
        syncStatus.innerHTML = `<span class="status-dot"></span> Sincronizado en vivo con Servidor (${hostLabel})`;
      }
      return true;
    }
  } catch (err) {
    if (syncStatus) {
      syncStatus.innerHTML = '<span class="status-dot"></span> Guardado localmente (Backend offline)';
    }
  }
  return false;
}

// Cargar catálogo de rutas (Ordinarias y Externas) desde Backend, localStorage o rutas_tacna.json
async function loadRoutesData() {
  const backendBase = getBackendBaseUrl();

  try {
    const res = await fetchWithTimeout(`${backendBase}/api/v1/transit/routes`, { cache: 'no-cache' });
    if (res.ok) {
      const data = await res.json();
      if (Array.isArray(data)) {
        state.routes = data;
        localStorage.setItem('bc_admin_routes', JSON.stringify(state.routes));
        return;
      }
    }
  } catch (e) {
    // Continuar con caché local
  }

  if (state.routes.length > 0 || hydrateRoutesFromLocalCache()) {
    return;
  }

  try {
    const res = await fetchWithTimeout('rutas_tacna.json', { cache: 'no-cache' });
    const fallback = await res.json();
    if (Array.isArray(fallback) && fallback.length > 0) {
      state.routes = fallback;
      localStorage.setItem('bc_admin_routes', JSON.stringify(state.routes));
    }
  } catch (err) {
    console.error('Error cargando rutas_tacna.json', err);
  }
}

function syncStopsFromRoutesLocally() {
  const mapStopRoutes = {};
  state.stops.forEach(s => { mapStopRoutes[s.id] = []; });
  state.routes.forEach(r => {
    const code = (r.code || '').trim();
    if (!code) return;
    (r.keyStopIds || []).forEach(sid => {
      if (mapStopRoutes[sid] && !mapStopRoutes[sid].includes(code)) {
        mapStopRoutes[sid].push(code);
      }
    });
  });
  state.stops.forEach(s => {
    s.routesPassing = mapStopRoutes[s.id] || [];
  });
  localStorage.setItem('bc_admin_stops', JSON.stringify(state.stops));
}

function saveRoutesToLocalStorage() {
  syncStopsFromRoutesLocally();
  localStorage.setItem('bc_admin_routes', JSON.stringify(state.routes));
  const syncStatus = document.getElementById('sync-status');
  if (syncStatus) {
    syncStatus.innerHTML = '<span class="status-dot"></span> Sincronizando rutas...';
  }
  syncRoutesWithBackendServer();
}

async function syncRoutesWithBackendServer() {
  const syncStatus = document.getElementById('sync-status');
  const backendBase = getBackendBaseUrl();

  try {
    const res = await fetch(`${backendBase}/api/v1/transit/routes`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(state.routes)
    });
    if (res.ok) {
      const result = await res.json();
      if (result.stops && Array.isArray(result.stops)) {
        state.stops = result.stops;
        localStorage.setItem('bc_admin_stops', JSON.stringify(state.stops));
      }
      if (syncStatus) {
        const hostLabel = window.location.host || 'Cloud Backend';
        syncStatus.innerHTML = `<span class="status-dot"></span> Rutas y Paraderos sincronizados (${hostLabel})`;
      }
      return true;
    }
  } catch (err) {
    if (syncStatus) {
      syncStatus.innerHTML = '<span class="status-dot"></span> Rutas guardadas localmente';
    }
  }
  return false;
}

// ═══════════════════════════════════════════════════════════════════════
// MAPA INTERACTIVO LEAFLET
// ═══════════════════════════════════════════════════════════════════════

function initLeafletMap() {
  // Coordenadas centrales de Tacna (Paseo Cívico / Centro Histórico)
  const tacnaCenter = [-18.01358, -70.25055];

  state.map = L.map('tacna-map', {
    center: tacnaCenter,
    zoom: 14,
    zoomControl: false,
    minZoom: 10,
    maxZoom: 19
  });

  // Controles de Zoom en la esquina inferior derecha
  L.control.zoom({ position: 'bottomright' }).addTo(state.map);

  // Capas de Mapas Disponibles (100% Libres de API Key y sin marcas de agua)
  state.tileLayers = {
    dark: L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors',
      className: 'map-tiles-dark',
      maxZoom: 19
    }),
    streets: L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors',
      maxZoom: 19
    }),
    satellite: L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
      attribution: 'Tiles &copy; Esri &mdash; Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and GIS User Community',
      maxZoom: 19
    })
  };

  // Capa inicial: Dark Mode
  state.activeTileLayer = state.tileLayers.dark;
  state.activeTileLayer.addTo(state.map);

  // Grupo de capas para polilíneas y nodos de rutas
  state.routeLayersGroup = L.layerGroup().addTo(state.map);

  // Evento de Movimiento del Ratón: Actualizar coordenadas en vivo
  const liveCoords = document.getElementById('live-coords');
  state.map.on('mousemove', (e) => {
    const lat = e.latlng.lat.toFixed(6);
    const lng = e.latlng.lng.toFixed(6);
    liveCoords.innerHTML = `<span>Tacna: ${lat}, ${lng}</span>`;
  });

  // Evento de Clic en el Mapa
  state.map.on('click', (e) => {
    // 1. Si estamos en modo de Trazado Interactivo de Ruta en el mapa: alinear punto a la calle y trazar ruta vial
    if (state.tracingRouteId) {
      handleMapClickDuringRouteTrace(e.latlng.lat, e.latlng.lng);
      return;
    }

    // 2. Si estamos en modo de reubicación activa: mover el pin a este punto exacto
    if (state.relocatingStopId) {
      const marker = state.markersMap.get(state.relocatingStopId);
      if (marker) {
        marker.setLatLng(e.latlng);
        updateRelocationCoordsDisplay(e.latlng.lat, e.latlng.lng);
      }
      return;
    }

    if (state.pickingCoordsMode) {
      // Si el modal de creación/edición estaba esperando un clic en el mapa:
      document.getElementById('field-lat').value = e.latlng.lat.toFixed(6);
      document.getElementById('field-lng').value = e.latlng.lng.toFixed(6);
      state.pickingCoordsMode = false;
      document.getElementById('btn-pick-coords').textContent = '📍 Coordenadas capturadas';
      document.getElementById('stop-dialog').showModal();
      showToast(`Coordenadas seleccionadas: ${e.latlng.lat.toFixed(6)}, ${e.latlng.lng.toFixed(6)}`);
      return;
    }

    // Clic en espacio libre del mapa: Ofrecer crear paradero ahí
    const popupContent = document.createElement('div');
    popupContent.className = 'map-add-popup';
    popupContent.innerHTML = `
      <div style="font-family: var(--font-sans); padding: 4px;">
        <strong style="display:block; font-size: 12px; margin-bottom: 4px; color: #0F172A;">¿Crear paradero en este punto?</strong>
        <span style="display:block; font-size: 11px; color: #475569; margin-bottom: 8px;">${e.latlng.lat.toFixed(6)}, ${e.latlng.lng.toFixed(6)}</span>
        <button id="btn-popup-create" style="background: #2563EB; color: white; border: none; border-radius: 6px; padding: 4px 10px; font-size: 11px; font-weight: bold; cursor: pointer; width: 100%;">
          + Crear Paradero Aquí
        </button>
      </div>
    `;

    const popup = L.popup()
      .setLatLng(e.latlng)
      .setContent(popupContent)
      .openOn(state.map);

    popupContent.querySelector('#btn-popup-create').addEventListener('click', () => {
      state.map.closePopup();
      openStopDialog(null, e.latlng.lat, e.latlng.lng);
    });
  });

  // Renderizar todos los marcadores y rutas
  renderMapMarkers();
  renderMapRoutes();
}

// ═══════════════════════════════════════════════════════════════════════
// MARCADORES Y FLUJO DE REUBICACIÓN SEGURA ("¿Deseas mover?" ➔ "Establecer")
// ═══════════════════════════════════════════════════════════════════════

// Mapeo del símbolo SF Symbol seleccionado en el Administrador a Emoji para el mapa web
function getStopIconEmoji(iconName) {
  switch (iconName) {
    case 'parkingsign.circle.fill': return '🚏';
    case 'storefront.fill': case 'storefront': return '🛒';
    case 'cross.case.fill': return '🏥';
    case 'graduationcap.fill': return '🎓';
    case 'building.columns.fill': return '🏛️';
    case 'tree.fill': return '🌳';
    case 'mappin.and.ellipse': return '📍';
    default: return '🚌';
  }
}

function renderMapMarkers() {
  // Limpiar marcadores existentes
  state.markersMap.forEach(marker => marker.remove());
  state.markersMap.clear();

  state.stops.forEach(stop => {
    const isOfficial = stop.isOfficial ?? (!stop.category.includes('proposed') && !stop.id.startsWith('prop-'));
    const markerColorClass = isOfficial ? 'is-official' : 'is-proposal';
    const iconLetter = getStopIconEmoji(stop.iconName);

    // HTML personalizado para el pin interactivo
    const customIcon = L.divIcon({
      className: 'custom-map-pin',
      html: `
        <div class="pin-container ${markerColorClass}" id="pin-${stop.id}">
          <span style="font-size: 12px;">${iconLetter}</span>
          <span class="pin-label">${escapeHtml(stop.shortName || stop.name)}</span>
        </div>
      `,
      iconSize: [32, 32],
      iconAnchor: [16, 16],
      popupAnchor: [0, -20]
    });

    // Marcador Leaflet: NO arrastrable por defecto (seguridad para evitar movimientos accidentales)
    const marker = L.marker([stop.latitude, stop.longitude], {
      icon: customIcon,
      draggable: false,
      title: stop.name
    });

    // Crear el contenido del Popup interactivo con la opción "¿Deseas mover el paradero?"
    const popupContent = createStopPopupElement(stop);
    marker.bindPopup(popupContent, {
      className: 'stop-leaflet-popup',
      closeButton: true,
      autoPan: true
    });

    // Evento CLICK: Seleccionar y abrir popup, o agregar al trazado si estamos en modo trazado
    marker.on('click', (e) => {
      if (state.tracingRouteId) {
        if (e && e.originalEvent) L.DomEvent.stopPropagation(e.originalEvent);
        handleStopClickedDuringRouteTrace(stop);
        return;
      }
      // Si ya estamos reubicando este u otro paradero, no interrumpir el flujo
      if (state.relocatingStopId && state.relocatingStopId === stop.id) {
        return;
      }
      selectStop(stop.id, false);
      marker.openPopup();
    });

    // Eventos de arrastre cuando el modo de reubicación está activado:
    marker.on('dragstart', () => {
      const el = document.getElementById(`pin-${stop.id}`);
      if (el) el.classList.add('is-dragging');
    });

    marker.on('drag', (event) => {
      const pos = event.target.getLatLng();
      updateRelocationCoordsDisplay(pos.lat, pos.lng);

      // Sincronización en vivo estilo Google Docs: emitir coordenadas cada 40ms al otro admin
      const now = Date.now();
      if (now - state.lastDragBroadcastTime > 40) {
        state.lastDragBroadcastTime = now;
        sendWsMessage({
          type: 'drag_stop',
          stopId: stop.id,
          lat: parseFloat(pos.lat.toFixed(6)),
          lng: parseFloat(pos.lng.toFixed(6)),
          user: state.currentUser
        });
      }
    });

    marker.on('dragend', (event) => {
      const el = document.getElementById(`pin-${stop.id}`);
      if (el) el.classList.remove('is-dragging');
      const pos = event.target.getLatLng();
      updateRelocationCoordsDisplay(pos.lat, pos.lng);
    });

    marker.addTo(state.map);
    state.markersMap.set(stop.id, marker);
  });
}

// Crea la tarjeta emergente interactiva para cada paradero
function createStopPopupElement(stop) {
  const isOfficial = stop.isOfficial ?? (!stop.category.includes('proposed') && !stop.id.startsWith('prop-'));
  const lock = state.lockedStops[stop.id];
  const isLockedByOther = lock && lock.id !== state.currentUser.id;
  const lockedByUser = isLockedByOther ? (lock.name || 'otro administrador') : null;
  const notifInfo = getStopNotificationStatus(stop);

  const container = document.createElement('div');
  container.className = 'stop-popup-card';
  container.innerHTML = `
    <div class="popup-header">
      <span class="popup-badge ${isOfficial ? 'official' : 'proposal'}">
        ${isOfficial ? 'PARADERO OFICIAL' : 'PROPUESTA'}
      </span>
      ${isLockedByOther ? `<span class="badge" style="background:#F59E0B; color:#000; font-weight:800; font-size:10px;">🔒 EN EDICIÓN</span>` : ''}
    </div>
    <h3 class="popup-title">${escapeHtml(stop.name)}</h3>
    <p class="popup-subtitle">${escapeHtml(stop.subtitle || 'Tacna, Perú')}</p>
    <div class="popup-coords">📍 ${stop.latitude.toFixed(6)}, ${stop.longitude.toFixed(6)}</div>
    <div style="margin-bottom: 8px; font-size: 11px; font-weight: 700; padding: 5px 8px; border-radius: 6px; ${notifInfo.inlineStyle}">
      ${notifInfo.badgeHtml}
    </div>
    
    <div class="popup-move-cta" style="${isLockedByOther ? 'border-color: #F59E0B; background: rgba(245, 158, 11, 0.1);' : ''}">
      <p class="popup-move-question">
        ${isLockedByOther ? `🔒 En edición por <strong>${escapeHtml(lockedByUser)}</strong>` : '¿Deseas mover este paradero?'}
      </p>
      <button type="button" class="btn btn-primary btn-sm btn-start-move" id="popup-btn-move-${stop.id}" ${isLockedByOther ? 'disabled style="background: #475569 !important; cursor: not-allowed; opacity: 0.6;"' : ''}>
        ${isLockedByOther ? '🔒 Bloqueado temporalmente' : '📍 Mover Paradero'}
      </button>
    </div>

    <div class="popup-actions-footer">
      <button type="button" class="btn btn-ghost btn-xs" id="popup-btn-edit-${stop.id}" ${isLockedByOther ? 'disabled style="opacity: 0.5;"' : ''}>✏️ Editar datos</button>
      <button type="button" class="btn btn-destructive btn-xs" id="popup-btn-del-${stop.id}" ${isLockedByOther ? 'disabled style="opacity: 0.5;"' : ''}>🗑️ Eliminar</button>
    </div>
  `;

  // Listeners dentro del popup
  container.querySelector(`#popup-btn-move-${stop.id}`).addEventListener('click', (e) => {
    e.stopPropagation();
    if (!isLockedByOther) {
      startRelocatingStop(stop.id);
    }
  });

  container.querySelector(`#popup-btn-edit-${stop.id}`).addEventListener('click', (e) => {
    e.stopPropagation();
    if (!isLockedByOther) {
      state.map.closePopup();
      openStopDialog(stop);
    }
  });

  container.querySelector(`#popup-btn-del-${stop.id}`).addEventListener('click', (e) => {
    e.stopPropagation();
    if (!isLockedByOther) {
      state.map.closePopup();
      promptDeleteStop(stop.id);
    }
  });

  return container;
}

// Inicia el proceso controlado de reubicación
function startRelocatingStop(stopId) {
  const stop = state.stops.find(s => s.id === stopId);
  const marker = state.markersMap.get(stopId);
  if (!stop || !marker) return;

  // Si otro administrador ya tiene bloqueado este paradero, impedir movimiento simultáneo
  if (state.lockedStops[stopId] && state.lockedStops[stopId].id !== state.currentUser.id) {
    const lockingUser = state.lockedStops[stopId].name || 'otro administrador';
    showToast(`⚠️ Este paradero está siendo editado por ${lockingUser}. Espera a que termine.`);
    return;
  }

  // Si había otro paradero en movimiento, cancelarlo primero
  if (state.relocatingStopId) {
    cancelRelocation();
  }

  state.relocatingStopId = stopId;
  state.originalCoords = { lat: stop.latitude, lng: stop.longitude };
  state.tempCoords = { lat: stop.latitude, lng: stop.longitude };

  // Notificar al servidor en tiempo real que este paradero está bloqueado por este admin
  sendWsMessage({
    type: 'lock_stop',
    stopId: stopId,
    user: state.currentUser
  });

  // Cerrar el popup para despejar la vista del mapa
  state.map.closePopup();

  // Habilitar arrastre solo en este marcador
  marker.dragging.enable();

  // Añadir efecto visual pulsante
  const pinEl = document.getElementById(`pin-${stopId}`);
  if (pinEl) {
    pinEl.classList.add('is-relocating');
  }

  // Mostrar la barra flotante de confirmación "Establecer"
  const relocationBar = document.getElementById('relocation-bar');
  const stopNameEl = document.getElementById('relocation-stop-name');
  if (stopNameEl) stopNameEl.textContent = stop.name;
  updateRelocationCoordsDisplay(stop.latitude, stop.longitude);
  if (relocationBar) relocationBar.classList.remove('hidden');

  showToast(`Modo reubicación activado para "${stop.name}". Arrastra el marcador o haz clic en la nueva esquina.`);
}

// Actualiza en tiempo real el indicador de coordenadas
function updateRelocationCoordsDisplay(lat, lng) {
  state.tempCoords = { lat: parseFloat(lat.toFixed(6)), lng: parseFloat(lng.toFixed(6)) };
  const coordsDisplay = document.getElementById('relocation-coords-display');
  if (coordsDisplay) {
    coordsDisplay.textContent = `Nueva posición: ${lat.toFixed(6)}, ${lng.toFixed(6)}`;
  }
}

// Confirma y establece la nueva posición
function confirmRelocation() {
  if (!state.relocatingStopId) return;

  const stop = state.stops.find(s => s.id === state.relocatingStopId);
  const marker = state.markersMap.get(state.relocatingStopId);

  if (stop && marker) {
    const finalCoords = state.tempCoords || {
      lat: parseFloat(marker.getLatLng().lat.toFixed(6)),
      lng: parseFloat(marker.getLatLng().lng.toFixed(6))
    };

    stop.latitude = finalCoords.lat;
    stop.longitude = finalCoords.lng;

    // Deshabilitar arrastre y bloquear pin
    marker.dragging.disable();

    const pinEl = document.getElementById(`pin-${stop.id}`);
    if (pinEl) {
      pinEl.classList.remove('is-relocating');
      pinEl.classList.remove('is-dragging');
    }

    // Actualizar el popup con las nuevas coordenadas
    const newPopup = createStopPopupElement(stop);
    marker.setPopupContent(newPopup);

    // Guardar en localStorage y sincronizar con backend local en vivo
    saveToLocalStorage();
    renderStopsList();
    selectStop(stop.id, false);

    // Emitir actualización por WebSocket en tiempo real estilo Google Docs
    sendWsMessage({
      type: 'save_stop',
      stop: stop,
      user: state.currentUser
    });

    showToast(`✓ Ubicación de "${stop.shortName || stop.name}" establecida en [${stop.latitude}, ${stop.longitude}]`);
  }

  // Ocultar barra flotante
  const relocationBar = document.getElementById('relocation-bar');
  if (relocationBar) relocationBar.classList.add('hidden');
  state.relocatingStopId = null;
  state.originalCoords = null;
  state.tempCoords = null;
}

// Cancela y restaura la posición original
function cancelRelocation() {
  if (!state.relocatingStopId) return;

  const stop = state.stops.find(s => s.id === state.relocatingStopId);
  const marker = state.markersMap.get(state.relocatingStopId);

  if (stop && marker && state.originalCoords) {
    // Notificar al WebSocket que liberamos el bloqueo del paradero
    sendWsMessage({
      type: 'unlock_stop',
      stopId: state.relocatingStopId,
      user: state.currentUser
    });

    // Restaurar posición original
    marker.setLatLng([state.originalCoords.lat, state.originalCoords.lng]);
    marker.dragging.disable();

    const pinEl = document.getElementById(`pin-${stop.id}`);
    if (pinEl) {
      pinEl.classList.remove('is-relocating');
      pinEl.classList.remove('is-dragging');
    }

    showToast(`Reubicación cancelada. "${stop.shortName || stop.name}" mantiene su posición original.`);
  }

  // Ocultar barra flotante
  const relocationBar = document.getElementById('relocation-bar');
  if (relocationBar) relocationBar.classList.add('hidden');
  state.relocatingStopId = null;
  state.originalCoords = null;
  state.tempCoords = null;
}

// ═══════════════════════════════════════════════════════════════════════
// CLASIFICACIÓN DE RUTAS POR PARADERO (ORDINARIAS VS EXTERNAS & SERVICIO)
// ═══════════════════════════════════════════════════════════════════════

function getRouteByCode(routeCode) {
  const clean = (routeCode || '').trim().toLowerCase();
  return state.routes.find(r => (r.code || '').trim().toLowerCase() === clean) || null;
}

function getStopRoutePillClass(routeCode) {
  const route = getRouteByCode(routeCode);
  if (!route) return 'is-external';
  if (route.routeType === 'ordinary') {
    return route.isInService ? 'is-ordinary-active' : 'is-ordinary-inactive';
  }
  return 'is-external';
}

function getStopNotificationStatus(stop) {
  const routeCodes = Array.isArray(stop.routesPassing) ? stop.routesPassing : [];
  const matchingRoutes = routeCodes.map(c => getRouteByCode(c)).filter(Boolean);
  const ordinaryRoutes = matchingRoutes.filter(r => r.routeType === 'ordinary');
  const activeOrdinaryRoutes = ordinaryRoutes.filter(r => r.isInService);

  if (activeOrdinaryRoutes.length > 0) {
    const names = activeOrdinaryRoutes.map(r => r.code).join(', ');
    return {
      status: 'available',
      badgeHtml: `🔔 Notificación Habilitada (${escapeHtml(names)} en servicio)`,
      inlineStyle: 'background: rgba(16, 185, 129, 0.14); color: #34D399; border: 1px solid rgba(16, 185, 129, 0.35);'
    };
  }
  if (ordinaryRoutes.length > 0) {
    const names = ordinaryRoutes.map(r => r.code).join(', ');
    return {
      status: 'ordinary_out_of_service',
      badgeHtml: `⚠️ Sin rutas ordinarias en servicio (${escapeHtml(names)} fuera de servicio)`,
      inlineStyle: 'background: rgba(245, 158, 11, 0.14); color: #FBBF24; border: 1px solid rgba(245, 158, 11, 0.38);'
    };
  }
  return {
    status: 'external_only',
    badgeHtml: `📍 Solo Punto de Encuentro / Ir (Sin rutas ordinarias trackeadas)`,
    inlineStyle: 'background: rgba(148, 163, 184, 0.12); color: #94A3B8; border: 1px solid rgba(148, 163, 184, 0.25);'
  };
}

// ═══════════════════════════════════════════════════════════════════════
// RENDERIZADO DE LA LISTA LATERAL DE PARADEROS
// ═══════════════════════════════════════════════════════════════════════

function renderStopsList() {
  const container = document.getElementById('stops-list');
  const showingCountText = document.getElementById('showing-count-text');
  if (!container || !showingCountText) return;

  const filtered = state.stops.filter(stop => {
    // Filtro por categoría
    if (state.activeFilter !== 'all') {
      if (state.activeFilter === 'proposals') {
        const isProposal = stop.category.startsWith('proposed') || stop.id.startsWith('prop-');
        if (!isProposal) return false;
      } else if (stop.category !== state.activeFilter) {
        return false;
      }
    }

    // Filtro por texto de búsqueda
    if (state.searchQuery) {
      const q = state.searchQuery.toLowerCase();
      const nameMatch = stop.name.toLowerCase().includes(q);
      const subtitleMatch = stop.subtitle.toLowerCase().includes(q);
      const routesMatch = (stop.routesPassing || []).some(r => r.toLowerCase().includes(q));
      if (!nameMatch && !subtitleMatch && !routesMatch) return false;
    }

    return true;
  });

  showingCountText.textContent = `Mostrando ${filtered.length} de ${state.stops.length} paraderos`;

  if (filtered.length === 0) {
    container.innerHTML = `
      <div style="text-align: center; padding: 40px 20px; color: var(--text-muted); font-size: 0.8rem;">
        No se encontraron paraderos para el filtro aplicado.
      </div>
    `;
    return;
  }

  container.innerHTML = filtered.map(stop => {
    const isOfficial = stop.isOfficial ?? (!stop.category.includes('proposed') && !stop.id.startsWith('prop-'));
    const isSelected = state.selectedStopId === stop.id;
    const badgeText = isOfficial ? 'OFICIAL' : 'PROPUESTA';
    const badgeClass = isOfficial ? 'badge-official' : 'badge-proposal';
    const pinBg = isOfficial ? 'var(--color-official)' : 'var(--color-proposal)';
    const notifInfo = getStopNotificationStatus(stop);

    const routePillsHtml = (stop.routesPassing || []).length > 0
      ? stop.routesPassing.map(r => {
          const pillClass = getStopRoutePillClass(r);
          return `<span class="route-pill ${pillClass}">${escapeHtml(r)}</span>`;
        }).join('')
      : `<span class="route-pill is-external">Sin rutas asignadas</span>`;

    return `
      <li class="stop-item ${isSelected ? 'selected' : ''}" data-id="${stop.id}" tabindex="0">
        <div class="stop-item-header">
          <div class="stop-pin-icon" style="background: ${pinBg};">
            ${getStopIconEmoji(stop.iconName)}
          </div>
          <div class="stop-item-titles">
            <div class="stop-title-row">
              <span class="stop-name" title="${escapeHtml(stop.name)}">${escapeHtml(stop.name)}</span>
              <span class="badge ${badgeClass}">${badgeText}</span>
            </div>
            <p class="stop-subtitle">${escapeHtml(stop.subtitle)}</p>
          </div>
        </div>

        <div class="stop-routes">
          ${routePillsHtml}
        </div>

        <div style="font-size: 0.65rem; font-weight: 700; padding: 4px 8px; border-radius: 5px; margin-bottom: 7px; ${notifInfo.inlineStyle}">
          ${notifInfo.badgeHtml}
        </div>

        <div class="stop-coords-row">
          <span class="stop-coords">${stop.latitude.toFixed(6)}, ${stop.longitude.toFixed(6)}</span>
          <div class="stop-actions-row">
            <button type="button" class="btn-icon btn-focus-map" data-id="${stop.id}" title="Centrar en el mapa">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"></polygon></svg>
            </button>
            <button type="button" class="btn-icon btn-prompt-move" data-id="${stop.id}" title="¿Deseas mover este paradero?">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 9l-3 3 3 3M9 5l3-3 3 3M15 19l-3 3-3-3M19 9l3 3-3 3M2 12h20M12 2v20"/></svg>
            </button>
            <button type="button" class="btn-icon btn-edit" data-id="${stop.id}" title="Editar paradero">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 20h9"></path><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"></path></svg>
            </button>
            <button type="button" class="btn-icon delete btn-delete" data-id="${stop.id}" title="Eliminar paradero">
              <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path></svg>
            </button>
          </div>
        </div>
      </li>
    `;
  }).join('');

  // Event Listeners para cada ítem de la lista
  container.querySelectorAll('.stop-item').forEach(item => {
    item.addEventListener('click', (e) => {
      if (e.target.closest('.btn-icon')) return;
      const stopId = item.dataset.id;
      selectStop(stopId, true);
    });
  });

  container.querySelectorAll('.btn-focus-map').forEach(btn => {
    btn.addEventListener('click', () => {
      const stopId = btn.dataset.id;
      selectStop(stopId, true);
    });
  });

  container.querySelectorAll('.btn-prompt-move').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const stopId = btn.dataset.id;
      selectStop(stopId, true);
      startRelocatingStop(stopId);
    });
  });

  container.querySelectorAll('.btn-edit').forEach(btn => {
    btn.addEventListener('click', () => {
      const stopId = btn.dataset.id;
      const stop = state.stops.find(s => s.id === stopId);
      if (stop) openStopDialog(stop);
    });
  });

  container.querySelectorAll('.btn-delete').forEach(btn => {
    btn.addEventListener('click', () => {
      const stopId = btn.dataset.id;
      promptDeleteStop(stopId);
    });
  });
}

function selectStop(stopId, panToMap = true) {
  state.selectedStopId = stopId;
  const stop = state.stops.find(s => s.id === stopId);
  if (!stop) return;

  // Actualizar clase selected en la lista
  document.querySelectorAll('.stop-item').forEach(item => {
    item.classList.toggle('selected', item.dataset.id === stopId);
  });

  // Centrar el mapa en la ubicación del paradero
  if (panToMap && state.map) {
    state.map.flyTo([stop.latitude, stop.longitude], 16, {
      duration: 0.8,
      easeLinearity: 0.25
    });
  }

  // Resaltar visualmente el marcador
  const marker = state.markersMap.get(stopId);
  if (marker) {
    const pinEl = document.getElementById(`pin-${stopId}`);
    if (pinEl) {
      pinEl.classList.add('is-dragging');
      setTimeout(() => pinEl.classList.remove('is-dragging'), 1200);
    }
  }
}

function updateStats() {
  const total = state.stops.length;
  const official = state.stops.filter(s => s.isOfficial ?? (!s.category.includes('proposed') && !s.id.startsWith('prop-'))).length;
  const proposals = total - official;

  const statTotal = document.getElementById('stat-total');
  const statOfficial = document.getElementById('stat-official');
  const statProposals = document.getElementById('stat-proposals');
  const badgeStops = document.getElementById('tab-badge-stops');

  if (statTotal) statTotal.textContent = total;
  if (statOfficial) statOfficial.textContent = official;
  if (statProposals) statProposals.textContent = proposals;
  if (badgeStops) badgeStops.textContent = total;
}

// ═══════════════════════════════════════════════════════════════════════
// MÓDULO 2: GESTIÓN DE RUTAS OFICIALES Y EXTERNAS + TRAZADO EN MAPA
// ═══════════════════════════════════════════════════════════════════════

function switchAdminModule(moduleName) {
  state.activeModule = moduleName;

  const tabStops = document.getElementById('tab-module-stops');
  const tabRoutes = document.getElementById('tab-module-routes');
  const tabDrivers = document.getElementById('tab-module-drivers');
  const tabClients = document.getElementById('tab-module-clients');
  const tabPos = document.getElementById('tab-module-pos');
  const tabStats = document.getElementById('tab-module-stats');

  const tabs = [
    { name: 'stops', el: tabStops },
    { name: 'routes', el: tabRoutes },
    { name: 'drivers', el: tabDrivers },
    { name: 'clients', el: tabClients },
    { name: 'pos', el: tabPos },
    { name: 'stats', el: tabStats }
  ];

  tabs.forEach(t => {
    if (t.el) {
      const isActive = t.name === moduleName;
      t.el.classList.toggle('active', isActive);
      t.el.setAttribute('aria-selected', isActive ? 'true' : 'false');
    }
  });

  const stopsHeader = document.getElementById('stops-header-controls');
  const routesHeader = document.getElementById('routes-header-controls');
  const stopsSection = document.getElementById('stops-list-section');
  const routesSection = document.getElementById('routes-list-section');
  const mapViewport = document.querySelector('.map-viewport');
  const modeLabel = document.getElementById('current-mode-label');

  const posPanel = document.getElementById('pos-admin-panel');
  const driversPanel = document.getElementById('drivers-admin-panel');
  const clientsPanel = document.getElementById('clients-admin-panel');
  const statsPanel = document.getElementById('stats-admin-panel');

  if (moduleName !== 'routes' && state.tracingRouteId) {
    cancelRouteTrace();
  }

  // Ocultar todos los paneles full-width primero
  posPanel?.classList.add('hidden');
  driversPanel?.classList.add('hidden');
  clientsPanel?.classList.add('hidden');
  statsPanel?.classList.add('hidden');

  if (moduleName === 'pos') {
    mapViewport?.classList.add('hidden');
    posPanel?.classList.remove('hidden');
    stopsHeader?.classList.add('hidden');
    routesHeader?.classList.add('hidden');
    stopsSection?.classList.add('hidden');
    routesSection?.classList.add('hidden');
    renderPosTerminals();
    renderTransactionsTable();
    updatePosKPIs();
  } else if (moduleName === 'drivers') {
    mapViewport?.classList.add('hidden');
    driversPanel?.classList.remove('hidden');
    stopsHeader?.classList.add('hidden');
    routesHeader?.classList.add('hidden');
    stopsSection?.classList.add('hidden');
    routesSection?.classList.add('hidden');
    renderDriversTable();
  } else if (moduleName === 'clients') {
    mapViewport?.classList.add('hidden');
    clientsPanel?.classList.remove('hidden');
    stopsHeader?.classList.add('hidden');
    routesHeader?.classList.add('hidden');
    stopsSection?.classList.add('hidden');
    routesSection?.classList.add('hidden');
    renderUsersTable();
  } else if (moduleName === 'stats') {
    mapViewport?.classList.add('hidden');
    statsPanel?.classList.remove('hidden');
    stopsHeader?.classList.add('hidden');
    routesHeader?.classList.add('hidden');
    stopsSection?.classList.add('hidden');
    routesSection?.classList.add('hidden');
    renderStatsCharts();
  } else if (moduleName === 'routes') {
    mapViewport?.classList.remove('hidden');
    stopsHeader?.classList.add('hidden');
    routesHeader?.classList.remove('hidden');
    stopsSection?.classList.add('hidden');
    routesSection?.classList.remove('hidden');

    if (modeLabel) {
      modeLabel.textContent = 'Modo: Gestión de Rutas y Trazados Oficiales (Referencia ETA App + Chofer)';
    }

    if (!state.selectedRouteId && state.routes.length > 0) {
      state.selectedRouteId = state.routes[0].id;
    }
    renderRoutesList();
    updateRouteStats();
    renderMapRoutes();
    setTimeout(() => state.map?.invalidateSize(), 60);
  } else {
    // Paraderos (default)
    mapViewport?.classList.remove('hidden');
    routesHeader?.classList.add('hidden');
    stopsHeader?.classList.remove('hidden');
    routesSection?.classList.add('hidden');
    stopsSection?.classList.remove('hidden');

    if (modeLabel) {
      modeLabel.textContent = 'Modo: Selección & Gestión Oficial (Haz clic en un paradero)';
    }

    renderStopsList();
    updateStats();
    renderMapRoutes();
    setTimeout(() => state.map?.invalidateSize(), 60);
  }
}

function haversineDistanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371.0;
  const toRad = (deg) => (deg * Math.PI) / 180.0;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function computeRouteDistanceAndEta(coords, speedKmh = 22.0, stopsCount = 0) {
  if (!Array.isArray(coords) || coords.length < 2) {
    return { totalDistanceKm: 0.0, estimatedTotalMinutes: 0 };
  }
  let dist = 0.0;
  for (let i = 0; i < coords.length - 1; i++) {
    const [lat1, lng1] = coords[i];
    const [lat2, lng2] = coords[i + 1];
    dist += haversineDistanceKm(lat1, lng1, lat2, lng2);
  }
  const safeSpeed = Math.max(5.0, parseFloat(speedKmh) || 22.0);
  // Si la polilínea ya sigue la geometría real de las calles (más vértices que los nodos/paraderos),
  // la suma Haversine ya es la distancia real de conducción; si son líneas rectas, aplicamos factor urbano 1.25x.
  const isStreetAlignedGeometry = coords.length > Math.max(4, (stopsCount || 2) + 3);
  const roadDist = isStreetAlignedGeometry ? dist : dist * 1.25;
  const driveMinutes = (roadDist / safeSpeed) * 60.0;
  const dwellMinutes = (stopsCount || Math.min(coords.length, 15)) * 0.42;
  const totalMinutes = Math.max(4, Math.round(driveMinutes + dwellMinutes));

  return {
    totalDistanceKm: parseFloat(roadDist.toFixed(2)),
    estimatedTotalMinutes: totalMinutes
  };
}

// ═══════════════════════════════════════════════════════════════════════
// MOTOR DE ALINEACIÓN NATIVA A CALLES (OSRM NEAREST & DRIVING ROUTER)
// ═══════════════════════════════════════════════════════════════════════

/**
 * Ajusta (snap) una coordenada arbitraria al nodo vial más cercano de las calles de Tacna.
 */
async function snapCoordinateToStreet(lat, lng) {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 3500);
    const url = `https://router.project-osrm.org/nearest/v1/driving/${lng.toFixed(6)},${lat.toFixed(6)}?number=1`;
    const res = await fetch(url, { signal: controller.signal });
    clearTimeout(timeoutId);
    if (res.ok) {
      const data = await res.json();
      if (data.code === 'Ok' && Array.isArray(data.waypoints) && data.waypoints.length > 0) {
        const wp = data.waypoints[0];
        const [snappedLng, snappedLat] = wp.location;
        return {
          lat: parseFloat(snappedLat.toFixed(6)),
          lng: parseFloat(snappedLng.toFixed(6)),
          streetName: wp.name || 'Vía urbana'
        };
      }
    }
  } catch (_) {
    // Fallback silencioso a la coordenada original si no hay red
  }
  return {
    lat: parseFloat(lat.toFixed(6)),
    lng: parseFloat(lng.toFixed(6)),
    streetName: 'Coordenada directa'
  };
}

/**
 * Calcula la polilínea exacta siguiendo las calles de la ciudad entre dos nodos.
 */
async function fetchStreetAlignedSegment(nodeA, nodeB) {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 4500);
    const coordsQuery = `${nodeA.lng.toFixed(6)},${nodeA.lat.toFixed(6)};${nodeB.lng.toFixed(6)},${nodeB.lat.toFixed(6)}`;
    const url = `https://router.project-osrm.org/route/v1/driving/${coordsQuery}?overview=full&geometries=geojson&continue_straight=true`;
    const res = await fetch(url, { signal: controller.signal });
    clearTimeout(timeoutId);
    if (res.ok) {
      const data = await res.json();
      if (data.code === 'Ok' && Array.isArray(data.routes) && data.routes.length > 0) {
        const geoCoords = data.routes[0].geometry?.coordinates || [];
        if (geoCoords.length >= 2) {
          return geoCoords.map(([lon, lat]) => [
            parseFloat(lat.toFixed(6)),
            parseFloat(lon.toFixed(6))
          ]);
        }
      }
    }
  } catch (_) {
    // Fallback a segmento recto si falla la consulta
  }
  return [
    [parseFloat(nodeA.lat.toFixed(6)), parseFloat(nodeA.lng.toFixed(6))],
    [parseFloat(nodeB.lat.toFixed(6)), parseFloat(nodeB.lng.toFixed(6))]
  ];
}

/**
 * Alinea una lista completa de nodos de control a las calles de la ciudad y construye
 * tanto los segmentos individuales como la polilínea continua completa.
 */
async function alignNodesToStreetNetwork(rawNodes) {
  if (!Array.isArray(rawNodes) || rawNodes.length === 0) {
    return { nodes: [], segments: [], fullCoords: [] };
  }
  if (rawNodes.length === 1) {
    const snapped = await snapCoordinateToStreet(rawNodes[0].lat, rawNodes[0].lng);
    const singleNode = { ...rawNodes[0], ...snapped };
    return {
      nodes: [singleNode],
      segments: [],
      fullCoords: [[singleNode.lat, singleNode.lng]]
    };
  }

  // Consultamos OSRM route en lote para obtener los waypoints alineados y la geometría por tramo (legs)
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 6500);
    const coordsStr = rawNodes.map(n => `${n.lng.toFixed(6)},${n.lat.toFixed(6)}`).join(';');
    const url = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=full&geometries=geojson&steps=true&continue_straight=true`;
    const res = await fetch(url, { signal: controller.signal });
    clearTimeout(timeoutId);

    if (res.ok) {
      const data = await res.json();
      if (data.code === 'Ok' && Array.isArray(data.routes) && data.routes.length > 0) {
        const routeObj = data.routes[0];
        const waypoints = data.waypoints || [];

        const alignedNodes = rawNodes.map((orig, idx) => {
          const wp = waypoints[idx];
          if (wp && Array.isArray(wp.location)) {
            return {
              ...orig,
              lat: parseFloat(wp.location[1].toFixed(6)),
              lng: parseFloat(wp.location[0].toFixed(6)),
              streetName: wp.name || orig.streetName || 'Calle alineada'
            };
          }
          return orig;
        });

        // Extraer geometría por cada leg (tramo entre nodo i y nodo i+1)
        const segments = [];
        if (Array.isArray(routeObj.legs) && routeObj.legs.length === rawNodes.length - 1) {
          routeObj.legs.forEach((leg, legIdx) => {
            const legPts = [];
            (leg.steps || []).forEach(step => {
              const stepCoords = step.geometry?.coordinates || [];
              stepCoords.forEach(([lon, lat]) => {
                const pt = [parseFloat(lat.toFixed(6)), parseFloat(lon.toFixed(6))];
                if (
                  legPts.length === 0 ||
                  legPts[legPts.length - 1][0] !== pt[0] ||
                  legPts[legPts.length - 1][1] !== pt[1]
                ) {
                  legPts.push(pt);
                }
              });
            });
            if (legPts.length >= 2) {
              segments.push(legPts);
            } else {
              segments.push([
                [alignedNodes[legIdx].lat, alignedNodes[legIdx].lng],
                [alignedNodes[legIdx + 1].lat, alignedNodes[legIdx + 1].lng]
              ]);
            }
          });
        }

        const fullCoords = flattenStreetSegments(segments, alignedNodes);
        return { nodes: alignedNodes, segments, fullCoords };
      }
    }
  } catch (_) {
    // Fallback tramo por tramo
  }

  // Fallback secuencial si el batch excede límites o falla
  const alignedNodes = [];
  for (const n of rawNodes) {
    const snapped = await snapCoordinateToStreet(n.lat, n.lng);
    alignedNodes.push({ ...n, ...snapped });
  }
  const segments = [];
  for (let i = 0; i < alignedNodes.length - 1; i++) {
    const seg = await fetchStreetAlignedSegment(alignedNodes[i], alignedNodes[i + 1]);
    segments.push(seg);
  }
  const fullCoords = flattenStreetSegments(segments, alignedNodes);
  return { nodes: alignedNodes, segments, fullCoords };
}

function flattenStreetSegments(segments, nodes = []) {
  if (!Array.isArray(segments) || segments.length === 0) {
    return nodes.map(n => [n.lat, n.lng]);
  }
  const coords = [];
  segments.forEach(seg => {
    (seg || []).forEach(pt => {
      if (
        coords.length === 0 ||
        coords[coords.length - 1][0] !== pt[0] ||
        coords[coords.length - 1][1] !== pt[1]
      ) {
        coords.push([pt[0], pt[1]]);
      }
    });
  });
  return coords;
}

function rebuildTraceCoordsFromSegments() {
  state.tempTraceCoords = flattenStreetSegments(state.tempTraceSegments, state.tempTraceNodes);
  state.tempTraceStopIds = [...new Set(
    state.tempTraceNodes
      .map(n => n.stopId)
      .filter(Boolean)
  )];
}

function syncStopsRoutesPassingFromRoutes() {
  const stopRoutesMap = new Map();
  (state.stops || []).forEach(s => stopRoutesMap.set(s.id, []));
  (state.routes || []).forEach(r => {
    const code = (r.code || '').trim();
    if (!code) return;
    (r.keyStopIds || []).forEach(sid => {
      if (stopRoutesMap.has(sid)) {
        const list = stopRoutesMap.get(sid);
        if (!list.includes(code)) list.push(code);
      }
    });
  });
  (state.stops || []).forEach(s => {
    s.routesPassing = stopRoutesMap.get(s.id) || [];
  });
}

function buildFlexibleStopMap() {
  const map = new Map();
  state.stops.forEach(s => {
    map.set(s.id, s);
    const bare = s.id.replace(/^stop-/, '');
    map.set(bare, s);
    map.set(`stop-${bare}`, s);
    if (bare === 'mercado-2-de-mayo' || bare === 'mercado-2-mayo') {
      map.set('mercado-2-de-mayo', s);
      map.set('mercado-2-mayo', s);
      map.set('stop-mercado-2-de-mayo', s);
      map.set('stop-mercado-2-mayo', s);
    }
  });
  return map;
}

function getResolvedCoordinatesForRoute(route) {
  if (Array.isArray(route.pathCoordinates) && route.pathCoordinates.length >= 2) {
    return route.pathCoordinates;
  }
  // Fallback: construir desde los paraderos asignados
  const stopMap = buildFlexibleStopMap();
  const coords = [];
  (route.keyStopIds || []).forEach(sid => {
    const s = stopMap.get(sid);
    if (s) coords.push([s.latitude, s.longitude]);
  });
  return coords;
}

function renderMapRoutes() {
  if (!state.routeLayersGroup || !state.map) return;
  state.routeLayersGroup.clearLayers();

  const stopMap = buildFlexibleStopMap();

  // 1. Si estamos trazando una ruta en el mapa en vivo: dibujar la polilínea alineada a calles + nodos de control arrastrables
  if (state.tracingRouteId) {
    const route = state.routes.find(r => r.id === state.tracingRouteId);
    const traceColor = route ? (route.colorHex || '#2563EB') : '#2563EB';

    if (state.tempTraceCoords.length >= 2) {
      // Halo exterior
      L.polyline(state.tempTraceCoords, {
        color: traceColor,
        weight: 10,
        opacity: 0.25,
        lineCap: 'round',
        lineJoin: 'round'
      }).addTo(state.routeLayersGroup);

      // Polilínea principal siguiendo las calles de la ciudad
      L.polyline(state.tempTraceCoords, {
        color: traceColor,
        weight: 5,
        opacity: 0.95,
        dashArray: '10, 6',
        lineCap: 'round',
        lineJoin: 'round'
      }).addTo(state.routeLayersGroup);
    }

    // Dibujar los Nodos de Control (waypoints/paraderos alineados a calle) con capacidad de arrastre (drag & snap)
    let cumulativeKm = 0;
    const speedKmh = route ? (route.averageSpeedKmh || 22) : 22;
    const nodesToRender = state.tempTraceNodes.length > 0
      ? state.tempTraceNodes
      : state.tempTraceCoords.map(pt => ({ lat: pt[0], lng: pt[1], stopId: null, streetName: 'Vía urbana' }));

    nodesToRender.forEach((node, idx) => {
      if (idx > 0) {
        const seg = state.tempTraceSegments[idx - 1];
        if (Array.isArray(seg) && seg.length >= 2) {
          for (let k = 0; k < seg.length - 1; k++) {
            cumulativeKm += haversineDistanceKm(seg[k][0], seg[k][1], seg[k + 1][0], seg[k + 1][1]);
          }
        } else {
          cumulativeKm += haversineDistanceKm(
            nodesToRender[idx - 1].lat,
            nodesToRender[idx - 1].lng,
            node.lat,
            node.lng
          ) * 1.25;
        }
      }
      const etaMin = Math.round((cumulativeKm / speedKmh) * 60 + idx * 0.42);
      const isStopNode = Boolean(node.stopId);
      const canCloseLoopHere = idx === 0 && nodesToRender.length >= 2 && !state.tempTraceClosedLoop;
      const nodeIcon = L.divIcon({
        className: 'custom-route-seq-node',
        html: `<div class="route-seq-node" style="background:${traceColor}; border:${canCloseLoopHere ? '3px solid #F59E0B' : (isStopNode ? '2.5px solid #FFFFFF' : '2px dashed #E0F2FE')};">${idx + 1}</div>`,
        iconSize: [24, 24],
        iconAnchor: [12, 12]
      });

      const nodeMarker = L.marker([node.lat, node.lng], {
        icon: nodeIcon,
        interactive: true,
        draggable: true,
        zIndexOffset: idx === 0 ? 1200 : 1100
      });

      const stopObj = node.stopId ? stopMap.get(node.stopId) : null;
      const nodeTitle = stopObj
        ? `Paradero: ${stopObj.shortName || stopObj.name}`
        : `Nodo vial: ${node.streetName || 'Calle alineada'}`;

      const closeHint = canCloseLoopHere
        ? '<br><span style="color:#FBBF24;font-weight:700;">Clic aquí para cerrar ruta (Inicio/Fin)</span>'
        : '';

      nodeMarker.bindTooltip(
        `<strong>#${idx + 1} ${escapeHtml(nodeTitle)}</strong><br>` +
        `+${etaMin} min (${cumulativeKm.toFixed(2)} km) • <em>Arrastra para reajustar calle</em>${closeHint}`,
        { direction: 'top', offset: [0, -10] }
      );

      if (canCloseLoopHere) {
        nodeMarker.on('click', (ev) => {
          L.DomEvent.stopPropagation(ev);
          closeRouteLoopToFirstNode();
        });
      }

      // Al arrastrar un nodo de control, se alinea automáticamente a la calle más cercana y recalcula los tramos adyacentes
      nodeMarker.on('dragend', async (ev) => {
        const pos = ev.target.getLatLng();
        if (!state.tempTraceNodes[idx]) return;
        const snapped = await snapCoordinateToStreet(pos.lat, pos.lng);
        state.tempTraceNodes[idx].lat = snapped.lat;
        state.tempTraceNodes[idx].lng = snapped.lng;
        state.tempTraceNodes[idx].streetName = snapped.streetName;

        if (idx > 0) {
          state.tempTraceSegments[idx - 1] = await fetchStreetAlignedSegment(
            state.tempTraceNodes[idx - 1],
            state.tempTraceNodes[idx]
          );
        }
        if (idx < state.tempTraceNodes.length - 1) {
          state.tempTraceSegments[idx] = await fetchStreetAlignedSegment(
            state.tempTraceNodes[idx],
            state.tempTraceNodes[idx + 1]
          );
        }
        rebuildTraceCoordsFromSegments();
        renderMapRoutes();
        updateTraceBarMetrics();
        showToast(`🛣️ Nodo #${idx + 1} alineado a ${snapped.streetName || 'la calle más cercana'}.`);
      });

      nodeMarker.addTo(state.routeLayersGroup);
    });
    return;
  }

  // 2. Determinar qué rutas dibujar en el mapa
  const routesToDraw = state.routes.filter(r => {
    if (state.showAllRoutesOnMap) return true;
    if (state.activeModule === 'routes' && state.selectedRouteId === r.id) return true;
    return false;
  });

  routesToDraw.forEach(route => {
    const coords = getResolvedCoordinatesForRoute(route);
    if (coords.length < 2) return;

    const isSelected = state.selectedRouteId === route.id;
    const isOrdinary = route.routeType === 'ordinary';
    const isInService = Boolean(route.isInService);
    const color = route.colorHex || (isOrdinary ? '#2563EB' : '#64748B');

    // Halo para ruta ordinaria seleccionada
    if (isSelected) {
      L.polyline(coords, {
        color: color,
        weight: 11,
        opacity: isOrdinary && isInService ? 0.26 : 0.14,
        lineCap: 'round',
        lineJoin: 'round'
      }).addTo(state.routeLayersGroup);
    }

    // Polilínea principal (Sólida para Ordinaria en servicio; Punteada para Externa o Fuera de Servicio)
    const poly = L.polyline(coords, {
      color: color,
      weight: isSelected ? 5 : 3.5,
      opacity: isSelected ? 0.95 : 0.65,
      dashArray: (isOrdinary && isInService) ? null : '8, 7',
      lineCap: 'round',
      lineJoin: 'round'
    }).addTo(state.routeLayersGroup);

    const statusLabel = isOrdinary
      ? (isInService ? '🟢 ORDINARIA • EN SERVICIO' : '⚠️ ORDINARIA • FUERA DE SERVICIO')
      : '🗺️ RUTA EXTERNA • REFERENCIAL (SIN TRACKING)';

    poly.bindTooltip(
      `<strong>${escapeHtml(route.code)}</strong> — ${escapeHtml(route.title)}<br>` +
      `<span style="font-size:11px;">${statusLabel} • ${route.totalDistanceKm || 0} km • ~${route.estimatedTotalMinutes || 0} min</span>`,
      { sticky: true }
    );

    poly.on('click', () => {
      if (state.activeModule === 'routes') {
        selectRouteOnMap(route.id, false);
      }
    });

    // Si es la ruta seleccionada en el módulo de rutas, numerar sus paraderos con su ETA progresivo (referencia Chofer/App)
    if (isSelected && state.activeModule === 'routes') {
      let cumKm = 0;
      let prevStop = null;
      const speed = route.averageSpeedKmh || 22;

      (route.keyStopIds || []).forEach((stopId, idx) => {
        const stop = stopMap.get(stopId);
        if (!stop) return;
        if (prevStop) {
          cumKm += haversineDistanceKm(prevStop.latitude, prevStop.longitude, stop.latitude, stop.longitude) * 1.25;
        }
        prevStop = stop;
        const etaMin = Math.round((cumKm / speed) * 60 + idx * 0.42);

        const seqIcon = L.divIcon({
          className: 'custom-route-seq-node',
          html: `<div class="route-seq-node" style="background:${color};">${idx + 1}</div>`,
          iconSize: [22, 22],
          iconAnchor: [11, 11]
        });

        const seqMarker = L.marker([stop.latitude, stop.longitude], {
          icon: seqIcon,
          zIndexOffset: 900
        });

        seqMarker.bindTooltip(
          `<strong>#${idx + 1} ${escapeHtml(stop.shortName || stop.name)}</strong><br>` +
          `Tiempo ref. desde inicio: <strong>+${etaMin} min</strong> (${cumKm.toFixed(1)} km)`,
          { direction: 'top', offset: [0, -12] }
        );

        seqMarker.on('click', () => {
          selectStop(stop.id, false);
          const m = state.markersMap.get(stop.id);
          if (m) m.openPopup();
        });

        seqMarker.addTo(state.routeLayersGroup);
      });
    }
  });
}

function updateRouteStats() {
  const total = state.routes.length;
  const ordinaryAll = state.routes.filter(r => r.routeType === 'ordinary');
  const ordinaryActive = ordinaryAll.filter(r => r.isInService);
  const externalCount = state.routes.filter(r => r.routeType === 'external').length;

  const elTotal = document.getElementById('stat-routes-total');
  const elOrd = document.getElementById('stat-routes-ordinary');
  const elExt = document.getElementById('stat-routes-external');
  const elBadge = document.getElementById('tab-badge-routes');

  if (elTotal) elTotal.textContent = total;
  if (elOrd) elOrd.textContent = `${ordinaryActive.length}/${ordinaryAll.length}`;
  if (elExt) elExt.textContent = externalCount;
  if (elBadge) elBadge.textContent = total;
}

function renderRoutesList() {
  const container = document.getElementById('routes-list');
  const countText = document.getElementById('showing-routes-count-text');
  if (!container || !countText) return;

  const stopMap = buildFlexibleStopMap();

  const filtered = state.routes.filter(route => {
    if (state.activeRouteFilter === 'ordinary' && route.routeType !== 'ordinary') return false;
    if (state.activeRouteFilter === 'in_service' && !(route.routeType === 'ordinary' && route.isInService)) return false;
    if (state.activeRouteFilter === 'external' && route.routeType !== 'external') return false;

    if (state.routeSearchQuery) {
      const q = state.routeSearchQuery.toLowerCase();
      const codeMatch = (route.code || '').toLowerCase().includes(q);
      const titleMatch = (route.title || '').toLowerCase().includes(q);
      const corridorMatch = (route.corridor || '').toLowerCase().includes(q);
      const stopMatch = (route.keyStopIds || []).some(sid => {
        const st = stopMap.get(sid);
        return st && (st.name.toLowerCase().includes(q) || (st.shortName || '').toLowerCase().includes(q));
      });
      if (!codeMatch && !titleMatch && !corridorMatch && !stopMatch) return false;
    }
    return true;
  });

  countText.textContent = `Mostrando ${filtered.length} de ${state.routes.length} rutas configuradas`;

  if (filtered.length === 0) {
    container.innerHTML = `
      <div style="text-align: center; padding: 36px 20px; color: var(--text-muted); font-size: 0.8rem;">
        No se encontraron rutas con el filtro seleccionado.
      </div>
    `;
    return;
  }

  container.innerHTML = filtered.map(route => {
    const isOrdinary = route.routeType === 'ordinary';
    const isInService = Boolean(route.isInService);
    const isSelected = state.selectedRouteId === route.id;
    const color = route.colorHex || (isOrdinary ? '#2563EB' : '#64748B');
    const stopsCount = (route.keyStopIds || []).length;

    // Construir secuencia resumida de primeros paraderos con su ETA referencial
    let cumKm = 0;
    let prevStop = null;
    const speed = route.averageSpeedKmh || 22;
    const previewStops = (route.keyStopIds || []).slice(0, 6).map((sid, idx) => {
      const st = stopMap.get(sid);
      if (!st) return null;
      if (prevStop) {
        cumKm += haversineDistanceKm(prevStop.latitude, prevStop.longitude, st.latitude, st.longitude) * 1.25;
      }
      prevStop = st;
      const etaMin = Math.round((cumKm / speed) * 60 + idx * 0.42);
      return `<span class="route-pill ${isOrdinary ? (isInService ? 'is-ordinary-active' : 'is-ordinary-inactive') : 'is-external'}" title="ETA ref: +${etaMin} min desde inicio">${idx + 1}. ${escapeHtml(st.shortName || st.name)} (+${etaMin}m)</span>`;
    }).filter(Boolean).join('');

    const extraStopsCount = Math.max(0, stopsCount - 6);

    return `
      <li class="stop-item route-card ${isSelected ? 'selected' : ''}" data-route-id="${route.id}" tabindex="0">
        <div class="route-card-top">
          <div class="route-code-badge" style="background: ${color};">
            <span>🚌</span>
            <span>${escapeHtml(route.code)}</span>
          </div>

          ${isOrdinary ? `
            <button type="button" class="service-toggle-btn ${isInService ? 'in-service' : 'out-of-service'} btn-toggle-service" data-route-id="${route.id}" title="Cambiar estado operativo en tiempo real (Afecta avisos de paraderos en la App)">
              <span class="service-dot"></span>
              <span>${isInService ? 'EN SERVICIO' : 'FUERA DE SERVICIO'}</span>
            </button>
          ` : `
            <span class="external-route-tag" title="Línea referencial de Tacna: sin tracking GPS ni notificación">
              EXTERNA • SIN TRACKING
            </span>
          `}
        </div>

        <h3 class="route-card-title">${escapeHtml(route.title)}</h3>
        <p class="route-card-corridor">${escapeHtml(route.corridor)}</p>

        <div class="route-metrics-grid">
          <div class="route-metric-box">
            <span class="route-metric-val">${route.totalDistanceKm || 0} km</span>
            <span class="route-metric-lbl">Recorrido</span>
          </div>
          <div class="route-metric-box">
            <span class="route-metric-val">~${route.estimatedTotalMinutes || 0} min</span>
            <span class="route-metric-lbl">Tiempo Vuelta</span>
          </div>
          <div class="route-metric-box">
            <span class="route-metric-val">${isOrdinary ? `Cada ${route.frequencyMinutes || 8}m` : 'Ref.'}</span>
            <span class="route-metric-lbl">${isOrdinary ? 'Frecuencia' : 'Sin GPS'}</span>
          </div>
          <div class="route-metric-box">
            <span class="route-metric-val">${stopsCount}</span>
            <span class="route-metric-lbl">Paraderos</span>
          </div>
        </div>

        <div class="stop-routes" style="margin-bottom: 6px;">
          ${previewStops}
          ${extraStopsCount > 0 ? `<span class="route-pill">+${extraStopsCount} más</span>` : ''}
        </div>

        <div class="route-card-actions">
          <button type="button" class="btn btn-secondary btn-xs btn-view-route-map" data-route-id="${route.id}" title="Centrar recorrido en el mapa">
            🗺️ Ver en Mapa
          </button>
          <button type="button" class="btn btn-secondary btn-xs btn-trace-route-map" data-route-id="${route.id}" title="Trazar o modificar recorrido haciendo clic sobre el mapa">
            🛣️ Trazar Mapa
          </button>
          <button type="button" class="btn btn-ghost btn-xs btn-edit-route" data-route-id="${route.id}" title="Editar configuración y paraderos de la ruta">
            ✏️ Editar
          </button>
          <button type="button" class="btn btn-destructive btn-xs btn-delete-route-item" data-route-id="${route.id}" title="Eliminar ruta">
            🗑️
          </button>
        </div>
      </li>
    `;
  }).join('');

  // Listeners de tarjetas de ruta
  container.querySelectorAll('.route-card').forEach(card => {
    card.addEventListener('click', (e) => {
      if (e.target.closest('button')) return;
      selectRouteOnMap(card.dataset.routeId, true);
    });
  });

  container.querySelectorAll('.btn-toggle-service').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      toggleRouteServiceStatus(btn.dataset.routeId);
    });
  });

  container.querySelectorAll('.btn-view-route-map').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      selectRouteOnMap(btn.dataset.routeId, true);
    });
  });

  container.querySelectorAll('.btn-trace-route-map').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      startTracingRouteOnMap(btn.dataset.routeId);
    });
  });

  container.querySelectorAll('.btn-edit-route').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const route = state.routes.find(r => r.id === btn.dataset.routeId);
      if (route) openRouteDialog(route);
    });
  });

  container.querySelectorAll('.btn-delete-route-item').forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      promptDeleteRoute(btn.dataset.routeId);
    });
  });
}

function selectRouteOnMap(routeId, flyToBounds = true) {
  state.selectedRouteId = routeId;
  const route = state.routes.find(r => r.id === routeId);
  if (!route) return;

  document.querySelectorAll('.route-card').forEach(card => {
    card.classList.toggle('selected', card.dataset.routeId === routeId);
  });

  renderMapRoutes();

  if (flyToBounds && state.map) {
    const coords = getResolvedCoordinatesForRoute(route);
    if (coords.length >= 2) {
      const bounds = L.latLngBounds(coords);
      state.map.flyToBounds(bounds, { padding: [55, 55], duration: 0.75 });
    }
  }
}

function toggleRouteServiceStatus(routeId) {
  const route = state.routes.find(r => r.id === routeId);
  if (!route || route.routeType !== 'ordinary') return;

  route.isInService = !route.isInService;
  route.statusLabel = route.isInService
    ? 'En Servicio • GPS & Pago QR Activo'
    : 'Fuera de Servicio Temporal • Sin unidades activas';

  saveRoutesToLocalStorage();
  renderRoutesList();
  updateRouteStats();
  renderMapRoutes();
  renderStopsList();
  renderMapMarkers();

  sendWsMessage({
    type: 'save_route',
    route: route,
    user: state.currentUser
  });

  showToast(
    route.isInService
      ? `🟢 ${route.code} ahora está EN SERVICIO. Notificaciones de paraderos activadas en la App.`
      : `⚠️ ${route.code} marcada FUERA DE SERVICIO. La App mostrará el aviso en sus paraderos.`
  );
}

// ═══════════════════════════════════════════════════════════════════════
// TRAZADOR INTERACTIVO DE RECORRIDOS EN EL MAPA CON ALINEACIÓN A CALLES
// ═══════════════════════════════════════════════════════════════════════

async function startTracingRouteOnMap(routeId) {
  const route = state.routes.find(r => r.id === routeId);
  if (!route) return;

  if (state.relocatingStopId) {
    cancelRelocation();
  }

  state.tracingRouteId = route.id;
  state.selectedRouteId = route.id;
  state.tempTraceStopIds = [...(route.keyStopIds || [])];
  state.tempTraceClosedLoop = Boolean(route.isClosedLoop);

  const stopMap = buildFlexibleStopMap();

  // Inicializar nodos de control desde controlNodes guardados o desde los paraderos de la ruta
  if (Array.isArray(route.controlNodes) && route.controlNodes.length >= 2) {
    state.tempTraceNodes = route.controlNodes.map(n => ({ ...n }));
  } else if (state.tempTraceStopIds.length >= 2) {
    state.tempTraceNodes = state.tempTraceStopIds.map(sid => {
      const st = stopMap.get(sid);
      return st
        ? { lat: parseFloat(st.latitude.toFixed(6)), lng: parseFloat(st.longitude.toFixed(6)), stopId: sid, streetName: st.name }
        : null;
    }).filter(Boolean);
  } else {
    state.tempTraceNodes = getResolvedCoordinatesForRoute(route).map(pt => ({
      lat: pt[0],
      lng: pt[1],
      stopId: null,
      streetName: 'Vía urbana'
    }));
  }

  state.tempTraceCoords = getResolvedCoordinatesForRoute(route).map(pt => [pt[0], pt[1]]);
  state.tempTraceSegments = [];

  const traceBar = document.getElementById('route-trace-bar');
  const traceName = document.getElementById('trace-route-name');
  const colorDot = document.getElementById('trace-route-color-dot');

  if (traceName) traceName.textContent = `${route.code} (${route.title})`;
  if (colorDot) colorDot.style.background = route.colorHex || '#2563EB';
  if (traceBar) traceBar.classList.remove('hidden');

  updateTraceBarMetrics();
  renderMapRoutes();

  if (state.tempTraceCoords.length >= 2 && state.map) {
    state.map.flyToBounds(L.latLngBounds(state.tempTraceCoords), { padding: [70, 70], duration: 0.6 });
  }

  // Alinear automáticamente los nodos a las calles de Tacna para tener los tramos viales listos
  if (state.tempTraceNodes.length >= 2) {
    showToast(`🛣️ Alineando nodos de ${route.code} a las calles de Tacna...`);
    const aligned = await alignNodesToStreetNetwork(state.tempTraceNodes);
    if (state.tracingRouteId === route.id && aligned.fullCoords.length >= 2) {
      state.tempTraceNodes = aligned.nodes;
      state.tempTraceSegments = aligned.segments;
      state.tempTraceCoords = aligned.fullCoords;
      renderMapRoutes();
      updateTraceBarMetrics();
      showToast(`✓ Modo Trazado Vial activo (${route.code}): haz clic en cualquier calle o paradero, o arrastra los nodos.`);
    }
  } else {
    showToast(`Modo Trazado Vial activo para ${route.code}: haz clic en calles o paraderos del mapa.`);
  }
}

/**
 * Al hacer clic en cualquier punto del mapa durante el modelado de ruta:
 * 1) Alinea el punto a la calle más cercana (OSRM nearest).
 * 2) Traza automáticamente el camino por las calles desde el nodo anterior (OSRM route).
 */
async function closeRouteLoopToFirstNode() {
  if (!state.tracingRouteId || state.isRoutingStreet) return;
  if (state.tempTraceNodes.length < 2) {
    showToast('⚠️ Agrega al menos 2 nodos antes de cerrar la ruta en el Nodo #1.');
    return;
  }
  const firstNode = state.tempTraceNodes[0];
  const prevNode = state.tempTraceNodes[state.tempTraceNodes.length - 1];
  state.isRoutingStreet = true;
  try {
    const closingNode = {
      lat: firstNode.lat,
      lng: firstNode.lng,
      stopId: firstNode.stopId || null,
      streetName: firstNode.streetName || 'Inicio / Fin',
      isLoopClosure: true
    };
    const seg = await fetchStreetAlignedSegment(prevNode, closingNode);
    state.tempTraceSegments.push(seg);
    state.tempTraceNodes.push(closingNode);
    state.tempTraceClosedLoop = true;
    rebuildTraceCoordsFromSegments();
    renderMapRoutes();
    updateTraceBarMetrics();
  } finally {
    state.isRoutingStreet = false;
  }
  saveRouteTrace(true);
}

async function handleMapClickDuringRouteTrace(rawLat, rawLng) {
  if (!state.tracingRouteId || state.isRoutingStreet) return;

  if (state.tempTraceNodes.length >= 2 && !state.tempTraceClosedLoop) {
    const firstNode = state.tempTraceNodes[0];
    const distMeters = haversineDistanceKm(rawLat, rawLng, firstNode.lat, firstNode.lng) * 1000;
    if (distMeters <= 25) {
      await closeRouteLoopToFirstNode();
      return;
    }
  }

  state.isRoutingStreet = true;

  try {
    const snapped = await snapCoordinateToStreet(rawLat, rawLng);
    const newNode = {
      lat: snapped.lat,
      lng: snapped.lng,
      stopId: null,
      streetName: snapped.streetName
    };

    if (state.tempTraceNodes.length > 0) {
      const prevNode = state.tempTraceNodes[state.tempTraceNodes.length - 1];
      const seg = await fetchStreetAlignedSegment(prevNode, newNode);
      state.tempTraceSegments.push(seg);
    }

    state.tempTraceNodes.push(newNode);
    rebuildTraceCoordsFromSegments();
    renderMapRoutes();
    updateTraceBarMetrics();

    showToast(`🛣️ Nodo #${state.tempTraceNodes.length} alineado a ${snapped.streetName || 'calle'}`);
  } finally {
    state.isRoutingStreet = false;
  }
}

async function handleStopClickedDuringRouteTrace(stop) {
  if (!state.tracingRouteId || state.isRoutingStreet) return;

  if (
    state.tempTraceNodes.length >= 2 &&
    !state.tempTraceClosedLoop &&
    state.tempTraceNodes[0].stopId === stop.id
  ) {
    await closeRouteLoopToFirstNode();
    return;
  }

  state.isRoutingStreet = true;

  try {
    const lastNode = state.tempTraceNodes[state.tempTraceNodes.length - 1];
    // Si hace clic sobre el último paradero que acaba de poner, lo retira (toggle rápido)
    if (lastNode && lastNode.stopId === stop.id) {
      state.tempTraceNodes.pop();
      if (state.tempTraceSegments.length > 0) {
        state.tempTraceSegments.pop();
      }
      rebuildTraceCoordsFromSegments();
      renderMapRoutes();
      updateTraceBarMetrics();
      showToast(`Paradero "${stop.shortName || stop.name}" retirado del final del recorrido.`);
      return;
    }

    const snapped = await snapCoordinateToStreet(stop.latitude, stop.longitude);
    const stopNode = {
      lat: snapped.lat,
      lng: snapped.lng,
      stopId: stop.id,
      streetName: snapped.streetName || stop.name
    };

    if (state.tempTraceNodes.length > 0) {
      const prevNode = state.tempTraceNodes[state.tempTraceNodes.length - 1];
      const seg = await fetchStreetAlignedSegment(prevNode, stopNode);
      state.tempTraceSegments.push(seg);
    }

    state.tempTraceNodes.push(stopNode);
    rebuildTraceCoordsFromSegments();
    renderMapRoutes();
    updateTraceBarMetrics();

    showToast(`+ Paradero "${stop.shortName || stop.name}" conectado por calle (#${state.tempTraceNodes.length})`);
  } finally {
    state.isRoutingStreet = false;
  }
}

function updateTraceBarMetrics() {
  const route = state.routes.find(r => r.id === state.tracingRouteId);
  const speed = route ? (route.averageSpeedKmh || 22) : 22;
  const metrics = computeRouteDistanceAndEta(state.tempTraceCoords, speed, state.tempTraceStopIds.length);
  const pill = document.getElementById('trace-route-metrics');
  if (pill) {
    pill.textContent = `${metrics.totalDistanceKm} km • ~${metrics.estimatedTotalMinutes} min (${state.tempTraceNodes.length} nodos / ${state.tempTraceStopIds.length} paraderos)`;
  }
}

function undoTracePoint() {
  if (!state.tracingRouteId || state.tempTraceNodes.length === 0) return;
  const popped = state.tempTraceNodes.pop();
  if (popped && popped.isLoopClosure) {
    state.tempTraceClosedLoop = false;
  }
  if (state.tempTraceSegments.length > 0) {
    state.tempTraceSegments.pop();
  }
  rebuildTraceCoordsFromSegments();
  renderMapRoutes();
  updateTraceBarMetrics();
  showToast(`↶ Último nodo deshecho (${state.tempTraceNodes.length} nodos restantes).`);
}

function clearTracePoints() {
  if (!state.tracingRouteId) return;
  state.tempTraceNodes = [];
  state.tempTraceSegments = [];
  state.tempTraceCoords = [];
  state.tempTraceStopIds = [];
  state.tempTraceClosedLoop = false;
  renderMapRoutes();
  updateTraceBarMetrics();
  showToast('🧹 Lienzo de ruta limpiado. Haz clic en paraderos o calles del mapa para modelar desde cero.');
}

async function snapTraceToRouteStops() {
  if (!state.tracingRouteId || state.isRoutingStreet) return;
  const stopMap = buildFlexibleStopMap();

  // Si hay nodos actuales los realineamos todos por las calles; si no hay nodos, usamos los paraderos de la ruta
  let baseNodes = state.tempTraceNodes.length >= 2
    ? [...state.tempTraceNodes]
    : state.tempTraceStopIds.map(sid => {
        const st = stopMap.get(sid);
        return st ? { lat: st.latitude, lng: st.longitude, stopId: sid, streetName: st.name } : null;
      }).filter(Boolean);

  if (baseNodes.length < 2) {
    showToast('⚠️ Agrega al menos 2 nodos o paraderos en el mapa para alinearlos a las calles.');
    return;
  }

  state.isRoutingStreet = true;
  showToast('🛣️ Calculando trazado exacto por las calles de Tacna...');
  try {
    const aligned = await alignNodesToStreetNetwork(baseNodes);
    state.tempTraceNodes = aligned.nodes;
    state.tempTraceSegments = aligned.segments;
    rebuildTraceCoordsFromSegments();
    renderMapRoutes();
    updateTraceBarMetrics();
    showToast(`✓ Recorrido alineado a las calles (${state.tempTraceNodes.length} nodos viales / ${state.tempTraceCoords.length} vértices).`);
  } finally {
    state.isRoutingStreet = false;
  }
}

function saveRouteTrace(closedByLoop = false) {
  if (!state.tracingRouteId) return;
  const route = state.routes.find(r => r.id === state.tracingRouteId);
  if (!route) return;

  if (state.tempTraceCoords.length < 2) {
    showToast('⚠️ La ruta necesita al menos 2 nodos en el mapa para guardar el trazado.');
    return;
  }

  const uniqueStopIds = [...new Set(state.tempTraceStopIds)];
  const metrics = computeRouteDistanceAndEta(
    state.tempTraceCoords,
    route.averageSpeedKmh || 22,
    uniqueStopIds.length
  );

  route.keyStopIds = uniqueStopIds;
  route.controlNodes = state.tempTraceNodes.map(n => ({
    lat: n.lat,
    lng: n.lng,
    stopId: n.stopId || null,
    streetName: n.streetName || '',
    isLoopClosure: Boolean(n.isLoopClosure)
  }));
  route.pathCoordinates = [...state.tempTraceCoords];
  route.totalDistanceKm = metrics.totalDistanceKm;
  route.estimatedTotalMinutes = metrics.estimatedTotalMinutes;

  const isClosed = Boolean(closedByLoop || state.tempTraceClosedLoop);
  const firstNode = state.tempTraceNodes[0] || null;
  route.isClosedLoop = isClosed;
  route.terminalStopId = isClosed && firstNode ? (firstNode.stopId || null) : null;
  route.terminalLabel = isClosed && firstNode ? (firstNode.streetName || 'Inicio / Fin') : null;
  route.loopRule = isClosed ? 'mandatory_alighting_reboard_pays' : null;

  const traceBar = document.getElementById('route-trace-bar');
  if (traceBar) traceBar.classList.add('hidden');

  state.tracingRouteId = null;
  state.tempTraceNodes = [];
  state.tempTraceSegments = [];
  state.tempTraceCoords = [];
  state.tempTraceStopIds = [];
  state.tempTraceClosedLoop = false;

  syncStopsRoutesPassingFromRoutes();
  saveRoutesToLocalStorage();
  renderRoutesList();
  updateRouteStats();
  renderMapRoutes();
  renderStopsList();
  renderMapMarkers();

  sendWsMessage({
    type: 'save_route',
    route: route,
    user: state.currentUser
  });

  if (isClosed) {
    showToast(`🔁 Ruta cerrada en Nodo #1 (Inicio/Fin: descenso obligatorio; reabordaje paga nuevo pasaje). ${route.code} guardada (${route.totalDistanceKm} km).`);
  } else {
    showToast(`✓ Trazado vial de ${route.code} guardado (${route.totalDistanceKm} km • ~${route.estimatedTotalMinutes} min).`);
  }
}

function cancelRouteTrace() {
  const traceBar = document.getElementById('route-trace-bar');
  if (traceBar) traceBar.classList.add('hidden');
  state.tracingRouteId = null;
  state.tempTraceNodes = [];
  state.tempTraceSegments = [];
  state.tempTraceCoords = [];
  state.tempTraceStopIds = [];
  state.tempTraceClosedLoop = false;
  renderMapRoutes();
  showToast('Edición de trazado cancelada.');
}

// ═══════════════════════════════════════════════════════════════════════
// DIÁLOGO MODAL: CREAR / EDITAR RUTA (ORDINARIA O EXTERNA)
// ═══════════════════════════════════════════════════════════════════════

function openRouteDialog(route = null) {
  const dialog = document.getElementById('route-dialog');
  const title = document.getElementById('route-dialog-title');
  const badge = document.getElementById('route-dialog-badge');
  const btnDelete = document.getElementById('btn-delete-route');
  const btnOpenTracer = document.getElementById('btn-open-map-tracer-from-modal');

  if (route) {
    title.textContent = `Editar ${route.code}`;
    const isOrd = route.routeType === 'ordinary';
    badge.textContent = isOrd ? 'ORDINARIA • TRACKING & QR' : 'EXTERNA • REFERENCIAL';
    badge.className = `dialog-badge ${isOrd ? 'official' : 'proposal'}`;
    btnDelete.style.display = 'inline-flex';
    btnOpenTracer.style.display = 'inline-flex';

    document.getElementById('route-field-id').value = route.id;
    document.getElementById('route-field-code').value = route.code;
    document.getElementById('route-field-title').value = route.title;
    document.getElementById('route-field-type').value = route.routeType || 'ordinary';
    document.getElementById('route-field-service').value = route.isInService ? 'true' : 'false';
    document.getElementById('route-field-corridor').value = route.corridor || '';
    document.getElementById('route-field-freq').value = route.frequencyMinutes || 6;
    document.getElementById('route-field-speed').value = route.averageSpeedKmh || 22;
    document.getElementById('route-field-schedule').value = route.scheduleLabel || '05:30 - 22:30';
    document.getElementById('route-field-color').value = route.colorHex || '#2563EB';

    renderRouteStopsChecklist(route.keyStopIds || []);
  } else {
    title.textContent = 'Nueva Ruta de Transporte';
    badge.textContent = 'NUEVA RUTA';
    badge.className = 'dialog-badge official';
    btnDelete.style.display = 'none';
    btnOpenTracer.style.display = 'inline-flex';

    document.getElementById('route-field-id').value = '';
    document.getElementById('route-field-code').value = '';
    document.getElementById('route-field-title').value = '';
    document.getElementById('route-field-type').value = 'ordinary';
    document.getElementById('route-field-service').value = 'true';
    document.getElementById('route-field-corridor').value = '';
    document.getElementById('route-field-freq').value = 8;
    document.getElementById('route-field-speed').value = 22;
    document.getElementById('route-field-schedule').value = '05:30 - 22:30';
    document.getElementById('route-field-color').value = '#10B981';

    renderRouteStopsChecklist([]);
  }

  syncRouteTypeVisibilityInModal();
  updateRouteModalEtaPreview();
  dialog.showModal();
}

function syncRouteTypeVisibilityInModal() {
  const typeSelect = document.getElementById('route-field-type');
  const serviceSelect = document.getElementById('route-field-service');
  const badge = document.getElementById('route-dialog-badge');
  if (!typeSelect || !serviceSelect) return;

  const isOrd = typeSelect.value === 'ordinary';
  serviceSelect.disabled = !isOrd;
  if (!isOrd) {
    serviceSelect.value = 'false';
  }
  if (badge) {
    badge.textContent = isOrd ? 'ORDINARIA • TRACKING & QR' : 'EXTERNA • REFERENCIAL';
    badge.className = `dialog-badge ${isOrd ? 'official' : 'proposal'}`;
  }
}

function renderRouteStopsChecklist(selectedIds = []) {
  const container = document.getElementById('route-stops-checklist');
  if (!container) return;

  const selectedSet = new Set(selectedIds);
  // Ordenar: primero los ya seleccionados en su orden de secuencia, luego el resto
  const stopMap = buildFlexibleStopMap();
  const orderedStops = [];
  selectedIds.forEach(sid => {
    const s = stopMap.get(sid);
    if (s) orderedStops.push(s);
  });
  state.stops.forEach(s => {
    if (!selectedSet.has(s.id)) orderedStops.push(s);
  });

  container.innerHTML = orderedStops.map((stop) => {
    const checked = selectedSet.has(stop.id);
    const seqIdx = selectedIds.indexOf(stop.id);
    const isOfficial = stop.isOfficial ?? (!stop.category.includes('proposed') && !stop.id.startsWith('prop-'));

    return `
      <label class="route-stop-check-item ${checked ? 'is-checked' : ''}" data-stop-id="${stop.id}">
        <input type="checkbox" class="route-stop-checkbox" value="${stop.id}" ${checked ? 'checked' : ''}>
        <span class="route-stop-check-name" title="${escapeHtml(stop.name)}">
          ${seqIdx !== -1 ? `<strong>#${seqIdx + 1}</strong> ` : ''}${escapeHtml(stop.shortName || stop.name)}
        </span>
        <span class="route-stop-check-badge">${isOfficial ? 'Oficial' : 'Prop.'}</span>
      </label>
    `;
  }).join('');

  container.querySelectorAll('.route-stop-checkbox').forEach(cb => {
    cb.addEventListener('change', () => {
      const label = cb.closest('.route-stop-check-item');
      if (label) label.classList.toggle('is-checked', cb.checked);
      updateRouteModalEtaPreview();
    });
  });
}

function getSelectedStopIdsFromRouteModal() {
  const container = document.getElementById('route-stops-checklist');
  if (!container) return [];
  return Array.from(container.querySelectorAll('.route-stop-checkbox:checked')).map(cb => cb.value);
}

function updateRouteModalEtaPreview() {
  const selectedIds = getSelectedStopIdsFromRouteModal();
  const countEl = document.getElementById('route-selected-stops-count');
  const previewEl = document.getElementById('route-modal-eta-preview');
  const speed = parseFloat(document.getElementById('route-field-speed')?.value) || 22;

  if (countEl) countEl.textContent = selectedIds.length;

  const stopMap = buildFlexibleStopMap();
  const coords = selectedIds.map(sid => {
    const s = stopMap.get(sid);
    return s ? [s.latitude, s.longitude] : null;
  }).filter(Boolean);

  const metrics = computeRouteDistanceAndEta(coords, speed, selectedIds.length);
  if (previewEl) {
    previewEl.textContent = `Distancia est.: ${metrics.totalDistanceKm} km • Tiempo vuelta: ~${metrics.estimatedTotalMinutes} min`;
  }
}

function closeRouteDialog() {
  const dialog = document.getElementById('route-dialog');
  if (dialog) {
    dialog.close();
    dialog.returnValue = '';
  }
}

async function handleRouteFormSubmit(e, openTracerAfter = false) {
  if (e && e.preventDefault) e.preventDefault();

  const id = document.getElementById('route-field-id').value.trim();
  const code = document.getElementById('route-field-code').value.trim();
  const title = document.getElementById('route-field-title').value.trim();
  if (!code || !title) {
    showToast('⚠️ Ingresa al menos el código y el título de la ruta.');
    return;
  }
  const routeType = document.getElementById('route-field-type').value;
  const isOrdinary = routeType === 'ordinary';
  const isInService = isOrdinary && document.getElementById('route-field-service').value === 'true';
  const corridor = document.getElementById('route-field-corridor').value.trim();
  const frequencyMinutes = parseInt(document.getElementById('route-field-freq').value, 10) || 8;
  const averageSpeedKmh = parseFloat(document.getElementById('route-field-speed').value) || 22.0;
  const scheduleLabel = document.getElementById('route-field-schedule').value.trim() || '05:30 - 22:30';
  const colorHex = document.getElementById('route-field-color').value || '#2563EB';
  const keyStopIds = getSelectedStopIdsFromRouteModal();
  const shouldLaunchTracer = openTracerAfter || (!id && keyStopIds.length < 2);

  const stopMap = buildFlexibleStopMap();
  const rawStopNodes = keyStopIds.map(sid => {
    const s = stopMap.get(sid);
    return s
      ? { lat: parseFloat(s.latitude.toFixed(6)), lng: parseFloat(s.longitude.toFixed(6)), stopId: sid, streetName: s.name }
      : null;
  }).filter(Boolean);

  const statusLabel = isOrdinary
    ? (isInService ? 'En Servicio • GPS & Pago QR Activo' : 'Fuera de Servicio Temporal • Sin unidades activas')
    : 'Línea Externa de Tacna • Sin Tracking GPS';

  let savedRoute = null;

  if (id) {
    const idx = state.routes.findIndex(r => r.id === id);
    if (idx !== -1) {
      const prevIds = (state.routes[idx].keyStopIds || []).join(',');
      const nextIds = keyStopIds.join(',');
      const alreadyStreetAligned =
        prevIds === nextIds &&
        Array.isArray(state.routes[idx].pathCoordinates) &&
        state.routes[idx].pathCoordinates.length > keyStopIds.length + 2;

      let pathCoordinates = state.routes[idx].pathCoordinates || [];
      let controlNodes = state.routes[idx].controlNodes || rawStopNodes;

      if (!alreadyStreetAligned && rawStopNodes.length >= 2) {
        showToast(`🛣️ Alineando paraderos de "${code}" por las calles de Tacna...`);
        const aligned = await alignNodesToStreetNetwork(rawStopNodes);
        pathCoordinates = aligned.fullCoords.length >= 2
          ? aligned.fullCoords
          : rawStopNodes.map(n => [n.lat, n.lng]);
        controlNodes = aligned.nodes;
      }

      const updatedMetrics = computeRouteDistanceAndEta(pathCoordinates, averageSpeedKmh, keyStopIds.length);

      savedRoute = {
        ...state.routes[idx],
        code,
        title,
        routeType,
        isInService,
        supportsQrPayment: isOrdinary,
        supportsArrivalNotification: isOrdinary,
        statusLabel,
        corridor,
        frequencyMinutes: isOrdinary ? frequencyMinutes : 0,
        averageSpeedKmh,
        scheduleLabel,
        colorHex,
        keyStopIds,
        controlNodes,
        pathCoordinates,
        totalDistanceKm: updatedMetrics.totalDistanceKm,
        estimatedTotalMinutes: updatedMetrics.estimatedTotalMinutes
      };
      state.routes[idx] = savedRoute;
      showToast(`✓ Ruta "${code}" actualizada y alineada a las calles.`);
    }
  } else {
    let pathCoordinates = [];
    let controlNodes = [];
    if (rawStopNodes.length >= 2) {
      showToast(`🛣️ Trazando nueva ruta "${code}" por las calles de Tacna...`);
      const aligned = await alignNodesToStreetNetwork(rawStopNodes);
      pathCoordinates = aligned.fullCoords.length >= 2
        ? aligned.fullCoords
        : rawStopNodes.map(n => [n.lat, n.lng]);
      controlNodes = aligned.nodes;
    }
    const metrics = computeRouteDistanceAndEta(pathCoordinates, averageSpeedKmh, keyStopIds.length);

    const newId = `route-${slugify(code)}-${Date.now().toString(36)}`;
    savedRoute = {
      id: newId,
      code,
      title,
      routeType,
      isInService,
      supportsQrPayment: isOrdinary,
      supportsArrivalNotification: isOrdinary,
      statusLabel,
      corridor,
      frequencyMinutes: isOrdinary ? frequencyMinutes : 0,
      averageSpeedKmh,
      scheduleLabel,
      colorHex,
      iconName: 'bus.doubledecker.fill',
      keyStopIds,
      controlNodes,
      pathCoordinates,
      totalDistanceKm: metrics.totalDistanceKm,
      estimatedTotalMinutes: metrics.estimatedTotalMinutes
    };
    state.routes.push(savedRoute);
    state.selectedRouteId = newId;
    if (!shouldLaunchTracer) {
      showToast(`✓ Nueva ruta "${code}" creada y alineada a las calles de Tacna.`);
    }
  }

  syncStopsRoutesPassingFromRoutes();
  saveRoutesToLocalStorage();
  renderRoutesList();
  updateRouteStats();
  renderMapRoutes();
  renderStopsList();
  renderMapMarkers();
  closeRouteDialog();

  if (savedRoute) {
    sendWsMessage({
      type: 'save_route',
      route: savedRoute,
      user: state.currentUser
    });
    if (shouldLaunchTracer) {
      startTracingRouteOnMap(savedRoute.id);
    } else {
      selectRouteOnMap(savedRoute.id, true);
    }
  }
}

function promptDeleteRoute(routeId) {
  const route = state.routes.find(r => r.id === routeId);
  if (!route) return;

  const dialog = document.getElementById('confirm-dialog');
  const title = document.getElementById('confirm-dialog-title');
  const desc = document.getElementById('confirm-dialog-desc');
  const btnConfirm = document.getElementById('btn-confirm-delete');

  if (title) title.textContent = `¿Eliminar ${route.code}?`;
  if (desc) {
    desc.textContent = `¿Estás seguro de que deseas eliminar la ruta "${route.code} - ${route.title}"? Se actualizarán automáticamente los paraderos asociados.`;
  }
  if (btnConfirm) {
    btnConfirm.textContent = 'Sí, Eliminar Ruta';
    btnConfirm.onclick = () => {
      executeDeleteRoute(routeId);
      dialog.close();
    };
  }

  dialog.showModal();
}

function executeDeleteRoute(routeId) {
  const route = state.routes.find(r => r.id === routeId);
  state.routes = state.routes.filter(r => r.id !== routeId);
  if (state.selectedRouteId === routeId) {
    state.selectedRouteId = state.routes[0]?.id || null;
  }

  saveRoutesToLocalStorage();
  renderRoutesList();
  updateRouteStats();
  renderMapRoutes();
  renderStopsList();
  renderMapMarkers();
  closeRouteDialog();

  sendWsMessage({
    type: 'delete_route',
    routeId: routeId,
    user: state.currentUser
  });

  showToast(`🗑️ Ruta "${route?.code || routeId}" eliminada.`);
}

function downloadRoutesJsonFile() {
  const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(state.routes, null, 2));
  const downloadAnchor = document.createElement('a');
  downloadAnchor.setAttribute("href", dataStr);
  downloadAnchor.setAttribute("download", `rutas_tacna_${new Date().toISOString().slice(0, 10)}.json`);
  document.body.appendChild(downloadAnchor);
  downloadAnchor.click();
  downloadAnchor.remove();
  showToast('Catálogo de rutas JSON descargado con éxito.');
}

// ═══════════════════════════════════════════════════════════════════════
// DIÁLOGO DE EDICIÓN / CREACIÓN DE PARADERO (MODERN-WEB-GUIDANCE COMPLIANT)
// ═══════════════════════════════════════════════════════════════════════

function openStopDialog(stop = null, defaultLat = null, defaultLng = null) {
  const dialog = document.getElementById('stop-dialog');
  const title = document.getElementById('dialog-title');
  const badge = document.getElementById('dialog-badge');
  const btnDelete = document.getElementById('btn-delete-stop');

  if (stop) {
    // Modo Edición
    title.textContent = 'Editar Paradero';
    const isOfficial = stop.isOfficial ?? (!stop.category.includes('proposed') && !stop.id.startsWith('prop-'));
    badge.textContent = isOfficial ? 'OFICIAL' : 'PROPUESTA';
    badge.className = `dialog-badge ${isOfficial ? 'official' : 'proposal'}`;
    btnDelete.style.display = 'inline-flex';

    document.getElementById('field-id').value = stop.id;
    document.getElementById('field-name').value = stop.name;
    document.getElementById('field-shortname').value = stop.shortName || stop.name;
    document.getElementById('field-subtitle').value = stop.subtitle;
    document.getElementById('field-category').value = stop.category;
    document.getElementById('field-icon').value = stop.iconName || 'bus.fill';
    document.getElementById('field-routes').value = (stop.routesPassing || []).join(', ');
    document.getElementById('field-lat').value = stop.latitude.toFixed(6);
    document.getElementById('field-lng').value = stop.longitude.toFixed(6);
    document.getElementById('field-note').value = stop.statusNote || '';
  } else {
    // Modo Creación
    title.textContent = 'Nuevo Paradero';
    badge.textContent = 'NUEVO';
    badge.className = 'dialog-badge official';
    btnDelete.style.display = 'none';

    document.getElementById('field-id').value = '';
    document.getElementById('field-name').value = '';
    document.getElementById('field-shortname').value = '';
    document.getElementById('field-subtitle').value = '';
    document.getElementById('field-category').value = 'marketsCommercial';
    document.getElementById('field-icon').value = 'bus.fill';
    document.getElementById('field-routes').value = '';
    document.getElementById('field-lat').value = defaultLat ? defaultLat.toFixed(6) : '-18.013580';
    document.getElementById('field-lng').value = defaultLng ? defaultLng.toFixed(6) : '-70.250550';
    document.getElementById('field-note').value = '';
  }

  document.getElementById('btn-pick-coords').textContent = '📍 Marcar en mapa';
  dialog.showModal();
}

function closeStopDialog() {
  const dialog = document.getElementById('stop-dialog');
  dialog.close();
  dialog.returnValue = '';
}

function handleStopFormSubmit(e) {
  e.preventDefault();

  const id = document.getElementById('field-id').value.trim();
  const name = document.getElementById('field-name').value.trim();
  const shortName = document.getElementById('field-shortname').value.trim() || name;
  const subtitle = document.getElementById('field-subtitle').value.trim();
  const category = document.getElementById('field-category').value;
  const iconName = document.getElementById('field-icon').value || 'bus.fill';
  const routesStr = document.getElementById('field-routes').value.trim();
  const lat = parseFloat(document.getElementById('field-lat').value);
  const lng = parseFloat(document.getElementById('field-lng').value);
  const statusNote = document.getElementById('field-note').value.trim() || null;

  const routesPassing = routesStr ? routesStr.split(',').map(r => r.trim()).filter(Boolean) : [];
  const isOfficial = !category.startsWith('proposed');

  let targetStopId = id;

  if (id) {
    // Actualizar paradero existente
    const index = state.stops.findIndex(s => s.id === id);
    if (index !== -1) {
      state.stops[index] = {
        ...state.stops[index],
        name,
        shortName,
        subtitle,
        category,
        iconName,
        isOfficial,
        routesPassing,
        latitude: lat,
        longitude: lng,
        statusNote
      };
      showToast(`Paradero "${name}" actualizado con éxito.`);
    }
  } else {
    // Crear nuevo paradero
    const newId = `stop-${slugify(name)}-${Date.now().toString(36)}`;
    targetStopId = newId;
    const newStop = {
      id: newId,
      name,
      shortName,
      subtitle,
      category,
      categoryLabel: getCategoryLabel(category),
      isOfficial,
      latitude: lat,
      longitude: lng,
      routesPassing,
      colorHex: isOfficial ? '#2563EB' : '#F59E0B',
      iconName,
      statusNote
    };
    state.stops.push(newStop);
    showToast(`Nuevo paradero "${name}" creado.`);
  }

  // Sincronizar bidireccionalmente con las rutas del catálogo (keyStopIds)
  if (targetStopId) {
    const passedSet = new Set(routesPassing.map(c => c.toLowerCase()));
    state.routes.forEach(route => {
      const codeLower = (route.code || '').trim().toLowerCase();
      const hasStop = (route.keyStopIds || []).includes(targetStopId);
      if (passedSet.has(codeLower) && !hasStop) {
        route.keyStopIds = [...(route.keyStopIds || []), targetStopId];
      } else if (!passedSet.has(codeLower) && hasStop) {
        route.keyStopIds = (route.keyStopIds || []).filter(sid => sid !== targetStopId);
      }
    });
    saveRoutesToLocalStorage();
  }

  saveToLocalStorage();
  renderMapMarkers();
  renderMapRoutes();
  renderStopsList();
  renderRoutesList();
  updateStats();
  updateRouteStats();
  closeStopDialog();

  if (targetStopId) selectStop(targetStopId, true);
}

function promptDeleteStop(stopId) {
  const stop = state.stops.find(s => s.id === stopId);
  if (!stop) return;

  const dialog = document.getElementById('confirm-dialog');
  const title = document.getElementById('confirm-dialog-title');
  const desc = document.getElementById('confirm-dialog-desc');
  const btnConfirm = document.getElementById('btn-confirm-delete');

  if (title) title.textContent = '¿Eliminar este paradero?';
  if (desc) {
    desc.textContent = `¿Estás seguro de que deseas eliminar permanentemente el paradero "${stop.name}" (${stop.subtitle})?`;
  }
  if (btnConfirm) {
    btnConfirm.textContent = 'Sí, Eliminar Paradero';
    btnConfirm.onclick = () => {
      executeDeleteStop(stopId);
      dialog.close();
    };
  }

  dialog.showModal();
}

function executeDeleteStop(stopId) {
  const stop = state.stops.find(s => s.id === stopId);
  state.stops = state.stops.filter(s => s.id !== stopId);
  // También retirar de las rutas que lo referenciaban
  state.routes.forEach(r => {
    if (Array.isArray(r.keyStopIds) && r.keyStopIds.includes(stopId)) {
      r.keyStopIds = r.keyStopIds.filter(sid => sid !== stopId);
    }
  });
  saveRoutesToLocalStorage();
  saveToLocalStorage();
  renderMapMarkers();
  renderMapRoutes();
  renderStopsList();
  renderRoutesList();
  updateStats();
  updateRouteStats();
  closeStopDialog();
  showToast(`Paradero "${stop?.name || stopId}" eliminado.`);
}

// ═══════════════════════════════════════════════════════════════════════
// EXPORTACIÓN A SWIFT (DomainModels.swift) & JSON
// ═══════════════════════════════════════════════════════════════════════

function openExportSwiftDialog() {
  const codeBlock = document.getElementById('export-code-block');
  codeBlock.textContent = generateSwiftCatalogCode(state.stops);
  document.getElementById('export-dialog').showModal();
}

function generateSwiftCatalogCode(stops) {
  const official = stops.filter(s => s.isOfficial ?? (!s.category.includes('proposed') && !s.id.startsWith('prop-')));
  const proposals = stops.filter(s => !(s.isOfficial ?? (!s.category.includes('proposed') && !s.id.startsWith('prop-'))));

  let swift = `// ═══════════════════════════════════════════════════════════════════════\n`;
  swift += `// CATÁLOGO OFICIAL DE PARADEROS Y PUNTOS CLAVE DE TACNA\n`;
  swift += `// Generado automáticamente desde Bus Conectado Admin Panel (${new Date().toLocaleDateString('es-PE')})\n`;
  swift += `// Total: ${stops.length} paraderos geocalibrados con precisión de alta resolución\n`;
  swift += `// ═══════════════════════════════════════════════════════════════════════\n\n`;
  swift += `extension TacnaDestinationPlace {\n`;
  swift += `    static let catalog: [TacnaDestinationPlace] = [\n`;

  // 1. Oficiales
  swift += `        // ── 1. PARADEROS OFICIALES CLAVE DE TACNA (${official.length}) ──\n`;
  official.forEach(stop => {
    swift += formatSwiftPlaceEntry(stop);
  });

  // 2. Propuestas
  swift += `\n        // ── 2. PROPUESTAS DE PARADEROS PARA OFICIALIZAR (${proposals.length}) ──\n`;
  proposals.forEach(stop => {
    swift += formatSwiftPlaceEntry(stop);
  });

  swift += `    ]\n`;
  swift += `}\n`;

  return swift;
}

function formatSwiftPlaceEntry(stop) {
  const routesFormatted = (stop.routesPassing || []).map(r => `"${r}"`).join(', ');
  const categoryEnumCase = mapCategoryToSwiftEnum(stop.category);
  const noteStr = stop.statusNote ? `"${stop.statusNote.replace(/"/g, '\\"')}"` : `nil`;

  return `        TacnaDestinationPlace(
            id: "${stop.id}",
            name: "${stop.name}",
            shortName: "${stop.shortName || stop.name}",
            subtitle: "${stop.subtitle}",
            category: .${categoryEnumCase},
            routesPassing: [${routesFormatted}],
            iconName: "${stop.iconName || 'mappin.and.ellipse'}",
            iconColorHex: "${stop.colorHex || '#2563EB'}",
            latitude: ${stop.latitude.toFixed(6)},
            longitude: ${stop.longitude.toFixed(6)},
            routeCase: .busRoute14,
            totalDurationMinutes: 8,
            secondaryDurationMinutes: 13,
            walkingDirectMinutes: 14,
            distanceLabel: "Tacna",
            walkInitialMinutes: 2,
            busRideMinutes: 6,
            walkFinalMinutes: 0,
            boardingStopName: "Paradero cercano",
            alightingStopName: "${stop.shortName || stop.name}",
            intermediateStopName: nil,
            statusNote: ${noteStr}
        ),\n`;
}

function mapCategoryToSwiftEnum(cat) {
  switch (cat) {
    case 'marketsCommercial': return 'marketsCommercial';
    case 'plazasCentral': return 'plazasCentral';
    case 'institutionsTerminals': return 'institutionsTerminals';
    case 'proposedHospitals': return 'proposedHospitals';
    case 'proposedUrbanGrowth': return 'proposedUrbanGrowth';
    case 'proposedEducation': return 'proposedEducation';
    case 'proposedTouristBorder': return 'proposedTouristBorder';
    default: return 'marketsCommercial';
  }
}

function downloadJsonFile() {
  const dataStr = "data:text/json;charset=utf-8," + encodeURIComponent(JSON.stringify(state.stops, null, 2));
  const downloadAnchor = document.createElement('a');
  downloadAnchor.setAttribute("href", dataStr);
  downloadAnchor.setAttribute("download", `paraderos_tacna_${new Date().toISOString().slice(0, 10)}.json`);
  document.body.appendChild(downloadAnchor);
  downloadAnchor.click();
  downloadAnchor.remove();
  showToast('Base de datos JSON descargada con éxito.');
}

function downloadSwiftFile() {
  const swiftCode = generateSwiftCatalogCode(state.stops);
  const dataStr = "data:text/plain;charset=utf-8," + encodeURIComponent(swiftCode);
  const downloadAnchor = document.createElement('a');
  downloadAnchor.setAttribute("href", dataStr);
  downloadAnchor.setAttribute("download", `DomainModels_paraderos.swift`);
  document.body.appendChild(downloadAnchor);
  downloadAnchor.click();
  downloadAnchor.remove();
  showToast('Archivo Swift descargado con éxito.');
}

// ═══════════════════════════════════════════════════════════════════════
// SETUP DE EVENTOS DE INTERFAZ & DIÁLOGOS
// ═══════════════════════════════════════════════════════════════════════

function setupUIEventListeners() {
  // Conmutador principal de módulos: Paraderos vs Rutas vs Choferes vs Clientes vs POS vs Estadísticas
  const tabStops = document.getElementById('tab-module-stops');
  const tabRoutes = document.getElementById('tab-module-routes');
  const tabDrivers = document.getElementById('tab-module-drivers');
  const tabClients = document.getElementById('tab-module-clients');
  const tabPos = document.getElementById('tab-module-pos');
  const tabStats = document.getElementById('tab-module-stats');

  if (tabStops) tabStops.addEventListener('click', () => switchAdminModule('stops'));
  if (tabRoutes) tabRoutes.addEventListener('click', () => switchAdminModule('routes'));
  if (tabDrivers) tabDrivers.addEventListener('click', () => switchAdminModule('drivers'));
  if (tabClients) tabClients.addEventListener('click', () => switchAdminModule('clients'));
  if (tabPos) tabPos.addEventListener('click', () => switchAdminModule('pos'));
  if (tabStats) tabStats.addEventListener('click', () => switchAdminModule('stats'));

  const btnGotoCreateRoute = document.getElementById('btn-goto-create-route');
  if (btnGotoCreateRoute) {
    btnGotoCreateRoute.addEventListener('click', () => {
      switchAdminModule('routes');
      document.getElementById('btn-add-route')?.click();
    });
  }

  const btnOpenAddDriver = document.getElementById('btn-open-add-driver');
  if (btnOpenAddDriver) {
    btnOpenAddDriver.addEventListener('click', () => {
      openUserDialog('DRIVER');
    });
  }

  const driversSearchInput = document.getElementById('drivers-search-input');
  if (driversSearchInput) {
    driversSearchInput.addEventListener('input', () => renderDriversTable());
  }

  // Botón Refrescar POS
  const btnRefreshPos = document.getElementById('btn-refresh-pos');
  if (btnRefreshPos) {
    btnRefreshPos.addEventListener('click', async () => {
      await loadPosData();
      showToast('Datos POS y transacciones actualizados.');
    });
  }

  // Botones de Modales POS y Usuarios
  const btnOpenAddPos = document.getElementById('btn-open-add-pos');
  if (btnOpenAddPos) btnOpenAddPos.addEventListener('click', () => openPosDialog());

  const btnOpenAddUser = document.getElementById('btn-open-add-user');
  if (btnOpenAddUser) btnOpenAddUser.addEventListener('click', () => openUserDialog());

  // Botón Nuevo Paradero
  document.getElementById('btn-add-stop').addEventListener('click', () => {
    openStopDialog(null);
  });

  // Botón Nueva Ruta
  const btnAddRoute = document.getElementById('btn-add-route');
  if (btnAddRoute) {
    btnAddRoute.addEventListener('click', () => openRouteDialog(null));
  }

  // Botón Ver Todas las Rutas en el Mapa
  const btnToggleAllRoutes = document.getElementById('btn-toggle-all-routes');
  if (btnToggleAllRoutes) {
    btnToggleAllRoutes.addEventListener('click', () => {
      state.showAllRoutesOnMap = !state.showAllRoutesOnMap;
      btnToggleAllRoutes.textContent = state.showAllRoutesOnMap ? '🗺️ Ocultar Superposición' : '🗺️ Ver Todas en Mapa';
      renderMapRoutes();
      showToast(state.showAllRoutesOnMap ? 'Mostrando todas las rutas sobre el mapa de Tacna.' : 'Mostrando únicamente la ruta seleccionada.');
    });
  }

  // Botón Descargar JSON de Rutas
  const btnExportRoutesJson = document.getElementById('btn-export-routes-json');
  if (btnExportRoutesJson) {
    btnExportRoutesJson.addEventListener('click', downloadRoutesJsonFile);
  }

  // Buscador de Rutas
  const routeSearchInput = document.getElementById('route-search-input');
  const routeSearchClear = document.getElementById('route-search-clear');
  if (routeSearchInput && routeSearchClear) {
    routeSearchInput.addEventListener('input', (e) => {
      state.routeSearchQuery = e.target.value.trim();
      routeSearchClear.hidden = !state.routeSearchQuery;
      renderRoutesList();
    });
    routeSearchClear.addEventListener('click', () => {
      routeSearchInput.value = '';
      state.routeSearchQuery = '';
      routeSearchClear.hidden = true;
      renderRoutesList();
      routeSearchInput.focus();
    });
  }

  // Chips de filtro de Rutas
  document.querySelectorAll('.route-chip').forEach(chip => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.route-chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      state.activeRouteFilter = chip.dataset.routefilter;
      renderRoutesList();
    });
  });

  // Controles de la Barra Flotante de Trazado de Ruta
  document.getElementById('btn-undo-trace-point')?.addEventListener('click', undoTracePoint);
  document.getElementById('btn-clear-trace-points')?.addEventListener('click', clearTracePoints);
  document.getElementById('btn-snap-trace-stops')?.addEventListener('click', snapTraceToRouteStops);
  document.getElementById('btn-cancel-trace')?.addEventListener('click', cancelRouteTrace);
  document.getElementById('btn-save-trace')?.addEventListener('click', saveRouteTrace);

  // Eventos del Modal de Ruta
  document.getElementById('route-form')?.addEventListener('submit', handleRouteFormSubmit);
  document.getElementById('btn-cancel-route-dialog')?.addEventListener('click', closeRouteDialog);
  document.getElementById('route-dialog-close-x')?.addEventListener('click', closeRouteDialog);
  document.getElementById('route-field-type')?.addEventListener('change', syncRouteTypeVisibilityInModal);
  document.getElementById('route-field-speed')?.addEventListener('input', updateRouteModalEtaPreview);

  document.getElementById('btn-delete-route')?.addEventListener('click', () => {
    const id = document.getElementById('route-field-id').value;
    if (id) promptDeleteRoute(id);
  });

  document.getElementById('btn-open-map-tracer-from-modal')?.addEventListener('click', () => {
    handleRouteFormSubmit(null, true);
  });

  // Botones de la Barra Flotante de Reubicación ("¿Deseas mover?" ➔ "Establecer")
  const btnEstablish = document.getElementById('btn-establish-relocation');
  if (btnEstablish) {
    btnEstablish.addEventListener('click', confirmRelocation);
  }

  const btnCancelReloc = document.getElementById('btn-cancel-relocation');
  if (btnCancelReloc) {
    btnCancelReloc.addEventListener('click', cancelRelocation);
  }

  // Botón Exportar a Swift
  document.getElementById('btn-export-swift').addEventListener('click', () => {
    openExportSwiftDialog();
  });

  // Botón Descargar JSON
  document.getElementById('btn-export-json').addEventListener('click', () => {
    downloadJsonFile();
  });

  // Botón Descargar Swift desde modal
  document.getElementById('btn-download-swift-file').addEventListener('click', () => {
    downloadSwiftFile();
  });

  // Copiar código Swift al portapapeles
  document.getElementById('btn-copy-swift').addEventListener('click', async () => {
    const code = document.getElementById('export-code-block').textContent;
    try {
      await navigator.clipboard.writeText(code);
      showToast('¡Código Swift copiado al portapapeles!');
    } catch {
      showToast('Error al copiar. Selecciona y copia manualmente.');
    }
  });

  // Selector de capas del mapa (Dark / Streets / Satellite)
  document.querySelectorAll('.layer-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.layer-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      const layerKey = btn.dataset.layer;
      if (state.tileLayers[layerKey] && state.activeTileLayer !== state.tileLayers[layerKey]) {
        state.map.removeLayer(state.activeTileLayer);
        state.activeTileLayer = state.tileLayers[layerKey];
        state.activeTileLayer.addTo(state.map);
      }
    });
  });

  // Filtros de categoría (Chips)
  document.querySelectorAll('.chip').forEach(chip => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      state.activeFilter = chip.dataset.category;
      renderStopsList();
    });
  });

  // Buscador de Paraderos
  const searchInput = document.getElementById('search-input');
  const searchClear = document.getElementById('search-clear');
  searchInput.addEventListener('input', (e) => {
    state.searchQuery = e.target.value.trim();
    searchClear.hidden = !state.searchQuery;
    renderStopsList();
  });

  searchClear.addEventListener('click', () => {
    searchInput.value = '';
    state.searchQuery = '';
    searchClear.hidden = true;
    renderStopsList();
    searchInput.focus();
  });

  // Formulario de Paradero
  document.getElementById('stop-form').addEventListener('submit', handleStopFormSubmit);

  // Botón Cancelar en modal de paradero
  document.getElementById('btn-cancel-dialog').addEventListener('click', closeStopDialog);
  document.getElementById('dialog-close-x').addEventListener('click', closeStopDialog);

  // Botón Eliminar dentro del modal de edición
  document.getElementById('btn-delete-stop').addEventListener('click', () => {
    const id = document.getElementById('field-id').value;
    if (id) promptDeleteStop(id);
  });

  // Botón Marcar Coordenadas en mapa
  document.getElementById('btn-pick-coords').addEventListener('click', () => {
    state.pickingCoordsMode = true;
    document.getElementById('stop-dialog').close();
    showToast('Haz clic en cualquier punto del mapa para fijar la coordenada.');
  });

  // Modales de Confirmación y Exportación
  document.getElementById('btn-cancel-confirm').addEventListener('click', () => {
    document.getElementById('confirm-dialog').close();
  });
  document.getElementById('confirm-dialog-close-x').addEventListener('click', () => {
    document.getElementById('confirm-dialog').close();
  });

  document.getElementById('btn-close-export').addEventListener('click', () => {
    document.getElementById('export-dialog').close();
  });
  document.getElementById('export-dialog-close-x').addEventListener('click', () => {
    document.getElementById('export-dialog').close();
  });

  // Botón Restablecer catálogo predeterminado
  document.getElementById('btn-reset-catalog').addEventListener('click', async () => {
    if (confirm('¿Restablecer el catálogo completo de paraderos y rutas a sus valores predeterminados de Tacna?')) {
      localStorage.removeItem('bc_admin_stops');
      localStorage.removeItem('bc_admin_routes');
      await loadStopsData();
      await loadRoutesData();
      renderMapMarkers();
      renderMapRoutes();
      renderStopsList();
      renderRoutesList();
      updateStats();
      updateRouteStats();
      showToast('Catálogo de paraderos y rutas restablecido.');
    }
  });
}

// Configuración de Light Dismiss conforme a modern-web-guidance
function setupDialogLightDismiss() {
  const outside = (e, dialog) => {
    const r = dialog.getBoundingClientRect();
    return e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom;
  };

  document.querySelectorAll('dialog[closedby="any"]').forEach(dialog => {
    let pressedOutside = false;
    dialog.addEventListener('pointerdown', (e) => {
      pressedOutside = outside(e, dialog);
    });
    dialog.addEventListener('pointerup', (e) => {
      if (pressedOutside && outside(e, dialog)) {
        dialog.close();
      }
    });
  });
}

// ═══════════════════════════════════════════════════════════════════════
// UTILIDADES
// ═══════════════════════════════════════════════════════════════════════

function showToast(message) {
  const toast = document.getElementById('toast');
  toast.textContent = message;
  toast.classList.add('show');
  clearTimeout(toast._timeout);
  toast._timeout = setTimeout(() => {
    toast.classList.remove('show');
  }, 3200);
}

function escapeHtml(str) {
  if (!str) return '';
  return str.replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/"/g, "&quot;")
            .replace(/'/g, "&#039;");
}

function slugify(text) {
  return text.toString().toLowerCase()
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, '-')
    .replace(/[^\w\-]+/g, '')
    .replace(/\-\-+/g, '-')
    .replace(/^-+/, '')
    .replace(/-+$/, '');
}

function getCategoryLabel(cat) {
  switch (cat) {
    case 'marketsCommercial': return 'Mercados y Zonas Comerciales';
    case 'plazasCentral': return 'Plazas y Zonas Céntricas';
    case 'institutionsTerminals': return 'Instituciones y Terminales';
    case 'proposedHospitals': return 'Propuesta: Hospitales y Salud';
    case 'proposedUrbanGrowth': return 'Propuesta: Cono Sur y Cono Norte';
    case 'proposedEducation': return 'Propuesta: Zonas Educativas (Geofencing)';
    case 'proposedTouristBorder': return 'Propuesta: Zonas Turísticas y Frontera';
    default: return 'Paradero Oficial';
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MÓDULO 3: GESTIÓN DE POS, RECAUDACIÓN Y ABORDAJES EN VIVO
// ═══════════════════════════════════════════════════════════════════════

async function loadPosData() {
  try {
    const [resPos, resTx] = await Promise.all([
      fetch('/api/v1/admin/pos-terminals'),
      fetch('/api/v1/admin/transactions')
    ]);
    if (resPos.ok) {
      state.posTerminals = await resPos.json();
    }
    if (resTx.ok) {
      state.transactions = await resTx.json();
    }
  } catch (err) {
    console.warn('⚠️ [POS Admin] Modo local sin backend activo:', err);
  }

  const countBadge = document.getElementById('pos-terminals-count');
  if (countBadge) {
    countBadge.textContent = `${state.posTerminals.length} terminales`;
  }
  const tabBadgePos = document.getElementById('tab-badge-pos');
  if (tabBadgePos) {
    tabBadgePos.textContent = `${state.posTerminals.length} POS`;
  }

  if (state.activeModule === 'pos') {
    renderPosTerminals();
    renderTransactionsTable();
    updatePosKPIs();
  }
}

function updatePosKPIs() {
  const kpiGross = document.getElementById('pos-kpi-gross');
  const kpiNet = document.getElementById('pos-kpi-net');
  const kpiComm = document.getElementById('pos-kpi-comm');
  const kpiTrips = document.getElementById('pos-kpi-trips');
  const kpiTripsSub = document.getElementById('pos-kpi-trips-sub');

  let totalGross = 0;
  let totalNet = 0;
  let totalComm = 0;
  let totalTrips = 0;
  let studentTrips = 0;
  let conadisTrips = 0;
  let adultTrips = 0;

  state.transactions.forEach(tx => {
    const amount = Number(tx.amount_pen) || 0;
    const comm = Number(tx.commission_pen) || 0;
    const net = Number(tx.net_pen) || (amount - comm);
    const comps = Number(tx.companions_count) || 0;
    const count = 1 + comps;

    totalGross += amount;
    totalComm += comm;
    totalNet += net;
    totalTrips += count;

    if (tx.user_role === 'STUDENT' || (tx.fare_label && tx.fare_label.includes('Universitaria'))) {
      studentTrips += 1;
      if (comps > 0) adultTrips += comps;
    } else if (tx.user_role === 'CONADIS' || (tx.fare_label && tx.fare_label.includes('CONADIS'))) {
      conadisTrips += 1;
    } else {
      adultTrips += count;
    }
  });

  if (kpiGross) kpiGross.textContent = `S/. ${totalGross.toFixed(2)}`;
  if (kpiNet) kpiNet.textContent = `S/. ${totalNet.toFixed(2)}`;
  if (kpiComm) kpiComm.textContent = `S/. ${totalComm.toFixed(2)}`;
  if (kpiTrips) kpiTrips.textContent = `${totalTrips}`;
  if (kpiTripsSub) {
    kpiTripsSub.textContent = `Adulto: ${adultTrips} · Univ: ${studentTrips} · Conadis: ${conadisTrips}`;
  }
}

function renderPosTerminals() {
  const container = document.getElementById('pos-terminals-grid');
  if (!container) return;

  if (state.posTerminals.length === 0) {
    container.innerHTML = `<div class="empty-state">No hay terminales POS registrados. Haz clic en "+ Vincular Nuevo POS / Chofer" para agregar uno.</div>`;
    return;
  }

  container.innerHTML = state.posTerminals.map(pos => {
    const isOnline = pos.status === 'ONLINE';
    return `
      <div class="pos-terminal-card" data-posid="${escapeHtml(pos.pos_id)}">
        <div class="pos-card-head">
          <div>
            <div class="pos-card-title">${escapeHtml(pos.pos_id)}</div>
            <div class="pos-card-unit">${escapeHtml(pos.unit_code)} • Placa ${escapeHtml(pos.plate)}</div>
          </div>
          <span class="pos-status-pill ${isOnline ? 'online' : 'offline'}">
            <span class="presence-dot"></span> ${isOnline ? 'EN LÍNEA' : 'OFFLINE'}
          </span>
        </div>

        <div class="pos-card-info-grid">
          <div class="pos-info-item">
            <span class="lbl">Ruta Asignada</span>
            <span class="val" style="color: #38BDF8;">${escapeHtml(pos.route_code)}</span>
          </div>
          <div class="pos-info-item">
            <span class="lbl">PIN de Inicio</span>
            <span class="val pos-card-pin">${escapeHtml(pos.pairing_code || '1408')}</span>
          </div>
          <div class="pos-info-item" style="grid-column: span 2;">
            <span class="lbl">Chofer Titular</span>
            <span class="val" style="color: #F8FAFC;">${escapeHtml(pos.driver_name)}</span>
          </div>
          <div class="pos-info-item" style="grid-column: span 2;">
            <span class="lbl">Hardware Validador</span>
            <span class="val" style="font-size: 0.72rem; color: #94A3B8;">${escapeHtml(pos.device_model || 'Tablet Android')}</span>
          </div>
        </div>

        <div class="pos-card-stats">
          <div>
            <span style="color: #94A3B8; font-size: 0.72rem;">Turno hoy:</span>
            <strong style="color: #34D399; margin-left: 4px;">S/. ${(Number(pos.today_gross_pen) || 0).toFixed(2)}</strong>
          </div>
          <div style="font-size: 0.72rem; color: #CBD5E1;">
            ${pos.today_trips_count || 0} viajes (App: ${pos.today_app_trips || 0} · Yape: ${pos.today_yape_trips || 0})
          </div>
        </div>
      </div>
    `;
  }).join('');
}

function renderTransactionsTable() {
  const tbody = document.getElementById('transactions-table-body');
  if (!tbody) return;

  const routeFilter = state.posFilterRoute;
  const methodFilter = state.posFilterMethod;
  const search = state.posSearchText.toLowerCase().trim();

  const filtered = state.transactions.filter(tx => {
    if (routeFilter !== 'all' && tx.route_code !== routeFilter) return false;
    if (methodFilter !== 'all') {
      if (methodFilter === 'APP_BUS_CONECTADO' && tx.payment_method !== 'APP_BUS_CONECTADO' && tx.payment_method !== 'APP_PUNTOS') return false;
      if (methodFilter === 'YAPE_EMPRESA' && tx.payment_method !== 'YAPE_EMPRESA') return false;
      if (methodFilter === 'NFC' && tx.payment_method !== 'NFC') return false;
      if (methodFilter === 'CONADIS' && tx.payment_method !== 'CONADIS') return false;
    }
    if (search) {
      const matchName = (tx.passenger_name || '').toLowerCase().includes(search);
      const matchCarnet = (tx.carnet_code || '').toLowerCase().includes(search);
      const matchUnit = (tx.unit_code || '').toLowerCase().includes(search);
      const matchPlate = (tx.plate || '').toLowerCase().includes(search);
      if (!matchName && !matchCarnet && !matchUnit && !matchPlate) return false;
    }
    return true;
  });

  if (filtered.length === 0) {
    tbody.innerHTML = `<tr><td colspan="10" style="text-align: center; padding: 24px; color: var(--text-muted);">No se encontraron transacciones con los filtros actuales.</td></tr>`;
    return;
  }

  tbody.innerHTML = filtered.map(tx => {
    const timeStr = tx.timestamp ? new Date(tx.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' }) : '--:--';
    const amount = Number(tx.amount_pen) || 0;
    const comm = Number(tx.commission_pen) || 0;
    const net = Number(tx.net_pen) || (amount - comm);

    let methodBadge = '<span class="badge-method badge-method-app">📱 App Bus Conectado</span>';
    if (tx.payment_method === 'YAPE_EMPRESA') {
      methodBadge = '<span class="badge-method badge-method-yape">🟣 Yape Empresas BCP</span>';
    } else if (tx.payment_method === 'NFC') {
      methodBadge = '<span class="badge-method badge-method-nfc">💳 Contactless NFC</span>';
    } else if (tx.payment_method === 'CONADIS') {
      methodBadge = '<span class="badge-method badge-method-conadis">♿ Pase Libre CONADIS</span>';
    }

    let passengerLabel = escapeHtml(tx.passenger_name || 'Pasajero General');
    if (tx.carnet_code) {
      passengerLabel += ` <span style="font-size: 0.72rem; color: #A5B4FC; font-family: var(--font-mono);">(${escapeHtml(tx.carnet_code)})</span>`;
    }

    return `
      <tr>
        <td style="font-family: var(--font-mono); font-size: 0.78rem; color: #94A3B8;">${timeStr}</td>
        <td>
          <strong style="color: #F8FAFC;">${escapeHtml(tx.unit_code)}</strong>
          <span style="font-size: 0.72rem; color: #94A3B8; margin-left: 4px;">(${escapeHtml(tx.plate)})</span>
        </td>
        <td><span style="color: #38BDF8; font-weight: 600;">${escapeHtml(tx.route_code)}</span></td>
        <td>${passengerLabel}</td>
        <td>${methodBadge}</td>
        <td><span style="font-size: 0.78rem; color: #CBD5E1;">${escapeHtml(tx.fare_label || 'Tarifa Plana')}</span></td>
        <td class="text-right" style="font-family: var(--font-mono); font-weight: 700; color: #F8FAFC;">S/. ${amount.toFixed(2)}</td>
        <td class="text-right" style="font-family: var(--font-mono); font-size: 0.78rem; color: #F59E0B;">${comm > 0 ? `-S/. ${comm.toFixed(2)}` : 'S/. 0.00'}</td>
        <td class="text-right" style="font-family: var(--font-mono); font-weight: 800; color: #34D399;">S/. ${net.toFixed(2)}</td>
        <td><span class="pos-status-pill online">VALIDADO</span></td>
      </tr>
    `;
  }).join('');
}

// ═══════════════════════════════════════════════════════════════════════
// MÓDULO 4: DIRECTORIO DE USUARIOS, CHOFERES Y BENEFICIARIOS
// ═══════════════════════════════════════════════════════════════════════

async function loadUsersData() {
  try {
    const [res, sessRes, carnetRes] = await Promise.all([
      fetch('/api/v1/admin/users'),
      fetch('/api/v1/admin/drivers/sessions').catch(() => null),
      fetch('/api/v1/admin/carnets').catch(() => null)
    ]);
    if (res.ok) {
      state.users = await res.json();
    }
    if (sessRes && sessRes.ok) {
      const sData = await sessRes.json();
      state.driverSessions = sData.sessions || {};
      state.disabledDrivers = sData.disabled || [];
      state.unitOccupancy = sData.occupancy || {};
    }
    if (carnetRes && carnetRes.ok) {
      state.carnetRequests = await carnetRes.json();
    }
  } catch (err) {
    console.warn('⚠️ [Users Admin] Modo local sin backend activo:', err);
  }
  renderSuneduCarnets();

  // Actualizar contadores separados: Choferes vs Clientes
  const drivers = state.users.filter(u => u.role === 'DRIVER');
  const clients = state.users.filter(u => u.role !== 'DRIVER');

  const countClients = clients.length;
  const countDriver = drivers.length;
  const countStudent = clients.filter(u => u.role === 'STUDENT').length;
  const countConadis = clients.filter(u => u.role === 'CONADIS').length;
  const countPassenger = clients.filter(u => u.role === 'PASSENGER').length;
  const countAdmin = clients.filter(u => u.role === 'ADMIN').length;

  const setCnt = (id, val) => {
    const el = document.getElementById(id);
    if (el) el.textContent = val;
  };
  setCnt('user-count-all', countClients);
  setCnt('user-count-student', countStudent);
  setCnt('user-count-conadis', countConadis);
  setCnt('user-count-passenger', countPassenger);
  setCnt('user-count-admin', countAdmin);
  setCnt('driver-count-total', countDriver);
  setCnt('driver-count-pos', drivers.filter(d => (state.posTerminals || []).some(p => p.driver_dni === d.dni || p.unit_code === d.unit_code)).length || countDriver);

  const tabBadgeDrivers = document.getElementById('tab-badge-drivers');
  if (tabBadgeDrivers) tabBadgeDrivers.textContent = `${countDriver}`;
  const tabBadgeClients = document.getElementById('tab-badge-clients');
  if (tabBadgeClients) tabBadgeClients.textContent = `${countClients}`;

  if (state.activeModule === 'drivers') {
    renderDriversTable();
  } else if (state.activeModule === 'clients') {
    renderUsersTable();
  }
}

function renderDriversTable() {
  const tbody = document.getElementById('drivers-table-body');
  if (!tbody) return;

  const searchEl = document.getElementById('drivers-search-input');
  const search = (searchEl ? searchEl.value : '').toLowerCase().trim();

  const drivers = state.users.filter(u => {
    if (u.role !== 'DRIVER') return false;
    if (search) {
      const hay = `${u.name || ''} ${u.dni || ''} ${u.brevete || ''} ${u.unit_code || ''} ${u.plate || ''} ${u.route_code || ''}`.toLowerCase();
      if (!hay.includes(search)) return false;
    }
    return true;
  });

  if (drivers.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" style="text-align: center; padding: 24px; color: var(--text-muted);">No hay choferes registrados. Usa "+ Registrar Chofer en Ruta" para asignar uno.</td></tr>`;
    return;
  }

  tbody.innerHTML = drivers.map(u => {
    const linkedPos = (state.posTerminals || []).find(p => p.driver_dni === u.dni || p.unit_code === u.unit_code);
    const posCode = linkedPos ? linkedPos.terminal_id : (u.pos_terminal_id || 'POS-TACNA');
    const pinCode = linkedPos ? linkedPos.pin : (u.pin || '1408');
    const sess = (state.driverSessions || {})[u.dni] || {};
    const isDisabled = (state.disabledDrivers || []).includes(u.dni);
    const isOnline = !isDisabled && Boolean(sess.active);
    const occ = (state.unitOccupancy || {})[u.unit_code || 'UNI-1408'] ?? 0;

    const statusPill = isDisabled
      ? '<span class="pos-status-pill" style="background:rgba(239,68,68,0.18);color:#FCA5A5;border-color:rgba(239,68,68,0.4);">DESHABILITADO</span>'
      : (isOnline
        ? '<span class="pos-status-pill online">EN LÍNEA</span>'
        : '<span class="pos-status-pill" style="background:rgba(148,163,184,0.15);color:#94A3B8;border-color:rgba(148,163,184,0.3);">DESCONECTADO</span>');

    return `
      <tr>
        <td>
          <div style="display: flex; align-items: center; gap: 10px;">
            <div style="width: 34px; height: 34px; border-radius: 50%; background: rgba(56,189,248,0.16); border: 1px solid rgba(56,189,248,0.4); display: flex; align-items: center; justify-content: center; font-weight: 800; font-size: 0.78rem; color: #38BDF8;">
              🚌
            </div>
            <div>
              <strong style="color: #F8FAFC;">${escapeHtml(u.name)}</strong>
              <div style="font-size: 0.74rem; color: #94A3B8;">${escapeHtml(u.phone || 'Sin teléfono')}</div>
            </div>
          </div>
        </td>
        <td>
          <div style="font-family: var(--font-mono); font-size: 0.8rem; color: #CBD5E1;">DNI: <strong>${escapeHtml(u.dni)}</strong></div>
          <div style="font-size: 0.72rem; color: #94A3B8;">Brevete: ${escapeHtml(u.brevete || 'N/A')} (${escapeHtml(u.brevete_category || 'A-IIIa')})</div>
        </td>
        <td>
          <span class="badge badge-route" style="font-size:0.78rem;">${escapeHtml(u.route_code || 'Ruta 14')}</span>
        </td>
        <td>
          <strong style="color: #F8FAFC;">${escapeHtml(u.unit_code || 'UNI-1408')}</strong>
          <div style="font-size: 0.74rem; color: #CBD5E1; font-family: var(--font-mono);">Placa: ${escapeHtml(u.plate || 'Z4B-812')} · Aforo: <strong style="color:#34D399;">${occ}/45</strong></div>
        </td>
        <td>
          <div style="font-size: 0.76rem; color: #34D399; font-family: var(--font-mono); font-weight: 700;">${escapeHtml(posCode)}</div>
          <div style="font-size: 0.72rem; color: #94A3B8;">PIN Enlace: <strong style="color:#FBBF24;">${escapeHtml(pinCode)}</strong></div>
        </td>
        <td>${statusPill}</td>
        <td>
          <div style="display:flex; gap:6px; flex-wrap:wrap;">
            <button type="button" class="btn btn-secondary btn-sm" onclick="openDriverDetailModal('${escapeHtml(u.dni || u.id || '')}')">
              Ver Ficha
            </button>
            <button type="button" class="btn btn-secondary btn-sm" onclick="openEditDriverDialog('${escapeHtml(u.id || u.dni || '')}')">
              ✏️ Editar
            </button>
            <button type="button" class="btn btn-secondary btn-sm" onclick="controlDriverSession('${escapeHtml(u.dni)}', 'force_logout')" title="Cerrar sesión remota en Cabina y POS">
              🔒 Cerrar Sesión
            </button>
            <button type="button" class="btn btn-secondary btn-sm" onclick="controlDriverSession('${escapeHtml(u.dni)}', '${isDisabled ? 'enable' : 'disable'}')">
              ${isDisabled ? '⚡ Habilitar' : '⛔ Deshabilitar'}
            </button>
          </div>
        </td>
      </tr>
    `;
  }).join('');
}

async function controlDriverSession(dni, action) {
  try {
    const res = await fetch('/api/v1/admin/drivers/control', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ dni, action })
    });
    if (res.ok) {
      await loadUsersData();
    }
  } catch (err) {
    console.error('Error controlando sesión del chofer:', err);
  }
}

function renderSuneduCarnets() {
  const container = document.getElementById('sunedu-carnets-list');
  const badge = document.getElementById('sunedu-pending-badge');
  if (!container) return;
  const reqs = state.carnetRequests || [];
  const pendingCount = reqs.filter(r => r.status === 'PENDING_ADMIN').length;
  if (badge) badge.textContent = `${pendingCount} pendiente${pendingCount === 1 ? '' : 's'}`;

  if (reqs.length === 0) {
    container.innerHTML = `<p style="color: var(--text-muted); font-size:0.82rem; margin:0;">No hay solicitudes de carnet SUNEDU registradas.</p>`;
    return;
  }

  container.innerHTML = reqs.map(r => {
    const isPending = r.status === 'PENDING_ADMIN';
    const isApproved = r.status === 'APPROVED';
    const statusBadge = isApproved
      ? '<span class="pos-status-pill online">APROBADO</span>'
      : (isPending
        ? '<span class="pos-status-pill" style="background:rgba(245,158,11,0.18);color:#FCD34D;border-color:rgba(245,158,11,0.4);">PENDIENTE</span>'
        : '<span class="pos-status-pill" style="background:rgba(239,68,68,0.18);color:#FCA5A5;border-color:rgba(239,68,68,0.4);">RECHAZADO</span>');

    const imgHtml = r.front_photo_base64
      ? `<img src="data:image/jpeg;base64,${escapeHtml(r.front_photo_base64)}" alt="Carnet Frontal" style="width:100%; max-height:140px; object-fit:cover; border-radius:10px; border:1px solid rgba(255,255,255,0.12); margin-bottom:8px;">`
      : '';

    return `
      <div style="background:rgba(15,23,42,0.85); border:1px solid rgba(99,102,241,0.28); border-radius:14px; padding:12px;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:8px;">
          <strong style="color:#F8FAFC; font-size:0.9rem;">${escapeHtml(r.passenger_name || 'Estudiante')}</strong>
          ${statusBadge}
        </div>
        ${imgHtml}
        <div style="font-size:0.78rem; color:#CBD5E1; line-height:1.5; margin-bottom:8px;">
          <div>DNI: <strong style="font-family:var(--font-mono); color:#38BDF8;">${escapeHtml(r.dni || '')}</strong> · QR: <span style="color:#34D399;">Validado ✓</span></div>
          <div>Universidad: <strong>${escapeHtml(r.university || '')}</strong></div>
          <div>Código: <span style="font-family:var(--font-mono);">${escapeHtml(r.carnet_code || '')}</span></div>
          <div style="margin-top:4px;">Caducidad: <input type="date" id="carnet-exp-${escapeHtml(r.id)}" value="${escapeHtml(r.expiry_date || '2026-12-31')}" style="background:#0F172A; color:#F8FAFC; border:1px solid #334155; border-radius:6px; padding:2px 6px; font-size:0.76rem;"></div>
        </div>
        ${isPending ? `
          <div style="display:flex; gap:8px;">
            <button type="button" class="btn btn-primary btn-sm" style="flex:1;" onclick="reviewSuneduCarnet('${escapeHtml(r.id)}', 'approve')">✓ Aprobar Carnet</button>
            <button type="button" class="btn btn-secondary btn-sm" onclick="reviewSuneduCarnet('${escapeHtml(r.id)}', 'reject')">✕ Rechazar</button>
          </div>
        ` : ''}
      </div>
    `;
  }).join('');
}

async function reviewSuneduCarnet(requestId, action) {
  const expEl = document.getElementById(`carnet-exp-${requestId}`);
  const expiry_date = expEl ? expEl.value : '2026-12-31';
  try {
    const res = await fetch('/api/v1/admin/carnets/review', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ request_id: requestId, action, expiry_date })
    });
    if (res.ok) {
      await loadUsersData();
    }
  } catch (err) {
    console.error('Error revisando carnet SUNEDU:', err);
  }
}

function renderUsersTable() {
  const tbody = document.getElementById('users-table-body');
  if (!tbody) return;

  const roleFilter = state.userFilterRole;
  const search = state.userSearchText.toLowerCase().trim();

  const filtered = state.users.filter(u => {
    if (u.role === 'DRIVER') return false; // Choferes tienen su propio panel
    if (roleFilter !== 'all' && u.role !== roleFilter) return false;
    if (search) {
      const matchName = (u.name || '').toLowerCase().includes(search);
      const matchDni = (u.dni || '').toLowerCase().includes(search);
      const matchCarnet = (u.carnet_code || '').toLowerCase().includes(search);
      if (!matchName && !matchDni && !matchCarnet) return false;
    }
    return true;
  });

  if (filtered.length === 0) {
    tbody.innerHTML = `<tr><td colspan="7" style="text-align: center; padding: 24px; color: var(--text-muted);">No se encontraron usuarios registrados con el filtro actual.</td></tr>`;
    return;
  }

  tbody.innerHTML = filtered.map(u => {
    let roleBadge = '';
    let opsDetail = '<span style="color: var(--text-muted);">-</span>';
    let balanceOrCarnet = '';

    if (u.role === 'DRIVER') {
      roleBadge = '<span class="badge-role badge-driver">🚌 Chofer Profesional</span>';
      opsDetail = `
        <div style="display: flex; flex-direction: column; gap: 2px;">
          <strong style="color: #38BDF8;">${escapeHtml(u.route_code || 'Ruta 14')}</strong>
          <span style="font-size: 0.74rem; color: #CBD5E1;">Unidad: <strong>${escapeHtml(u.unit_code || 'UNI-1408')}</strong> • Placa: ${escapeHtml(u.plate || 'Z4B-812')}</span>
          <span style="font-size: 0.7rem; color: #94A3B8; font-family: var(--font-mono);">Brevete: ${escapeHtml(u.brevete || '')} (${escapeHtml(u.brevete_category || 'A-IIIa')})</span>
        </div>
      `;
      balanceOrCarnet = `<span style="font-size: 0.74rem; color: #34D399;">Turno habilitado</span>`;
    } else if (u.role === 'STUDENT') {
      roleBadge = '<span class="badge-role badge-student">🎓 Universitario SUNEDU</span>';
      opsDetail = `
        <div style="display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 0.78rem; color: #CBD5E1;">${escapeHtml(u.university || 'UNJBG Tacna')}</span>
          <span style="font-size: 0.72rem; color: #A5B4FC; font-family: var(--font-mono);">Carnet: ${escapeHtml(u.carnet_code || '')}</span>
        </div>
      `;
      balanceOrCarnet = `
        <div style="display: flex; flex-direction: column; gap: 2px;">
          <strong style="color: #A5B4FC; font-family: var(--font-mono);">${u.points_balance || 0} pts</strong>
          <span style="font-size: 0.7rem; color: #94A3B8;">Vence: ${escapeHtml(u.carnet_expiry || '2026-12-31')}</span>
        </div>
      `;
    } else if (u.role === 'CONADIS') {
      roleBadge = '<span class="badge-role badge-conadis">♿ Pase Libre CONADIS</span>';
      opsDetail = `
        <div style="display: flex; flex-direction: column; gap: 2px;">
          <span style="font-size: 0.78rem; color: #34D399; font-weight: 600;">Ley 30412 (Pase 100% Libre)</span>
          <span style="font-size: 0.72rem; color: #94A3B8; font-family: var(--font-mono);">${escapeHtml(u.conadis_code || '')}</span>
        </div>
      `;
      balanceOrCarnet = `<span style="color: #34D399; font-weight: 700;">Exento (S/. 0.00)</span>`;
    } else if (u.role === 'ADMIN') {
      roleBadge = '<span class="badge-role badge-admin">🛡️ Administrador General</span>';
      opsDetail = `<span style="color: #38BDF8; font-weight: 600;">Control Maestro Tacna</span>`;
      balanceOrCarnet = `<span style="color: #94A3B8; font-family: var(--font-mono);">${u.points_balance || 0} pts</span>`;
    } else {
      roleBadge = '<span class="badge-role badge-passenger">📱 Pasajero General</span>';
      opsDetail = `<span style="color: #94A3B8;">Transporte Urbano</span>`;
      balanceOrCarnet = `<strong style="color: #F8FAFC; font-family: var(--font-mono);">${u.points_balance || 0} pts</strong>`;
    }

    const fullName = u.display_name || u.name || `${u.first_name || ''} ${u.last_name || ''}`.trim() || 'Pasajero BC';
    const contactLine = [u.email, u.phone].filter(Boolean).join(' · ') || 'Sin contacto';
    const userKey = u.id || u.dni || '';

    return `
      <tr>
        <td>
          <div style="display: flex; align-items: center; gap: 10px;">
            <div style="width: 32px; height: 32px; border-radius: 50%; background: #1E293B; display: flex; align-items: center; justify-content: center; font-weight: 800; font-size: 0.75rem; color: #38BDF8;">
              ${escapeHtml(fullName.substring(0, 2).toUpperCase())}
            </div>
            <div>
              <strong style="color: #F8FAFC;">${escapeHtml(fullName)}</strong>
              <div style="font-size: 0.74rem; color: #94A3B8;">${escapeHtml(contactLine)}</div>
            </div>
          </div>
        </td>
        <td style="font-family: var(--font-mono); font-size: 0.8rem; color: #CBD5E1;">${escapeHtml(u.dni || '-')}</td>
        <td>${roleBadge}</td>
        <td>${opsDetail}</td>
        <td>${balanceOrCarnet}</td>
        <td><span class="pos-status-pill online">ACTIVO</span></td>
        <td>
          <button type="button" class="btn btn-secondary btn-sm" onclick="openClientDetailModal('${escapeHtml(userKey)}')">
            Ver Ficha
          </button>
        </td>
      </tr>
    `;
  }).join('');
}

function openUserDialog(defaultRole = 'STUDENT') {
  const dialog = document.getElementById('user-dialog');
  const form = document.getElementById('user-form');
  if (!dialog || !form) return;

  form.reset();
  document.getElementById('user-field-id').value = '';
  document.getElementById('user-field-points').value = '100';
  document.getElementById('user-field-university').value = 'UNJBG Tacna';
  document.getElementById('user-field-student-expiry').value = '2026-12-31';

  const titleEl = document.getElementById('user-dialog-title');
  if (titleEl) {
    titleEl.textContent = defaultRole === 'DRIVER' ? '🚌 Registrar Chofer en Ruta' : '👤 Registrar Usuario';
  }
  const pinInput = document.getElementById('user-field-pin');
  if (pinInput) pinInput.value = '';
  const roleSelect = document.getElementById('user-field-role');
  if (roleSelect && defaultRole) {
    roleSelect.value = defaultRole;
  }

  // Sincronizar campos según rol inicial
  handleUserRoleFieldsToggle(defaultRole || 'STUDENT');

  dialog.showModal();
}

function openEditDriverDialog(key) {
  const u = (state.users || []).find((x) => (x.id && x.id === key) || (x.dni && x.dni === key));
  if (!u) {
    showToast('No se encontró el chofer para editar.', 'error');
    return;
  }

  const dialog = document.getElementById('user-dialog');
  const form = document.getElementById('user-form');
  if (!dialog || !form) return;

  form.reset();

  const linkedPos = (state.posTerminals || []).find(
    (p) => (p.driver_dni && p.driver_dni === u.dni) || (u.unit_code && p.unit_code === u.unit_code)
  );

  document.getElementById('user-field-id').value = u.id || u.dni || '';
  document.getElementById('user-field-role').value = u.role || 'DRIVER';
  document.getElementById('user-field-name').value = u.name || '';
  document.getElementById('user-field-dni').value = u.dni || '';
  document.getElementById('user-field-phone').value = u.phone || '';
  document.getElementById('user-field-email').value = u.email || '';
  document.getElementById('user-field-points').value = String(u.points ?? 100);
  document.getElementById('user-field-route').value = u.route_code || '';
  document.getElementById('user-field-unit').value = u.unit_code || '';
  document.getElementById('user-field-plate').value = u.plate || '';
  document.getElementById('user-field-brevete').value = u.brevete || '';
  const pinInput = document.getElementById('user-field-pin');
  if (pinInput) {
    pinInput.value = u.pin || (linkedPos && (linkedPos.pairing_code || linkedPos.pin)) || '';
  }

  const titleEl = document.getElementById('user-dialog-title');
  if (titleEl) {
    titleEl.textContent = `✏️ Editar Chofer: ${u.name || u.dni || ''}`;
  }

  handleUserRoleFieldsToggle('DRIVER');
  dialog.showModal();
}

function handleUserRoleFieldsToggle(role) {
  const driverBox = document.getElementById('user-role-fields-driver');
  const studentBox = document.getElementById('user-role-fields-student');
  const conadisBox = document.getElementById('user-role-fields-conadis');

  if (driverBox) driverBox.classList.toggle('hidden', role !== 'DRIVER');
  if (studentBox) studentBox.classList.toggle('hidden', role !== 'STUDENT');
  if (conadisBox) conadisBox.classList.toggle('hidden', role !== 'CONADIS');
}

function openPosDialog() {
  const dialog = document.getElementById('pos-dialog');
  const form = document.getElementById('pos-form');
  if (!dialog || !form) return;

  form.reset();
  const nextNum = (state.posTerminals.length + 1).toString().padStart(2, '0');
  document.getElementById('pos-field-id').value = `POS-UNI-14${nextNum}`;
  document.getElementById('pos-field-unit').value = `UNI-14${nextNum}`;
  document.getElementById('pos-field-pairing-code').value = `14${nextNum}`;
  document.getElementById('pos-field-device-model').value = 'Samsung Galaxy Tab S6 Lite (SM-P613)';

  dialog.showModal();
}

function renderStatsCharts() {
  const container = document.getElementById('hourly-bars-container');
  if (!container) return;

  // 17 franjas de 06:00 a 22:00
  const hourlyData = [
    { hour: '06:00', trips: 14, isPeak: false },
    { hour: '07:00', trips: 68, isPeak: true },
    { hour: '08:00', trips: 85, isPeak: true },
    { hour: '09:00', trips: 36, isPeak: false },
    { hour: '10:00', trips: 28, isPeak: false },
    { hour: '11:00', trips: 34, isPeak: false },
    { hour: '12:00', trips: 58, isPeak: false },
    { hour: '13:00', trips: 92, isPeak: true },
    { hour: '14:00', trips: 64, isPeak: true },
    { hour: '15:00', trips: 32, isPeak: false },
    { hour: '16:00', trips: 40, isPeak: false },
    { hour: '17:00', trips: 55, isPeak: false },
    { hour: '18:00', trips: 88, isPeak: true },
    { hour: '19:00', trips: 95, isPeak: true },
    { hour: '20:00', trips: 62, isPeak: false },
    { hour: '21:00', trips: 30, isPeak: false },
    { hour: '22:00', trips: 12, isPeak: false }
  ];

  const maxTrips = Math.max(...hourlyData.map(d => d.trips));

  container.innerHTML = hourlyData.map(d => {
    const heightPercent = Math.max(10, Math.round((d.trips / maxTrips) * 100));
    return `
      <div class="hourly-bar ${d.isPeak ? 'peak' : ''}" style="height: ${heightPercent}%;" title="${d.hour}: ${d.trips} abordajes"></div>
    `;
  }).join('');
}

// ═══════════════════════════════════════════════════════════════════════
// LISTENERS DE FORMULARIOS Y FILTROS POS / USUARIOS
// ═══════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
  // Filtros de Transacciones POS
  const filterTxRoute = document.getElementById('filter-tx-route');
  if (filterTxRoute) {
    filterTxRoute.addEventListener('change', (e) => {
      state.posFilterRoute = e.target.value;
      renderTransactionsTable();
    });
  }

  const filterTxMethod = document.getElementById('filter-tx-method');
  if (filterTxMethod) {
    filterTxMethod.addEventListener('change', (e) => {
      state.posFilterMethod = e.target.value;
      renderTransactionsTable();
    });
  }

  const searchTxInput = document.getElementById('search-tx-input');
  if (searchTxInput) {
    searchTxInput.addEventListener('input', (e) => {
      state.posSearchText = e.target.value;
      renderTransactionsTable();
    });
  }

  // Filtro de Chips de Usuarios por Rol
  const roleChipsNav = document.getElementById('user-role-chips');
  if (roleChipsNav) {
    roleChipsNav.addEventListener('click', (e) => {
      const btn = e.target.closest('button[data-userfilter]');
      if (!btn) return;
      roleChipsNav.querySelectorAll('button').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      state.userFilterRole = btn.dataset.userfilter;
      renderUsersTable();
    });
  }

  const usersSearchInput = document.getElementById('users-search-input');
  if (usersSearchInput) {
    usersSearchInput.addEventListener('input', (e) => {
      state.userSearchText = e.target.value;
      renderUsersTable();
    });
  }

  // Cambio dinámico de campos en Diálogo de Usuario
  const userFieldRole = document.getElementById('user-field-role');
  if (userFieldRole) {
    userFieldRole.addEventListener('change', (e) => {
      handleUserRoleFieldsToggle(e.target.value);
    });
  }

  // Envío de Formulario Nuevo Usuario / Chofer
  const userForm = document.getElementById('user-form');
  if (userForm) {
    userForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const editId = document.getElementById('user-field-id').value.trim();
      const role = document.getElementById('user-field-role').value;
      const name = document.getElementById('user-field-name').value.trim();
      const dni = document.getElementById('user-field-dni').value.trim();
      const phone = document.getElementById('user-field-phone').value.trim();
      const email = document.getElementById('user-field-email').value.trim();
      const points = parseInt(document.getElementById('user-field-points').value) || 0;

      const newUser = {
        name,
        dni,
        phone,
        role,
        points_balance: points,
        email: email || `${slugify(name)}@busconectado.pe`
      };
      if (editId) {
        newUser.id = editId;
      }

      if (role === 'DRIVER') {
        newUser.route_code = document.getElementById('user-field-route').value;
        newUser.unit_code = document.getElementById('user-field-unit').value.trim();
        newUser.plate = document.getElementById('user-field-plate').value.trim().toUpperCase();
        newUser.brevete = document.getElementById('user-field-brevete').value.trim().toUpperCase();
        const pinVal = (document.getElementById('user-field-pin')?.value || '').trim();
        if (pinVal) newUser.pin = pinVal;
      } else if (role === 'STUDENT') {
        newUser.carnet_code = document.getElementById('user-field-student-code').value.trim();
        newUser.university = document.getElementById('user-field-university').value.trim();
        newUser.carnet_expiry = document.getElementById('user-field-student-expiry').value;
      } else if (role === 'CONADIS') {
        newUser.conadis_code = document.getElementById('user-field-conadis-code').value.trim();
        newUser.is_exempt = true;
      }

      try {
        const res = await fetch('/api/v1/admin/users', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(newUser)
        });
        if (res.ok) {
          const saved = await res.json();
          showToast(`✓ Usuario ${saved.name} registrado con éxito.`);
          document.getElementById('user-dialog').close();
          await loadUsersData();
        } else {
          showToast('Error al registrar usuario en el servidor.');
        }
      } catch (err) {
        showToast('Error de conexión al guardar usuario.');
      }
    });
  }

  // Cancelar Diálogo Usuario
  const btnCancelUserDialog = document.getElementById('btn-cancel-user-dialog');
  if (btnCancelUserDialog) {
    btnCancelUserDialog.addEventListener('click', () => {
      document.getElementById('user-dialog').close();
    });
  }
  const userDialogCloseX = document.getElementById('user-dialog-close-x');
  if (userDialogCloseX) {
    userDialogCloseX.addEventListener('click', () => {
      document.getElementById('user-dialog').close();
    });
  }

  // Envío de Formulario Vincular POS
  const posForm = document.getElementById('pos-form');
  if (posForm) {
    posForm.addEventListener('submit', async (e) => {
      e.preventDefault();
      const posId = document.getElementById('pos-field-id').value.trim();
      const unitCode = document.getElementById('pos-field-unit').value.trim();
      const plate = document.getElementById('pos-field-plate').value.trim().toUpperCase();
      const routeCode = document.getElementById('pos-field-route').value;
      const driverName = document.getElementById('pos-field-driver-name').value.trim();
      const pairingCode = document.getElementById('pos-field-pairing-code').value.trim();
      const deviceModel = document.getElementById('pos-field-device-model').value.trim();

      const newPos = {
        pos_id: posId,
        unit_code: unitCode,
        plate: plate,
        route_code: routeCode,
        driver_name: driverName,
        pairing_code: pairingCode,
        device_model: deviceModel
      };

      try {
        const res = await fetch('/api/v1/admin/pos-terminals', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(newPos)
        });
        if (res.ok) {
          const saved = await res.json();
          showToast(`✓ Terminal ${saved.pos_id} enlazado a unidad ${saved.unit_code} con PIN ${saved.pairing_code}.`);
          document.getElementById('pos-dialog').close();
          await loadPosData();
        } else {
          showToast('Error al vincular terminal POS en el servidor.');
        }
      } catch (err) {
        showToast('Error de conexión al vincular POS.');
      }
    });
  }

  // Cancelar Diálogo POS
  const btnCancelPosDialog = document.getElementById('btn-cancel-pos-dialog');
  if (btnCancelPosDialog) {
    btnCancelPosDialog.addEventListener('click', () => {
      document.getElementById('pos-dialog').close();
    });
  }
  const posDialogCloseX = document.getElementById('pos-dialog-close-x');
  if (posDialogCloseX) {
    posDialogCloseX.addEventListener('click', () => {
      document.getElementById('pos-dialog').close();
    });
  }

  startLiveBusesMapPolling();
});

// ═══════════════════════════════════════════════════════════════════════
// TELEMETRÍA EN VIVO DE BUSES POS SOBRE EL MAPA + FICHA DETALLADA CHOFER
// ═══════════════════════════════════════════════════════════════════════
let liveBusesLayer = null;

function startLiveBusesMapPolling() {
  const poll = async () => {
    if (!state.map) return;
    try {
      const res = await fetch('/api/v1/transit/buses/live');
      if (!res.ok) return;
      const buses = await res.json();
      if (!liveBusesLayer) {
        liveBusesLayer = L.layerGroup().addTo(state.map);
      }
      liveBusesLayer.clearLayers();
      buses.forEach(bus => {
        if (typeof bus.latitude !== 'number' || typeof bus.longitude !== 'number') return;
        const markerHtml = `
          <div style="display:flex;align-items:center;gap:6px;background:#0F172A;color:#F8FAFC;border:2px solid #38BDF8;border-radius:999px;padding:4px 10px;box-shadow:0 4px 14px rgba(56,189,248,0.45);font-weight:800;font-size:11px;white-space:nowrap;">
            <span>🚌</span>
            <span>${escapeHtml(bus.unit_code || 'UNI')}</span>
            <span style="color:#34D399;">${Math.round(bus.speed_kmh || 25)} km/h</span>
          </div>
        `;
        const icon = L.divIcon({
          className: 'live-bus-div-icon',
          html: markerHtml,
          iconSize: [120, 30],
          iconAnchor: [60, 15]
        });
        const marker = L.marker([bus.latitude, bus.longitude], { icon, zIndexOffset: 900 });
        marker.bindPopup(`
          <div style="font-family:system-ui;min-width:190px;">
            <strong style="font-size:13px;">🚌 ${escapeHtml(bus.unit_code || 'Unidad')} (${escapeHtml(bus.plate || '')})</strong><br/>
            <span style="color:#38BDF8;font-weight:700;">${escapeHtml(bus.route_code || 'Ruta 14')}</span><br/>
            Velocidad: <strong>${Math.round(bus.speed_kmh || 25)} km/h</strong><br/>
            Próx. paradero: <strong>${escapeHtml(bus.closest_stop_name || 'En ruta')}</strong> (${Math.max(1, Math.round((bus.eta_seconds || 120) / 60))} min)
          </div>
        `);
        marker.addTo(liveBusesLayer);
      });
    } catch (_) {}
  };
  poll();
  setInterval(poll, 3000);
}

async function openDriverDetailModal(key) {
  const driver = (state.users || []).find(u => (u.dni === key || u.id === key) && u.role === 'DRIVER');
  if (!driver) {
    showToast('No se encontró información del chofer.');
    return;
  }

  let txs = state.posTransactions || [];
  try {
    const res = await fetch('/api/v1/admin/pos/transactions');
    if (res.ok) txs = await res.json();
  } catch (_) {}

  const unitCode = (driver.unit_code || '').toUpperCase();
  const driverTxs = txs.filter(t => !unitCode || (t.unit_code || '').toUpperCase() === unitCode);
  const appCount = driverTxs.filter(t => t.payment_method === 'APP_BUS_CONECTADO').length;
  const yapeCount = driverTxs.filter(t => t.payment_method === 'YAPE_EMPRESA').length;
  const totalNet = driverTxs.reduce((acc, t) => acc + Number(t.net_pen || t.amount_pen || 0), 0);

  const linkedPos = (state.posTerminals || []).find(p => p.driver_dni === driver.dni || p.unit_code === driver.unit_code);
  const posId = linkedPos?.pos_id || linkedPos?.terminal_id || driver.pos_terminal_id || 'Sin asignar';
  const posPin = linkedPos?.pairing_code || linkedPos?.pin || driver.pin || '-';
  const driverName = driver.display_name || driver.name || 'Chofer';

  let dialog = document.getElementById('driver-detail-dialog');
  if (!dialog) {
    dialog = document.createElement('dialog');
    dialog.id = 'driver-detail-dialog';
    dialog.style.cssText = 'padding:0;border:1px solid rgba(148,163,184,0.28);border-radius:16px;background:#0F172A;color:#F8FAFC;max-width:740px;width:92vw;margin:auto;';
    document.body.appendChild(dialog);
  }

  const rowsHtml = driverTxs.slice(0, 20).map(t => `
    <tr>
      <td style="font-family:var(--font-mono);font-size:0.75rem;">${t.timestamp ? new Date(t.timestamp).toLocaleTimeString('es-PE') : '-'}</td>
      <td><strong>${escapeHtml(t.passenger_name || 'Pasajero')}</strong></td>
      <td>${escapeHtml(t.fare_label || 'Tarifa General')}</td>
      <td>${escapeHtml(t.method_label || t.payment_method || 'App')}</td>
      <td style="font-family:var(--font-mono);font-weight:700;color:#34D399;">S/. ${Number(t.amount_pen || 0).toFixed(2)}</td>
    </tr>
  `).join('') || `<tr><td colspan="5" style="text-align:center;padding:16px;color:#94A3B8;">Sin abordajes registrados aún para esta unidad.</td></tr>`;

  dialog.innerHTML = `
    <div style="padding:22px;background:#0F172A;color:#F8FAFC;border-radius:16px;">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:14px;gap:12px;">
        <div>
          <h3 style="margin:0;font-size:1.15rem;">🚌 Ficha del Chofer: ${escapeHtml(driverName)}</h3>
          <p style="margin:4px 0 0;color:#94A3B8;font-size:0.82rem;">ID: ${escapeHtml(driver.id || '-')} • DNI: ${escapeHtml(driver.dni || '-')} • Correo: ${escapeHtml(driver.email || '-')}</p>
          <p style="margin:2px 0 0;color:#94A3B8;font-size:0.82rem;">Brevete: ${escapeHtml(driver.brevete || 'N/A')} (${escapeHtml(driver.brevete_category || 'A-IIIa')}) • Tel: ${escapeHtml(driver.phone || '-')}</p>
        </div>
        <button type="button" class="btn btn-secondary btn-sm" onclick="document.getElementById('driver-detail-dialog').close()">Cerrar</button>
      </div>
      <div style="display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px;">
        <div class="stat-card"><span class="stat-number" style="font-size:1rem;">${escapeHtml(driver.unit_code || '-')}</span><span class="stat-label">${escapeHtml(driver.plate || '-')} · ${escapeHtml(driver.route_code || '-')}</span></div>
        <div class="stat-card"><span class="stat-number" style="font-size:1rem;color:#38BDF8;">${appCount + yapeCount}</span><span class="stat-label">App (${appCount}) / Yape (${yapeCount})</span></div>
        <div class="stat-card"><span class="stat-number" style="font-size:1rem;color:#FBBF24;">${escapeHtml(posPin)}</span><span class="stat-label">PIN Enlace POS</span></div>
        <div class="stat-card"><span class="stat-number" style="font-size:1rem;color:#34D399;">S/. ${totalNet.toFixed(2)}</span><span class="stat-label">POS ${escapeHtml(posId)}</span></div>
      </div>
      <h4 style="margin:0 0 8px;font-size:0.9rem;color:#CBD5E1;">Historial de Abordajes (App QR y Yape)</h4>
      <div class="table-responsive" style="max-height:260px;overflow-y:auto;">
        <table class="admin-data-table">
          <thead><tr><th>Hora</th><th>Pasajero</th><th>Tarifa</th><th>Medio</th><th>Monto</th></tr></thead>
          <tbody>${rowsHtml}</tbody>
        </table>
      </div>
    </div>
  `;
  if (typeof dialog.showModal === 'function') {
    if (!dialog.open) dialog.showModal();
  }
}

function openClientDetailModal(key) {
  const user = (state.users || []).find(u => (u.id === key || u.dni === key) && u.role !== 'DRIVER');
  if (!user) {
    showToast('No se encontró información del cliente.');
    return;
  }

  let dialog = document.getElementById('client-detail-dialog');
  if (!dialog) {
    dialog = document.createElement('dialog');
    dialog.id = 'client-detail-dialog';
    dialog.style.cssText = 'padding:0;border:1px solid rgba(148,163,184,0.28);border-radius:16px;background:#0F172A;color:#F8FAFC;max-width:640px;width:92vw;margin:auto;';
    document.body.appendChild(dialog);
  }

  const fullName = user.display_name || user.name || `${user.first_name || ''} ${user.last_name || ''}`.trim() || 'Pasajero BC';
  const points = Number(user.points_balance || 0);
  const pen = (points / 10).toFixed(2);
  const phoneStatus = user.phone ? (user.phone_verified === false ? 'Pendiente' : 'Verificado') : 'Sin vincular';

  dialog.innerHTML = `
    <div style="padding:22px;background:#0F172A;color:#F8FAFC;border-radius:16px;">
      <div style="display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:16px;gap:12px;">
        <div>
          <h3 style="margin:0;font-size:1.15rem;">👤 Ficha del Cliente: ${escapeHtml(fullName)}</h3>
          <p style="margin:4px 0 0;color:#94A3B8;font-size:0.8rem;font-family:var(--font-mono);">ID: ${escapeHtml(user.id || '-')}</p>
        </div>
        <button type="button" class="btn btn-secondary btn-sm" onclick="document.getElementById('client-detail-dialog').close()">Cerrar</button>
      </div>
      <div style="display:grid;grid-template-columns:repeat(2,1fr);gap:10px;font-size:0.86rem;">
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">NOMBRE Y APELLIDO</div>
          <div style="font-weight:700;margin-top:3px;">${escapeHtml(user.first_name || fullName)} ${escapeHtml(user.last_name || '')}</div>
        </div>
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">CORREO ELECTRÓNICO</div>
          <div style="font-weight:700;margin-top:3px;word-break:break-all;">${escapeHtml(user.email || 'No registrado')}</div>
        </div>
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">CELULAR (${escapeHtml(phoneStatus)})</div>
          <div style="font-weight:700;margin-top:3px;font-family:var(--font-mono);">${escapeHtml(user.phone || 'Sin celular')}</div>
        </div>
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">DNI</div>
          <div style="font-weight:700;margin-top:3px;font-family:var(--font-mono);">${escapeHtml(user.dni || 'No registrado')}</div>
        </div>
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">PROVEEDOR / ROL</div>
          <div style="font-weight:700;margin-top:3px;">${escapeHtml((user.auth_provider || 'app').toUpperCase())} · ${escapeHtml(user.role || 'ADULT')}</div>
        </div>
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">SALDO MONEDERO</div>
          <div style="font-weight:700;margin-top:3px;color:#34D399;">${points} pts (S/. ${pen})</div>
        </div>
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">CARNET SUNEDU / UNIVERSIDAD</div>
          <div style="font-weight:700;margin-top:3px;">${escapeHtml(user.university || '-')} ${user.carnet_code ? '· ' + escapeHtml(user.carnet_code) : ''}</div>
          <div style="color:#94A3B8;font-size:0.72rem;margin-top:2px;">Vence: ${escapeHtml(user.carnet_expiry || '-')}</div>
        </div>
        <div class="stat-card" style="text-align:left;padding:12px;">
          <div style="color:#94A3B8;font-size:0.72rem;">FECHA DE REGISTRO</div>
          <div style="font-weight:700;margin-top:3px;font-family:var(--font-mono);">${escapeHtml(user.created_at || '-')}</div>
        </div>
      </div>
    </div>
  `;
  if (typeof dialog.showModal === 'function') {
    if (!dialog.open) dialog.showModal();
  }
}


