import SwiftUI
import CoreImage.CIFilterBuiltins

struct PayQrView: View {
    @ObservedObject var viewModel: AuthViewModel
    @State private var remainingSeconds: Int = 59
    @State private var timerActive = true
    @State private var timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        ZStack {
            Color(red: 11/255, green: 17/255, blue: 30/255)
                .ignoresSafeArea()

            if viewModel.isGuestMode {
                guestGateView
            } else {
                authenticatedQrView
            }
        }
    }

    private var authenticatedQrView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Presenta este código al subir al bus")
                    .font(.headline)
                    .foregroundColor(.white)
                Text("El validador de la Línea 10 debitará tu pasaje automáticamente")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 10)

            // Contenedor del código QR
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color.white)
                        .frame(width: 250, height: 250)
                        .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)

                    if let qrImage = generateQrCode(from: "BC-PAY-USER-\(viewModel.currentUser?.id ?? "DEMO")-\(remainingSeconds)") {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 210, height: 210)
                    }
                }

                // Temporizador regresivo
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .foregroundColor(.blue)
                    Text("Expira en \(remainingSeconds) segundos")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
            }

            // Tarjeta de Tarifa Aplicada
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.amber.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Image(systemName: "graduationcap.fill")
                        .foregroundColor(.amber)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tarifa Universitaria SUNEDU")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Cobro por viaje: 7 pts (S/. 0.70)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("7 pts")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.emerald)
                    Text("Saldo: \(viewModel.currentUser?.pointsBalance ?? 42) pts")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.horizontal, 20)
        .onReceive(timer) { _ in
            if remainingSeconds > 1 {
                remainingSeconds -= 1
            } else {
                remainingSeconds = 59
            }
        }
    }

    private var guestGateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 100, height: 100)

                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
            }

            VStack(spacing: 8) {
                Text("Función para usuarios registrados")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Para generar un código QR de pasaje y pagar en el validador del bus, necesitas iniciar sesión con tu número celular.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                withAnimation {
                    viewModel.isGuestMode = false
                    viewModel.currentStep = .splash
                }
            } label: {
                Text("Iniciar Sesión / Registrarse")
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.emerald)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.top, 12)
        }
    }

    private func generateQrCode(from string: String) -> UIImage? {
        filter.message = Data(string.utf8)

        if let outputImage = filter.outputImage {
            if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgImage)
            }
        }
        return nil
    }
}
