import SwiftUI

/// Optionen für Verbund Größe, Verbund Farbe und Pipes Farbe; Farb-Mapping mit klaren RGB-Tönen.
enum ProjectOptions {
    static let verbundGroessen = ["22x7", "8x7", "12x7"]

    static let verbundFarben = [
        "Orange",
        "Orange - Schwarz",
        "Orange - Rot",
        "Orange - Weiß"
    ]

    /// RGB-Farben für kräftige, gut erkennbare Darstellung (nicht zu dunkel).
    private static let rgbOrange = Color(red: 1, green: 0.5, blue: 0)
    private static let rgbSchwarz = Color(red: 0.15, green: 0.15, blue: 0.15)
    private static let rgbRot = Color(red: 1, green: 0.2, blue: 0.2)
    private static let rgbWeiß = Color(red: 0.98, green: 0.98, blue: 0.98)
    private static let rgbGrün = Color(red: 0.2, green: 0.8, blue: 0.2)
    private static let rgbBlau = Color(red: 0.2, green: 0.4, blue: 1)
    private static let rgbGelb = Color(red: 1, green: 0.85, blue: 0.2)
    private static let rgbGrau = Color(red: 0.55, green: 0.55, blue: 0.55)
    private static let rgbBraun = Color(red: 0.6, green: 0.35, blue: 0.15)
    private static let rgbViolett = Color(red: 0.6, green: 0.2, blue: 0.8)
    private static let rgbTürkis = Color(red: 0.2, green: 0.8, blue: 0.8)
    private static let rgbRosa = Color(red: 1, green: 0.5, blue: 0.7)

    /// Für Verbund: liefert (Farbe 1, Farbe 2). Bei nur "Orange" beide Kästchen orange.
    static func verbundColors(for option: String?) -> (Color, Color)? {
        guard let o = option, !o.isEmpty else { return nil }
        switch o {
        case "Orange": return (rgbOrange, rgbOrange)
        case "Orange - Schwarz": return (rgbOrange, rgbSchwarz)
        case "Orange - Rot": return (rgbOrange, rgbRot)
        case "Orange - Weiß": return (rgbOrange, rgbWeiß)
        default: return nil
        }
    }

    static let pipesFarben = [
        "rot", "grün", "blau", "gelb", "weiß", "grau", "braun", "violett",
        "türkis", "schwarz", "orange", "rosa"
    ]

    static func pipesColor(for name: String?) -> Color? {
        guard let n = name?.lowercased(), !n.isEmpty else { return nil }
        switch n {
        case "rot": return rgbRot
        case "grün": return rgbGrün
        case "blau": return rgbBlau
        case "gelb": return rgbGelb
        case "weiß": return rgbWeiß
        case "grau": return rgbGrau
        case "braun": return rgbBraun
        case "violett": return rgbViolett
        case "türkis": return rgbTürkis
        case "schwarz": return rgbSchwarz
        case "orange": return rgbOrange
        case "rosa": return rgbRosa
        default: return nil
        }
    }
}
