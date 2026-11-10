import SwiftUI

@main
struct BusConectadoApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isLoggedIn || authViewModel.isGuestMode {
                    MainTabView(viewModel: authViewModel)
                } else {
                    OnboardingView(viewModel: authViewModel)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
