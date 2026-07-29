import XCTest
@testable import TimelineModel

/// Schránka osy a rámečkový výběr (fáze 17, modul 2).
///
/// Těžiště je na svázaných dvojicích: vložit kopii se stejnou vazbou je
/// nejsnazší způsob, jak vyrobit `brokenLink`, a stalo se to už jednou
/// (split páru, fáze 2).
final class ClipboardTests: XCTestCase {

    // MARK: Kopie klipu

    /// Kdo přidá na `Clip` pole, musí ho přidat do `copied` — a tenhle test
    /// mu to řekne, i když ho nikdo neupraví. Porovnává REFLEXÍ, ne
    /// vypsaným seznamem: seznam by zestárnul se stejnou chybou.
    func testCopiedCarriesEveryField() throws {
        var f = Fixture(seconds: 30)
        let id = try f.addClip(start: 0, duration: 100, sourceStartFrames: 30)
        try f.project.setColorGrade(clipID: id, ColorGrade(preset: .warmFilm, intensity: 0.7))
        let original = try XCTUnwrap(f.clip(id))

        let copy = original.copied(linkID: nil, timelineStart: Frames(500))
        XCTAssertNotEqual(copy.id, original.id, "kopie má vlastní ID")
        XCTAssertEqual(copy.timelineStart, Frames(500))
        XCTAssertNil(copy.linkID)

        // Všechno ostatní se musí přenést beze změny.
        let skipped: Set<String> = ["id", "linkID", "timelineStart"]
        let before = Dictionary(uniqueKeysWithValues: Mirror(reflecting: original).children.map {
            ($0.label ?? "?", String(describing: $0.value))
        })
        let after = Dictionary(uniqueKeysWithValues: Mirror(reflecting: copy).children.map {
            ($0.label ?? "?", String(describing: $0.value))
        })
        XCTAssertEqual(before.count, after.count)
        for (field, value) in before where !skipped.contains(field) {
            XCTAssertEqual(after[field], value, "pole \(field) se do kopie nepřeneslo")
        }
    }

    // MARK: Kopírování

