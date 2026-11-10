import SwiftUI

struct WalletView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var selectedFilter: Int = 0 // 0: Todos, 1: Viajes, 2: Recargas
    @State private var showRechargeSheet: Bool = false
    @State private var showSuneduSheet: Bool = false
    @State private var dniInput: String = "74829103"

    private var tripTransactions: [LedgerTransactionItem] {
        viewModel.transactions.filter { !$0.isPositive }
    }

    private var rechargeTransactions: [LedgerTransactionItem] {
        viewModel.transactions.filter { $0.isPositive }
    }

    private var filteredTransactions: [LedgerTransactionItem] {
        switch selectedFilter {
        case 1: return tripTransactions
        case 2: return rechargeTransactions
        default: return viewModel.transactions
        }
    }

    var body: some View {
        ZStack {
            BCTheme.background
                .ignoresSafeArea()

            if viewModel.isGuestMode {
                guestGateView
            } else {
                authenticatedWalletContent
            }
        }
        .sheet(isPresented: $showRechargeSheet) {
            rechargeSheetView
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSuneduSheet) {
            suneduAccreditationSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var authenticatedWalletContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Cabecera del Monedero (Fiel al Mockup)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "wallet.pass.fill")
                                .font(.title3)
                                .foregroundColor(BCTheme.royalBlue)
                            Text("Mi Monedero BC")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        Text("Saldo prepago para transporte urbano de Tacna")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.55))
                    }

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(BCTheme.emerald)
                            .frame(width: 7, height: 7)
                        Text("Verificado")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(BCTheme.emerald)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(BCTheme.emerald.opacity(0.14))
                    .overlay(
                        Capsule()
                            .stroke(BCTheme.emerald.opacity(0.35), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                // 2. Tarjeta Principal Azul: Saldo Prepago Bus Conectado
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 37/255, green: 99/255, blue: 235/255),
                                    Color(red: 29/255, green: 78/255, blue: 216/255),
                                    Color(red: 30/255, green: 58/255, blue: 138/255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Saldo Prepago Bus Conectado")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.white.opacity(0.92))

                            Spacer()

                            Text("1 PEN = 10 Pts")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("\(viewModel.currentUser?.pointsBalance ?? 0)")
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.white)

                            Text("PUNTOS BC")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white.opacity(0.85))
                        }

                        HStack {
                            Text(String(format: "Equivalente: S/. %.2f", viewModel.currentUser?.balancePen ?? 0.0))
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white.opacity(0.85))

                            Spacer()

                            Button {
                                BCFeedbackManager.shared.impactLight()
                                showRechargeSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Recargar")
                                        .fontWeight(.bold)
                                }
                                .font(.subheadline)
                                .foregroundColor(BCTheme.royalBlue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Color.white)
                                .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(20)
                }
                .padding(.horizontal, 20)

                // 3. Tarjeta de Beneficio Tarifario (SUNEDU Vigente / CONADIS / Acreditar SUNEDU)
                benefitTierCard
                    .padding(.horizontal, 20)

                // 4. Historial de Viajes y Movimientos (CU-08)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .foregroundColor(BCTheme.royalBlue)
                            Text("HISTORIAL DE VIAJES")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.white)
                        }

                        Spacer()

                        Text("Últimos movimientos")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.45))
                    }

                    // Chips con contadores dinámicos reales
                    HStack(spacing: 8) {
                        filterChip(title: "Todos (\(viewModel.transactions.count))", index: 0)
                        filterChip(title: "Viajes (\(tripTransactions.count))", index: 1)
                        filterChip(title: "Recargas (\(rechargeTransactions.count))", index: 2)
                    }

                    if filteredTransactions.isEmpty {
                        emptyTransactionsCard
                    } else {
                        VStack(spacing: 10) {
                            ForEach(filteredTransactions) { tx in
                                transactionRow(tx)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 36)
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: - Tarjeta de Beneficio Estudiantil SUNEDU o Acreditación (CU-03)
    @ViewBuilder
    private var benefitTierCard: some View {
        let role = viewModel.currentUser?.roleType ?? .adult

        if role == .student {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 38/255, green: 22/255, blue: 8/255))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(BCTheme.amber.opacity(0.45), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(BCTheme.amber.opacity(0.2))
                                .frame(width: 40, height: 40)
                            Image(systemName: "graduationcap.fill")
                                .foregroundColor(BCTheme.amber)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Carné Universitario SUNEDU")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(Color(red: 251/255, green: 191/255, blue: 36/255))
                            Text("Vigente")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(Color(red: 251/255, green: 191/255, blue: 36/255))
                        }

                        Spacer()

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tarifa 7")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(red: 253/255, green: 230/255, blue: 138/255))
                            Text("pts")
                                .font(.caption.weight(.bold))
                                .foregroundColor(Color(red: 253/255, green: 230/255, blue: 138/255))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(red: 92/255, green: 45/255, blue: 12/255))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    Text("Válido hasta el \(viewModel.currentUser?.studentVerification?.expiresAt ?? "31/12/2026"). Ahorro del 53% respecto a tarifa regular (15 pts / S/. 1.50).")
                        .font(.caption)
                        .foregroundColor(Color(red: 217/255, green: 179/255, blue: 130/255))
                }
                .padding(16)
            }
        } else if role == .conadis {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BCTheme.cyanAccent.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "figure.roll")
                        .foregroundColor(BCTheme.cyanAccent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Acreditación CONADIS Vigente")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                    Text("Pase Libre Ley N° 30412 · Tarifa 0 pts (S/. 0.00)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }
                Spacer()
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BCTheme.cyanAccent.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            // Opción para Adulto de acreditar su carné universitario SUNEDU (CU-03)
            Button {
                BCFeedbackManager.shared.impactLight()
                showSuneduSheet = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(BCTheme.amber.opacity(0.16))
                            .frame(width: 40, height: 40)
                        Image(systemName: "graduationcap.fill")
                            .foregroundColor(BCTheme.amber)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("¿Eres estudiante universitario?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text("Acredita tu carné SUNEDU para activar la tarifa de 7 pts (S/. 0.70)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(BCTheme.amber)
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BCTheme.amber.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func filterChip(title: String, index: Int) -> some View {
        let isSelected = selectedFilter == index
        return Button {
            BCFeedbackManager.shared.impactLight()
            selectedFilter = index
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .white : .white.opacity(0.55))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? BCTheme.royalBlue : Color.white.opacity(0.05))
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : BCTheme.hairlineBorder, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
    }

    private var emptyTransactionsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundColor(.white.opacity(0.35))
            Text("Sin movimientos registrados")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
            Text("Tus recargas con Yape/Plin y tus pasajes validados por QR aparecerán aquí en orden cronológico.")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color.white.opacity(0.03))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func transactionRow(_ tx: LedgerTransactionItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tx.isPositive ? BCTheme.emerald.opacity(0.15) : BCTheme.royalBlue.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: tx.isPositive ? "arrow.down.left" : "bus.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(tx.isPositive ? BCTheme.emerald : BCTheme.royalBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tx.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)

                    if let plate = tx.plateBadge {
                        Text(plate)
                            .font(.caption2.monospaced())
                            .foregroundColor(.white.opacity(0.65))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }

                Text(tx.subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(tx.timestampLabel)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                    Text("Completado")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(BCTheme.emerald)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(tx.formattedPoints)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(tx.isPositive ? BCTheme.emerald : Color(red: 248/255, green: 113/255, blue: 113/255))
                Text(tx.formattedPen)
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Hoja de Recarga Instantánea Yape / Plin (CU-05)
    private var rechargeSheetView: some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Recargar Monedero BC")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)

                Text("Selecciona un paquete de recarga instantánea (1 PEN = 10 Puntos BC):")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    rechargePackageButton(points: 50, penLabel: "S/. 5.00")
                    rechargePackageButton(points: 100, penLabel: "S/. 10.00")
                    rechargePackageButton(points: 200, penLabel: "S/. 20.00")
                    rechargePackageButton(points: 500, penLabel: "S/. 50.00")
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private func rechargePackageButton(points: Int, penLabel: String) -> some View {
        Button {
            Task {
                await viewModel.rechargePoints(points: points, gateway: "Yape BCP")
                showRechargeSheet = false
            }
        } label: {
            VStack(spacing: 6) {
                Text("+\(points) pts")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                Text(penLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(BCTheme.emerald)
                Text("Yape / Plin")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BCTheme.hairlineBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Hoja de Acreditación SUNEDU (CU-03)
    private var suneduAccreditationSheet: some View {
        ZStack {
            BCTheme.elevatedSurface.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Acreditación Universitaria SUNEDU")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)

                Text("Valida tu DNI asociado a tu carné universitario vigente para activar la tarifa medio pasaje (7 pts / S/. 0.70).")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))

                TextField("DNI de 8 dígitos", text: $dniInput)
                    .keyboardType(.numberPad)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    Task {
                        await viewModel.accreditSuneduCard(
                            dni: dniInput,
                            university: "Universidad Nacional Jorge Basadre Grohmann (UNJBG)",
                            career: "Ingeniería en Informática y Sistemas"
                        )
                        showSuneduSheet = false
                    }
                } label: {
                    Text("Verificar con SUNEDU y Activar Tarifa 7 pts")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(BCTheme.amber)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Spacer()
            }
            .padding(24)
        }
    }

    // MARK: - Gate de Modo Invitado (#wallet-guest-gate)
    private var guestGateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(BCTheme.royalBlue.opacity(0.14))
                    .frame(width: 92, height: 92)
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 40))
                    .foregroundColor(BCTheme.royalBlue)
            }

            VStack(spacing: 8) {
                Text("Tu Monedero Prepago BC")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                Text("Inicia sesión con tu número celular para recargar con Yape/Plin, acreditar tu carné SUNEDU y revisar tu historial de viajes.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewModel.isGuestMode = false
                    viewModel.currentStep = .splash
                }
            } label: {
                Text("Iniciar Sesión / Registrarse")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BCTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 32)
        }
    }
}
