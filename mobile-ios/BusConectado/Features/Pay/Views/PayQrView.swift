import SwiftUI
import AVFoundation
import PhotosUI
import CoreImage

struct PayQrView: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = QRCameraController()

    @State private var companionsCount: Int = 0 // RN-07: Máximo 4 acompañantes
    @State private var scanLaserOffset: CGFloat = -110
    @State private var toastMessage: String? = nil
    @State private var toastIsSuccess: Bool = true
    @State private var photoPickerItem: PhotosPickerItem? = nil

    private let scanWindowSize: CGFloat = 248

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

    /// La cámara solo puede estar activa si: hay sesión, la pestaña Pagar QR está visible y la app está en primer plano
    private var cameraShouldRun: Bool {
        !viewModel.isGuestMode && viewModel.selectedTab == 2 && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isGuestMode {
                guestGateView
            } else {
                scannerContentView
            }
        }
        .onAppear {
            camera.onCodeScanned = { payload in handleScannedPayload(payload) }
            syncCameraState()
        }
        // Privacidad: apagar la cámara inmediatamente al abandonar el módulo
        .onDisappear { camera.stop() }
        .onChange(of: viewModel.selectedTab) { _, _ in syncCameraState() }
        .onChange(of: scenePhase) { _, _ in syncCameraState() }
        .onChange(of: viewModel.isGuestMode) { _, _ in syncCameraState() }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            decodeQrFromPhoto(newItem)
        }
    }

    private func syncCameraState() {
        if cameraShouldRun {
            camera.start()
        } else {
            camera.stop()
        }
    }

    // MARK: - Escáner Estilo Yape (Cámara completa + capa translúcida + recorte centrado + panel inferior)
    private var scannerContentView: some View {
        ZStack {
            // 1. Vista de cámara a pantalla completa (o estado sin permiso)
            if camera.permission == .denied || camera.permission == .restricted {
                cameraDeniedBackground
            } else {
                CameraPreviewLayerView(session: camera.session)
                    .ignoresSafeArea()
            }

            // 2. Capa translúcida oscura con ventana centrada transparente
            GeometryReader { geo in
                let cutoutCenterY = geo.size.height * 0.36
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.58))
                        .ignoresSafeArea()

                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .frame(width: scanWindowSize, height: scanWindowSize)
                        .position(x: geo.size.width / 2, y: cutoutCenterY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .allowsHitTesting(false)

                // Esquinas, láser y texto guía sobre la ventana
                ZStack {
                    ScannerCornerBrackets()
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                        .frame(width: scanWindowSize, height: scanWindowSize)

                    if camera.isRunning {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, BCTheme.emerald, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: scanWindowSize - 36, height: 2.5)
                            .shadow(color: BCTheme.emerald, radius: 6)
                            .offset(y: scanLaserOffset)
                            .onAppear {
                                scanLaserOffset = -110
                                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                                    scanLaserOffset = 110
                                }
                            }
                    }

                    Text("Enfoca el código QR del validador en la puerta del bus")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .environment(\.colorScheme, .dark)
                        .offset(y: scanWindowSize / 2 + 30)
                }
                .position(x: geo.size.width / 2, y: cutoutCenterY)
                .allowsHitTesting(false)
            }

            // 3. Barra superior (título + linterna + cerrar)
            VStack {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pagar con QR")
                            .font(.headline.weight(.bold))
                            .foregroundColor(.white)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(camera.isRunning ? BCTheme.emerald : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(camera.isRunning ? "Cámara activa solo en esta pantalla" : "Cámara apagada")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }

                    Spacer()

                    circleGlassButton(icon: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                      tint: camera.torchOn ? BCTheme.amber : .white) {
                        camera.toggleTorch()
                    }
                    .disabled(!camera.isRunning)

                    circleGlassButton(icon: "xmark", tint: .white) {
                        camera.stop()
                        viewModel.selectedTab = 0
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Spacer()
            }

            // 4. Panel inferior translúcido con las opciones del módulo
            VStack(spacing: 10) {
                Spacer()

                if let toastMessage {
                    HStack(spacing: 8) {
                        Image(systemName: toastIsSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(toastIsSuccess ? BCTheme.emerald : BCTheme.amber)
                        Text(toastMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomPaymentPanel
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Panel Inferior (Tarifa, Acompañantes RN-07, Total, Subir Imagen, Validar)
    private var bottomPaymentPanel: some View {
        VStack(spacing: 12) {
            // Badge de tarifa activa
            if let user = viewModel.currentUser {
                let tint = user.roleType == .student ? BCTheme.amber : (user.roleType == .conadis ? BCTheme.cyanAccent : BCTheme.emerald)
                HStack(spacing: 6) {
                    Image(systemName: user.roleType.iconName)
                        .font(.caption)
                    Text(user.roleType.badgeLabel)
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("Saldo: \(user.pointsBalance) pts")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundColor(.white.opacity(0.75))
                }
                .foregroundColor(tint)
            }

            Divider().background(Color.white.opacity(0.12))

            // Selector de acompañantes
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Acompañantes")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text("Máx. 4 · +15 pts c/u (tarifa general)")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.55))
                }
                Spacer()
                HStack(spacing: 12) {
                    stepperButton(icon: "minus", enabled: companionsCount > 0, filled: false) {
                        companionsCount -= 1
                    }
                    Text("\(companionsCount)")
                        .font(.headline.monospacedDigit())
                        .foregroundColor(.white)
                        .frame(minWidth: 18)
                    stepperButton(icon: "plus", enabled: companionsCount < 4, filled: true) {
                        companionsCount += 1
                    }
                }
            }

            // Total
            HStack {
                Text(companionsCount == 0 ? "Total · 1 pasajero" : "Total · Titular + \(companionsCount) acomp.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.65))
                Spacer()
                Text("\(totalPointsToPay) pts")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundColor(BCTheme.emerald)
                Text(String(format: "S/. %.2f", totalPenToPay))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }

            // Subir imagen con QR (Como Yape)
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                HStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.subheadline)
                    Text("Subir una imagen con QR")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Simulación de lectura (mientras no haya validadores físicos instalados)
            Button {
                processPayment(busUnit: "BUS 01", busPlate: "Z1A-780", lineNumber: "14")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Simular lectura en puerta (\(totalPointsToPay) pts)")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(BCTheme.emerald)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var cameraDeniedBackground: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.fill")
                .font(.system(size: 34))
                .foregroundColor(.white.opacity(0.5))
            Text("Permiso de cámara desactivado")
                .font(.headline)
                .foregroundColor(.white)
            Text("Actívalo en Ajustes para escanear el QR del bus, o sube una imagen con el código.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(BCTheme.cyanAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 260)
        .background(BCTheme.background.ignoresSafeArea())
    }

    // MARK: - Componentes auxiliares
    private func circleGlassButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            BCFeedbackManager.shared.impactLight()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 40, height: 40)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
    }

    private func stepperButton(icon: String, enabled: Bool, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            guard enabled else { return }
            BCFeedbackManager.shared.impactLight()
            action()
        } label: {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundColor(filled ? .black : .white)
                .frame(width: 32, height: 32)
                .background(filled ? (enabled ? BCTheme.emerald : Color.gray) : Color.white.opacity(0.12))
                .clipShape(Circle())
        }
        .disabled(!enabled)
    }

    // MARK: - Lógica de validación del QR
    /// Formato esperado del validador: "BC-BUS|<unidad>|<placa>|<ruta>" (Ej: BC-BUS|BUS 01|Z1A-780|14)
    private func handleScannedPayload(_ payload: String) {
        let parts = payload.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3, parts[0] == "BC-BUS" else {
            showToast("QR no reconocido como validador Bus Conectado", success: false)
            BCFeedbackManager.shared.notificationError()
            return
        }
        let line = parts.count >= 4 ? parts[3] : "14"
        processPayment(busUnit: parts[1], busPlate: parts[2], lineNumber: line)
    }

    private func processPayment(busUnit: String, busPlate: String, lineNumber: String) {
        let ok = viewModel.payPassageWithQr(
            companionsCount: companionsCount,
            busUnit: busUnit,
            busPlate: busPlate,
            lineNumber: lineNumber
        )
        if ok {
            companionsCount = 0
            showToast("¡Pasaje validado! Buen viaje en la Ruta \(lineNumber)", success: true)
            // Tras un pago exitoso no se necesita la cámara: se libera por privacidad
            camera.stop()
        }
    }

    private func decodeQrFromPhoto(_ item: PhotosPickerItem) {
        Task {
            defer { photoPickerItem = nil }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let ciImage = CIImage(data: data) else {
                showToast("No se pudo leer la imagen", success: false)
                return
            }
            let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
            let message = (detector?.features(in: ciImage).first as? CIQRCodeFeature)?.messageString
            if let message {
                handleScannedPayload(message)
            } else {
                showToast("La imagen no contiene un código QR", success: false)
            }
        }
    }

    private func showToast(_ message: String, success: Bool) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toastMessage = message
            toastIsSuccess = success
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation { toastMessage = nil }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BCTheme.background.ignoresSafeArea())
    }
}

