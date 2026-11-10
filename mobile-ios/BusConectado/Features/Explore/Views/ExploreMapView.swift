import SwiftUI
import MapKit

struct BusStopAnnotation: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let isKeyStop: Bool
}

struct ExploreMapView: View {
    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -18.0139, longitude: -70.2520), // Tacna Centro
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )

    private let busStops: [BusStopAnnotation] = [
        BusStopAnnotation(name: "Plaza Zela", coordinate: CLLocationCoordinate2D(latitude: -18.0125, longitude: -70.2530), isKeyStop: true),
        BusStopAnnotation(name: "Paseo Cívico / Bolognesi", coordinate: CLLocationCoordinate2D(latitude: -18.0142, longitude: -70.2505), isKeyStop: true),
        BusStopAnnotation(name: "Campus UNJBG (Av. Miraflores)", coordinate: CLLocationCoordinate2D(latitude: -18.0055, longitude: -70.2430), isKeyStop: true),
        BusStopAnnotation(name: "Mercado Central", coordinate: CLLocationCoordinate2D(latitude: -18.0160, longitude: -70.2520), isKeyStop: false),
        BusStopAnnotation(name: "Terminal Terrestre Manuel A. Odría", coordinate: CLLocationCoordinate2D(latitude: -18.0260, longitude: -70.2590), isKeyStop: true),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position) {
                ForEach(busStops) { stop in
                    Annotation(stop.name, coordinate: stop.coordinate) {
                        ZStack {
                            Circle()
                                .fill(stop.isKeyStop ? Color.blue : Color.emerald)
                                .frame(width: 32, height: 32)
                                .shadow(radius: 4)

                            Image(systemName: "bus.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }

                // Bus 01 en movimiento
                Annotation("BUS 01 (En ruta)", coordinate: CLLocationCoordinate2D(latitude: -18.0130, longitude: -70.2515)) {
                    ZStack {
                        Circle()
                            .fill(Color.emerald.opacity(0.3))
                            .frame(width: 44, height: 44)

                        Circle()
                            .fill(Color.emerald)
                            .frame(width: 24, height: 24)

                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea(edges: .top)

            // Tarjeta Inferior de Parada Próxima
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PRÓXIMO BUS APROXIMÁNDOSE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.emerald)

                        Text("Línea 10 · BUS 01")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("3 min")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.emerald)
                        Text("a 450 metros")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundColor(.blue)
                    Text("Paradero: Plaza Zela (Hacia Cono Sur)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(16)
            .background(Color(red: 15/255, green: 23/255, blue: 42/255))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }
}
