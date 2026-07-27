import XCTest
@testable import TimelineModel

/// Split svázaného páru (krok 9 fáze 2). Vazba smí mít nejvýš dva členy
/// různého druhu — split proto řeže i dvojče a poloviny přepojuje po
/// dvojicích. Bez toho by po rozříznutí sdílely jednu vazbu tři klipy
/// a `validate()` by hlásil `brokenLink`.
final class LinkedSplitTests: XCTestCase {

    /// Pár obraz+zvuk přes celý asset, vložený na V1 + A1.
    private func makeLinkedFixture() throws -> (f: Fixture, video: ClipID, audio: ClipID) {
        var f = Fixture(seconds: 10)   // 10 s × 30 fps = 300 snímků
        let pair = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: pair.video, onVideoTrack: f.v1,
                                   audio: pair.audio, onAudioTrack: f.a1)
        return (f, pair.video.id, pair.audio.id)
    }

    func testSplitLinkedPairCutsBothAndRelinksHalves() throws {
        var (f, video, _) = try makeLinkedFixture()

        let (leftV, rightV) = try f.project.split(clipID: video, at: Frames(120))

        // Obě stopy mají dvě poloviny se správnými délkami.
        XCTAssertEqual(f.clips(on: f.v1).map(\.duration), [Frames(120), Frames(180)])
        XCTAssertEqual(f.clips(on: f.a1).map(\.duration), [Frames(120), Frames(180)])

        // Levé poloviny sdílí jednu vazbu, pravé druhou, a nejsou to tytéž.
        let leftA = f.clips(on: f.a1)[0], rightA = f.clips(on: f.a1)[1]
        XCTAssertNotNil(f.clip(leftV)?.linkID)
        XCTAssertEqual(f.clip(leftV)?.linkID, leftA.linkID)
        XCTAssertNotNil(f.clip(rightV)?.linkID)
        XCTAssertEqual(f.clip(rightV)?.linkID, rightA.linkID)
        XCTAssertNotEqual(f.clip(leftV)?.linkID, f.clip(rightV)?.linkID)

        XCTAssertValid(f.project)
    }

    func testSplitLinkedPairKeepsSourceContinuityOnPartner() throws {
        var (f, video, _) = try makeLinkedFixture()
        try f.project.split(clipID: video, at: Frames(120))

        // Druhá polovina dvojčete navazuje ve zdroji tam, kde první končí.
        let audioHalves = f.clips(on: f.a1)
        let expected = f.project.sourceOffset(in: audioHalves[0], atFrame: audioHalves[0].duration)
        XCTAssertEqual(audioHalves[1].sourceStart, expected)
    }

    func testSplitViaPartnerGivesSameResult() throws {
        // Řez vedený zvukem musí dopadnout stejně jako řez vedený obrazem.
        var (f, _, audio) = try makeLinkedFixture()
        try f.project.split(clipID: audio, at: Frames(90))

        XCTAssertEqual(f.clips(on: f.v1).map(\.duration), [Frames(90), Frames(210)])
        XCTAssertEqual(f.clips(on: f.a1).map(\.duration), [Frames(90), Frames(210)])
        XCTAssertValid(f.project)
    }

    func testSplitUnlinkedClipLeavesOtherTracksAlone() throws {
        var f = Fixture(seconds: 10)
        let clip = try f.addClip(start: 0, duration: 300)
        try f.addClip(start: 0, duration: 300, on: f.a2)

        try f.project.split(clipID: clip, at: Frames(100))

        XCTAssertEqual(f.clips(on: f.v1).count, 2)
        XCTAssertEqual(f.clips(on: f.a2).count, 1)
        XCTAssertValid(f.project)
    }

    func testSplitWithShiftedPartnerKeepsLinkOnOverlappingHalf() throws {
        // Nesouosé dvojče (vzniká trimem jednoho z páru — `move` hýbe oběma):
        // obraz zatrimovaný na 150..300, zvuk celý 0..300. Řez zvukem na 100
        // vede mimo obraz; vazba pak patří té polovině zvuku, se kterou se
        // obraz překrývá (pravé), a levá je bez vazby — tři klipy na jedné
        // vazbě nesmí vzniknout.
        var (f, video, audio) = try makeLinkedFixture()
        try f.project.trimStart(clipID: video, to: Frames(150))

        let (leftA, rightA) = try f.project.split(clipID: audio, at: Frames(100))

        XCTAssertNil(f.clip(leftA)?.linkID)
        XCTAssertEqual(f.clip(rightA)?.linkID, f.clip(video)?.linkID)
        // Obraz zůstal v jednom kuse.
        XCTAssertEqual(f.clips(on: f.v1).count, 1)
        XCTAssertValid(f.project)
    }

    func testSplitLinkedThenUndoRoundTrip() throws {
        var (f, video, _) = try makeLinkedFixture()
        var undo = UndoStack()

        undo.record(f.project)
        try f.project.split(clipID: video, at: Frames(60))
        XCTAssertEqual(f.clips(on: f.v1).count, 2)

        if let previous = undo.undo(current: f.project) { f.project = previous }
        XCTAssertEqual(f.clips(on: f.v1).count, 1)
        XCTAssertEqual(f.clips(on: f.a1).count, 1)
        XCTAssertValid(f.project)
    }
}
