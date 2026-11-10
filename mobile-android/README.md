# Proyecto Móvil Android — Bus Conectado (BC)
## Arquitectura Nativa Kotlin + Jetpack Compose (Android 13+ / API 33+)

> **Directorio:** `mobile-android/`  
> **Estándar:** SWEBOK v4 / Clean Architecture + Android Architecture Components (MVI / MVVM)  
> **Dispositivos Objetivo:** Smartphones de pasajeros y Tablets de conductores de 10" (Landscape).

---

## 1. Estructura del Proyecto

```
mobile-android/app/src/main/java/pe/edu/unjbg/busconectado/
├── core/
│   ├── network/                         # OkHttp / Retrofit con interceptores JWT
│   │   ├── BCNetworkClient.kt
│   │   └── AuthInterceptor.kt
│   ├── security/                        # EncryptedSharedPreferences (Android Keystore)
│   │   └── EncryptedStorage.kt
│   └── model/                           # Data classes: User, Wallet, BusTelemetry
├── feature/
│   ├── auth/                            # CU-00: Onboarding y Validación OTP
│   │   ├── AuthViewModel.kt
│   │   └── ui/OnboardingScreen.kt
│   ├── map/                             # CU-07: Google Maps SDK en Compose
│   ├── qrscan/                          # CU-01: ML Kit Barcode Scanning + CameraX
│   └── driver/                          # CU-04: Tablet de Chofer (Landscape / Aforo)
└── ui/theme/                            # Material 3 Dark Theme (Slate-950 base)
```

---

## 2. Dependencias Principales

* **Kotlin:** 1.9.23+
* **Compose BOM:** 2024.04.00
* **Google Maps Compose:** 4.3.3
* **Google ML Kit:** `com.google.mlkit:barcode-scanning:17.2.0`
* **Retrofit / OkHttp:** 2.11.0 / 4.12.0
* **Security Crypto:** `androidx.security:security-crypto:1.1.0-alpha06`
