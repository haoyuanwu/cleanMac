import Foundation
import Security

@objc(CleanMacMemoryHelperProtocol)
nonisolated protocol MemoryHelperProtocol {
    func ping(reply: @escaping () -> Void)
    func purgeCaches(reply: @escaping (String?) -> Void)
}

nonisolated enum MemoryHelperIdentity {
    static let service = "com.cleanMac.cache.cleanMac.memory-helper"
    static let client = "com.cleanMac.cache.cleanMac"
    static let plist = service + ".plist"

    static func signature(at url: URL? = nil) -> (team: String, debuggable: Bool)? {
        var code: SecStaticCode?
        let path = url ?? Bundle.main.executableURL
        guard let path, SecStaticCodeCreateWithPath(path as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), nil) == errSecSuccess else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty, team.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return (team, entitlements?["com.apple.security.get-task-allow"] as? Bool == true)
    }
    static func requirement(identifier: String, team: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and ! (entitlement[\"com.apple.security.get-task-allow\"] exists) and ! (entitlement[\"com.apple.security.cs.disable-library-validation\"] exists) and ! (entitlement[\"com.apple.security.cs.allow-dyld-environment-variables\"] exists)"
    }
}
