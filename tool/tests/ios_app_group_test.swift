import Foundation

@main
enum AppGroupLocationTests {
  static func main() throws {
    let original = URL(fileURLWithPath: "/groups/original")
    let remapped = URL(fileURLWithPath: "/groups/remapped")
    let candidates = ["group.example.3", "group.example.1", "group.example.2"]
    for bundle in ["com.follow.clash", "com.follow.clash.NECore", "com.follow.clash.Widget"] {
      let standard = AppGroupLocation.resolve(bundleIdentifier: bundle, profileGroups: candidates) {
        $0 == "group.com.follow.clash" ? original : remapped
      }
      precondition(standard == original)
      let signed = AppGroupLocation.resolve(bundleIdentifier: bundle, profileGroups: candidates) {
        $0 == "group.example.1" ? remapped : nil
      }
      precondition(signed?.path == "/groups/remapped/FlClash-com.follow.clash")
      let reordered = AppGroupLocation.resolve(bundleIdentifier: bundle, profileGroups: candidates.reversed()) {
        $0 == "group.com.follow.clash" ? nil : remapped
      }
      precondition(reordered == signed)
    }
    precondition(AppGroupLocation.resolve(bundleIdentifier: "com.follow.clash", profileGroups: candidates) { _ in nil } == nil)
    let entitlements = ["Entitlements": ["com.apple.security.application-groups": candidates]]
    let xml = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)
    let cms = Data([0x30, 0x82, 0x01]) + xml + Data([0, 1, 2])
    precondition(AppGroupLocation.groups(in: cms) == candidates)
    precondition(AppGroupLocation.groups(in: Data("invalid".utf8)).isEmpty)
    print("Passed app, VPN and widget group remapping, OS denial, and profile parsing checks")
  }
}
