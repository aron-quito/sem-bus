# Bus Conectado • Panel Web de Administración de Paraderos (Tacna)

Aplicación web interactiva desarrollada para calibrar, reubicar visualmente, crear y eliminar paraderos de la red de transporte urbano de Tacna.

---

## Características Principales

1. **Reubicación Directa por Arrastre (Drag & Drop en Mapa):**
   - Todos los paraderos están representados con marcadores interactivos en el mapa de Tacna.
   - Basta con **hacer clic y arrastrar** cualquier pin hasta la esquina, avenida o intersección exacta. Al soltarlo, las coordenadas de latitud y longitud se actualizan y guardan inmediatamente en tiempo real.
2. **Creación de Nuevos Paraderos:**
   - Haz clic en el botón superior **"+ Nuevo Paradero"** o haz clic directamente en cualquier punto libre del mapa para abrir el menú emergente *"Crear Paradero Aquí"*.
3. **Edición Completa:**
   - Edita nombre completo, nombre corto, dirección/subtítulo, categoría urbana, rutas que abordan y notas de modernización.
4. **Eliminación Segura:**
   - Diálogo modal accesible con confirmación antes de eliminar cualquier paradero.
5. **Selector de Capas Cartográficas:**
   - **Oscuro:** Estilo minimalista Apple/Google Maps Dark Mode (CartoDB Dark Matter).
   - **Calles:** Vista detallada de calles y nomenclaturas (OpenStreetMap).
   - **Satélite:** Fotografía satelital real en alta resolución (Esri World Imagery) para verificar techos de mercados, paraderos físicos y veredas.
6. **Exportación a iOS en 1 Clic:**
   - Haz clic en **"Exportar a iOS"** para generar automáticamente la estructura Swift para `DomainModels.swift`.
7. **Descarga de JSON y Persistencia:**
   - Todos los cambios se guardan localmente en el navegador (`localStorage`) y se pueden descargar en `paraderos_tacna.json`.

---

## Cómo Ejecutar la Aplicación Web

### Opción 1: Abrir directamente en el navegador (Sin dependencias)
Simplemente haz doble clic o abre el archivo `index.html` en Safari, Chrome o Firefox:
```bash
open admin-web/index.html
```

### Opción 2: Servidor local ligero (Python)
Desde la terminal en la raíz del repositorio:
```bash
python3 -m http.server 3000 --directory admin-web
```
Luego abre tu navegador en:
**http://localhost:3000**

