import Foundation
import SFEngine
import Testing

/// The built framework on the Mac: it says which StockfishEmbedded it is, starts with the
/// net, finds a mate in one and searches at optimised speed. The engine tests need the net
/// (`build/StockfishEmbedded/Scripts/download-nnue.sh`, or `CALCOLA_NNUE`); without it
/// they're skipped.
@Suite(.serialized)
struct EngineTests {
    static let network: URL? = {
        if let path = ProcessInfo.processInfo.environment["CALCOLA_NNUE"] {
            return URL(fileURLWithPath: path)
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "build/StockfishEmbedded/Resources/NNUE/\(SFEngine.defaultNetworkFileName)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    @Test func saysWhichUpstreamItIs() throws {
        let info = try #require(Bundle(for: SFEngine.self).infoDictionary)
        #expect(info["CalcolaStockfishEmbeddedVersion"] as? String == "1.14.0")
        #expect((info["CalcolaStockfishEmbeddedCommit"] as? String)?.count == 40)
        #expect(SFEngine.defaultNetworkFileName == "nn-c9e480e92425.nnue")
    }

    @Test(.enabled(if: network != nil))
    func findsMateAndSearchesFast() async throws {
        let session = try await Session(network: #require(Self.network))
        defer { session.engine.stop() }

        // Back-rank mate: Rd8#.
        let mate = try await session.search(fen: "6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1", go: "go depth 8")
        #expect(mate.bestMove == "d1d8")
        #expect(mate.lines.contains { $0.contains(" score mate 1 ") })

        // Optimised, one thread searches about 570k nodes a second on an M3; an
        // unoptimised build about 20k. The bar leaves room for a busy or older Mac.
        let speed = try await session.search(
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", go: "go movetime 1000")
        let nps = speed.lines.compactMap { line -> Int? in
            let tokens = line.split(separator: " ")
            return tokens.firstIndex(of: "nps").flatMap { Int(tokens[$0 + 1]) }
        }.last ?? 0
        print("Calcola: \(nps) nodes/s on one thread")
        #expect(nps > 300_000)
    }
}

/// One engine, driven line by line.
private final class Session: Sendable {
    let engine: SFEngine
    private let lines: AsyncStream<String>

    init(network: URL) async throws {
        let (lines, output) = AsyncStream<String>.makeStream()
        self.lines = lines
        engine = SFEngine(networkFileURL: network) { output.yield($0) }
        engine.start()
        engine.sendCommand("uci")
        try await wait(for: "uciok")
        engine.sendCommand("isready")
        try await wait(for: "readyok")
    }

    struct Result {
        let lines: [String]
        let bestMove: String?
    }

    func search(fen: String, go: String) async throws -> Result {
        engine.sendCommand("position fen \(fen)")
        engine.sendCommand(go)
        var seen: [String] = []
        for await line in lines {
            if line.hasPrefix("info string StockfishEmbedded error") { throw EngineError(line: line) }
            if line.hasPrefix("bestmove ") {
                return Result(lines: seen, bestMove: line.split(separator: " ").dropFirst().first.map(String.init))
            }
            seen.append(line)
        }
        throw EngineError(line: "the engine stopped")
    }

    private func wait(for reply: String) async throws {
        for await line in lines {
            if line.hasPrefix("info string StockfishEmbedded error") { throw EngineError(line: line) }
            if line == reply { return }
        }
        throw EngineError(line: "the engine stopped")
    }
}

private struct EngineError: Error {
    let line: String
}

extension SFEngine: @retroactive @unchecked Sendable {}
