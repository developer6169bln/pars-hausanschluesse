import Foundation

enum Config {
    /// Backend-URL der Web-App (anpassen für Lokal/Produktion).
    static var apiBaseURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:3010")!
        #else
        return URL(string: "https://deine-domain.de")!
        #endif
    }
}
