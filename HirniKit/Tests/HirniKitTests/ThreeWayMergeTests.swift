import Testing
@testable import HirniKit

struct ThreeWayMergeTests {
    let base = "Einkauf\n- Milch\n- Brot\n\nNotizen\nEnde\n"

    @Test func changesInDifferentLinesAreBothKept() {
        let mine = "Einkauf\n- Milch\n- Brot\n- Käse\n\nNotizen\nEnde\n"   // Zeile angefügt
        let theirs = "Einkauf\n- Milch\n- Brot\n\nNotizen von Claude\nEnde\n" // andere Zeile geändert
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)
            == "Einkauf\n- Milch\n- Brot\n- Käse\n\nNotizen von Claude\nEnde\n")
    }

    @Test func sameLineChangedDifferentlyIsAConflict() {
        let mine = base.replacingOccurrences(of: "- Brot", with: "- Zopf")
        let theirs = base.replacingOccurrences(of: "- Brot", with: "- Gipfeli")
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs) == nil)
    }

    @Test func identicalChangesAreTakenOnce() {
        let both = base.replacingOccurrences(of: "Ende", with: "Schluss")
        #expect(ThreeWayMerge.merge(base: base, mine: both, theirs: both) == both)
        let mine = both.replacingOccurrences(of: "Einkauf", with: "Einkaufen")
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: both) == mine)
    }

    @Test func insertionsAtBothEnds() {
        let mine = "Titel\n" + base
        let theirs = base + "Nachtrag\n"
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs) == "Titel\n" + base + "Nachtrag\n")
    }

    @Test func twoInsertionsAtSamePlaceConflict() {
        let mine = base.replacingOccurrences(of: "- Brot\n", with: "- Brot\n- Käse\n")
        let theirs = base.replacingOccurrences(of: "- Brot\n", with: "- Brot\n- Eier\n")
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs) == nil)
    }

    @Test func adjacentLinesMerge() {
        let mine = base.replacingOccurrences(of: "- Milch", with: "- Hafermilch")
        let theirs = base.replacingOccurrences(of: "- Brot", with: "- Ruchbrot")
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs)
            == "Einkauf\n- Hafermilch\n- Ruchbrot\n\nNotizen\nEnde\n")
    }

    @Test func deletionAndEditElsewhere() {
        let mine = base.replacingOccurrences(of: "- Milch\n", with: "")
        let theirs = base.replacingOccurrences(of: "Ende", with: "Fertig")
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: theirs) == "Einkauf\n- Brot\n\nNotizen\nFertig\n")
    }

    @Test func onlyOneSideChanged() {
        let mine = base + "x"
        #expect(ThreeWayMerge.merge(base: base, mine: mine, theirs: base) == mine)
        #expect(ThreeWayMerge.merge(base: base, mine: base, theirs: mine) == mine)
    }
}

struct ConflictCopyTests {
    @Test func copyGetsDeviceNameAndIsNotPinned() throws {
        let test = try TestVault()
        try test.write("", to: "Inbox/Einkauf.md")
        let note = test.vault.inboxURL.appending(path: "Einkauf.md")

        let copy = try test.vault.saveConflictCopy(text: "---\nangepinnt: true\n---\nAndere", of: note, deviceName: "iPhone von Raphael")
        #expect(copy.lastPathComponent == "Einkauf (iPhone von Raphael).md")
        #expect(try test.vault.readNote(at: copy) == "Andere")

        let unknown = try test.vault.saveConflictCopy(text: "x", of: note, deviceName: nil)
        #expect(unknown.lastPathComponent == "Einkauf (Konflikt).md")
    }

    @Test func noConflictsForOrdinaryFiles() throws {
        let test = try TestVault()
        try test.write("x", to: "Inbox/A.md")
        let note = test.vault.inboxURL.appending(path: "A.md")
        #expect(test.vault.conflictVersions(of: note).isEmpty)
        #expect(try test.vault.resolveConflict(at: note, choice: .keepCurrent).isEmpty)
    }
}
