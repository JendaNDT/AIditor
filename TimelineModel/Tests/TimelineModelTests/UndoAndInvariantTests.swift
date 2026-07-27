import XCTest
@testable import TimelineModel

/// Undo (54–61) a property testy invariantů (1–3).
final class UndoAndInvariantTests: XCTestCase {

    // MARK: Undo (54–61)

    // 54.
    func testUndoRestoresExactPreviousState() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        var stack = UndoStack()
        let before = f.project

        stack.record(f.project)
        try f.project.move(clipID: id, toTrack: f.v1, start: Frames(200))
        XCTAssertNotEqual(f.project, before)

        f.project = stack.undo(current: f.project)!
        XCTAssertEqual(f.project, before)
    }

    // 55.
    func testUndoRedoUndoEndsAtUndo() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        var stack = UndoStack()
        let before = f.project

        stack.record(f.project)
        try f.project.move(clipID: id, toTrack: f.v1, start: Frames(200))
        let after = f.project

        f.project = stack.undo(current: f.project)!
        f.project = stack.redo(current: f.project)!
        XCTAssertEqual(f.project, after)
        f.project = stack.undo(current: f.project)!
        XCTAssertEqual(f.project, before)
    }

    // 56.
    func testNewOperationClearsRedoBranch() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        var stack = UndoStack()

        stack.record(f.project)
        try f.project.move(clipID: id, toTrack: f.v1, start: Frames(200))
        f.project = stack.undo(current: f.project)!
        XCTAssertTrue(stack.canRedo)

        stack.record(f.project)
        try f.project.move(clipID: id, toTrack: f.v1, start: Frames(300))
        XCTAssertFalse(stack.canRedo, "nová operace musí zahodit redo větev")
    }

    // 57.
    func testStackStopsAtLimit() throws {
        var f = Fixture()
        var stack = UndoStack(limit: 5)
        for i in 0..<20 {
            stack.record(f.project)
            try f.addClip(start: i * 10, duration: 5)
        }
        XCTAssertEqual(stack.depth, 5)
    }

    // 58.
    func testInteractionIsASingleUndoStep() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        var stack = UndoStack()
        let before = f.project

        stack.beginInteraction(f.project)
        for end in [110, 120, 130, 140] {          // tažení trimu
            try f.project.trimEnd(clipID: id, to: Frames(end))
        }
        stack.endInteraction(f.project)

        XCTAssertEqual(stack.depth, 1, "šedesát mezistavů tažení je jeden undo krok")
        f.project = stack.undo(current: f.project)!
        XCTAssertEqual(f.project, before)
    }

    // 59.
    func testEndInteractionWithoutChangeCreatesNoStep() {
        let f = Fixture()
        var stack = UndoStack()
        stack.beginInteraction(f.project)
        stack.endInteraction(f.project)
        XCTAssertEqual(stack.depth, 0, "jinak by Cmd+Z dvakrát nic neudělalo")
        XCTAssertFalse(stack.canUndo)
    }

    // 60.
    func testUnpairedBeginInteractionDoesNotBreakStack() throws {
        var f = Fixture()
        var stack = UndoStack()
        stack.beginInteraction(f.project)
        stack.beginInteraction(f.project)      // druhé volání se musí ignorovat
        try f.addClip(start: 0, duration: 10)
        stack.endInteraction(f.project)
        XCTAssertEqual(stack.depth, 1)
    }

    func testCancelInteractionReturnsStateBeforeDrag() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        var stack = UndoStack()
        let before = f.project

        stack.beginInteraction(f.project)
        try f.project.trimEnd(clipID: id, to: Frames(150))
        let restored = stack.cancelInteraction()

        XCTAssertEqual(restored, before)
        XCTAssertFalse(stack.isInteracting)
        XCTAssertEqual(stack.depth, 0)
    }

    // 61. Undo přes operaci, která přidala asset, musí vrátit i ten asset.
    func testUndoRestoresAddedAsset() throws {
        var p = Project.empty()
        var stack = UndoStack()
        let before = p

        stack.record(p)
        let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/x.mov"),
                          duration: SourceTime(seconds: 5),
                          measuredFrameRate: 30)
        p.addAsset(asset)
        let clip = try p.makeClip(assetID: asset.id)
        try p.insert(clip, onTrack: p.timeline.tracks[0].id)

        p = stack.undo(current: p)!
        XCTAssertEqual(p, before)
        XCTAssertTrue(p.assets.isEmpty, "undo musí vrátit i asset, ne jen klip")

        p = stack.redo(current: p)!
        XCTAssertValid(p)
        XCTAssertEqual(p.assets.count, 1, "po redo musí být asset zpátky, jinak visí klip na prázdnu")
    }

    // MARK: Invarianty (1–3)

    // 1. + 2. Náhodná posloupnost operací nesmí porušit invarianty.
    func testRandomOperationSequenceKeepsInvariants() throws {
        let seed: UInt64 = 0xC0FFEE
        var rng = SeededRandom(seed: seed)
        var f = Fixture(seconds: 120)      // 3600 snímků materiálu
        var ids: [ClipID] = []
        /// Pojistka proti testu, který nic netestuje: kdyby všechny operace
        /// selhaly, invarianty by triviálně platily a test by byl zelený.
        var succeeded = 0

        for step in 0..<100 {
            let action = Int(rng.next() % 7)
            let pick = ids.isEmpty ? nil : ids[Int(rng.next() % UInt64(ids.count))]
            do {
                switch action {
                case 0:
                    let start = Int(rng.next() % 2000)
                    let dur = 1 + Int(rng.next() % 200)
                    let clip = Clip(assetID: f.assetID, timelineStart: Frames(start),
                                    duration: Frames(dur), sourceStart: .zero)
                    try f.project.insert(clip, onTrack: f.v1)
                    ids.append(clip.id)
                case 1:
                    if let pick { try f.project.remove(clipID: pick); ids.removeAll { $0 == pick } }
                case 2:
                    if let pick { try f.project.rippleRemove(clipID: pick); ids.removeAll { $0 == pick } }
                case 3:
                    if let pick {
                        try f.project.move(clipID: pick, toTrack: f.v1,
                                           start: Frames(Int(rng.next() % 2000)))
                    }
                case 4:
                    if let pick, let clip = f.clip(pick), clip.duration.count > 1 {
                        let at = clip.timelineStart + Frames(1 + Int(rng.next() % UInt64(clip.duration.count - 1)))
                        let (l, r) = try f.project.split(clipID: pick, at: at)
                        ids.removeAll { $0 == pick }
                        ids.append(contentsOf: [l, r])
                    }
                case 5:
                    if let pick, let clip = f.clip(pick) {
                        try f.project.trimEnd(clipID: pick,
                                              to: clip.timelineStart + Frames(1 + Int(rng.next() % 300)))
                    }
                default:
                    if let pick { try f.project.slip(clipID: pick, by: Frames(Int(rng.next() % 40) - 20)) }
                }
                succeeded += 1
            } catch is TimelineError {
                // Odmítnutá operace je legitimní výsledek — testuje se, že po ní
                // model není rozbitý, ne že každá operace projde.
            }
            let violations = f.project.validate()
            XCTAssertTrue(violations.isEmpty,
                          "krok \(step), semínko 0x\(String(seed, radix: 16)): \(violations)")
            if !violations.isEmpty { return }
        }
        XCTAssertGreaterThan(succeeded, 40,
                             "moc operací selhalo — test by pak nic netestoval")
        XCTAssertGreaterThan(f.project.timeline.tracks[0].clips.count, 0)
    }

    // 3. Chyba nesmí nechat polovičatou mutaci — pokryto v XCTAssertThrowsUnchanged
    // napříč testy; tady ještě pro složenou operaci.
    func testFailedLinkedInsertLeavesNothingBehind() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100, on: f.a1)     // blokuje zvukovou stopu
        let pair = try f.project.makeLinkedClips(assetID: f.assetID, at: .zero)
        var v = pair.video; v.duration = Frames(50)
        var a = pair.audio; a.duration = Frames(50)

        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.insertLinked(video: v, onVideoTrack: f.v1, audio: a, onAudioTrack: f.a1)
        }
        XCTAssertEqual(f.clips(on: f.v1).count, 0,
                       "obrazová část se nesmí vložit, když zvuková selže")
    }

    // MARK: Validace chytá, co má

    func testValidateDetectsOverlap() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        // Obejít operace a vyrobit neplatný stav ručně.
        var track = f.project.timeline.tracks[0]
        track.clips.append(Clip(assetID: f.assetID, timelineStart: Frames(50),
                                duration: Frames(100), sourceStart: .zero))
        f.project.timeline.tracks[0] = track
        XCTAssertFalse(f.project.isValid)
    }

    func testValidateDetectsWrongTrackKind() throws {
        var f = Fixture(hasVideo: true, hasAudio: false)
        var track = f.project.timeline.tracks[1]      // A1
        track.clips.append(Clip(assetID: f.assetID, timelineStart: .zero,
                                duration: Frames(10), sourceStart: .zero))
        f.project.timeline.tracks[1] = track
        XCTAssertTrue(f.project.validate().contains { if case .wrongTrackKind = $0 { return true }; return false })
    }

    func testValidateDetectsExceededSource() throws {
        var f = Fixture(seconds: 1)      // 30 snímků
        var track = f.project.timeline.tracks[0]
        track.clips.append(Clip(assetID: f.assetID, timelineStart: .zero,
                                duration: Frames(100), sourceStart: .zero))
        f.project.timeline.tracks[0] = track
        XCTAssertTrue(f.project.validate().contains { if case .exceedsSource = $0 { return true }; return false })
    }

    func testValidateDetectsDuplicateClipID() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 50)
        let clone = Clip(id: id, assetID: f.assetID, timelineStart: Frames(100),
                         duration: Frames(50), sourceStart: .zero)
        var track = f.project.timeline.tracks[0]
        track.clips.append(clone)
        f.project.timeline.tracks[0] = track
        XCTAssertTrue(f.project.validate().contains(.duplicateClipID(id)))
    }

    func testAdjacentClipsAreNotOverlapping() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 100, duration: 100)
        XCTAssertValid(f.project)
    }
}
