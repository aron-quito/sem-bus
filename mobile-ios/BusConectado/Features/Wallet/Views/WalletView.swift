import SwiftUI

struct WalletTransactionItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let time: String
    let points: String
    let pen: String
    let isPositive: Bool
}

struct WalletView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var selectedFilter: Int = 0 // 0: Todos, 1: Viajes, 2: Recargas
    @State private var showRechargeSheet: Bool = false

    private let transactions: [WalletTransactionItem] = [
        WalletTransactionItem(title: "Línea 10 • BUS 01", subtitle: "Plaza Zela ➔ P. Mercado (Mercado Central)", time: "Hoy, 18:30 • 12 min", points: "-7 pts", pen: "-S/. 0.70", isPositive: false),
        WalletTransactionItem(title: "Recarga Yape BCP", subtitle: "Abono exitoso vía pasarela Yape", time: "Hoy, 14:15", points: "+50 pts", pen: "+S/. 5.00", isPositive: true),
        WalletTransactionItem(title: "Línea 10 • BUS 04", subtitle: "UNJBG Campus ➔ Bolognesi", time: "Ayer, 13:05 • 18 min", points: "-7 pts", pen: "-S/. 0.70", isPositive: false),
        WalletTransactionItem(title: "Línea 10 • BUS 02", subtitle: "Av. Leguía ➔ Plaza Zela", time: "Ayer, 08:20 • 15 min", points: "-7 pts", pen: "-S/. 0.70", isPositive: false),
    ]

    var filteredTransactions: [WalletTransactionItem] {
        switch selectedFilter {
        case 1:
            return transactions.filter { !$0.isPositive }
        case 2:
            return transactions.filter { $0.isPositive }
        default:
            return transactions
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "wallet.pass.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                            Text("Mi Monedero BC")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        Text("Saldo prepago para transporte urbano de Tacna")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.emerald)
                            .frame(width: 7, height: 7)
                        Text("Verificado")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.emerald)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.emerald.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // TARJETA 1: Saldo Prepago Bus Conectado
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 26/255, green: 86/255, blue: 219/255), Color(red: 30/255, green: 58/255, blue: 138/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Saldo Prepago Bus Conectado")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white.opacity(0.9))

                            Spacer()

                            Text("1 PEN = 10 Pts")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(viewModel.currentUser?.pointsBalance ?? 42)")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundColor(.white)

                            Text("PUNTOS BC")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        HStack {
                            Text("Equivalente aprox: S/. \(Double(viewModel.currentUser?.pointsBalance ?? 42) / 10.0, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))

                            Spacer()

                            Button {
                                showRechargeSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Recargar")
                                        .fontWeight(.bold)
                                }
                                .font(.subheadline)
                                .foregroundColor(Color(red: 26/255, green: 86/255, blue: 219/255))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.white)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(20)
                }
                .padding(.horizontal, 20)

                // TARJETA 2: Carné Universitario SUNEDU Vigente
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(red: 38/255, green: 22/255, blue: 8/255))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.amber.opacity(0.4), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.amber.opacity(0.2))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "graduationcap.fill")
                                    .foregroundColor(.amber)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Carné Universitario SUNEDU")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("Vigente")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.emerald)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Tarifa 7")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                Text("pts")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Text("Válido hasta el 31/12/2026. Ahorro del 53% respecto a tarifa regular (15 pts / S/. 1.50).")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .padding(16)
                }
                .padding(.horizontal, 20)

                // SECCIÓN: Historial de Viajes
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundColor(.blue)
                            Text("HISTORIAL DE VIAJES")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }

                        Spacer()

                        Text("Últimos movimientos")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }

                    // Filtros
                    HStack(spacing: 8) {
                        filterButton(title: "Todos (4)", index: 0)
                        filterButton(title: "Viajes (3)", index: 1)
                        filterButton(title: "Recargas (1)", index: 2)
                    }

                    // Lista de items
                    VStack(spacing: 10) {
                        ForEach(filteredTransactions) { tx in
                            transactionRow(tx)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)

                Spacer(minLength: 40)
            }
            .padding(.vertical, 10)
        }
        .background(Color(red: 11/255, green: 17/255, blue: 30/255).ignoresSafeArea())
        .sheet(isPresented: $showRechargeSheet) {
            rechargeSheetView
        }
    }

    private func filterButton(title: String, index: Int) -> some View {
        Button {
            selectedFilter = index
        } label: {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(selectedFilter == index ? .white : .gray)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selectedFilter == index ? Color.blue : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    private func transactionRow(_ tx: WalletTransactionItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tx.isPositive ? Color.emerald.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: tx.isPositive ? "arrow.down.left" : "bus.fill")
                    .foregroundColor(tx.isPositive ? .emerald : .blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(tx.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(tx.subtitle)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                Text(tx.time)
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.8))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.points)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(tx.isPositive ? .emerald : .red.opacity(0.85))
                Text(tx.pen)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var rechargeSheetView: some View {
        ZStack {
            Color(red: 11/255, green: 17/255, blue: 30/255).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("Recargar Puntos BC")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Selecciona el monto a recargar vía Yape o Plin:")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                HStack(spacing: 12) {
                    rechargeOption(points: "50 pts", pen: "S/. 5.00")
                    rechargeOption(points: "100 pts", pen: "S/. 10.00")
                    rechargeOption(points: "200 pts", pen: "S/. 20.00")
                }

                Button {
                    if var current = viewModel.currentUser {
                        current.pointsBalance += 50
                        viewModel.currentUser = current
                    }
                    showRechargeSheet = false
                } label: {
                    Text("Pagar con Yape")
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 12)

                Button("Cancelar") {
                    showRechargeSheet = false
                }
                .foregroundColor(.gray)
            }
            .padding(24)
        }
    }

    private func rechargeOption(points: String, pen: String) -> some View {
        VStack(spacing: 4) {
            Text(points)
                .font(.headline)
                .foregroundColor(.white)
            Text(pen)
                .font(.caption)
                .foregroundColor(.emerald)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}
