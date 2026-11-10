import Foundation

public enum AppGroupLocation {
  public static let directory: URL? = resolve(
    bundleIdentifier: Bundle.main.bundleIdentifier ?? "",
    profileGroups: provisioningGroups(in: Bundle.main.bundleURL),
    container: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
  )

  public static func resolve(
    bundleIdentifier: String,
    profileGroups: [String],
    container: (String) -> URL?
  ) -> URL? {
    var baseIdentifier = bundleIdentifier
    for suffix in [".NECore", ".Widget"] where baseIdentifier.hasSuffix(suffix) {
      baseIdentifier = String(baseIdentifier.dropLast(suffix.count))
      break
    }
    let expected = "group.\(baseIdentifier)"
    if let original = container(expected) {
      return original
    }
    // Re-signers can replace the requested group with one allowed by the profile.
    // The OS container lookup, not the unverified profile text, grants access.
    for identifier in Set(profileGroups).sorted() where identifier.hasPrefix("group.") {
      if let remapped = container(identifier) {
        return remapped.appendingPathComponent("FlClash-\(baseIdentifier)", isDirectory: true)
      }
    }
    return nil
  }

  public static func groups(in profile: Data) -> [String] {
    guard let start = profile.range(of: Data("<?xml".utf8)),
      let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex),
      let dictionary = try? PropertyListSerialization.propertyList(
        from: profile.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil
      ) as? [String: Any],
      let entitlements = dictionary["Entitlements"] as? [String: Any]
    else {
      return []
    }
    return entitlements["com.apple.security.application-groups"] as? [String] ?? []
  }

  private static func provisioningGroups(in bundleURL: URL) -> [String] {
    guard let data = try? Data(contentsOf: bundleURL.appendingPathComponent("embedded.mobileprovision")) else {
      return []
    }
    return groups(in: data)
  }
}
