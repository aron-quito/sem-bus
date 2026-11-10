import SwiftUI
import UIKit
import AVFoundation

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
