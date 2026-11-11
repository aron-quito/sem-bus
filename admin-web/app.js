/**
 * BUS CONECTADO • APLICACIÓN DE ADMINISTRACIÓN DE PARADEROS (TACNA)
 * Gestión visual en mapa, reubicación directa con Drag & Drop, creación, edición y exportación a iOS.
 */

// Estado global de la aplicación
const state = {
  stops: [],
  selectedStopId: null,
  activeFilter: 'all',
  searchQuery: '',
  map: null,
  markersMap: new Map(), // Map<stopId, L.Marker>
  activeTileLayer: null,
  tileLayers: {},
  pickingCoordsMode: false,
  relocatingStopId: null,    // ID del paradero actualmente en proceso de reubicación
  originalCoords: null,      // { lat, lng } para restaurar si el usuario cancela
  tempCoords: null           // { lat, lng } posición en tiempo real mientras se mueve
};

// ═══════════════════════════════════════════════════════════════════════
// INICIALIZACIÓN
// ═══════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', async () => {
  await loadStopsData();
  initLeafletMap();
  setupUIEventListeners();
  setupDialogLightDismiss();
  renderStopsList();
  updateStats();
});

// Obtener la URL base del backend dinámicamente según el host (local o cloud)
function getBackendBaseUrl() {
  if (window.location.protocol.startsWith('http')) {
    return window.location.origin;
  }
  return 'http://localhost:8000';
}

