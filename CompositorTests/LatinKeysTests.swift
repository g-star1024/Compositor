import AppKit
import Testing
@testable import Compositor

/// A layout that types no Latin letters still reaches the tool shortcuts, on the same physical keys the Latin
/// layout uses for them.
struct LatinKeysTests {
    @Test func nonLatinLayoutsReachTheShortcutsOnTheSameKeys() throws {
        func key(_ typed: String, code: UInt16) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, characters: typed,
                                          charactersIgnoringModifiers: typed, isARepeat: false, keyCode: code))
        }
        let latin = try #require(LatinKeys.character(for: 11, shift: false))
        // Keep throwing calls out of #expect: Swift Testing expands a lone rethrowing call
        // (e.g. allSatisfy(\.isASCII)) into __checkFunctionCall, whose closure cannot throw.
        let russian = try key("и", code: 11)
        let latinB = try key("b", code: 11)
        #expect(LatinKeys.event(russian).charactersIgnoringModifiers == latin)
        #expect(LatinKeys.event(latinB).charactersIgnoringModifiers == "b")
    }
}
