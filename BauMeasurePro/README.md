# BauMeasurePro

iOS-App für Baumessungen mit Foto, GPS, Adresse und AR.

## Funktionen

- **Foto aufnehmen** (PhotosPicker)
- **GPS-Koordinaten** und **Adresse + Hausnummer** (LocationService, Reverse Geocoding)
- **Messpunkte im Foto setzen** (PhotoMeasureView)
- **Fotos auf der Karte** anzeigen (MapView mit Annotationen)
- **AR-Distanzmessung** (ARKit / RealityKit)
- **PDF-Messberichte** (PDFService)
- **Speicherung** der Messungen (StorageService, UserDefaults + Bilder im Documents-Ordner)

## Projektstruktur

```
BauMeasurePro/
├── App/
│   ├── BauMeasureProApp.swift
│   └── ContentView.swift
├── Models/
│   ├── Measurement.swift
│   ├── PhotoPoint.swift
│   └── Project.swift
├── ViewModels/
│   ├── MapViewModel.swift
│   ├── MeasurementViewModel.swift
│   └── CameraViewModel.swift
├── Services/
│   ├── LocationService.swift
│   ├── CameraService.swift
│   ├── StorageService.swift
│   └── PDFService.swift
├── Views/
│   ├── Map/
│   │   └── MapView.swift
│   ├── Camera/
│   │   └── CameraView.swift
│   ├── Measurement/
│   │   ├── ARMeasureView.swift
│   │   └── PhotoMeasureView.swift
│   └── Detail/
│       └── MeasurementDetailView.swift
└── Resources/
    ├── Info.plist
    └── Assets.xcassets
```

## Öffnen

- **Xcode:** `BauMeasurePro.xcworkspace` öffnen (oder `BauMeasurePro.xcodeproj`).
- **Voraussetzungen:** Xcode 15+, iOS 17+, Gerät mit Standort/Kamera für volle Funktion.

## Ablauf

1. Karte mit gespeicherten Messungen anzeigen.
2. **+** tippen → Foto auswählen → Standort/Adresse wird ermittelt → Messpunkte im Bild setzen → **Speichern**.
3. Messung auf der Karte tippen → Detailansicht mit Bild, Adresse, Länge, Punkte, Datum.
