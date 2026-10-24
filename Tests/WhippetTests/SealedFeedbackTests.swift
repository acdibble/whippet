import CryptoKit
import Foundation
import Testing

struct SealedFeedbackTests {
    private let content = FeedbackContent(message: "The calculator is great", email: "someone@example.com", details: "Whippet 0.6.0")

    @Test func theAdminKeyOpensSealedFeedback() throws {
        let adminKey = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try SealedFeedback.seal(content, to: adminKey.publicKey)

        let opened = try SealedFeedback.open(encapsulatedKey: sealed.encapsulatedKey, ciphertext: sealed.ciphertext, with: adminKey)
        #expect(opened == content)
    }

    @Test func theSealedFormRevealsNothing() throws {
        let sealed = try SealedFeedback.seal(content, to: Curve25519.KeyAgreement.PrivateKey().publicKey)
        let bytes = String(decoding: sealed.ciphertext + sealed.encapsulatedKey, as: UTF8.self)
        #expect(!bytes.contains("someone@example.com"))
        #expect(!bytes.contains("calculator"))
    }

    @Test func anotherKeyCantOpenIt() throws {
        let sealed = try SealedFeedback.seal(content, to: Curve25519.KeyAgreement.PrivateKey().publicKey)
        #expect(throws: (any Error).self) {
            try SealedFeedback.open(
                encapsulatedKey: sealed.encapsulatedKey,
                ciphertext: sealed.ciphertext,
                with: Curve25519.KeyAgreement.PrivateKey()
            )
        }
    }
}
