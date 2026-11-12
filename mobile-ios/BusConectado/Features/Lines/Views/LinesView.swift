import SwiftUI

struct LinesView: View {
    @ObservedObject var viewModel: AuthViewModel

    enum LinesSegment: CaseIterable {
        case routes
        case stops
    }

    enum RouteCatalogFilter: String, CaseIterable {
        case all = "Todas"
        case ordinaryInService = "En servicio"
        case ordinaryAll = "Ordinarias"
        case external = "Externas"
    }

    @State private var activeSegment: LinesSegment = .routes
    @State private var selectedRouteFilter: RouteCatalogFilter = .all
    @State private var expandedRouteId: String? = TacnaOfficialRouteCatalogItem.officialRoutes.first?.id
    @State private var routeSearchText: String = ""
    @State private var stopCategoryFilter: TacnaStopCategory? = nil

    private var ordinaryRoutes: [TacnaOfficialRouteCatalogItem] {
        viewModel.dynamicRoutes.filter { $0.isOrdinary }
    }

    private var ordinaryInServiceRoutes: [TacnaOfficialRouteCatalogItem] {
        viewModel.dynamicRoutes.filter { $0.isOrdinaryInService }
    }

    private var externalRoutes: [TacnaOfficialRouteCatalogItem] {
        viewModel.dynamicRoutes.filter { $0.isExternal }
    }

    private var filteredRoutes: [TacnaOfficialRouteCatalogItem] {
        var base = viewModel.dynamicRoutes
        switch selectedRouteFilter {
        case .all:
            break
        case .ordinaryInService:
            base = base.filter { $0.isOrdinaryInService }
        case .ordinaryAll:
            base = base.filter { $0.isOrdinary }
        case .external:
            base = base.filter { $0.isExternal }
        }

        let trimmed = routeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter { route in
            route.code.localizedCaseInsensitiveContains(trimmed) ||
            route.title.localizedCaseInsensitiveContains(trimmed) ||
            route.corridorSummary.localizedCaseInsensitiveContains(trimmed) ||
            route.resolvedStops(using: viewModel.dynamicCatalogStops).contains {
                $0.name.localizedCaseInsensitiveContains(trimmed) ||
                $0.shortName.localizedCaseInsensitiveContains(trimmed)
            }
        }
    }

    private var filteredStops: [TacnaDestinationPlace] {
        var stops = viewModel.dynamicCatalogStops
        if let category = stopCategoryFilter {
            if category.isProposedModernization {
                stops = stops.filter { $0.category.isProposedModernization }
            } else {
                stops = stops.filter { $0.category == category }
            }
        }
        let trimmed = routeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return stops }
        return stops.filter { stop in
            stop.name.localizedCaseInsensitiveContains(trimmed) ||
            stop.subtitle.localizedCaseInsensitiveContains(trimmed) ||
            stop.routesPassing.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Selector de Segmento Superior (Líneas Sincronizadas vs Directorio de Paraderos)
                HStack(spacing: 0) {
                    ForEach(LinesSegment.allCases, id: \.self) { segment in
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeSegment = segment
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: segment == .routes ? "bus.fill" : "mappin.and.ellipse")
                                    .font(.system(size: 11, weight: .bold))
                                Text(
                                    segment == .routes
                                        ? "Líneas (\(viewModel.dynamicRoutes.count))"
                                        : "Paraderos (\(viewModel.dynamicCatalogStops.count))"
                                )
                                    .font(.caption.weight(.bold))
                            }
                            .foregroundColor(activeSegment == segment ? .white : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                activeSegment == segment ?
                                    Capsule().fill(BCTheme.royalBlue) :
                                    Capsule().fill(Color.clear)
                            )
                        }
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .padding(.horizontal, 20)
                .padding(.top, 14)

