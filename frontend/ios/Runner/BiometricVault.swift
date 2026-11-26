import Flutter
import LocalAuthentication
import Security
import UIKit

final class BiometricVault {
  private let service = "primitive_accumulation.ledger.biometric.v1"
  private var pending: LAContext?

  private var item: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: "personal-ledger"]
  }

  init() {
    NotificationCenter.default.addObserver(self, selector: #selector(backgrounded),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
  }

  @objc private func backgrounded() {
    pending?.invalidate()
    pending = nil
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let failure = FlutterError(code: "unavailable", message: nil, details: nil)
    switch call.method {
    case "available":
      result(LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil))
    case "enabled":
      // Keychain items may outlive an install. Opt-in belongs to this installation.
      result(UserDefaults.standard.bool(forKey: service))
    case "disable":
      let status = SecItemDelete(item as CFDictionary)
      guard status == errSecSuccess || status == errSecItemNotFound else {
        result(failure)
        return
      }
      UserDefaults.standard.removeObject(forKey: service)
      result(nil)
    case "enable", "unlock":
      let enable = call.method == "enable"
      guard pending == nil, enable || UserDefaults.standard.bool(forKey: service) else {
        result(failure)
        return
      }
      let context = LAContext()
      context.localizedFallbackTitle = ""
      pending = context
      let reason = enable ? "验证身份以开启本机账本的生物识别解锁" : "验证身份以解锁本机账本"
      context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, _ in
        DispatchQueue.main.async {
          defer { context.invalidate() }
          guard self.pending === context else {
            result(failure)
            return
          }
          self.pending = nil
          guard ok else {
            result(FlutterError(code: "authentication", message: nil, details: nil))
            return
          }
          var query = self.item
          query[kSecUseAuthenticationContext as String] = context
          if enable {
            guard let password = call.arguments as? String,
                  let access = SecAccessControlCreateWithFlags(nil,
                    kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil) else {
              result(failure)
              return
            }
            let status = SecItemDelete(self.item as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
              result(failure)
              return
            }
            query[kSecAttrAccessControl as String] = access
            query[kSecValueData as String] = Data(password.utf8)
            guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
              result(failure)
              return
            }
            UserDefaults.standard.set(true, forKey: self.service)
            result(nil)
          } else {
            query[kSecReturnData as String] = true
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            guard status == errSecSuccess, let bytes = value as? Data,
                  let password = String(data: bytes, encoding: .utf8) else {
              result(failure)
              return
            }
            result(password)
          }
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
