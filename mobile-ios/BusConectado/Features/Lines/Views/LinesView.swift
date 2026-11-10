import SwiftUI

struct LinesView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var selectedDirection: String = "UP" // "UP" (Subida) o "DOWN" (Bajada)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cabecera Minimalista Apple HIG
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Líneas y Paraderos")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Red oficial de transporte urbano de Tacna")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Spacer()

                    // Selector de Sentido (Ida / Vuelta)
                    HStack(spacing: 4) {
                        directionPill(title: "Subida", code: "UP")
                        directionPill(title: "Bajada", code: "DOWN")
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                // Renderizado dinámico: Si no existen rutas/paraderos activos (Cuenta de Prueba), muestra Estado Vacío Limpio
                if viewModel.routes.isEmpty {
                    emptyLinesStateView
                } else {
                    ForEach(viewModel.routes) { route in
                        routeCardView(route)
                    }
                }

                Spacer(minLength: 32)
            }
        }
        .background(BCTheme.background.ignoresSafeArea())
    }

    private func directionPill(title: String, code: String) -> some View {
        let isSelected = selectedDirection == code
        return Button {
            BCFeedbackManager.shared.impactLight()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDirection = code
            }
        } label: {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? BCTheme.royalBlue : Color.clear)
                .clipShape(Capsule())
        }
    }

    // MARK: - Estado Vacío Minimalista cuando no existen rutas ni paraderos registrados
    private var emptyLinesStateView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 76, height: 76)
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.top, 24)

            VStack(spacing: 6) {
                Text("Sin paraderos ni rutas activas")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.white)

                Text("Al estar en una cuenta de prueba sin unidades ni paraderos dados de alta en operación, esta lista permanece limpia. En cuanto se habiliten rutas y paraderos en el servidor, se listarán aquí con su secuencia e itinerario en tiempo real.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                BCFeedbackManager.shared.impactLight()
                Task {
                    await viewModel.refreshStateFromBackendIfAvailable()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                    Text("Sincronizar con el Servidor")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - Tarjeta Dinámica de Ruta y Paraderos (Lista para cuando se implementen en BD)
    private func routeCardView(_ route: BusRouteModel) -> some View {
        let filteredStops = route.stops.filter { $0.direction == selectedDirection }

        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(BCTheme.royalBlue)
                        .frame(width: 44, height: 44)
                    Text(route.lineNumber)
                        .font(.title3.weight(.heavy))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(route.name)
                        .font(.headline.weight(.bold))
                        .foregroundColor(.white)
                    Text("\(route.originName) ⇄ \(route.destinationName)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()

                Text("Cada \(route.frequencyMinutes) min")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(BCTheme.emerald)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BCTheme.emerald.opacity(0.14))
                    .clipShape(Capsule())
            }

            Divider().background(BCTheme.hairlineBorder)

            ForEach(filteredStops) { stop in
                HStack(spacing: 12) {
                    Circle()
                        .fill(stop.isKeyStop ? BCTheme.emerald : BCTheme.royalBlue)
                        .frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                        Text(stop.subtitle)
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    Spacer()
                }
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }
}