                // Resumen de la Red Urbana de Tacna
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(activeSegment == .routes ? "Líneas Ordinarias y Externas" : "Directorio Oficial de Paraderos")
                            .font(.system(size: 21, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            Task {
                                await viewModel.refreshStateFromBackendIfAvailable(isManual: true)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Sincronizar")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(BCTheme.cyanAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(BCTheme.cyanAccent.opacity(0.12))
                            .clipShape(Capsule())
                        }
                    }

                    Text(
                        activeSegment == .routes
                            ? "Rutas Ordinarias (con tracking GPS, pago QR y notificación de llegada) y Rutas Externas referenciales de Tacna."
                            : "\(viewModel.dynamicCatalogStops.count) paraderos sincronizados con estado de servicio de rutas ordinarias y alertas."
                    )
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 20)

                // Buscador de Rutas o Paraderos
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    TextField(
                        activeSegment == .routes
                            ? "Buscar línea ordinaria, externa o paradero (Ej: Ruta 14, UNJBG)"
                            : "Buscar paradero o avenida (Ej: Mercado Central, Viñani)",
                        text: $routeSearchText
                    )
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()

                    if !routeSearchText.isEmpty {
                        Button {
                            routeSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(Color.white.opacity(0.06))
                .overlay(
                    Capsule().stroke(BCTheme.hairlineBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
                .padding(.horizontal, 20)

                if activeSegment == .routes {
                    // Estadísticas de Rutas Sincronizadas
                    HStack(spacing: 10) {
                        statPill(
                            value: "\(ordinaryInServiceRoutes.count)/\(ordinaryRoutes.count)",
                            label: "Ordinarias en Servicio",
                            color: BCTheme.emerald
                        )
                        statPill(
                            value: "\(externalRoutes.count)",
                            label: "Externas (Tacna)",
                            color: BCTheme.amber
                        )
                        statPill(
                            value: "\(viewModel.dynamicCatalogStops.count)",
                            label: "Paraderos Red",
                            color: BCTheme.royalBlue
                        )
                    }
                    .padding(.horizontal, 20)

                    // Banner de Estado Operativo de Líneas Ordinarias en Servicio
                    ordinaryServiceStatusBanner

                    // Píldoras de Filtro por Tipo de Ruta
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RouteCatalogFilter.allCases, id: \.self) { filter in
                                categoryChip(
                                    title: filterChipTitle(for: filter),
                                    isSelected: selectedRouteFilter == filter
                                ) {
                                    selectedRouteFilter = filter
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }

                    // Catálogo de Rutas Sincronizadas
                    if filteredRoutes.isEmpty {
                        Text("No se encontraron rutas para el filtro seleccionado.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        ForEach(filteredRoutes) { route in
                            routeCardView(route)
                        }
                    }
                } else {
                    // Vista Directorio de Paraderos Sincronizados
                    stopsDirectorySection
                }

                Text("El recorrido, kilometraje y tiempo aproximado por paradero sirven de referencia tanto para el pasajero como para el módulo del chofer.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.top, 6)

                Spacer(minLength: 32)
            }
        }
        .background(BCTheme.background.ignoresSafeArea())
    }

    private func filterChipTitle(for filter: RouteCatalogFilter) -> String {
        switch filter {
        case .all:
            return "Todas (\(viewModel.dynamicRoutes.count))"
        case .ordinaryInService:
            return "En servicio (\(ordinaryInServiceRoutes.count))"
        case .ordinaryAll:
            return "Ordinarias (\(ordinaryRoutes.count))"
        case .external:
            return "Externas (\(externalRoutes.count))"
        }
    }

    private var ordinaryServiceStatusBanner: some View {
        let activeCodes = ordinaryInServiceRoutes.map(\.code).joined(separator: ", ")
        let inactiveOrd = ordinaryRoutes.filter { !$0.isInService }.map(\.code).joined(separator: ", ")

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ordinaryInServiceRoutes.isEmpty ? BCTheme.amber : BCTheme.emerald)
                    .frame(width: 9, height: 9)
                Text(
                    ordinaryInServiceRoutes.isEmpty
                        ? "Ninguna línea ordinaria se encuentra en servicio activo"
                        : "Líneas Ordinarias en Servicio: \(activeCodes)"
                )
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                Spacer()
            }

            if !inactiveOrd.isEmpty {
                Text("Fuera de servicio actualmente: \(inactiveOrd). Los paraderos exclusivos de rutas fuera de servicio mostrarán un aviso preventivo.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.68))
            } else {
                Text("Todas las líneas ordinarias están operando con tracking GPS, pago QR y notificaciones de llegada.")
                    .font(.system(size: 10.5))
                    .foregroundColor(.white.opacity(0.68))
            }
        }
        .padding(12)
        .background(
            (ordinaryInServiceRoutes.isEmpty ? BCTheme.amber : BCTheme.emerald).opacity(0.10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke((ordinaryInServiceRoutes.isEmpty ? BCTheme.amber : BCTheme.emerald).opacity(0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var officialStopsCount: Int {
        viewModel.dynamicCatalogStops.filter { !$0.category.isProposedModernization }.count
    }

    private var proposedStopsCount: Int {
        viewModel.dynamicCatalogStops.filter { $0.category.isProposedModernization }.count
    }

    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.heavy).monospacedDigit())
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Tarjeta de Ruta (Ordinaria o Externa) con Tiempos Aproximados y Paraderos
    private func routeCardView(_ route: TacnaOfficialRouteCatalogItem) -> some View {
        let isExpanded = expandedRouteId == route.id
        let routeColor = Color(hex: route.colorHex)
        let stops = route.resolvedStops(using: viewModel.dynamicCatalogStops)

        return VStack(alignment: .leading, spacing: 14) {
            Button {
                BCFeedbackManager.shared.impactLight()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expandedRouteId = isExpanded ? nil : route.id
                }
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    // Cabecera de clasificación: Ordinaria (En Servicio / Fuera de Servicio) vs Externa
                    HStack {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(
                                    route.isOrdinary
                                        ? (route.isInService ? BCTheme.emerald : BCTheme.amber)
                                        : Color.white.opacity(0.45)
                                )
                                .frame(width: 7, height: 7)
                            Text(
                                route.isOrdinary
                                    ? (route.isInService ? "ORDINARIA • EN SERVICIO (TRACKING & QR)" : "ORDINARIA • FUERA DE SERVICIO")
                                    : "RUTA EXTERNA • REFERENCIAL (SIN TRACKING)"
                            )
                            .font(.system(size: 9, weight: .black))
                            .foregroundColor(
                                route.isOrdinary
                                    ? (route.isInService ? BCTheme.emerald : BCTheme.amber)
                                    : .white.opacity(0.65)
                            )
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            route.isOrdinary
                                ? (route.isInService ? BCTheme.emerald.opacity(0.14) : BCTheme.amber.opacity(0.14))
                                : Color.white.opacity(0.07)
                        )
                        .clipShape(Capsule())

                        Spacer()

                        Text(String(format: "%.1f km • ~%d min", route.totalDistanceKm, route.estimatedTotalMinutes))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(BCTheme.cyanAccent)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Text(route.code.replacingOccurrences(of: "RUTA ", with: ""))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(width: 48, height: 48)
                            .background(routeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(route.code)
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundColor(routeColor)
                            Text(route.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 8) {
                                Label(route.frequencyLabel, systemImage: "clock")
                                Label(route.scheduleLabel, systemImage: "sun.max")
                                Label("\(stops.count) paraderos", systemImage: "mappin")
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(route.corridorSummary)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))

                if route.isOrdinary && !route.isInService {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(BCTheme.amber)
                        Text("Esta línea ordinaria se encuentra temporalmente fuera de servicio. Los paraderos que dependan únicamente de esta ruta no tendrán alerta de llegada activa.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(10)
                    .background(BCTheme.amber.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if route.isExternal {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.caption)
                            .foregroundColor(BCTheme.cyanAccent)
                        Text("Ruta externa tradicional de Tacna: sirve como referencia de recorrido en el mapa, pero no cuenta con unidades trackeadas por GPS ni pago con QR.")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Divider().background(BCTheme.hairlineBorder)

                // Recorrido vertical tipo Apple Maps Transit con Tiempo Aproximado Acumulado (Referencia App y Chofer)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        let cumulativeMins = route.estimatedArrivalMinutesFromOrigin(forStopAt: index, using: viewModel.dynamicCatalogStops)
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Rectangle()
                                    .fill(index == 0 ? Color.clear : routeColor)
                                    .frame(width: 3, height: 8)
                                Circle()
                                    .fill(index == 0 || index == stops.count - 1 ? routeColor : BCTheme.background)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(routeColor, lineWidth: 2.5))
                                Rectangle()
                                    .fill(index == stops.count - 1 ? Color.clear : routeColor)
                                    .frame(width: 3)
                                    .frame(maxHeight: .infinity)
                            }
                            .frame(width: 14)

                            Button {
                                viewModel.selectedTab = 0
                                viewModel.selectPlaceFromSearch(stop, startRouteImmediately: false)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(stop.shortName)
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(.white)
                                            if stop.category.isProposedModernization {
                                                Text("Propuesta")
                                                    .font(.system(size: 8, weight: .heavy))
                                                    .foregroundColor(BCTheme.amber)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(BCTheme.amber.opacity(0.15))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(stop.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.45))
                                            .lineLimit(1)
                                    }
                                    Spacer()

                                    Text(index == 0 ? "Inicio" : "+\(cumulativeMins) min")
                                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                        .foregroundColor(BCTheme.cyanAccent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(BCTheme.cyanAccent.opacity(0.12))
                                        .clipShape(Capsule())

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Proyectar ruta completa en el mapa principal
                Button {
                    viewModel.projectRouteOnMainMap(route)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "map.fill")
                            .font(.caption.weight(.bold))
                        Text("Ver trazado de \(route.code) en el mapa")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(routeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isExpanded ? routeColor.opacity(0.55) : BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }

    // MARK: - Directorio de Paraderos Sincronizados
    private var stopsDirectorySection: some View {
        let allStops = viewModel.dynamicCatalogStops
        let marketsCount = allStops.filter { $0.category == .marketsCommercial }.count
        let plazasCount = allStops.filter { $0.category == .plazasCentral }.count
        let instCount = allStops.filter { $0.category == .institutionsTerminals }.count
        let propCount = allStops.filter { $0.category.isProposedModernization }.count

        return VStack(alignment: .leading, spacing: 14) {
            // Filtros horizontales de categorías con conteos dinámicos reales
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(title: "Todos (\(allStops.count))", isSelected: stopCategoryFilter == nil) {
                        stopCategoryFilter = nil
                    }
                    categoryChip(title: "Mercados (\(marketsCount))", isSelected: stopCategoryFilter == .marketsCommercial) {
                        stopCategoryFilter = .marketsCommercial
                    }
                    categoryChip(title: "Plazas (\(plazasCount))", isSelected: stopCategoryFilter == .plazasCentral) {
                        stopCategoryFilter = .plazasCentral
                    }
                    categoryChip(title: "Instituciones (\(instCount))", isSelected: stopCategoryFilter == .institutionsTerminals) {
                        stopCategoryFilter = .institutionsTerminals
                    }
                    categoryChip(title: "Propuestas (\(propCount))", isSelected: stopCategoryFilter?.isProposedModernization == true) {
                        stopCategoryFilter = .proposedHospitals
                    }
                }
                .padding(.horizontal, 20)
            }

            if filteredStops.isEmpty {
                Text("No se encontraron paraderos para \"\(routeSearchText)\"")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
            } else {
                ForEach(filteredStops) { stop in
                    stopDirectoryCard(stop)
                }
            }
        }
    }

    private func categoryChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            BCFeedbackManager.shared.impactLight()
            action()
        }) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .white : .white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(isSelected ? BCTheme.royalBlue : Color.white.opacity(0.07))
                )
                .overlay(
                    Capsule().stroke(isSelected ? BCTheme.royalBlue : BCTheme.hairlineBorder, lineWidth: 1)
                )
        }
    }

