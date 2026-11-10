# Proyecto Móvil iOS — Bus Conectado (BC)
## Arquitectura Nativa SwiftUI (iOS 17.0+ / Xcode 15+)

> **Directorio:** `mobile-ios/`  
> **Estándar:** SWEBOK v4 / Clean Architecture + MVVM (Model-View-ViewModel)  
> **Dispositivo de Referencia:** iPhone 16 (Apple Viewport: 393 × 852 pt)

---

## 1. Estructura del Proyecto

```
mobile-ios/BusConectado/
├── App/
│   ├── BusConectadoApp.swift            # Entry Point @main con inyección de estado global
│   └── AppState.swift                   # Gestor de sesión (Auth / Guest / Onboarding)
├── Core/
│   ├── Network/
│   │   ├── APIEndpoint.swift            # Definición tipada de rutas base y endpoints
│   │   └── APIClient.swift              # URLSession con async/await, Bearer header y error handling
│   ├── Storage/
│   │   └── KeychainService.swift        # Almacenamiento seguro nativo (Keychain Services)
│   └── Models/
│       ├── User.swift                   # Entidades User, Role, FareType
│       └── Wallet.swift                 # Saldo de Puntos BC y transacciones
├── Features/
│   ├── Auth/                            # CU-00: Onboarding y Autenticación OTP
│   │   ├── ViewModels/AuthViewModel.swift
│   │   └── Views/OnboardingView.swift
│   ├── Explore/                         # CU-07: Mapa en tiempo real y paraderos
│   ├── QRScan/                          # CU-01: Escáner AVFoundation con feedback háptico
│   └── Wallet/                          # CU-05 / CU-08: Monedero e historial
└── LiveActivities/                      # ActivityKit: Dynamic Island para bus aproximándose
```

---

## 2. Requisitos y Dependencias

* **Xcode:** 15.0 o superior con Swift 5.10.
* **Target Mínimo:** iOS 17.0.
* **Frameworks Nativos:**
  - `SwiftUI`: Interfaz declarativa a 120 FPS.
  - `MapKit`: Mapas vectoriales de Tacna.
  - `AVFoundation`: Captura óptica de QR dinámico.
  - `ActivityKit`: Live Activities en Dynamic Island.
  - `Security`: Keychain para tokens JWT.

