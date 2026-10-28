import Foundation

/// Gemeinsamer Ordner von App, Teilen-Erweiterung und Widget.
///
/// Die Kennung kommt aus dem Info.plist (`HirniAppGroup`, Build-Einstellung
/// `HIRNI_APP_GROUP` in Config/Signing.xcconfig): auf dem iPhone
/// `group.ch.hebera.hirni`, am Mac `<Team-ID>.ch.hebera.hirni`. Am Mac
/// braucht eine «group.»-Kennung eine Freigabe im Profil, die Xcode nicht
/// für alle Teile anlegt; die Team-Kennung funktioniert ohne.
public enum AppGroup {
    public static var identifier: String {
        Bundle.main.object(forInfoDictionaryKey: "HirniAppGroup") as? String ?? "group.ch.hebera.hirni"
    }

    public static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}