    private func stopDirectoryCard(_ stop: TacnaDestinationPlace) -> some View {
        let availability = viewModel.stopNotificationAvailability(for: stop)

        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: stop.displayColorHex))
                        .frame(width: 38, height: 38)
                    Image(systemName: stop.displayIconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(stop.name)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)

                        Text(stop.displayBadgeText)
                            .font(.system(size: 8, weight: .black))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: stop.displayColorHex))
                            .clipShape(Capsule())
                    }

                    Text(stop.subtitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                        .lineLimit(1)

                    // Píldoras de rutas diferenciadas por Ordinaria (En Servicio / Fuera de Servicio) vs Externa
                    if !stop.routesPassing.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(stop.routesPassing, id: \.self) { routeCode in
                                    let rItem = viewModel.routeItem(forCode: routeCode)
                                    let isOrd = rItem?.isOrdinary ?? false
                                    let isActive = rItem?.isOrdinaryInService ?? false

                                    HStack(spacing: 3) {
                                        Circle()
                                            .fill(
                                                isOrd
                                                    ? (isActive ? BCTheme.emerald : BCTheme.amber)
                                                    : Color.white.opacity(0.4)
                                            )
                                            .frame(width: 5, height: 5)
                                        Text(routeCode)
                                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    }
                                    .foregroundColor(
                                        isOrd
                                            ? (isActive ? Color(hex: "#6EE7B7") : Color(hex: "#FDE68A"))
                                            : Color.white.opacity(0.75)
                                    )
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        isOrd
                                            ? (isActive ? BCTheme.emerald.opacity(0.16) : BCTheme.amber.opacity(0.18))
                                            : Color.white.opacity(0.08)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }

            // Aviso o estado de servicio de rutas ordinarias para este paradero
            switch availability {
            case .available(let activeRoutes):
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(BCTheme.emerald)
                    Text("Notificación activa disponible • En servicio: \(activeRoutes.map(\.code).joined(separator: ", "))")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BCTheme.emerald)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BCTheme.emerald.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .ordinaryOutOfService(let registeredRoutes):
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundColor(BCTheme.amber)
                        .padding(.top, 1)
                    Text("Aviso: No hay rutas en servicio para este paradero por parte de las ordinarias (\(registeredRoutes.map(\.code).joined(separator: ", ")) fuera de servicio).")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BCTheme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BCTheme.amber.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BCTheme.amber.opacity(0.38), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            case .noOrdinaryRoutes:
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                    Text("Solo rutas externas / Punto de encuentro • Sin opción de notificación")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider().background(BCTheme.hairlineBorder)

            HStack(spacing: 10) {
                Button {
                    BCFeedbackManager.shared.impactLight()
                    viewModel.selectedTab = 0
                    viewModel.focusMap(on: stop.coordinate, spanDelta: 0.009)
                    viewModel.searchedDestinationPin = stop
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "map.fill")
                            .font(.caption2.weight(.bold))
                        Text("Ver en Mapa")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    BCFeedbackManager.shared.impactMedium()
                    viewModel.openRoutePlanner(with: stop)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.caption2.weight(.bold))
                        Text(
                            availability == .noOrdinaryRoutes
                                ? "Ir / Punto de encuentro"
                                : "Ir (\(stop.totalDurationMinutes) min)"
                        )
                        .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(BCTheme.cyanAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20)
    }
}
