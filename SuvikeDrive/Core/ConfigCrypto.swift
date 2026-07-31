//
//  ConfigCrypto.swift
//  SuvikeDrive
//
//  功能: 配置加密/解密工具（AES-256-GCM）
//  位置: Core/
//

import Foundation
import CryptoKit
import CommonCrypto
import Security

// MARK: - 配置加密工具
class ConfigCrypto {
    private static let saltSize = 32
    private static let nonceSize = 12
    private static let tagSize = 16
    
    // MARK: - AES-256-GCM 加密/解密
    
    /// AES-256-GCM 加密配置数据
    static func encrypt(data: Data, password: String) -> Data? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        
        var salt = Data(count: saltSize)
        let saltResult = salt.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, saltSize, bytes.baseAddress!)
        }
        guard saltResult == errSecSuccess else { return nil }
        
        guard let key = deriveKey(password: passwordData, salt: salt) else { return nil }
        
        var nonceData = Data(count: nonceSize)
        let nonceResult = nonceData.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, nonceSize, bytes.baseAddress!)
        }
        guard nonceResult == errSecSuccess else { return nil }
        
        _ = nonceData
        
        do {
            let sealedBox = try AES.GCM.seal(
                data,
                using: SymmetricKey(data: key),
                nonce: try AES.GCM.Nonce(data: nonceData)
            )
            guard let combined = sealedBox.combined else { return nil }
            
            var result = Data()
            result.append(salt)
            result.append(nonceData)
            result.append(combined)
            return result
        } catch {
            return nil
        }
    }
    
    /// AES-256-GCM 解密配置数据
    static func decrypt(data: Data, password: String) -> Data? {
        guard let passwordData = password.data(using: .utf8) else { return nil }
        
        guard data.count > saltSize + nonceSize + tagSize else { return nil }
        let salt = data[0..<saltSize]
        let nonceData = data[saltSize..<(saltSize + nonceSize)]
        let ciphertext = data[(saltSize + nonceSize)...]
        
        _ = nonceData
        
        guard let key = deriveKey(password: passwordData, salt: Data(salt)) else { return nil }
        
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
            let decrypted = try AES.GCM.open(sealedBox, using: SymmetricKey(data: key))
            return decrypted
        } catch {
            return nil
        }
    }
    
    private static func deriveKey(password: Data, salt: Data) -> Data? {
        let keyLength = 32
        var key = Data(count: keyLength)
        let result = key.withUnsafeMutableBytes { keyBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        100000,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        return result == 0 ? key : nil
    }
}

// MARK: - Keychain 加密存储
extension ConfigCrypto {
    private static let service = "com.suvikedrive.drive"
    
    /// 保存密码到 Keychain
    static func savePassword(_ password: String, forKey key: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        
        // 删除旧数据
        deletePassword(forKey: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// 从 Keychain 读取密码
    static func getPassword(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return password
    }
    
    /// 从 Keychain 删除密码
    static func deletePassword(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
    
    /// 更新 Keychain 密码
    static func updatePassword(_ password: String, forKey key: String) -> Bool {
        guard let data = password.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status == errSecItemNotFound {
            return savePassword(password, forKey: key)
        }
        
        return status == errSecSuccess
    }
}
