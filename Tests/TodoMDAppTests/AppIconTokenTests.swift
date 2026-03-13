import Testing
@testable import TodoMDApp

struct AppIconTokenTests {
    @Test("SF Symbols with digits stay symbol-backed")
    func sfSymbolsWithDigitsAreNotTreatedAsEmoji() {
        let browseToken = AppIconToken("square.grid.2x2", fallbackSymbol: "list.bullet")
        let delegatedToken = AppIconToken("person.2", fallbackSymbol: "list.bullet")
        let badgeToken = AppIconToken("calendar.badge.clock", fallbackSymbol: "list.bullet")

        #expect(browseToken.isEmoji == false)
        #expect(browseToken.symbolName == "square.grid.2x2")
        #expect(delegatedToken.isEmoji == false)
        #expect(delegatedToken.symbolName == "person.2")
        #expect(badgeToken.isEmoji == false)
        #expect(badgeToken.symbolName == "calendar.badge.clock")
    }

    @Test("Actual emoji values still stay emoji-backed")
    func emojiValuesStayEmojiBacked() {
        let emojiToken = AppIconToken("🔥", fallbackSymbol: "list.bullet")
        let keycapToken = AppIconToken("2️⃣", fallbackSymbol: "list.bullet")

        #expect(emojiToken.isEmoji)
        #expect(emojiToken.storageValue == "🔥")
        #expect(keycapToken.isEmoji)
        #expect(keycapToken.storageValue == "2️⃣")
    }
}
