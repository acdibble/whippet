import CryptoKit
import Foundation
import Security

/// What a person sends as feedback, sealed as one piece so none of it is readable in the public database.
struct FeedbackContent: Codable, Hashable {
    let message: String
    let email: String
    let details: String
}

/// Seals feedback to the admin's public key with HPKE, so reading it needs the admin's private key and not only the
/// public database's security roles, which a schema deploy could get wrong.
enum SealedFeedback {
    private static let ciphersuite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly
    private static let info = Data("Whippet feedback v1".utf8)

    static func seal(
        _ content: FeedbackContent,
        to publicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> (encapsulatedKey: Data, ciphertext: Data) {
        var sender = try HPKE.Sender(recipientKey: publicKey, ciphersuite: ciphersuite, info: info)
        let ciphertext = try sender.seal(try JSONEncoder().encode(content))
        return (sender.encapsulatedKey, ciphertext)
    }

    static func open(
        encapsulatedKey: Data,
        ciphertext: Data,
        with privateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> FeedbackContent {
        var recipient = try HPKE.Recipient(
            privateKey: privateKey,
            ciphersuite: ciphersuite,
            info: info,
            encapsulatedKey: encapsulatedKey
        )
        return try JSONDecoder().decode(FeedbackContent.self, from: try recipient.open(ciphertext))
    }
}

/// The admin's feedback key. The public half is built into the app as `WhippetFeedbackPublicKey`; the private half is
/// kept only in the admin's iCloud Keychain, in a group Whippet and Whippet Dev share.
enum FeedbackKey {
    private static let accessGroup = "5G59X57VMZ.codes.dibble.whippet.shared"
    private static let service = "codes.dibble.whippet.feedback-key"

    /// Nil until a key is created and its public half is put in `project.yml`, and in builds made by others.
    static var publicKey: Curve25519.KeyAgreement.PublicKey? {
        guard
            let base64 = Bundle.main.object(forInfoDictionaryKey: "WhippetFeedbackPublicKey") as? String,
            let data = Data(base64Encoded: base64)
        else { return nil }
        return try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: data)
    }

    /// The private key in this Mac's keychain, if it matches the public key built into the app.
    static var matchingPrivateKey: Curve25519.KeyAgreement.PrivateKey? {
        guard let privateKey = storedPrivateKey, let publicKey else { return nil }
        return privateKey.publicKey.rawRepresentation == publicKey.rawRepresentation ? privateKey : nil
    }

    static var storedPrivateKey: Curve25519.KeyAgreement.PrivateKey? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    /// Creates a new key pair, replacing any stored private key, and returns it.
    static func create() throws -> Curve25519.KeyAgreement.PrivateKey {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        try store(privateKey)
        return privateKey
    }

    /// Stores a private key, such as one restored from a backup.
    static func store(_ privateKey: Curve25519.KeyAgreement.PrivateKey) throws {
        SecItemDelete(baseQuery as CFDictionary)
        var item = baseQuery
        item[kSecValueData] = privateKey.rawRepresentation
        item[kSecAttrLabel] = "Whippet feedback key"
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// Synced with iCloud Keychain, so every Mac of the admin's can read feedback.
    private static var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccessGroup: accessGroup,
            kSecAttrSynchronizable: true,
            kSecUseDataProtectionKeychain: true,
        ]
    }
}
