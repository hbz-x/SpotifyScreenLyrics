import Foundation

enum AppSettings {
    static let backgroundOpacityKey = "lyricsBackgroundOpacity"
    static let adaptiveLyricContrastEnabledKey = "adaptiveLyricContrastEnabled"
    static let defaultBackgroundOpacity: Double = 0.72

    static var backgroundOpacity: Double {
        get {
            guard UserDefaults.standard.object(forKey: backgroundOpacityKey) != nil else {
                return defaultBackgroundOpacity
            }
            return UserDefaults.standard.double(forKey: backgroundOpacityKey)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0), 1), forKey: backgroundOpacityKey)
        }
    }

    static var adaptiveLyricContrastEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: adaptiveLyricContrastEnabledKey) != nil else {
                return false
            }
            return UserDefaults.standard.bool(forKey: adaptiveLyricContrastEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: adaptiveLyricContrastEnabledKey)
        }
    }
}
