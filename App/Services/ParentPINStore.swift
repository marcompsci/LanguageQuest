import Foundation
import Security
import LocalAuthentication
import LQCore

/// Stores the parent PIN's salted hash in the Keychain (this device only).
enum ParentPINStore {
    private static let service = "com.phoronomics.languagequest.parentpin"
    private static let account = "parent"
    /// UI tests use memory so runs never leave a PIN behind.
    private static var memory: ParentPINRecord?

    static func load() -> ParentPINRecord? {
        if AppModel.isUITesting { return memory }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account, kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(ParentPINRecord.self, from: data)
    }

    @discardableResult
    static func save(pin: String) -> Bool {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let record = ParentPIN.makeRecord(pin: pin, salt: bytes.map { String(format: "%02x", $0) }.joined())
        if AppModel.isUITesting { memory = record; return true }
        guard let data = try? JSONEncoder().encode(record) else { return false }
        delete()
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecValueData as String: data,
                                  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete() {
        if AppModel.isUITesting { memory = nil; return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
    }

    /// "Forgot PIN": the device owner's passcode or Face ID / Touch ID resets it.
    static func resetWithDeviceOwner() async -> Bool {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { return false }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Reset the Language Quest parent PIN")
            if ok { delete() }
            return ok
        } catch {
            return false
        }
    }
}
