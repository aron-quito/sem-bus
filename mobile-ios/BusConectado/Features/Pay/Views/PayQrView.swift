import SwiftUI
import AVFoundation

struct PayQrView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var companionsCount: Int = 0 // RN-07: Máximo 4 acompañantes
    @State private var scanLaserOffset: CGFloat = -90
    @State private var showPaymentSuccessBanner: Bool = false

    private var holderFarePoints: Int {
        viewModel.currentUser?.roleType.farePoints ?? 15
    }

    private var companionsFarePoints: Int {
        companionsCount * 15 // RN-07: Cada acompañante abona tarifa Adulto (15 pts)
    }

    private var totalPointsToPay: Int {
        holderFarePoints + companionsFarePoints
    }

    private var totalPenToPay: Double {
        Double(totalPointsToPay) / 10.0
    }

    var body: some View {
        ZStack {
            BCTheme.background
                .ignoresSafeArea()

            if viewModel.isGuestMode {
                guestGateView
            } else {
                scannerContentView
            }
        }
    }

    // MARK: - Escáner de Cámara QR en Puerta + Selector de Acompañantes (CU-01 / RN-07)
    private var scannerContentView: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Cabecera y Badge de Tarifa Activa
                VStack(spacing: 8) {
                    Text("Pagar Pasaje con QR")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    if let user = viewModel.currentUser {
                        HStack(spacing: 6) {
                            Image(systemName: user.roleType.iconName)
                                .font(.caption)
                            Text(user.roleType.badgeLabel)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(user.roleType == .student ? BCTheme.amber : (user.roleType == .conadis ? BCTheme.cyanAccent : BCTheme.emerald))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            (user.roleType == .student ? BCTheme.amber : (user.roleType == .conadis ? BCTheme.cyanAccent : BCTheme.emerald))
                                .opacity(0.14)
                        )
                        .clipShape(Capsule())
                    }
                }
                .padding(.top, 8)

                // Visor de Cámara Nativo con Retícula Minimalista Apple
                ZStack {
                    CameraPreviewRepresentable()
                        .frame(width: 256, height: 256)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

                    // Marco y Esquinas del Escáner
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(BCTheme.emerald.opacity(0.65), lineWidth: 2)
                        .frame(width: 256, height: 256)

                    // Línea Láser Animada
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, BCTheme.emerald, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: 220, height: 2.5)
                        .offset(y: scanLaserOffset)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                scanLaserOffset = 90
                            }
                        }

                    VStack {
                        Spacer()
                        Text("Enfoca el código QR en la puerta del bus")
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(.bottom, 12)
                    }
                    .frame(width: 256, height: 256)
                }

                // Selector de Acompañantes (Regla de Negocio RN-07: Máx 4 acompañantes a 15 pts c/u)
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Viajar con acompañantes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text("Máx. 4 · Cada acompañante abona tarifa general (+15 pts)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.55))
                        }

                        Spacer()

                        HStack(spacing: 12) {
                            Button {
                                if companionsCount > 0 {
                                    BCFeedbackManager.shared.impactLight()
                                    companionsCount -= 1
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(0.1))
                                    .clipShape(Circle())
                            }
                            .disabled(companionsCount == 0)

                            Text("\(companionsCount)")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.white)
                                .frame(minWidth: 20)

                            Button {
                                if companionsCount < 4 {
                                    BCFeedbackManager.shared.impactLight()
                                    companionsCount += 1
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.caption.weight(.bold))
                                    .foregroundColor(.black)
                                    .frame(width: 32, height: 32)
                                    .background(companionsCount < 4 ? BCTheme.emerald : Color.gray)
                                    .clipShape(Circle())
                            }
                            .disabled(companionsCount >= 4)
                        }
                    }

                    Divider().background(BCTheme.hairlineBorder)

                    // Resumen de Débito Total en Tiempo Real
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total a debitar")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                            Text(companionsCount == 0 ? "1 pasajero (Titular)" : "Titular (\(holderFarePoints) pts) + \(companionsCount) acomp. (\(companionsFarePoints) pts)")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.45))
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(totalPointsToPay) pts")
                                .font(.title3.weight(.bold))
                                .foregroundColor(BCTheme.emerald)
                            Text(String(format: "S/. %.2f", totalPenToPay))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BCTheme.hairlineBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 20)

                if showPaymentSuccessBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(BCTheme.emerald)
                        Text("¡Pasaje validado! Buen viaje en la Línea 10.")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(BCTheme.emerald.opacity(0.18))
                    .clipShape(Capsule())
                }

                // Botón de Validación de Abordaje QR
                Button {
                    let ok = viewModel.payPassageWithQr(companionsCount: companionsCount)
                    if ok {
                        companionsCount = 0
                        withAnimation {
                            showPaymentSuccessBanner = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                            withAnimation {
                                showPaymentSuccessBanner = false
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Simular Lectura QR en Puerta (\(totalPointsToPay) pts)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(BCTheme.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 28)
            }
        }
    }

    // MARK: - Gate de Modo Invitado (#scan-guest-gate)
    private var guestGateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(BCTheme.royalBlue.opacity(0.14))
                    .frame(width: 92, height: 92)
                Image(systemName: "qrcode.viewfinder")
                    .font(.system(size: 40))
                    .foregroundColor(BCTheme.royalBlue)
            }

            VStack(spacing: 8) {
                Text("Inicia sesión para pagar con QR")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                Text("El cobro rápido en puerta y el descuento universitario SUNEDU requieren una cuenta verificada.")
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

// MARK: - Vista Previa de Cámara Real de iOS con Fallback Elegante
struct CameraPreviewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 256, height: 256))
        container.backgroundColor = UIColor(red: 14/255, green: 21/255, blue: 38/255, alpha: 1.0)

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized || status == .notDetermined {
            let session = AVCaptureSession()
            if let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
                let previewLayer = AVCaptureVideoPreviewLayer(session: session)
                previewLayer.videoGravity = .resizeAspectFill
                previewLayer.frame = container.bounds
                container.layer.addSublayer(previewLayer)
                DispatchQueue.global(qos: .userInitiated).async {
                    session.startRunning()
                }
            }
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
