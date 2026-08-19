import Foundation

/// Best-effort wrapper for credentials — minimizes lifetime and wipes bytes on deinit.
struct SensitiveData {
    private var bytes: Data

    init(_ string: String) {
        bytes = Data(string.utf8)
    }

    init?(keychain key: KeychainStore.Key) {
        guard let value = KeychainStore.string(for: key), !value.isEmpty else { return nil }
        bytes = Data(value.utf8)
    }

    var isEmpty: Bool { bytes.isEmpty }

    func withUTF8<R>(_ body: (UnsafeBufferPointer<UInt8>) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes { raw in
            let bound = raw.bindMemory(to: UInt8.self)
            return try body(
                UnsafeBufferPointer(start: bound.baseAddress, count: bound.count)
            )
        }
    }

    func utf8String() -> String {
        String(data: bytes, encoding: .utf8) ?? ""
    }

    deinit {
        var mutable = bytes
        mutable.withUnsafeMutableBytes { raw in
            raw.resetBytes(in: 0..<raw.count)
        }
    }
}
