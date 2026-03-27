# Krisenvorsorge (iOS / SwiftUI) – Projektkern

Dieses Ordner enthält den **Code-Kern (SwiftUI + Offline-first Datenmodelle)** für das Projekt „Krisenvorsorge“.

## So startest du in Xcode
1. Öffne Xcode.
2. `File` → `New` → `Project...` → `App`.
3. `Interface: SwiftUI`, `Language: Swift`.
4. Product Name: `Krisenvorsorge`
5. Ziel: iOS App.
6. Kopiere/übernimm die Dateien aus diesem Ordner:
   - `Core/Models/DomainModels.swift`
   - `Core/Storage/AppDataStore.swift`
   - `Core/Localization/Localization.swift`
   - `App/KrisenvorsorgeApp.swift`
   - `App/RootTabView.swift`
   - `App/AppViewModel.swift`
   - `Features/EmergencyPlan/EmergencyPlanFeature.swift`
   - `Features/Inventory/InventoryFeature.swift`
   - `Features/Handbook/HandbookFeature.swift`
   - `Features/Shop/ShopFeature.swift`
   - `Features/Meetups/MeetupsFeature.swift`

## Offline-first
Die Daten werden als JSON in `Documents/krisenvorsorge-appdata.json` gespeichert (kein Cloud-Zwang).

## Mehrsprachigkeit / RTL
MVP: Übersetzungen sind in `Core/Localization/Localization.swift` hinterlegt.
Arabisch schaltet RTL automatisch über `layoutDirection`.

> Hinweis: Das ist bewusst ein „Kernsystem“ für schnelle Iteration. Als nächstes bauen wir:
> - vollständige Inventory/Shop Abgleiche
> - echte Shop-Integration (Affiliate/Links)
> - zusätzliche Screens (Profil, Treffpunkte-Plan, Entscheidungshilfe)

