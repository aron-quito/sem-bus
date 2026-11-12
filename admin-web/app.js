/**
 * BUS CONECTADO • APLICACIÓN DE ADMINISTRACIÓN DE PARADEROS (TACNA)
 * Gestión visual en mapa, reubicación directa con Drag & Drop, creación, edición y exportación a iOS.
 * Módulo colaborativo en tiempo real estilo Google Docs con WebSockets.
 */

const PROFILES = [
  { id: 'admin1', username: 'admin', name: 'Admin 1 (Aron)', avatar: 'A1', color: '#2563EB' },
  { id: 'admin2', username: 'admin2', name: 'Admin 2', avatar: 'A2', color: '#10B981' }
];

// Estado global de la aplicación
const state = {
  activeModule: 'stops',     // 'stops' | 'routes'
  stops: [],
  routes: [],
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
  isRoutingStreet: false,    // Indicador de consulta activa al motor vial OSRM
  modalSelectedStopIds: [],  // IDs de paraderos seleccionados en orden dentro del modal de ruta
  currentUser: PROFILES[0],  // Perfil activo (Admin 1 por defecto)
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

  // 1. Hidratar al instante desde caché local (renderizado inmediato sin esperar red)
  const hadCachedStops = hydrateStopsFromLocalCache();
  const hadCachedRoutes = hydrateRoutesFromLocalCache();

  // 2. Iniciar mapa, listeners y WebSocket en paralelo (sin waterfall bloqueante)
  initLeafletMap();
  setupUIEventListeners();
  setupDialogLightDismiss();
  initCollaborationWebSocket();

  if (hadCachedStops || hadCachedRoutes) {
    renderMapMarkers();
    renderMapRoutes();
    renderStopsList();
    renderRoutesList();
    updateStats();
    updateRouteStats();
  }

  // 3. Validar con servidor usando ETag (304 Not Modified = 0 bytes si no hubo cambios)
  await Promise.all([loadStopsData(), loadRoutesData()]);
  renderMapMarkers();
  renderMapRoutes();
  renderStopsList();
  renderRoutesList();
  updateStats();
  updateRouteStats();
});

// ═══════════════════════════════════════════════════════════════════════
// GESTIÓN DE PERFILES Y WEBSOCKETS EN TIEMPO REAL (GOOGLE DOCS STYLE)
// ═══════════════════════════════════════════════════════════════════════

function loadStoredProfile() {
  const savedId = localStorage.getItem('bc_collab_profile_id');
  const found = PROFILES.find(p => p.id === savedId);
  if (found) {
    state.currentUser = found;
  }
  updateProfileUI();
}

function updateProfileUI() {
  const avatarEl = document.getElementById('collab-my-avatar');
  const nameEl = document.getElementById('collab-my-name');
  if (avatarEl) {
    avatarEl.textContent = state.currentUser.avatar;
    avatarEl.style.backgroundColor = state.currentUser.color;
    avatarEl.style.boxShadow = `0 0 10px ${state.currentUser.color}`;
  }
  if (nameEl) {
    nameEl.textContent = state.currentUser.name;
  }
}

