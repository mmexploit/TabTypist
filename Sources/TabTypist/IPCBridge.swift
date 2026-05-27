import Foundation

// ── Wire types ────────────────────────────────────────────────────────────────

struct RpcMessage: Codable {
    var id: UInt64?
    var method: String?
    var params: AnyCodable?
    var result: AnyCodable?
    var error: RpcError?
}

struct RpcError: Codable {
    var code: Int
    var message: String
}

// ── AnyCodable helper ─────────────────────────────────────────────────────────

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(Bool.self)   { value = v }
        else if let v = try? container.decode(Int.self)    { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) {
            value = v.map(\.value)
        } else if let v = try? container.decode([String: AnyCodable].self) {
            value = v.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Bool:   try container.encode(v)
        case let v as Int:    try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as [Any]:  try container.encode(v.map { AnyCodable($0) })
        case let v as [String: Any]:
            try container.encode(v.mapValues { AnyCodable($0) })
        default: try container.encodeNil()
        }
    }
}

// ── IPCBridge ─────────────────────────────────────────────────────────────────
//
// In STANDALONE mode (used in development when the Rust binary spawns us as a
// child): reads from our stdin, writes to our stdout.
//
// In APP mode (default, when the Swift app spawns the Rust core as a child):
// reads from the core's stdout pipe, writes to the core's stdin pipe.
// The AppDelegate wires this up via `configure(readHandle:writeHandle:)`.

final class IPCBridge: @unchecked Sendable {
    static let shared = IPCBridge()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let writeLock = NSLock()

    /// Called on every inbound message (dispatched on a background thread).
    var onMessage: ((RpcMessage) -> Void)?

    private var writeHandle: FileHandle?
    private var readHandle: FileHandle?

    /// Configure for app-bundle mode: Rust core is a subprocess.
    func configure(readHandle: FileHandle, writeHandle: FileHandle) {
        self.readHandle = readHandle
        self.writeHandle = writeHandle
    }

    /// Start reading.  Must be called after `configure` (if using app mode)
    /// or before spawning any threads (if using standalone mode).
    func start() {
        if let rh = readHandle {
            // App mode: read from the core subprocess's stdout pipe
            rh.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self?.processData(data)
            }
        } else {
            // Standalone mode: read from our own stdin
            Thread {
                while true {
                    guard let line = readLine(strippingNewline: true), !line.isEmpty else { continue }
                    guard let data = line.data(using: .utf8),
                          let msg = try? self.decoder.decode(RpcMessage.self, from: data)
                    else {
                        fputs("TabTypistSidecar: malformed RPC: \(line)\n", stderr)
                        continue
                    }
                    self.onMessage?(msg)
                }
            }.start()
        }
    }

    private func processData(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let msg = try? decoder.decode(RpcMessage.self, from: lineData)
            else { continue }
            onMessage?(msg)
        }
    }

    func send(_ msg: RpcMessage) {
        guard let data = try? encoder.encode(msg),
              var line = String(data: data, encoding: .utf8)
        else { return }
        line += "\n"
        writeLock.lock()
        defer { writeLock.unlock() }
        if let wh = writeHandle {
            wh.write(line.data(using: .utf8)!)
        } else {
            // Standalone mode: write to our stdout (parent reads it)
            print(line, terminator: "")
            fflush(stdout)
        }
    }

    func respond(id: UInt64, result: Any) {
        send(RpcMessage(
            id: id, method: nil, params: nil,
            result: AnyCodable(result), error: nil
        ))
    }

    func notify(method: String, params: [String: Any] = [:]) {
        send(RpcMessage(
            id: nil, method: method,
            params: AnyCodable(params),
            result: nil, error: nil
        ))
    }
}
