import SwiftUI

struct WalletView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var selectedFilter: Int = 0 // 0: Todos, 1: Viajes, 2: Recargas
    @State private var showRechargeSheet: Bool = false
    @State private var showCarnetRequestSheet: Bool = false
    @State private var selectedTransactionForDetail: LedgerTransactionItem? = nil

    // Estado Pasarela de Pagos
    @State private var gatewayStep: Int = 0 // 0: Monto/Método, 1: Checkout, 2: Comprobante
    @State private var selectedPointsPackage: Int = 50
    @State private var customPenInput: String = ""
    @State private var selectedGatewayMethod: WalletPaymentMethod = .yape
    @State private var operationCodeInput: String = ""
    @State private var cardNumberInput: String = ""
    @State private var cardExpiryInput: String = ""
    @State private var cardCvvInput: String = ""
    @State private var cardHolderInput: String = ""
    @State private var isProcessingPayment: Bool = false
    @State private var lastCompletedTransaction: LedgerTransactionItem? = nil

    // Estado Solicitud de Carné
    @State private var carnetType: String = "STUDENT"
    @State private var dniInput: String = ""
    @State private var institutionInput: String = "UNJBG - Universidad Nacional Jorge Basadre"
    @State private var documentCodeInput: String = ""
    @State private var expiryDateInput: Date = Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: 31)) ?? Date().addingTimeInterval(86400 * 180)

    enum WalletPaymentMethod: String, CaseIterable, Identifiable {
        case yape = "Yape BCP"
        case plin = "Plin"
        case card = "Tarjeta Visa / MC"

        var id: String { rawValue }

        var shortTitle: String {
            switch self {
            case .yape: return "Yape"
            case .plin: return "Plin"
            case .card: return "Tarjeta"
            }
        }

        var subtitle: String {
            switch self {
            case .yape: return "Sin comisión · Abono inmediato"
            case .plin: return "Interbank, BBVA, Scotiabank"
            case .card: return "Débito o crédito en Soles"
            }
        }

        var iconName: String {
            switch self {
            case .yape: return "qrcode"
            case .plin: return "arrow.left.arrow.right.circle.fill"
            case .card: return "creditcard.fill"
            }
        }

        var accentColor: Color {
            switch self {
            case .yape: return Color(hex: "#8B5CF6")
            case .plin: return Color(hex: "#06B6D4")
            case .card: return Color(hex: "#3B82F6")
            }
        }
    }

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

    private var effectiveRechargePoints: Int {
        let cleaned = customPenInput.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespacesAndNewlines)
        if let customPen = Double(cleaned), customPen >= 1.0 {
            return Int((customPen * 10.0).rounded())
        }
        return selectedPointsPackage
    }

    private var effectiveRechargePen: Double {
        Double(effectiveRechargePoints) / 10.0
    }

    var body: some View {
        ZStack {
            BCTheme.background
                .ignoresSafeArea()

            if viewModel.isGuestMode {
                guestGateView
            } else if !(viewModel.currentUser?.hasVerifiedPhone ?? false) {
                phoneRequiredGateView
            } else {
                authenticatedWalletContent
            }
        }
        .sheet(isPresented: $showRechargeSheet) {
            rechargeGatewaySheet
        }
        .sheet(isPresented: $showCarnetRequestSheet) {
            carnetRequestSheet
        }
        .sheet(item: $selectedTransactionForDetail) { tx in
            transactionDetailSheet(tx)
        }
    }

    private var authenticatedWalletContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Tarjeta Principal de Saldo Prepago (sin duplicar el header superior de MainTabView)
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 30/255, green: 58/255, blue: 138/255), Color(red: 37/255, green: 99/255, blue: 235/255)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.35), radius: 14, y: 6)

                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 140, height: 140)
                        .offset(x: 40, y: -40)

                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 8) {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(BCTheme.emerald)
                                    .frame(width: 6, height: 6)
                                Text("Cuenta Verificada")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.22))
                            .clipShape(Capsule())

                            Spacer()

                            Text("1 PEN = 10 Pts")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Capsule())
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(viewModel.currentUser?.pointsBalance ?? 0)")
                                .font(.system(size: 46, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("PUNTOS BC")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.white.opacity(0.85))
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "Equivalente: S/. %.2f", viewModel.currentUser?.balancePen ?? 0.0))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white.opacity(0.92))
                                Text("Tarifa actual: \(viewModel.currentUser?.roleType.farePoints ?? 15) pts / viaje")
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.75))
                            }

                            Spacer()

                            Button {
                                BCFeedbackManager.shared.impactLight()
                                resetPaymentGatewayState()
                                showRechargeSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.subheadline)
                                    Text("Recargar")
                                        .font(.subheadline.weight(.bold))
                                }
                                .foregroundColor(BCTheme.royalBlue)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                            }
                        }
                    }
                    .padding(20)
                }
                .padding(.top, 10)

                // Tarjeta de Beneficio Tarifario / Solicitud de Revisión y Caducidad de Carné
                benefitTierCard

                // Historial de Movimientos
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("HISTORIAL DE MOVIMIENTOS", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Text("Yape · Plin · QR")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.45))
                    }

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
                                Button {
                                    BCFeedbackManager.shared.impactLight()
                                    selectedTransactionForDetail = tx
                                } label: {
                                    transactionRow(tx)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 4)

                Spacer(minLength: 90)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
    }

    private func walletMetricMiniCard(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var benefitTierCard: some View {
        let role = viewModel.currentUser?.roleType ?? .adult

        if role == .student {
            let sv = viewModel.currentUser?.studentVerification
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(BCTheme.amber.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: "graduationcap.fill")
                            .foregroundColor(BCTheme.amber)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Carné Universitario Vigente")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text(sv?.university ?? "Universitario SUNEDU")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    Text("Tarifa 7 pts")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(BCTheme.amber)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BCTheme.amber.opacity(0.18))
                        .clipShape(Capsule())
                }

                Divider().background(Color.white.opacity(0.1))

                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundColor(BCTheme.amber)
                    Text(sv?.expirationSummaryText ?? "Válido hasta el 31/12/2026")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.88))
                    Spacer()
                }
            }
            .padding(16)
            .background(Color(red: 44/255, green: 30/255, blue: 10/255).opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BCTheme.amber.opacity(0.45), lineWidth: 1)
            )
        } else if role == .conadis {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(BCTheme.cyanAccent.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "figure.roll")
                            .foregroundColor(BCTheme.cyanAccent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pase Libre CONADIS Activo")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Text("Beneficio exonerado · Ley N° 30412")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Spacer()
                    Text("0 pts")
                        .font(.caption.weight(.black))
                        .foregroundColor(BCTheme.cyanAccent)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BCTheme.cyanAccent.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .padding(16)
            .background(Color(red: 12/255, green: 38/255, blue: 48/255).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BCTheme.cyanAccent.opacity(0.4), lineWidth: 1)
            )
        } else if let pending = viewModel.carnetReviewRequest {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(BCTheme.cyanAccent.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(BCTheme.cyanAccent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pending.carnetTypeDisplay)
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                        Text("Solicitud \(pending.id) · DNI \(pending.dni)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                    }

                    Spacer()

                    Text(pending.statusDisplay)
                        .font(.caption2.weight(.bold))
                        .foregroundColor(BCTheme.amber)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BCTheme.amber.opacity(0.16))
                        .clipShape(Capsule())
                }

                Text("Caducidad declarada: \(StudentVerificationInfo.formattedExpirationDate(pending.expiresAt))")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BCTheme.cyanAccent.opacity(0.35), lineWidth: 1)
            )
        } else {
            Button {
                BCFeedbackManager.shared.impactLight()
                showCarnetRequestSheet = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(BCTheme.amber.opacity(0.16))
                            .frame(width: 40, height: 40)
                        Image(systemName: "person.text.rectangle.fill")
                            .foregroundColor(BCTheme.amber)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("¿Tienes Carné Universitario o CONADIS?")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("Solicita revisión para tarifa preferencial (7 pts o 0 pts)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.68))
                            .lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(BCTheme.amber)
                }
                .padding(16)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BCTheme.amber.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    private func filterChip(title: String, index: Int) -> some View {
        let isSelected = selectedFilter == index
        return Button {
            BCFeedbackManager.shared.impactLight()
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedFilter = index
            }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(isSelected ? .white : .white.opacity(0.65))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? BCTheme.royalBlue : Color.white.opacity(0.05))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : BCTheme.hairlineBorder, lineWidth: 1)
                )
        }
    }

    private var emptyTransactionsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.title)
                .foregroundColor(.white.opacity(0.35))
            Text("Sin movimientos registrados")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Tus recargas con Yape/Plin/Tarjeta y tus pasajes validados por QR aparecerán aquí en orden cronológico.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
    }

    private func transactionRow(_ tx: LedgerTransactionItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(tx.isPositive ? BCTheme.emerald.opacity(0.15) : BCTheme.royalBlue.opacity(0.16))
                    .frame(width: 44, height: 44)

                Image(systemName: tx.isPositive ? "arrow.down.left" : "qrcode")
                    .font(.headline)
                    .foregroundColor(tx.isPositive ? BCTheme.emerald : BCTheme.royalBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(tx.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    if let plate = tx.plateBadge {
                        Text(plate)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                Text(tx.subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(tx.timestampLabel)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.45))
                    Text("·")
                        .foregroundColor(.white.opacity(0.35))
                    Text("Saldo: \(tx.balanceAfter) pts")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(BCTheme.emerald.opacity(0.85))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(tx.formattedPoints)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(tx.isPositive ? BCTheme.emerald : Color(red: 248/255, green: 113/255, blue: 113/255))
                Text(String(format: "S/. %.2f", tx.amountPen))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BCTheme.hairlineBorder, lineWidth: 1)
        )
    }

    // MARK: - Pasarela de Pagos en 3 Pasos (Monto + Método -> Checkout -> Comprobante)
    private var rechargeGatewaySheet: some View {
        NavigationStack {
            ZStack {
                BCTheme.elevatedSurface.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        // Indicador de Paso
                        HStack(spacing: 8) {
                            gatewayStepIndicator(step: 0, title: "1. Monto")
                            Rectangle().fill(gatewayStep >= 1 ? BCTheme.royalBlue : Color.white.opacity(0.12)).frame(height: 2)
                            gatewayStepIndicator(step: 1, title: "2. Pago")
                            Rectangle().fill(gatewayStep >= 2 ? BCTheme.emerald : Color.white.opacity(0.12)).frame(height: 2)
                            gatewayStepIndicator(step: 2, title: "3. Recibo")
                        }
                        .padding(.top, 4)

                        if gatewayStep == 0 {
                            gatewayAmountAndMethodStep
                        } else if gatewayStep == 1 {
                            gatewayCheckoutStep
                        } else {
                            gatewayReceiptStep
                        }
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Pasarela de Recarga")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if gatewayStep == 1 && !isProcessingPayment {
                        Button("Atrás") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                gatewayStep = 0
                            }
                        }
                        .foregroundColor(.white.opacity(0.8))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") {
                        showRechargeSheet = false
                    }
                    .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .presentationDetents([.large])
    }

    private func gatewayStepIndicator(step: Int, title: String) -> some View {
        let isActive = gatewayStep == step
        let isDone = gatewayStep > step
        let color: Color = isDone ? BCTheme.emerald : (isActive ? BCTheme.royalBlue : .white.opacity(0.4))
        return Text(title)
            .font(.system(size: 11, weight: isActive || isDone ? .bold : .medium))
            .foregroundColor(isActive || isDone ? .white : .white.opacity(0.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(isActive || isDone ? 0.25 : 0.08))
            .clipShape(Capsule())
    }

    private var gatewayAmountAndMethodStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ELIGE EL MONTO A RECARGAR")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.6))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    rechargePackageCard(points: 20, penLabel: "S/. 2.00")
                    rechargePackageCard(points: 50, penLabel: "S/. 5.00")
                    rechargePackageCard(points: 100, penLabel: "S/. 10.00")
                    rechargePackageCard(points: 200, penLabel: "S/. 20.00")
                }

                HStack(spacing: 10) {
                    Text("S/.")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white.opacity(0.7))
                    TextField("Otro monto (mín. S/. 1.00)", text: $customPenInput)
                        .keyboardType(.decimalPad)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Text("= \(effectiveRechargePoints) pts")
                        .font(.caption.weight(.bold))
                        .foregroundColor(BCTheme.emerald)
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("MÉTODO DE PAGO")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white.opacity(0.6))

                ForEach(WalletPaymentMethod.allCases) { method in
                    let isSelected = selectedGatewayMethod == method
                    Button {
                        BCFeedbackManager.shared.impactLight()
                        selectedGatewayMethod = method
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(method.accentColor.opacity(0.2))
                                    .frame(width: 40, height: 40)
                                Image(systemName: method.iconName)
                                    .foregroundColor(method.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(method.rawValue)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundColor(.white)
                                Text(method.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundColor(isSelected ? BCTheme.royalBlue : .white.opacity(0.3))
                        }
                        .padding(12)
                        .background(isSelected ? BCTheme.royalBlue.opacity(0.12) : Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isSelected ? BCTheme.royalBlue : BCTheme.hairlineBorder, lineWidth: 1.2)
                        )
                    }
                }
            }

            Button {
                BCFeedbackManager.shared.impactMedium()
                withAnimation(.easeInOut(duration: 0.2)) {
                    gatewayStep = 1
                }
            } label: {
                HStack {
                    Text(String(format: "Continuar · S/. %.2f (%d pts)", effectiveRechargePen, effectiveRechargePoints))
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(BCTheme.royalBlue)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func rechargePackageCard(points: Int, penLabel: String) -> some View {
        let isSelected = customPenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selectedPointsPackage == points
        return Button {
            BCFeedbackManager.shared.impactLight()
            customPenInput = ""
            selectedPointsPackage = points
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("+\(points) pts")
                    .font(.headline.weight(.black))
                    .foregroundColor(.white)
                Text(penLabel)
                    .font(.caption.weight(.bold))
                    .foregroundColor(isSelected ? BCTheme.emerald : .white.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(isSelected ? BCTheme.royalBlue.opacity(0.22) : Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? BCTheme.royalBlue : BCTheme.hairlineBorder, lineWidth: 1.3)
            )
        }
    }

    private var gatewayCheckoutStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Resumen de Pago
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL A PAGAR")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))
                    Text(String(format: "S/. %.2f", effectiveRechargePen))
                        .font(.title.weight(.black))
                        .foregroundColor(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(selectedGatewayMethod.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundColor(selectedGatewayMethod.accentColor)
                    Text("+\(effectiveRechargePoints) Puntos BC")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(BCTheme.emerald)
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))

            if selectedGatewayMethod == .card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DATOS DE TARJETA")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.6))

                    TextField("Número de tarjeta (4557 •••• •••• ••••)", text: $cardNumberInput)
                        .keyboardType(.numberPad)
                        .padding(14)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)

                    HStack(spacing: 10) {
                        TextField("MM/AA", text: $cardExpiryInput)
                            .keyboardType(.numbersAndPunctuation)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(.white)

                        TextField("CVV", text: $cardCvvInput)
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundColor(.white)
                    }

                    TextField("Nombre del titular", text: $cardHolderInput)
                        .padding(14)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 68, height: 68)
                            Image(systemName: "qrcode")
                                .font(.system(size: 38))
                                .foregroundColor(.black)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Paga con \(selectedGatewayMethod.shortTitle) al:")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                            Text("987 654 321")
                                .font(.title3.weight(.black))
                                .foregroundColor(.white)
                            Text("Bus Conectado Tacna SAC")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(selectedGatewayMethod.accentColor)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text("CÓDIGO DE APROBACIÓN / OPERACIÓN (OPCIONAL)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.55))

                    TextField("Ej. 482910 (deja vacío para auto-validar en demo)", text: $operationCodeInput)
                        .keyboardType(.numberPad)
                        .padding(14)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.white)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(BCTheme.emerald)
                Text("Transacción cifrada TLS · Recarga instantánea en Monedero BC")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.65))
            }

            Button {
                executeGatewayPayment()
            } label: {
                HStack(spacing: 10) {
                    if isProcessingPayment {
                        ProgressView().tint(.white)
                        Text("Procesando pago...")
                    } else {
                        Image(systemName: "checkmark.shield.fill")
                        Text(String(format: "Confirmar y Pagar S/. %.2f", effectiveRechargePen))
                    }
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isProcessingPayment ? BCTheme.royalBlue.opacity(0.6) : BCTheme.emerald)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(isProcessingPayment)
        }
    }

    private var gatewayReceiptStep: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(BCTheme.emerald.opacity(0.18))
                    .frame(width: 78, height: 78)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46))
                    .foregroundColor(BCTheme.emerald)
            }
            .padding(.top, 10)

            VStack(spacing: 4) {
                Text("¡Recarga Exitosa!")
                    .font(.title2.weight(.black))
                    .foregroundColor(.white)
                Text("Se acreditaron +\(lastCompletedTransaction?.amountPoints ?? effectiveRechargePoints) Puntos BC a tu cuenta.")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                receiptRow(label: "Método de pago", value: selectedGatewayMethod.rawValue)
                receiptRow(label: "Importe pagado", value: String(format: "S/. %.2f", lastCompletedTransaction?.amountPen ?? effectiveRechargePen))
                receiptRow(label: "Detalle", value: lastCompletedTransaction?.subtitle ?? "Abono confirmado")
                receiptRow(label: "Nuevo saldo total", value: "\(viewModel.currentUser?.pointsBalance ?? 0) Puntos BC")
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(BCTheme.hairlineBorder, lineWidth: 1))

            Button {
                showRechargeSheet = false
            } label: {
                Text("Listo")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(BCTheme.royalBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func receiptRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Modal de Solicitud de Revisión de Carné
    private var carnetRequestSheet: some View {
        NavigationStack {
            ZStack {
                BCTheme.elevatedSurface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Solicita la verificación de tu carnet universitario SUNEDU para acceder a la tarifa de S/. 0.70 (7 pts).")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.75))

                        VStack(alignment: .leading, spacing: 10) {
                            TextField("DNI (8 dígitos)", text: $dniInput)
                                .keyboardType(.numberPad)
                                .padding(14)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(.white)

                            TextField("Universidad (Perú)", text: $institutionInput)
                                .padding(14)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(.white)

                            TextField("Código de Carné Universitario", text: $documentCodeInput)
                                .padding(14)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundColor(.white)

                            DatePicker(
                                "Fecha de caducidad",
                                selection: $expiryDateInput,
                                displayedComponents: .date
                            )
                            .tint(BCTheme.amber)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button {
                            let df = DateFormatter()
                            df.dateFormat = "yyyy-MM-dd"
                            let cleanDni = dniInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            let cleanCode = documentCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            viewModel.submitCarnetReviewRequest(
                                type: "STUDENT",
                                dni: cleanDni.isEmpty ? "74829103" : cleanDni,
                                institution: institutionInput,
                                documentCode: cleanCode.isEmpty ? "SUNEDU-\(cleanDni)" : cleanCode,
                                expiresAt: df.string(from: expiryDateInput)
                            )
                            showCarnetRequestSheet = false
                        } label: {
                            Label("Enviar Solicitud de Revisión", systemImage: "paperplane.fill")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(BCTheme.amber)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Revisión de Carné")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { showCarnetRequestSheet = false }
                        .foregroundColor(.white.opacity(0.75))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Detalle de Movimiento del Historial
    private func transactionDetailSheet(_ tx: LedgerTransactionItem) -> some View {
        NavigationStack {
            ZStack {
                BCTheme.elevatedSurface.ignoresSafeArea()
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(tx.isPositive ? BCTheme.emerald.opacity(0.18) : BCTheme.royalBlue.opacity(0.18))
                            .frame(width: 64, height: 64)
                        Image(systemName: tx.isPositive ? "arrow.down.left" : "qrcode")
                            .font(.title2.weight(.bold))
                            .foregroundColor(tx.isPositive ? BCTheme.emerald : BCTheme.royalBlue)
                    }

                    Text(tx.formattedPoints)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundColor(tx.isPositive ? BCTheme.emerald : .white)

                    Text(tx.title)
                        .font(.headline)
                        .foregroundColor(.white)

                    VStack(spacing: 10) {
                        receiptRow(label: "Fecha / Hora", value: tx.timestampLabel)
                        receiptRow(label: "Descripción", value: tx.subtitle)
                        receiptRow(label: "Equivalente", value: String(format: "S/. %.2f", tx.amountPen))
                        if let plate = tx.plateBadge {
                            receiptRow(label: "Unidad / Placa", value: plate)
                        }
                        receiptRow(label: "Saldo anterior", value: "\(tx.balanceBefore) pts")
                        receiptRow(label: "Saldo resultante", value: "\(tx.balanceAfter) pts")
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(BCTheme.hairlineBorder, lineWidth: 1))

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Detalle de Movimiento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { selectedTransactionForDetail = nil }
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var guestGateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BCTheme.royalBlue.opacity(0.14))
                    .frame(width: 76, height: 76)
                Image(systemName: "wallet.pass.fill")
                    .font(.largeTitle)
                    .foregroundColor(BCTheme.royalBlue)
            }

            Text("Monedero BC requiere cuenta")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)

            Text("Regístrate o inicia sesión con tu número para recargar puntos, validar tu carné y conservar tu historial de viajes.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                BCFeedbackManager.shared.impactMedium()
                viewModel.isGuestMode = false
                viewModel.currentStep = .splash
            } label: {
                Text("Crear Cuenta o Iniciar Sesión")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BCTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private var phoneRequiredGateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(BCTheme.emerald.opacity(0.14))
                    .frame(width: 76, height: 76)
                Image(systemName: "wallet.pass.fill")
                    .font(.largeTitle)
                    .foregroundColor(BCTheme.emerald)
            }

            if let user = viewModel.currentUser {
                Text(user.displayFullName)
                    .font(.headline)
                    .foregroundColor(BCTheme.cyanAccent)
            }

            Text("Accede con tu número celular para usar tu Monedero")
                .font(.title3.weight(.bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("Si desea hacer pagos dentro de la app o acceder a los beneficios como descuentos o promociones, registre su celular.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                BCFeedbackManager.shared.impactMedium()
                viewModel.openPhoneLinkingFromApp()
            } label: {
                Text("Vincular número celular")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BCTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private func resetPaymentGatewayState() {
        gatewayStep = 0
        selectedPointsPackage = 50
        customPenInput = ""
        operationCodeInput = ""
        isProcessingPayment = false
        lastCompletedTransaction = nil
    }

    private func executeGatewayPayment() {
        isProcessingPayment = true
        let ref = operationCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            let tx = await viewModel.rechargePoints(
                points: effectiveRechargePoints,
                gateway: selectedGatewayMethod.rawValue,
                reference: ref.isEmpty ? nil : ref
            )
            await MainActor.run {
                lastCompletedTransaction = tx
                isProcessingPayment = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    gatewayStep = 2
                }
            }
        }
    }
}