function switchUserProfile() {
  const currentIdx = PROFILES.findIndex(p => p.id === state.currentUser.id);
  const nextProfile = PROFILES[(currentIdx + 1) % PROFILES.length];
  state.currentUser = nextProfile;
  localStorage.setItem('bc_collab_profile_id', nextProfile.id);
  updateProfileUI();
  sendWsMessage({ type: 'join', user: state.currentUser });
  showToast(`Cambiado a perfil: ${nextProfile.name}`);
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
      if (Array.isArray(data) && data.length > 0) {
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
      if (Array.isArray(data) && data.length > 0) {
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
  const stopsHeader = document.getElementById('stops-header-controls');
  const routesHeader = document.getElementById('routes-header-controls');
  const stopsSection = document.getElementById('stops-list-section');
  const routesSection = document.getElementById('routes-list-section');
  const modeLabel = document.getElementById('current-mode-label');

  if (moduleName === 'routes') {
    tabStops?.classList.remove('active');
    tabStops?.setAttribute('aria-selected', 'false');
    tabRoutes?.classList.add('active');
    tabRoutes?.setAttribute('aria-selected', 'true');

    stopsHeader?.classList.add('hidden');
    routesHeader?.classList.remove('hidden');
    stopsSection?.classList.add('hidden');
    routesSection?.classList.remove('hidden');

    if (modeLabel) {
      modeLabel.textContent = 'Modo: Gestión de Rutas y Trazados Oficiales (Referencia ETA App + Chofer)';
    }

    // Si no hay ruta seleccionada aún, seleccionar la primera ruta para visualizarla
    if (!state.selectedRouteId && state.routes.length > 0) {
      state.selectedRouteId = state.routes[0].id;
    }
    renderRoutesList();
    updateRouteStats();
    renderMapRoutes();
  } else {
    if (state.tracingRouteId) {
      cancelRouteTrace();
    }
    tabRoutes?.classList.remove('active');
    tabRoutes?.setAttribute('aria-selected', 'false');
    tabStops?.classList.add('active');
    tabStops?.setAttribute('aria-selected', 'true');

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
  state.tempTraceStopIds = state.tempTraceNodes
    .map(n => n.stopId)
    .filter(Boolean);
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
      const nodeIcon = L.divIcon({
        className: 'custom-route-seq-node',
        html: `<div class="route-seq-node" style="background:${traceColor}; border:${isStopNode ? '2.5px solid #FFFFFF' : '2px dashed #E0F2FE'};">${idx + 1}</div>`,
        iconSize: [24, 24],
        iconAnchor: [12, 12]
      });

      const nodeMarker = L.marker([node.lat, node.lng], {
        icon: nodeIcon,
        interactive: true,
        draggable: true,
        zIndexOffset: 1100
      });

      const stopObj = node.stopId ? stopMap.get(node.stopId) : null;
      const nodeTitle = stopObj
        ? `Paradero: ${stopObj.shortName || stopObj.name}`
        : `Nodo vial: ${node.streetName || 'Calle alineada'}`;

      nodeMarker.bindTooltip(
        `<strong>#${idx + 1} ${escapeHtml(nodeTitle)}</strong><br>` +
        `+${etaMin} min (${cumulativeKm.toFixed(2)} km) • <em>Arrastra para reajustar calle</em>`,
        { direction: 'top', offset: [0, -10] }
      );

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
async function handleMapClickDuringRouteTrace(rawLat, rawLng) {
  if (!state.tracingRouteId || state.isRoutingStreet) return;
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
  state.tempTraceNodes.pop();
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

function saveRouteTrace() {
  if (!state.tracingRouteId) return;
  const route = state.routes.find(r => r.id === state.tracingRouteId);
  if (!route) return;

  if (state.tempTraceCoords.length < 2) {
    showToast('⚠️ La ruta necesita al menos 2 nodos en el mapa para guardar el trazado.');
    return;
  }

  const metrics = computeRouteDistanceAndEta(
    state.tempTraceCoords,
    route.averageSpeedKmh || 22,
    state.tempTraceStopIds.length
  );

  if (state.tempTraceStopIds.length >= 2) {
    route.keyStopIds = [...state.tempTraceStopIds];
  }
  route.controlNodes = state.tempTraceNodes.map(n => ({
    lat: n.lat,
    lng: n.lng,
    stopId: n.stopId || null,
    streetName: n.streetName || ''
  }));
  route.pathCoordinates = [...state.tempTraceCoords];
  route.totalDistanceKm = metrics.totalDistanceKm;
  route.estimatedTotalMinutes = metrics.estimatedTotalMinutes;

  const traceBar = document.getElementById('route-trace-bar');
  if (traceBar) traceBar.classList.add('hidden');

  state.tracingRouteId = null;
  state.tempTraceNodes = [];
  state.tempTraceSegments = [];
  state.tempTraceCoords = [];
  state.tempTraceStopIds = [];

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

  showToast(`✓ Trazado vial de ${route.code} guardado (${route.totalDistanceKm} km • ~${route.estimatedTotalMinutes} min).`);
}

function cancelRouteTrace() {
  const traceBar = document.getElementById('route-trace-bar');
  if (traceBar) traceBar.classList.add('hidden');
  state.tracingRouteId = null;
  state.tempTraceNodes = [];
  state.tempTraceSegments = [];
  state.tempTraceCoords = [];
  state.tempTraceStopIds = [];
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
    btnOpenTracer.style.display = 'none';

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

    renderRouteStopsChecklist(['mercado-central', 'plaza-zela', 'unjbg']);
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

async function handleRouteFormSubmit(e) {
  e.preventDefault();

  const id = document.getElementById('route-field-id').value.trim();
  const code = document.getElementById('route-field-code').value.trim();
  const title = document.getElementById('route-field-title').value.trim();
  const routeType = document.getElementById('route-field-type').value;
  const isOrdinary = routeType === 'ordinary';
  const isInService = isOrdinary && document.getElementById('route-field-service').value === 'true';
  const corridor = document.getElementById('route-field-corridor').value.trim();
  const frequencyMinutes = parseInt(document.getElementById('route-field-freq').value, 10) || 8;
  const averageSpeedKmh = parseFloat(document.getElementById('route-field-speed').value) || 22.0;
  const scheduleLabel = document.getElementById('route-field-schedule').value.trim() || '05:30 - 22:30';
  const colorHex = document.getElementById('route-field-color').value || '#2563EB';
  const keyStopIds = getSelectedStopIdsFromRouteModal();

  if (keyStopIds.length < 2) {
    showToast('⚠️ Selecciona al menos 2 paraderos para conformar el recorrido de la ruta.');
    return;
  }

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

      if (!alreadyStreetAligned) {
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
    showToast(`🛣️ Trazando nueva ruta "${code}" por las calles de Tacna...`);
    const aligned = await alignNodesToStreetNetwork(rawStopNodes);
    const pathCoordinates = aligned.fullCoords.length >= 2
      ? aligned.fullCoords
      : rawStopNodes.map(n => [n.lat, n.lng]);
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
      controlNodes: aligned.nodes,
      pathCoordinates,
      totalDistanceKm: metrics.totalDistanceKm,
      estimatedTotalMinutes: metrics.estimatedTotalMinutes
    };
    state.routes.push(savedRoute);
    state.selectedRouteId = newId;
    showToast(`✓ Nueva ruta "${code}" creada y alineada a las calles de Tacna.`);
  }

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
    selectRouteOnMap(savedRoute.id, true);
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
    document.getElementById('field-routes').value = 'Ruta 14';
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
  // Conmutador principal de módulos: Paraderos vs Rutas y Trazados
  const tabStops = document.getElementById('tab-module-stops');
  const tabRoutes = document.getElementById('tab-module-routes');
  if (tabStops) tabStops.addEventListener('click', () => switchAdminModule('stops'));
  if (tabRoutes) tabRoutes.addEventListener('click', () => switchAdminModule('routes'));

  // Botón Cambiar Perfil de Colaborador (Admin 1 ⇄ Admin 2)
  const btnSwitchUser = document.getElementById('btn-switch-user');
  if (btnSwitchUser) {
    btnSwitchUser.addEventListener('click', switchUserProfile);
  }

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
    const id = document.getElementById('route-field-id').value;
    closeRouteDialog();
    if (id) startTracingRouteOnMap(id);
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