// Cargar paraderos desde Backend local/cloud, localStorage o archivo JSON predeterminado
async function loadStopsData() {
  const backendBase = getBackendBaseUrl();

  // 1. Intentar cargar desde el Backend (Cloud o Local)
  try {
    const res = await fetch(`${backendBase}/api/v1/transit/stops`, { cache: 'no-store' });
    if (res.ok) {
      state.stops = await res.json();
      localStorage.setItem('bc_admin_stops', JSON.stringify(state.stops));
      const syncStatus = document.getElementById('sync-status');
      if (syncStatus) {
        const hostLabel = window.location.host || 'Cloud Backend';
        syncStatus.innerHTML = `<span class="status-dot"></span> Conectado a Servidor (${hostLabel})`;
      }
      return;
    }
  } catch (e) {
    // Backend no activo, continuar con caché local
  }

  // 2. Si el backend no responde, leer de localStorage
  const localSaved = localStorage.getItem('bc_admin_stops');
  if (localSaved) {
    try {
      state.stops = JSON.parse(localSaved);
      return;
    } catch (e) {
      console.warn('Error al leer datos locales, cargando JSON base', e);
    }
  }

  // 3. Fallback estático
  try {
    const res = await fetch('paraderos_tacna.json');
    state.stops = await res.json();
    saveToLocalStorage();
  } catch (err) {
    console.error('Error cargando paraderos_tacna.json', err);
    state.stops = [];
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

  // Evento de Movimiento del Ratón: Actualizar coordenadas en vivo
  const liveCoords = document.getElementById('live-coords');
  state.map.on('mousemove', (e) => {
    const lat = e.latlng.lat.toFixed(6);
    const lng = e.latlng.lng.toFixed(6);
    liveCoords.innerHTML = `<span>Tacna: ${lat}, ${lng}</span>`;
  });

  // Evento de Clic en el Mapa
  state.map.on('click', (e) => {
    // Si estamos en modo de reubicación activa: mover el pin a este punto exacto
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

  // Renderizar todos los marcadores
  renderMapMarkers();
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

    // Evento CLICK: Seleccionar y abrir popup
    marker.on('click', () => {
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
  const container = document.createElement('div');
  container.className = 'stop-popup-card';
  container.innerHTML = `
    <div class="popup-header">
      <span class="popup-badge ${isOfficial ? 'official' : 'proposal'}">
        ${isOfficial ? 'PARADERO OFICIAL' : 'PROPUESTA'}
      </span>
    </div>
    <h3 class="popup-title">${escapeHtml(stop.name)}</h3>
    <p class="popup-subtitle">${escapeHtml(stop.subtitle || 'Tacna, Perú')}</p>
    <div class="popup-coords">📍 ${stop.latitude.toFixed(6)}, ${stop.longitude.toFixed(6)}</div>
    
    <div class="popup-move-cta">
      <p class="popup-move-question">¿Deseas mover este paradero?</p>
      <button type="button" class="btn btn-primary btn-sm btn-start-move" id="popup-btn-move-${stop.id}">
        📍 Mover Paradero
      </button>
    </div>

    <div class="popup-actions-footer">
      <button type="button" class="btn btn-ghost btn-xs" id="popup-btn-edit-${stop.id}">✏️ Editar datos</button>
      <button type="button" class="btn btn-destructive btn-xs" id="popup-btn-del-${stop.id}">🗑️ Eliminar</button>
    </div>
  `;

  // Listeners dentro del popup
  container.querySelector(`#popup-btn-move-${stop.id}`).addEventListener('click', (e) => {
    e.stopPropagation();
    startRelocatingStop(stop.id);
  });

  container.querySelector(`#popup-btn-edit-${stop.id}`).addEventListener('click', (e) => {
    e.stopPropagation();
    state.map.closePopup();
    openStopDialog(stop);
  });

  container.querySelector(`#popup-btn-del-${stop.id}`).addEventListener('click', (e) => {
    e.stopPropagation();
    state.map.closePopup();
    openDeleteDialog(stop.id);
  });

  return container;
}

// Inicia el proceso controlado de reubicación
function startRelocatingStop(stopId) {
  const stop = state.stops.find(s => s.id === stopId);
  const marker = state.markersMap.get(stopId);
  if (!stop || !marker) return;

  // Si había otro paradero en movimiento, cancelarlo primero
  if (state.relocatingStopId) {
    cancelRelocation();
  }

  state.relocatingStopId = stopId;
  state.originalCoords = { lat: stop.latitude, lng: stop.longitude };
  state.tempCoords = { lat: stop.latitude, lng: stop.longitude };

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
// RENDERIZADO DE LA LISTA LATERAL
// ═══════════════════════════════════════════════════════════════════════

function renderStopsList() {
  const container = document.getElementById('stops-list');
  const showingCountText = document.getElementById('showing-count-text');

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
      const routesMatch = stop.routesPassing.some(r => r.toLowerCase().includes(q));
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
          ${stop.routesPassing.map(r => `<span class="route-pill">${escapeHtml(r)}</span>`).join('')}
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
      // Ignorar si se pulsó un botón de acción
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

  document.getElementById('stat-total').textContent = total;
  document.getElementById('stat-official').textContent = official;
  document.getElementById('stat-proposals').textContent = proposals;
}

// ═══════════════════════════════════════════════════════════════════════
// DIÁLOGO DE EDICIÓN / CREACIÓN (MODERN-WEB-GUIDANCE COMPLIANT)
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
    document.getElementById('field-routes').value = stop.routesPassing.join(', ');
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

  const routesPassing = routesStr ? routesStr.split(',').map(r => r.trim()).filter(Boolean) : ['Ruta 14'];
  const isOfficial = !category.startsWith('proposed');

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

  saveToLocalStorage();
  renderMapMarkers();
  renderStopsList();
  updateStats();
  closeStopDialog();

  if (id) selectStop(id, true);
}

function promptDeleteStop(stopId) {
  const stop = state.stops.find(s => s.id === stopId);
  if (!stop) return;

  const dialog = document.getElementById('confirm-dialog');
  const desc = document.getElementById('confirm-dialog-desc');
  desc.textContent = `¿Estás seguro de que deseas eliminar permanentemente el paradero "${stop.name}" (${stop.subtitle})?`;

  const btnConfirm = document.getElementById('btn-confirm-delete');
  btnConfirm.onclick = () => {
    executeDeleteStop(stopId);
    dialog.close();
  };

  dialog.showModal();
}

function executeDeleteStop(stopId) {
  const stop = state.stops.find(s => s.id === stopId);
  state.stops = state.stops.filter(s => s.id !== stopId);
  saveToLocalStorage();
  renderMapMarkers();
  renderStopsList();
  updateStats();
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
  const routesFormatted = stop.routesPassing.map(r => `"${r}"`).join(', ');
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
  // Botón Nuevo Paradero
  document.getElementById('btn-add-stop').addEventListener('click', () => {
    openStopDialog(null);
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

  // Buscador
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
    if (confirm('¿Restablecer el catálogo completo a los 34 paraderos originales de Tacna? Se descartarán los cambios no exportados.')) {
      localStorage.removeItem('bc_admin_stops');
      await loadStopsData();
      renderMapMarkers();
      renderStopsList();
      updateStats();
      showToast('Catálogo restablecido a valores predeterminados.');
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