// MARK: - Esquinas del visor (estilo Yape)
struct ScannerCornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let len: CGFloat = 34
        let r: CGFloat = 22
        var p = Path()
        // Superior izquierda
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))
        // Superior derecha
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))
        // Inferior derecha
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))
        // Inferior izquierda
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))
        return p
    }
}

// MARK: - Controlador de Cámara con Ciclo de Vida Seguro
/// - La sesión solo se configura y arranca bajo demanda (nunca en segundo plano).
/// - `stop()` apaga linterna y detiene la captura; el indicador verde de iOS desaparece.
/// - Los fotogramas no se graban ni se envían: solo se procesa el texto del QR en el dispositivo.
final class QRCameraController: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    let session = AVCaptureSession()
    @Published var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isRunning: Bool = false
    @Published var torchOn: Bool = false

    var onCodeScanned: ((String) -> Void)?

    private let sessionQueue = DispatchQueue(label: "pe.edu.unjbg.busconectado.camera")
    private var isConfigured = false
    private var wantsRunning = false
    private var lastScanDate = Date.distantPast
    private var videoDevice: AVCaptureDevice?

    func start() {
        wantsRunning = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .authorized
            startSessionOnQueue()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permission = granted ? .authorized : .denied
                    if granted && self.wantsRunning {
                        self.startSessionOnQueue()
                    }
                }
            }
        default:
            permission = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func stop() {
        wantsRunning = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.setTorch(false)
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.isRunning = false
                self.torchOn = false
            }
        }
    }

    func toggleTorch() {
        let target = !torchOn
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let applied = self.setTorch(target)
            DispatchQueue.main.async { self.torchOn = applied && target }
        }
    }

    private func startSessionOnQueue() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured { self.configureSession() }
            // Verificar de nuevo: el usuario pudo salir mientras se configuraba
            guard self.wantsRunning, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        videoDevice = device

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }
        isConfigured = true
    }

    @discardableResult
    private func setTorch(_ on: Bool) -> Bool {
        guard let device = videoDevice, device.hasTorch else { return false }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard wantsRunning,
              let code = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first?.stringValue,
              Date().timeIntervalSince(lastScanDate) > 2.5 else { return }
        lastScanDate = Date()
        onCodeScanned?(code)
    }
}

// MARK: - Vista previa de cámara (capa nativa AVCaptureVideoPreviewLayer)
struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
