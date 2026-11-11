import SwiftUI

struct LinesView: View {
    @ObservedObject var viewModel: AuthViewModel

    enum LinesSegment: String, CaseIterable {
        case routes = "Rutas Troncales (33)"
        case stops = "Directorio de Paraderos (34)"
    }

    @State private var activeSegment: LinesSegment = .routes
    @State private var expandedRouteId: String? = TacnaOfficialRouteCatalogItem.officialRoutes.first?.id
    @State private var routeSearchText: String = ""
    @State private var stopCategoryFilter: TacnaStopCategory? = nil

    private var filteredRoutes: [TacnaOfficialRouteCatalogItem] {
        let trimmed = routeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return TacnaOfficialRouteCatalogItem.officialRoutes }
        return TacnaOfficialRouteCatalogItem.officialRoutes.filter { route in
            route.code.localizedCaseInsensitiveContains(trimmed) ||
            route.title.localizedCaseInsensitiveContains(trimmed) ||
            route.corridorSummary.localizedCaseInsensitiveContains(trimmed) ||
            route.resolvedStops.contains { $0.name.localizedCaseInsensitiveContains(trimmed) }
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
                // Selector de Segmento Superior (Rutas vs Paraderos)
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
                                Text(segment.rawValue)
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
                    Text(activeSegment == .routes ? "Red de Transporte Urbano" : "Directorio de Paraderos")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(activeSegment == .routes ?
                         "Tacna cuenta con 33 rutas en funcionamiento. Aquí se listan las rutas troncales con sus paraderos clave." :
                         "34 paraderos geolocalizados de Tacna: mercados, plazas, terminales y propuestas de modernización.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.horizontal, 20)

                // Buscador de Rutas o Paraderos
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    TextField(activeSegment == .routes ?
                              "Buscar ruta o paradero (Ej: Ruta 14, UNJBG)" :
                              "Buscar paradero o avenida (Ej: Mercado Central, Viñani)",
                              text: $routeSearchText)
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
                    // Estadísticas rápidas
                    HStack(spacing: 10) {
                        statPill(value: "33", label: "Rutas activas", color: BCTheme.royalBlue)
                        statPill(value: "\(officialStopsCount)", label: "Paraderos clave", color: BCTheme.emerald)
                        statPill(value: "\(proposedStopsCount)", label: "Propuestas", color: BCTheme.amber)
                    }
                    .padding(.horizontal, 20)

                    // Catálogo de Rutas
                    if filteredRoutes.isEmpty {
                        Text("No se encontraron rutas para \"\(routeSearchText)\"")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 30)
                    } else {
                        ForEach(filteredRoutes) { route in
                            routeCardView(route)
                        }
                    }

                    // Rutas adicionales registradas en el servidor (cuando existan)
                    if !viewModel.routes.isEmpty {
                        Text("RUTAS SINCRONIZADAS DEL SERVIDOR")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 20)
                            .padding(.top, 8)

                        ForEach(viewModel.routes) { route in
                            serverRouteCard(route)
                        }
                    }
                } else {
                    // Vista Directorio de Paraderos (34)
                    stopsDirectorySection
                }

                Text("Las unidades en vivo, ETAs y aforo se mostrarán automáticamente cuando los buses entren en operación con el sistema Bus Conectado.")
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

    // MARK: - Tarjeta de Ruta Oficial con Recorrido Vertical de Paraderos
    private func routeCardView(_ route: TacnaOfficialRouteCatalogItem) -> some View {
        let isExpanded = expandedRouteId == route.id
        let routeColor = Color(hex: route.colorHex)

        return VStack(alignment: .leading, spacing: 14) {
            Button {
                BCFeedbackManager.shared.impactLight()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    expandedRouteId = isExpanded ? nil : route.id
                }
            } label: {
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
                            Label("\(route.resolvedStops.count)", systemImage: "mappin")
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
            .buttonStyle(.plain)

            if isExpanded {
                Text(route.corridorSummary)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))

                Divider().background(BCTheme.hairlineBorder)

                // Recorrido vertical tipo Apple Maps Transit
                VStack(alignment: .leading, spacing: 0) {
                    let stops = route.resolvedStops
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
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
                        Text("Ver \(route.code) en el mapa")
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

    // MARK: - Tarjeta de Ruta proveniente del Backend
    private func serverRouteCard(_ route: BusRouteModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(route.lineNumber)
                    .font(.headline.weight(.heavy))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: route.colorHex))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(route.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                    Text("\(route.originName) ⇄ \(route.destinationName) · Cada \(route.frequencyMinutes) min")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }
                Spacer()
            }
            ForEach(route.stops.sorted { $0.sequenceOrder < $1.sequenceOrder }) { stop in
                HStack(spacing: 10) {
                    Circle()
                        .fill(stop.isKeyStop ? BCTheme.emerald : BCTheme.royalBlue)
                        .frame(width: 8, height: 8)
                    Text(stop.name)
                        .font(.caption)
                        .foregroundColor(.white)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }

    // MARK: - Directorio de Paraderos (34)
    private var stopsDirectorySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Filtros horizontales de categorías
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(title: "Todos (34)", isSelected: stopCategoryFilter == nil) {
                        stopCategoryFilter = nil
                    }
                    categoryChip(title: "Mercados (9)", isSelected: stopCategoryFilter == .marketsCommercial) {
                        stopCategoryFilter = .marketsCommercial
                    }
                    categoryChip(title: "Plazas (10)", isSelected: stopCategoryFilter == .plazasCentral) {
                        stopCategoryFilter = .plazasCentral
                    }
                    categoryChip(title: "Instituciones (8)", isSelected: stopCategoryFilter == .institutionsTerminals) {
                        stopCategoryFilter = .institutionsTerminals
                    }
                    categoryChip(title: "Propuestas (7)", isSelected: stopCategoryFilter?.isProposedModernization == true) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: stop.displayColorHex))
                        .frame(width: 38, height: 38)
                    Image(systemName: stop.displayIconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
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

                    HStack(spacing: 4) {
                        ForEach(stop.routesPassing, id: \.self) { route in
                            Text(route)
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Color(hex: "#93C5FD"))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color(hex: "#1E3A8A").opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                Spacer(minLength: 0)
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
                        Text("Ir (\(stop.totalDurationMinutes) min)")
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