    func testCopyKeepsRelativePositions() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 100, duration: 50)
        let b = try f.addClip(start: 200, duration: 50)

        let board = f.project.clipboard(copying: [a, b])
        XCTAssertEqual(board.count, 2)
        XCTAssertEqual(board.items.map(\.offset).sorted(by: { $0.count < $1.count }),
                       [Frames(0), Frames(100)], "offsety se počítají od nejlevější hrany")
        XCTAssertEqual(board.duration, Frames(150))
        XCTAssertEqual(f.project.timeline.tracks[0].clips.count, 2, "kopírování projekt nemění")
    }

    /// Dvojice se kopíruje CELÁ, i když uživatel vybral jen obraz — stejně
    /// jako se celá maže. Půlka záběru na ose je vždycky chyba, ne záměr.
    func testCopyPullsInLinkedTwin() throws {
        var f = Fixture(seconds: 30)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)

        let board = f.project.clipboard(copying: [video.id])
        XCTAssertEqual(board.count, 2, "zvukové dvojče jde s obrazem")
        XCTAssertEqual(Set(board.items.map(\.trackKind)), [.video, .audio])
    }

    func testCopyOfNothingIsEmpty() {
        let f = Fixture()
        XCTAssertTrue(f.project.clipboard(copying: []).isEmpty)
        XCTAssertTrue(f.project.clipboard(copying: [ClipID()]).isEmpty, "neznámé ID se přeskočí")
    }

    // MARK: Vkládání

    func testPasteLandsAtFrameAndKeepsGaps() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 0, duration: 50)
        let b = try f.addClip(start: 100, duration: 50)
        let board = f.project.clipboard(copying: [a, b])

        let inserted = try f.project.paste(board, at: Frames(1000))
        XCTAssertEqual(inserted.count, 2)
        let pasted = f.clips(on: f.v1).filter { inserted.contains($0.id) }
            .sorted { $0.timelineStart < $1.timelineStart }
        XCTAssertEqual(pasted.map(\.timelineStart), [Frames(1000), Frames(1100)],
                       "mezera 50 snímků se zachovala")
        XCTAssertEqual(f.clips(on: f.v1).count, 4)
        XCTAssertValid(f.project)
    }

    /// ⚠️ Jádro modulu: vložená dvojice dostane ČERSTVOU vazbu. Se stejnou
    /// by ji sdílely tři klipy a `validate()` hlásí `brokenLink`.
    func testPastedPairGetsFreshLink() throws {
        var f = Fixture(seconds: 30)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)
        let board = f.project.clipboard(copying: [video.id])

        let inserted = try f.project.paste(board, at: Frames(2000))
        XCTAssertValid(f.project)

        let links = inserted.compactMap { f.project.timeline.clip($0)?.linkID }
        XCTAssertEqual(links.count, 2)
        XCTAssertEqual(Set(links).count, 1, "kopie drží pohromadě mezi sebou")
        XCTAssertNotEqual(links[0], video.linkID, "…ale NE s originálem")
    }

    /// Dvě vložení za sebou musí dát dvě různé vazby — jinak by se páry
    /// slepily napříč vloženími (a to je tentýž `brokenLink`, jen později).
    func testTwoPastesGetDifferentLinks() throws {
        var f = Fixture(seconds: 30)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)
        let board = f.project.clipboard(copying: [video.id])

        let first = try f.project.paste(board, at: Frames(1000))
        let second = try f.project.paste(board, at: Frames(3000))
        XCTAssertValid(f.project)

        let firstLink = f.project.timeline.clip(first.first!)?.linkID
        let secondLink = f.project.timeline.clip(second.first!)?.linkID
        XCTAssertNotNil(firstLink)
        XCTAssertNotEqual(firstLink, secondLink)
    }

    /// Osamocená půlka dvojice (partner ve schránce chybí) vazbu nedostane.
    /// Vazba na jeden klip není vazba.
    func testPastedLonelyHalfLosesLink() throws {
        var f = Fixture(seconds: 30)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)
        // Schránka postavená ručně jen z obrazu — obchází rozšíření o dvojče.
        let board = Clipboard(items: [ClipboardItem(clip: video, trackID: f.v1,
                                                    trackKind: .video, offset: .zero)])

        let inserted = try f.project.paste(board, at: Frames(1000))
        XCTAssertNil(f.project.timeline.clip(inserted.first!)?.linkID)
        XCTAssertValid(f.project)
    }

    /// Vkládá se na PŮVODNÍ stopu — hudba z A2 nesmí přistát na A1 pod řečí.
    func testPasteReturnsToOriginalTrack() throws {
        var f = Fixture(seconds: 60)
        let music = try f.addClip(start: 0, duration: 100, on: f.a2)
        let board = f.project.clipboard(copying: [music])

        try f.project.paste(board, at: Frames(500))
        XCTAssertEqual(f.clips(on: f.a2).count, 2)
        XCTAssertTrue(f.clips(on: f.a1).isEmpty)
    }

    /// Když původní stopa zmizí, klip spadne na první stopu téhož druhu.
    func testPasteFallsBackToFirstTrackOfKind() throws {
        var f = Fixture(seconds: 60)
        let music = try f.addClip(start: 0, duration: 100, on: f.a2)
        let board = f.project.clipboard(copying: [music])
        try f.project.remove(clipID: music)
        try f.project.removeTrack(id: f.a2)

        try f.project.paste(board, at: Frames(0))
        XCTAssertEqual(f.clips(on: f.a1).count, 1)
    }

    /// Atomické: co se nevejde celé, nevloží se vůbec. Rozstrkat klipy po
    /// volných místech by rozbilo jejich vzájemnou polohu, a s ní sync.
    func testPasteOntoOccupiedSpaceChangesNothing() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 0, duration: 50)
        let b = try f.addClip(start: 100, duration: 50)
        let board = f.project.clipboard(copying: [a, b])
        let before = f.project

        XCTAssertThrowsUnchanged(&f.project) { p in
            _ = try p.paste(board, at: Frames(120))   // druhý klip by padl na `b`
        }
        XCTAssertEqual(f.project, before)
        XCTAssertFalse(f.project.canPaste(board, at: Frames(120)))
        XCTAssertTrue(f.project.canPaste(board, at: Frames(1000)))
    }

    /// Dotyk překryv není: vložení těsně za poslední klip projde.
    func testPasteTouchingNeighbourIsLegal() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 0, duration: 50)
        let board = f.project.clipboard(copying: [a])
        XCTAssertTrue(f.project.canPaste(board, at: Frames(50)))
        try f.project.paste(board, at: Frames(50))
        XCTAssertValid(f.project)
    }

    func testPasteAtNegativeFrameThrows() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 0, duration: 50)
        let board = f.project.clipboard(copying: [a])
        XCTAssertThrowsUnchanged(&f.project, .negativePosition) { p in
            _ = try p.paste(board, at: Frames(-10))
        }
    }

    /// Vložený klip si nese rampu, preset i fade — kompletní záběr, ne holá
    /// délka. (Tady se past z `copied` projeví na reálné operaci.)
    func testPasteKeepsRampAndGrade() throws {
        var f = Fixture(seconds: 60)
        let id = try f.addClip(start: 0, duration: 60, sourceStartFrames: 0)
        try f.project.setColorGrade(clipID: id, ColorGrade(preset: .blackAndWhite, intensity: 0.5))
        let source = try XCTUnwrap(f.clip(id))
        let board = f.project.clipboard(copying: [id])

        let inserted = try f.project.paste(board, at: Frames(500))
        let pasted = try XCTUnwrap(f.project.timeline.clip(inserted.first!))
        XCTAssertEqual(pasted.colorGrade, source.colorGrade)
        XCTAssertEqual(pasted.sourceStart, source.sourceStart)
        XCTAssertEqual(pasted.duration, source.duration)
    }

    // MARK: Vyjmutí

    func testCutRemovesAndFillsClipboard() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 0, duration: 50)
        _ = try f.addClip(start: 100, duration: 50)

        let board = try f.project.cut([a])
        XCTAssertEqual(board.count, 1)
        XCTAssertEqual(f.clips(on: f.v1).count, 1, "vyjmutý klip na ose není")
        XCTAssertValid(f.project)

        try f.project.paste(board, at: Frames(0))
        XCTAssertEqual(f.clips(on: f.v1).count, 2, "…a dá se vložit zpátky")
        XCTAssertValid(f.project)
    }

    /// Vyjmutí bere dvojici celou — jinak by na ose zůstal osiřelý zvuk.
    func testCutTakesLinkedPair() throws {
        var f = Fixture(seconds: 30)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)

        let board = try f.project.cut([video.id])
        XCTAssertEqual(board.count, 2)
        XCTAssertTrue(f.clips(on: f.v1).isEmpty)
        XCTAssertTrue(f.clips(on: f.a1).isEmpty)
        XCTAssertValid(f.project)
    }

    // MARK: Rámečkový výběr

    func testRubberBandSelectsIntersectingClips() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 0, duration: 50)      // 0–200 b při 4 b/snímek
        let b = try f.addClip(start: 100, duration: 50)    // 400–600 b
        let g = TimelineGeometry(pointsPerFrame: 4)

        // Rámeček přes první klip a kousek mezery.
        let rect = TimelineRect(from: (x: 10, y: 10), to: (x: 300, y: 40))
        XCTAssertEqual(g.clips(in: rect, in: f.project.timeline), [a])

        // Přes oba.
        let wide = TimelineRect(from: (x: 10, y: 10), to: (x: 500, y: 40))
        XCTAssertEqual(Set(g.clips(in: wide, in: f.project.timeline)), Set([a, b]))
    }

    /// Stačí PROTNOUT — u dlouhého klipu by „celý uvnitř" znamenalo táhnout
    /// rámeček přes půl osy.
    func testRubberBandTakesPartiallyCoveredClip() throws {
        var f = Fixture(seconds: 120)
        let long = try f.addClip(start: 0, duration: 2000)
        let g = TimelineGeometry(pointsPerFrame: 4)
        let rect = TimelineRect(from: (x: 100, y: 5), to: (x: 120, y: 20))
        XCTAssertEqual(g.clips(in: rect, in: f.project.timeline), [long])
    }

    /// Rámeček tažený vzhůru doleva platí stejně jako dolů doprava.
    func testRubberBandNormalizesCorners() throws {
        var f = Fixture(seconds: 60)
        let a = try f.addClip(start: 0, duration: 50)
        let g = TimelineGeometry(pointsPerFrame: 4)
        let backwards = TimelineRect(from: (x: 300, y: 40), to: (x: 10, y: 10))
        XCTAssertEqual(g.clips(in: backwards, in: f.project.timeline), [a])
    }

    /// Svisle se bere jen to, čeho se rámeček dotkl: klip na A1 pod pruhem
    /// obrazu ve výběru není.
    func testRubberBandRespectsTrackRows() throws {
        var f = Fixture(seconds: 60)
        let video = try f.addClip(start: 0, duration: 50)
        let audio = try f.addClip(start: 0, duration: 50, on: f.a1)
        let g = TimelineGeometry(pointsPerFrame: 4)     // V1 0–64, mezera, A1 66–110

        let onlyVideo = TimelineRect(from: (x: 0, y: 0), to: (x: 300, y: 30))
        XCTAssertEqual(g.clips(in: onlyVideo, in: f.project.timeline), [video])

        let both = TimelineRect(from: (x: 0, y: 0), to: (x: 300, y: 100))
        XCTAssertEqual(Set(g.clips(in: both, in: f.project.timeline)), Set([video, audio]))

        let onlyAudio = TimelineRect(from: (x: 0, y: 70), to: (x: 300, y: 100))
        XCTAssertEqual(g.clips(in: onlyAudio, in: f.project.timeline), [audio])
    }

    /// Rámeček, který se klipu jen dotkne hranou, ho nebere — jinak by
    /// klik do prázdna vedle klipu vybral klip.
    func testRubberBandIgnoresUntouchedClips() throws {
        var f = Fixture(seconds: 60)
        _ = try f.addClip(start: 100, duration: 50)       // 400–600 b
        let g = TimelineGeometry(pointsPerFrame: 4)
        let before = TimelineRect(from: (x: 100, y: 10), to: (x: 399, y: 40))
        XCTAssertTrue(g.clips(in: before, in: f.project.timeline).isEmpty)
    }
}
