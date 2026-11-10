import SwiftUI
import MapKit

struct ExploreMapView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var selectedStop: BusStopModel? = nil
    @State private var selectedBus: ActiveBusModel? = nil
    @State private var selectedAdvanceMinutes: Int = 5
    @State private var imminentAlertEnabled: Bool = true

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -18.0139, longitude: -70.2520), // Centro Histórico de Tacna
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        )
    )

    var body: some View {
        ZStack(alignment: .top) {
            // 1. Mapa Nativo de Tacna (Renderiza paraderos y buses únicamente cuando existen en el estado)
            Map(position: $cameraPosition) {
                // Marcadores dinámicos de Paraderos Oficiales (Vacío en cuentas de prueba hasta que se implementen)
                ForEach(viewModel.filteredStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            selectedStop = stop
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(stop.isKeyStop ? BCTheme.royalBlue : BCTheme.emerald)
                                    .frame(width: 34, height: 34)
                                    .shadow(color: .black.opacity(0.35), radius: 5)
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }

                // Marcadores dinámicos de Buses en Camino (Vacío en cuentas de prueba hasta que se implementen)
                ForEach(viewModel.filteredBuses) { bus in
                    Annotation("\(bus.unitNumber) · \(bus.plate)", coordinate: bus.coordinate) {
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            selectedBus = bus
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(BCTheme.emerald.opacity(0.28))
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .fill(BCTheme.emerald)
                                    .frame(width: 28, height: 28)
                                Image(systemName: "bus.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))

            // 2. Barra Superior de Filtros (Todo, Rutas, Paraderos) + Botón Detectar Bus
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(MapFilterCategory.allCases, id: \.self) { category in
                        let isSelected = viewModel.mapCategory == category
                        Button {
                            BCFeedbackManager.shared.impactLight()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.mapCategory = category
                            }
                        } label: {
                            Text(category.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? BCTheme.royalBlue : BCTheme.elevatedSurface.opacity(0.9))
                                .overlay(
                                    Capsule()
                                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                                )
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

                    Button {
                        BCFeedbackManager.shared.impactLight()
                        Task {
                            await viewModel.refreshStateFromBackendIfAvailable()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.caption)
                            Text("Sincronizar")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(BCTheme.cyanAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BCTheme.elevatedSurface.opacity(0.92))
                        .overlay(
                            Capsule()
                                .stroke(BCTheme.cyanAccent.opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                // Widget Circular de Alerta de Llegada (Si el usuario activó los 2 Timers de un paradero)
                if let alert = viewModel.activeArrivalAlert {
                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(BCTheme.emerald)
                                .frame(width: 8, height: 8)
                            Text("\(alert.stopName) · \(formatSeconds(alert.remainingSeconds))")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                            Button {
                                viewModel.cancelArrivalAlert()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(BCTheme.elevatedSurface.opacity(0.95))
                        .clipShape(Capsule())

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                }

                Spacer()

                // 3. Tarjeta Inferior Minimalista (Muestra Estado Vacío Limpio cuando no existen buses/paraderos)
                if viewModel.stops.isEmpty && viewModel.activeBuses.isEmpty {
                    emptyTransitStatusCard
                }
            }
        }
        .sheet(item: $selectedStop) { stop in
            stopDetailSheet(stop)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedBus) { bus in
            busTechnicalSheet(bus)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Tarjeta Minimalista Apple cuando no hay paraderos ni unidades en ruta
    private var emptyTransitStatusCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 42, height: 42)
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.65))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Sin paraderos ni buses en camino")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)

                Text("Cuenta de prueba activa. Los paraderos oficiales y unidades en ruta se visualizarán automáticamente cuando entren en operación.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(BCTheme.elevatedSurface.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Ficha de Paradero con Configurador de 2 Timers (Lista para cuando existan paraderos)
    private func stopDetailSheet(_ stop: BusStopModel) -> some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.name)
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                        Text(stop.subtitle)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text("Línea 10")
                        .font(.caption.weight(.bold))
                        .foregroundColor(BCTheme.royalBlue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BCTheme.royalBlue.opacity(0.15))
                        .clipShape(Capsule())
                }

                Divider().background(BCTheme.hairlineBorder)

                Text("ALERTA INTELIGENTE DE LLEGADA (2 TIMERS)")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.gray)

                HStack(spacing: 10) {
                    ForEach([5, 10, 15], id: \.self) { mins in
                        Button {
                            selectedAdvanceMinutes = mins
                        } label: {
                            Text("\(mins) min antes")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(selectedAdvanceMinutes == mins ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(selectedAdvanceMinutes == mins ? BCTheme.emerald : Color.white.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                Toggle(isOn: $imminentAlertEnabled) {
                    Text("Timer 2: Vibración inminente al frenar en paradero")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
                .tint(BCTheme.emerald)

                Button {
                    viewModel.activateStopArrivalAlert(
                        stop: stop,
                        advanceMinutes: selectedAdvanceMinutes,
                        imminentEnabled: imminentAlertEnabled
                    )
                    selectedStop = nil
                } label: {
                    Text("Activar Alerta de Llegada")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(BCTheme.emerald)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .padding(22)
        }
    }

    // MARK: - Ficha Técnica del Bus (Lista para cuando existan unidades en ruta)
    private func busTechnicalSheet(_ bus: ActiveBusModel) -> some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Línea \(bus.lineNumber) · \(bus.unitNumber)")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)
                        Text("Placa oficial: \(bus.plate) · Conductor: \(bus.driverName) (\(String(format: "%.1f", bus.driverRating))★)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Aforo en tiempo real")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("\(bus.occupancyCurrent)/\(bus.occupancyMax) pasajeros (\(bus.occupancyPercentage)%)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(BCTheme.emerald)
                    }
                    ProgressView(value: Double(bus.occupancyCurrent), total: Double(max(bus.occupancyMax, 1)))
                        .tint(BCTheme.emerald)
                }
                .padding(14)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                Text("Suscripción Automática activa: Tu app se vinculará a este bus en cuanto abordes o escanees tu QR en puerta.")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.55))

                Spacer()
            }
            .padding(22)
        }
    }

    private func formatSeconds(_ total: Int) -> String {
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
