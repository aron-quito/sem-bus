import SwiftUI
import UIKit
import AVFoundation
import Speech

// MARK: - Apple HIG Minimalist Dark Theme Tokens
enum BCTheme {
    static let background = Color(red: 9/255, green: 13/255, blue: 22/255)       // #090D16
    static let elevatedSurface = Color(red: 15/255, green: 23/255, blue: 42/255) // #0F172A
    static let cardSurface = Color.white.opacity(0.05)
    static let hairlineBorder = Color.white.opacity(0.09)

    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)       // #10B981
    static let royalBlue = Color(red: 37/255, green: 99/255, blue: 235/255)      // #2563EB
    static let cyanAccent = Color(red: 6/255, green: 182/255, blue: 212/255)     // #06B6D4
    static let amber = Color(red: 245/255, green: 158/255, blue: 11/255)         // #F59E0B
    static let yapePurple = Color(red: 116/255, green: 35/255, blue: 132/255)    // #742384
    static let destructiveRed = Color(red: 239/255, green: 68/255, blue: 68/255) // #EF4444
}

extension Color {
    static let emerald = BCTheme.emerald
    static let amber = BCTheme.amber

    init(hex: String) {
        let hexSanitized = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hexSanitized.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 15, 23, 42)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}

// MARK: - Haptic & Acoustic Feedback Engine (APP_PASAJERO.md Specs)
@MainActor
final class BCFeedbackManager {
    static let shared = BCFeedbackManager()
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private init() {}

    func impactLight() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }

    func impactMedium() {
        let gen = UIImpactFeedbackGenerator(style: .medium)
        gen.impactOccurred()
    }

    func notificationSuccess() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    func notificationError() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.error)
    }

    /// Emite el tono acústico de validación de pasaje QR (880Hz) o sonido de recarga
    func playValidationTone() {
        notificationSuccess()
        AudioServicesPlaySystemSound(1057) // Tono limpio nativo de confirmación iOS
    }

    func playRechargeChime() {
        notificationSuccess()
        AudioServicesPlaySystemSound(1054)
    }
}

// MARK: - Marcador Puntual de Paradero (Solo punto + ícono de paradero, sin texto sobre el mapa)
struct TransitStopDotMarker: View {
    let accentColor: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(0.28))
                .frame(width: 34, height: 34)
            Circle()
                .fill(accentColor)
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.42), radius: 3, y: 1)
            Image(systemName: "bus.fill")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Degradado Translúcido Superior para Barra de Estado (Dynamic Island / Hora / Señal)
struct TopMapStatusBarFade: View {
    var height: CGFloat = 112

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(height: height)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.95), location: 0.0),
                        .init(color: .black.opacity(0.68), location: 0.48),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}

// MARK: - Motor Nativo de Búsqueda por Voz (Micrófono + Speech Framework)
@MainActor
final class SpeechSearchEngine: ObservableObject {
    static let shared = SpeechSearchEngine()

    @Published var isListening: Bool = false
    @Published var liveTranscript: String = ""
    @Published var errorMessage: String? = nil

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var speechRecognizer: SFSpeechRecognizer?
    private var onTranscriptUpdate: ((String) -> Void)?
    private var silenceTimer: Timer?

    private init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-PE"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "es-419"))
            ?? SFSpeechRecognizer(locale: .current)
    }

    func toggleListening(onTranscript: @escaping (String) -> Void) {
        if isListening {
            stopListening()
        } else {
            startListening(onTranscript: onTranscript)
        }
    }

    func startListening(onTranscript: @escaping (String) -> Void) {
        stopListening()
        errorMessage = nil
        liveTranscript = ""
        onTranscriptUpdate = onTranscript

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            Task { @MainActor in
                guard let self = self else { return }
                guard authStatus == .authorized else {
                    self.errorMessage = "Activa el permiso de Reconocimiento de Voz en Ajustes."
                    return
                }
                let micGranted = await AVAudioApplication.requestRecordPermission()
                guard micGranted else {
                    self.errorMessage = "Activa el permiso del Micrófono en Ajustes."
                    return
                }
                self.beginAudioCapture()
            }
        }
    }

    private func beginAudioCapture() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            errorMessage = "Reconocimiento de voz no disponible en este momento."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "No se pudo iniciar el micrófono."
            return
        }

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = false
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            errorMessage = "No se pudo capturar audio."
            return
        }

        self.audioEngine = engine
        self.recognitionRequest = request
        self.isListening = true
        BCFeedbackManager.shared.impactMedium()
        scheduleAutoStop(after: 6.5)

        self.recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self = self else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.liveTranscript = text
                        self.onTranscriptUpdate?(text)
                        self.scheduleAutoStop(after: 1.9)
                    }
                    if result.isFinal {
                        self.stopListening()
                    }
                } else if error != nil {
                    self.stopListening()
                }
            }
        }
    }

    private func scheduleAutoStop(after seconds: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopListening()
            }
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        if let engine = audioEngine {
            if engine.isRunning {
                engine.stop()
            }
            engine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        if isListening {
            isListening = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

