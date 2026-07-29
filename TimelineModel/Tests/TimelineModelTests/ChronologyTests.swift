import XCTest
@testable import TimelineModel

/// Chronologie materiálu a rozsah exportu (fáze 17, modul 3).
final class ChronologyTests: XCTestCase {

    /// Projekt se třemi assety, jejichž časy natočení jsou naschvál v jiném
    /// pořadí než jména souborů — přesně jako materiál ze dvou kamer.
    private func makeShuffled() -> (project: Project, v1: TrackID, a1: TrackID,
                                    ids: [AssetID]) {
        var project = Project.empty()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        // Soubor A vznikl POZDĚJI než B, přestože se jmenuje dřív.
        let offsets: [TimeInterval] = [3600, 0, 1800]        // A: +1 h, B: 0, C: +30 min
        var ids: [AssetID] = []
        for (i, offset) in offsets.enumerated() {
            let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/\(["A", "B", "C"][i]).mov"),
                              duration: SourceTime(seconds: 60),
                              measuredFrameRate: 30,
                              creationDate: base.addingTimeInterval(offset),
                              creationDateSource: .metadata)
            project.addAsset(asset)
            ids.append(asset.id)
        }
        return (project, project.timeline.tracks[0].id, project.timeline.tracks[1].id, ids)
    }

    // MARK: Uspořádání

    func testArrangeSortsByCreationDateAndClosesGaps() throws {
        var (project, v1, _, ids) = makeShuffled()
        for (i, assetID) in ids.enumerated() {
            let clip = Clip(assetID: assetID, timelineStart: Frames(i * 200),
                            duration: Frames(60), sourceStart: .zero)
            try project.insert(clip, onTrack: v1)
        }

        let undated = try project.arrangeChronologically(trackID: v1)
        XCTAssertEqual(undated, 0)

        let order = project.timeline.tracks[0].clips.map(\.assetID)
        XCTAssertEqual(order, [ids[1], ids[2], ids[0]], "B (0) → C (+30 min) → A (+1 h)")
        XCTAssertEqual(project.timeline.tracks[0].clips.map(\.timelineStart),
                       [Frames(0), Frames(60), Frames(120)], "mezery se zavřely")
        XCTAssertValid(project)
    }

    /// Uspořádání začíná tam, kde stopa začínala — místo vpředu (na titulek)
    /// se nemá samo zahodit.
    func testArrangeKeepsLeadingOffset() throws {
        var (project, v1, _, ids) = makeShuffled()
        for (i, assetID) in ids.enumerated() {
            let clip = Clip(assetID: assetID, timelineStart: Frames(300 + i * 200),
                            duration: Frames(60), sourceStart: .zero)
            try project.insert(clip, onTrack: v1)
        }
        try project.arrangeChronologically(trackID: v1)
        XCTAssertEqual(project.timeline.tracks[0].clips.first?.timelineStart, Frames(300))
    }

    /// ⚠️ Nejdražší chyba, kterou tahle operace umí udělat: rozejít obraz
    /// se zvukem. Dvojče se musí posunout o TOTÉŽ.
    func testArrangeMovesLinkedTwins() throws {
        var (project, v1, a1, ids) = makeShuffled()
        for (i, assetID) in ids.enumerated() {
            let link = LinkID()
            var video = Clip(assetID: assetID, timelineStart: Frames(i * 200),
                             duration: Frames(60), sourceStart: .zero)
            var audio = Clip(assetID: assetID, timelineStart: Frames(i * 200),
                             duration: Frames(60), sourceStart: .zero)
            video.linkID = link
            audio.linkID = link
            try project.insertLinked(video: video, onVideoTrack: v1,
                                     audio: audio, onAudioTrack: a1)
        }

        try project.arrangeChronologically(trackID: v1)
        XCTAssertValid(project)

        // Každý obrazový klip má zvuk na TÉŽE pozici.
        for clip in project.timeline.tracks[0].clips {
            let partners = project.linkedPartners(of: clip.id)
            XCTAssertEqual(partners.count, 1)
            XCTAssertEqual(partners.first?.timelineStart, clip.timelineStart,
                           "zvuk se rozešel s obrazem")
        }
        XCTAssertEqual(project.timeline.tracks[1].clips.map(\.timelineStart),
                       [Frames(0), Frames(60), Frames(120)])
    }

    /// Klipy bez času natočení se nehádají — jdou dozadu v dosavadním
    /// pořadí a operace jejich počet přizná.
    func testUndatedClipsGoLastAndAreReported() throws {
        var (project, v1, _, ids) = makeShuffled()
        let unknown = Asset(originalURL: URL(fileURLWithPath: "/tmp/bezdata.mov"),
                            duration: SourceTime(seconds: 60), measuredFrameRate: 30)
        project.addAsset(unknown)

        // Na ose: nedatovaný první, pak A (+1 h), pak B (0).
        for (i, assetID) in [unknown.id, ids[0], ids[1]].enumerated() {
            let clip = Clip(assetID: assetID, timelineStart: Frames(i * 200),
                            duration: Frames(60), sourceStart: .zero)
            try project.insert(clip, onTrack: v1)
        }

        let undated = try project.arrangeChronologically(trackID: v1)
        XCTAssertEqual(undated, 1, "počet nedatovaných se hlásí")
        XCTAssertEqual(project.timeline.tracks[0].clips.map(\.assetID),
                       [ids[1], ids[0], unknown.id], "B → A → bez data")
        XCTAssertValid(project)
    }

    func testArrangeOnEmptyOrSingleTrackDoesNothing() throws {
        var (project, v1, _, ids) = makeShuffled()
        XCTAssertEqual(try project.arrangeChronologically(trackID: v1), 0)

        let clip = Clip(assetID: ids[0], timelineStart: Frames(100),
                        duration: Frames(60), sourceStart: .zero)
        try project.insert(clip, onTrack: v1)
        let before = project
        XCTAssertEqual(try project.arrangeChronologically(trackID: v1), 0)
        XCTAssertEqual(project, before, "jeden klip se nemá kam přeskládat")
    }

    func testArrangeUnknownTrackThrows() throws {
        var (project, _, _, _) = makeShuffled()
        XCTAssertThrowsUnchanged(&project) { p in
            _ = try p.arrangeChronologically(trackID: TrackID())
        }
    }

    // MARK: Rozsah exportu

    func testExportRangeUsesInAndOut() throws {
        var f = Fixture(seconds: 60)
        try f.addClip(start: 0, duration: 300)
        let range = f.project.exportRange(inPoint: Frames(60), outPoint: Frames(180))
        XCTAssertEqual(range, Frames(60) ..< Frames(180))
    }

    /// Chybějící body = celý projekt. Export nikdy nesmí tiše vyrobit
    /// prázdný soubor.
    func testExportRangeDefaultsToWholeProject() throws {
        var f = Fixture(seconds: 60)
        try f.addClip(start: 0, duration: 300)
        XCTAssertEqual(f.project.exportRange(inPoint: nil, outPoint: nil),
                       Frames(0) ..< Frames(300))
        XCTAssertEqual(f.project.exportRange(inPoint: Frames(100), outPoint: nil),
                       Frames(100) ..< Frames(300))
        XCTAssertEqual(f.project.exportRange(inPoint: nil, outPoint: Frames(100)),
                       Frames(0) ..< Frames(100))
    }

    /// Obrácené nebo nulové body: radši celý projekt než prázdno.
    func testExportRangeIgnoresInvertedPoints() throws {
        var f = Fixture(seconds: 60)
        try f.addClip(start: 0, duration: 300)
        XCTAssertEqual(f.project.exportRange(inPoint: Frames(200), outPoint: Frames(100)),
                       Frames(0) ..< Frames(300))
        XCTAssertEqual(f.project.exportRange(inPoint: Frames(150), outPoint: Frames(150)),
                       Frames(0) ..< Frames(300))
    }

    func testExportRangeClampsToProject() throws {
        var f = Fixture(seconds: 60)
        try f.addClip(start: 0, duration: 300)
        XCTAssertEqual(f.project.exportRange(inPoint: Frames(-50), outPoint: Frames(9000)),
                       Frames(0) ..< Frames(300))
    }

    // MARK: Formát souboru

    /// Čas natočení je volitelné pole — starší projekty se čtou dál
    /// a verze formátu se kvůli němu nezvedá.
    func testCreationDateSurvivesRoundtripAndOldFilesLoad() throws {
        var (project, v1, _, ids) = makeShuffled()
        let clip = Clip(assetID: ids[0], timelineStart: .zero,
                        duration: Frames(60), sourceStart: .zero)
        try project.insert(clip, onTrack: v1)

        let file = ProjectFile(project: project, name: "chronologie")
        let decoded = try ProjectFile.decode(try file.encoded()).project
        XCTAssertEqual(decoded.asset(ids[0])?.creationDate,
                       project.asset(ids[0])?.creationDate)
        XCTAssertEqual(decoded.asset(ids[0])?.creationDateSource, .metadata)

        // Asset bez těch polí (jako v souborech z doby před fází 17).
        let old = """
        {"id":"\(UUID().uuidString)","originalURL":"file:///tmp/x.mov",
         "duration":{"value":600,"timescale":600},"measuredFrameRate":30,
         "hasVideo":true,"hasAudio":true,"isOffline":false}
        """
        let asset = try JSONDecoder().decode(Asset.self, from: Data(old.utf8))
        XCTAssertNil(asset.creationDate)
        XCTAssertNil(asset.creationDateSource)
    }
}
