import SwiftUI

struct LineStopItem: Identifiable {
    let id = UUID()
    let order: Int
    let name: String
    let detail: String
    let isCurrent: Bool
}

struct LinesView: View {
    private let stops: [LineStopItem] = [
        LineStopItem(order: 1, name: "Terminal Pesquero (Cono Norte)", detail: "Punto de partida · Salidas cada 6 min", isCurrent: false),
        LineStopItem(order: 2, name: "Av. Pinto / Mercado Mayorista Grau", detail: "Conexión comercial", isCurrent: false),
        LineStopItem(order: 3, name: "Campus Central UNJBG", detail: "Av. Miraflores · Zona Universitaria", isCurrent: false),
        LineStopItem(order: 4, name: "Plaza Zela", detail: "Centro Histórico · Paradero Principal", isCurrent: true),
        LineStopItem(order: 5, name: "Paseo Cívico / Av. San Martín", detail: "Catedral de Tacna · Arco Parabólico", isCurrent: false),
        LineStopItem(order: 6, name: "Mercado Central de Tacna", detail: "Comercio céntrico", isCurrent: false),
        LineStopItem(order: 7, name: "Terminal Terrestre Manuel A. Odría", detail: "Zona Sur", isCurrent: false),
        LineStopItem(order: 8, name: "Asoc. Vista Alegre (Cono Sur)", detail: "Fin de ruta", isCurrent: false),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Cabecera de la Línea
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.blue)
                                .frame(width: 48, height: 48)

                            Text("10")
                                .font(.title2)
                                .fontWeight(.heavy)
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Línea 10 · Tacna")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("Cono Norte ⇄ Cono Sur (Vía Centro / UNJBG)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Activo")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.emerald)
                            Text("6 min frec.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }

                    HStack(spacing: 12) {
                        metricPill(icon: "clock.fill", title: "05:30 - 22:30", color: .blue)
                        metricPill(icon: "dollarsign.circle.fill", title: "S/. 0.70 Univ.", color: .amber)
                        metricPill(icon: "bus.fill", title: "18 buses", color: .emerald)
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // Lista de Paraderos en Ruta
                VStack(alignment: .leading, spacing: 14) {
                    Text("RECORRIDO Y PARADEROS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 20)

                    VStack(spacing: 0) {
                        ForEach(stops) { stop in
                            HStack(alignment: .top, spacing: 14) {
                                // Indicador visual de parada
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(stop.isCurrent ? Color.emerald : Color.blue.opacity(0.6))
                                        .frame(width: stop.isCurrent ? 14 : 10, height: stop.isCurrent ? 14 : 10)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: stop.isCurrent ? 2 : 0)
                                        )

                                    if stop.order != stops.count {
                                        Rectangle()
                                            .fill(Color.white.opacity(0.15))
                                            .frame(width: 2, height: 38)
                                    }
                                }
                                .padding(.top, 4)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(stop.name)
                                            .font(.subheadline)
                                            .fontWeight(stop.isCurrent ? .bold : .medium)
                                            .foregroundColor(.white)

                                        if stop.isCurrent {
                                            Text("Próxima")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.emerald)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.emerald.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text(stop.detail)
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 24)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 30)
            }
        }
        .background(Color(red: 11/255, green: 17/255, blue: 30/255).ignoresSafeArea())
    }

    private func metricPill(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }
}
