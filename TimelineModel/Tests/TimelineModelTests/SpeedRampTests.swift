//
//  SpeedRampTests.swift
//  TimelineModel — Projekt Krása
//
//  Rampová větev `sourceConsumption` / `sourceOffset` a všeho, co na nich
//  stojí. Referenční hodnota z `SpeedRampEngine`: klasický ramp
//  1,0 → 0,25 → 1,0 přes 5 s výstupu spotřebuje PŘESNĚ 3,125 s zdroje.
//  Když tu vyjde jiné číslo, chyba je v převodu na ticky, ne v matematice.
//

import XCTest
@testable import TimelineModel

final class SpeedRampModelTests: XCTestCase {

    /// Klasický ramp přes prvních 3,125 s zdroje: výstup přesně 5 s = 150 snímků.
    private func classicRamp(from startSeconds: Double = 0) -> TimelineModel.SpeedRamp {
        .classicSlowMotion(from: SourceTime(seconds: startSeconds),
                           spanning: SourceTime(seconds: 3.125),
                           slowSpeed: 0.25)
    }

    private func ticks(_ time: SourceTime) -> Int64 {
        time.converted(to: SourceTime.projectTimescale).value
    }

    // MARK: Platnost

    func testPlatnostKrivky() {
        XCTAssertFalse(TimelineModel.SpeedRamp(nodes: []).isUsable)
        XCTAssertTrue(TimelineModel.SpeedRamp(nodes: [
            SpeedNode(sourceTime: .zero, speed: 0.5),
        ]).isUsable, "jediný uzel = konstantní rychlost")
        XCTAssertFalse(TimelineModel.SpeedRamp(nodes: [
            SpeedNode(sourceTime: SourceTime(seconds: 1), speed: 1),
            SpeedNode(sourceTime: SourceTime(seconds: 1), speed: 0.5),
        ]).isUsable, "nerostoucí časy")
        XCTAssertFalse(TimelineModel.SpeedRamp(nodes: [
            SpeedNode(sourceTime: .zero, speed: 0),
            SpeedNode(sourceTime: SourceTime(seconds: 1), speed: 1),
        ]).isUsable, "nulová rychlost je freeze frame, ne ramp")
    }

    // MARK: Spotřeba

    func testBezRampyJeSpotrebaJednaKuJedne() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        let clip = f.clip(id)!
        XCTAssertEqual(ticks(f.project.sourceConsumption(of: clip)), 150 * 3000)
    }

    func testKlasickyRampSpotrebujePresne3125ms() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)   // 5 s na ose
        try f.project.setSpeedRamp(clipID: id, ramp: classicRamp())
        let clip = f.clip(id)!

        // 3,125 s = 281 250 ticků. Přesně — tolerance zaokrouhlení je 1e-3 ticku.
        XCTAssertEqual(ticks(f.project.sourceConsumption(of: clip)), 281_250)
        XCTAssertValid(f.project)
    }

    func testKonstantniPolovicniRychlost() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 120)   // 4 s na ose
        try f.project.setSpeedRamp(clipID: id, ramp: TimelineModel.SpeedRamp(nodes: [
            SpeedNode(sourceTime: .zero, speed: 0.5),
        ]))
        let clip = f.clip(id)!
        XCTAssertEqual(ticks(f.project.sourceConsumption(of: clip)), 120 * 1500,
                       "0,5× spotřebuje polovinu zdroje")
    }

    func testSpotrebaZaKoncemKrivkyJedeKrajniRychlosti() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 240)   // 8 s na ose
        try f.project.setSpeedRamp(clipID: id, ramp: classicRamp())
        let clip = f.clip(id)!

        // Prvních 5 s výstupu spotřebuje 3,125 s; zbylé 3 s jedou 1×.
        XCTAssertEqual(ticks(f.project.sourceConsumption(of: clip)),
                       281_250 + 3 * 90_000)
    }

    // MARK: sourceOffset a konzistence s join

    func testOffsetNaKonciKlipuRovnaSeSpotrebe() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp: classicRamp())
        let clip = f.clip(id)!

        let viaOffset = f.project.sourceOffset(in: clip, atFrame: clip.duration)
        let viaConsumption = clip.sourceStart + f.project.sourceConsumption(of: clip)
        XCTAssertEqual(viaOffset, viaConsumption,
                       "join stojí na tom, že obě cesty dají stejný výsledek")
    }

    func testOffsetJeMonotonni() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp: classicRamp())
        let clip = f.clip(id)!

        var previous = SourceTime.zero
        for frame in 1...150 {
            let s = f.project.sourceOffset(in: clip, atFrame: Frames(frame))
            XCTAssertTrue(previous < s || previous == s,
                          "zdrojová pozice nesmí couvat (snímek \(frame))")
            previous = s
        }
    }

    // MARK: Split a join na rampě

    func testSplitARejoinRampovanehoKlipu() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp: classicRamp())
        let whole = ticks(f.project.sourceConsumption(of: f.clip(id)!))

        let (leftID, rightID) = try f.project.split(clipID: id, at: Frames(70))
        XCTAssertValid(f.project)

        let left = f.clip(leftID)!, right = f.clip(rightID)!
        XCTAssertEqual(left.speedRamp, right.speedRamp,
                       "obě poloviny nesou tutéž zdrojově kotvenou křivku")

        // Poloviny dohromady spotřebují tolik co celek. Ne PŘESNĚ: sourceStart
        // pravé poloviny se kvantuje na celé ticky a v místě řezu uprostřed
        // zpomalení se chyba 1 ticku zesílí poměrem rychlostí (1 / 0,25 = 4).
        // 8 ticků = 89 µs zdroje, proti snímku (3000 ticků) nic.
        let sum = ticks(f.project.sourceConsumption(of: left))
                + ticks(f.project.sourceConsumption(of: right))
        XCTAssertLessThanOrEqual(abs(sum - whole), 8)

        try f.project.join(leftID: leftID, rightID: rightID)
        XCTAssertValid(f.project)
        XCTAssertEqual(ticks(f.project.sourceConsumption(of: f.clip(leftID)!)), whole)
    }

    /// Zpomalení kotvené ve zdroji: po trimu zepředu ukazuje snímek osy
    /// pořád totéž místo zdroje, jen posunuté o trim.
    func testTrimZepreduNechaZpomaleniNaUdalosti() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp: classicRamp())
        let original = f.clip(id)!

        let reference = f.project.sourceOffset(in: original, atFrame: Frames(90))

        try f.project.trimStart(clipID: id, to: Frames(30))
        XCTAssertValid(f.project)
        let trimmed = f.clip(id)!

        // Snímek 90 původního klipu je snímek 60 zkráceného.
        let after = f.project.sourceOffset(in: trimmed, atFrame: Frames(60))
        let delta = abs(ticks(after) - ticks(reference))
        XCTAssertLessThanOrEqual(delta, 2,
            "zpomalení se smí posunout nejvýš o zaokrouhlení ticků, ne o kus záběru")
    }

    // MARK: Meze zdroje

    func testProdlouzeniRampovanehoKlipuOmezujeZdroj() throws {
        // Asset 5 s, klip 150 snímků s klasickým rampem spotřebuje 3,125 s.
        // Za koncem jede 1× → zbývá 1,875 s = 56 snímků (zaokrouhleno dolů).
        var f = Fixture(seconds: 5)
        let id = try f.addClip(start: 0, duration: 150)
        try f.project.setSpeedRamp(clipID: id, ramp: classicRamp())
        let clip = f.clip(id)!

        XCTAssertEqual(f.project.remainingSourceFrames(after: clip), Frames(56))

        try f.project.trimEnd(clipID: id, to: Frames(150 + 56))
        XCTAssertValid(f.project)

        var p = f.project
        XCTAssertThrowsUnchanged(&p) {
            try $0.trimEnd(clipID: id, to: Frames(150 + 57))
        }
    }

    func testZrychleniNaKonciSouboruSelze() throws {
        // Klip přes celý asset zrychlený 2× by spotřeboval dvojnásobek zdroje.
        var f = Fixture(seconds: 5)
        let id = try f.addClip(start: 0, duration: 150)
        var p = f.project
        XCTAssertThrowsUnchanged(&p) {
            try $0.setSpeedRamp(clipID: id, ramp: TimelineModel.SpeedRamp(nodes: [
                SpeedNode(sourceTime: .zero, speed: 2.0),
            ]))
        }
    }

    func testNeplatnaKrivkaSeOdmitne() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 60)
        var p = f.project
        XCTAssertThrowsUnchanged(&p, .invalidSpeedRamp) {
            try $0.setSpeedRamp(clipID: id, ramp: TimelineModel.SpeedRamp(nodes: [
                SpeedNode(sourceTime: SourceTime(seconds: 1), speed: 1),
                SpeedNode(sourceTime: SourceTime(seconds: 1), speed: 0.5),
            ]))
        }
    }

    func testValidaceHlasiNeplatnouKrivkuNaKlipu() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 60)
        // Obejít operaci a zapsat vadnou křivku přímo — validate ji musí chytit.
        var tracks = f.project.timeline.tracks
        tracks[0].clips[0].speedRamp = TimelineModel.SpeedRamp(nodes: [])
        f.project.timeline.tracks = tracks
        XCTAssertTrue(f.project.validate().contains(.invalidSpeedRamp(id)))
    }

    // MARK: Vazba obraz–zvuk

    func testRampaSeNastaviISvazanemuDvojceti() throws {
        var f = Fixture(seconds: 10)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)

        try f.project.setSpeedRamp(clipID: video.id, ramp: classicRamp())
        XCTAssertEqual(f.clip(audio.id)?.speedRamp, classicRamp(),
                       "jinak se rozejde obraz se zvukem")

        try f.project.setSpeedRamp(clipID: audio.id, ramp: nil)
        XCTAssertNil(f.clip(video.id)?.speedRamp, "mazání jde přes vazbu taky")
    }
}

// MARK: - Plán přehrávání

final class RampPlaybackPlanTests: XCTestCase {

    private func rampedFixture(durationFrames: Int = 150,
                               assetSeconds: Double = 10) throws -> (Fixture, ClipID) {
        var f = Fixture(seconds: assetSeconds)
        let id = try f.addClip(start: 0, duration: durationFrames)
        try f.project.setSpeedRamp(clipID: id, ramp:
            .classicSlowMotion(from: .zero,
                               spanning: SourceTime(seconds: 3.125),
                               slowSpeed: 0.25))
        return (f, id)
    }

    func testBezRampyNeniPlan() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 150)
        XCTAssertNil(f.project.rampPlaybackPlan(of: f.clip(id)!))
    }

    func testSouctySediNaSpotrebuIDelku() throws {
        let (f, id) = try rampedFixture()
        let clip = f.clip(id)!
        let plan = f.project.rampPlaybackPlan(of: clip)!

        let outputSum = plan.segments.reduce(Int64(0)) { $0 + $1.outputTicks }
        XCTAssertEqual(outputSum, Int64(clip.duration.count) * 3000,
                       "výstup musí vyplnit slot klipu na osе přesně")

        let sourceSum = plan.segments.reduce(Int64(0)) { $0 + $1.sourceDurationTicks }
        let consumption = f.project.sourceConsumption(of: clip)
            .converted(to: SourceTime.projectTimescale).value
        XCTAssertEqual(sourceSum, consumption,
                       "zdroj musí pokrýt přesně vložený rozsah")
    }

    func testUsekyNavazujiBezMezer() throws {
        let (f, id) = try rampedFixture()
        let plan = f.project.rampPlaybackPlan(of: f.clip(id)!)!

        var cursor: Int64 = 0
        for segment in plan.segments {
            XCTAssertEqual(segment.sourceStartTicks, cursor)
            cursor += segment.sourceDurationTicks
        }
    }

    func testSkokRychlostiDodrzenNeboPriznan() throws {
        let (f, id) = try rampedFixture()
        let plan = f.project.rampPlaybackPlan(of: f.clip(id)!)!
        if !plan.limitedByFrameRate {
            XCTAssertLessThanOrEqual(plan.achievedMaxStep, 0.015)
        }
    }

    func testKonstantniRychlostDaJedinySegment() throws {
        var f = Fixture(seconds: 10)
        let id = try f.addClip(start: 0, duration: 120)
        try f.project.setSpeedRamp(clipID: id, ramp: TimelineModel.SpeedRamp(nodes: [
            SpeedNode(sourceTime: .zero, speed: 0.5),
        ]))
        let plan = f.project.rampPlaybackPlan(of: f.clip(id)!)!
        XCTAssertEqual(plan.segments.count, 1)
        XCTAssertEqual(plan.segments[0].outputTicks, 120 * 3000)
        XCTAssertEqual(plan.segments[0].sourceDurationTicks, 120 * 1500)
    }

    func testPlanPoSplituNavazujeNaKrivku() throws {
        let (f, id) = try rampedFixture()
        var f2 = f
        let (leftID, rightID) = try f2.project.split(clipID: id, at: Frames(70))

        let left = f2.clip(leftID)!, right = f2.clip(rightID)!
        let leftPlan = f2.project.rampPlaybackPlan(of: left)!
        let rightPlan = f2.project.rampPlaybackPlan(of: right)!

        let leftOut = leftPlan.segments.reduce(Int64(0)) { $0 + $1.outputTicks }
        let rightOut = rightPlan.segments.reduce(Int64(0)) { $0 + $1.outputTicks }
        XCTAssertEqual(leftOut, 70 * 3000)
        XCTAssertEqual(rightOut, 80 * 3000)

        // Zdroj obou polovin dohromady = zdroj celku (křivka je táž), až na
        // kvantizaci sourceStart pravé poloviny — viz komentář u
        // testSplitARejoinRampovanehoKlipu.
        let leftSrc = leftPlan.segments.reduce(Int64(0)) { $0 + $1.sourceDurationTicks }
        let rightSrc = rightPlan.segments.reduce(Int64(0)) { $0 + $1.sourceDurationTicks }
        let whole = f.project.sourceConsumption(of: f.clip(id)!)
            .converted(to: SourceTime.projectTimescale).value
        XCTAssertLessThanOrEqual(abs(leftSrc + rightSrc - whole), 8)
    }
}

// MARK: - Podíl duplikovaných snímků (fáze 18, modul 10)

final class DuplicatedFrameShareTests: XCTestCase {

    /// Zdroj na úrovni výstupu (30 fps → základna 30 fps): klasický ramp
    /// 1× → 0,25× → 1× má průměrnou rychlost 0,625, takže se duplikuje
    /// 37,5 % snímků. Číslo z CLAUDE.md, naměřené na reálných klipech.
    func testShareOnSourceAtOutputRate() throws {
        var project = Project.empty()
        let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/a.mp4"),
                          duration: SourceTime(seconds: 20),
                          measuredFrameRate: 30,
                          hasVideo: true, hasAudio: false)
        project.addAsset(asset)
        var clip = try project.makeClip(assetID: asset.id)
        try project.insert(clip, onTrack: project.timeline.tracks[0].id)
        try project.setSpeedRamp(clipID: clip.id,
                                 ramp: .classicSlowMotion(from: .zero,
                                                          spanning: SourceTime(seconds: 5),
                                                          slowSpeed: 0.25))
        // ⚠️ Klip se musí zkrátit na to, co křivka vydá. Ramp přes 5 s zdroje
        // dá při průměrné rychlosti 0,625 osm sekund výstupu, tedy 240 snímků;
        // na delším klipu už rampa neplatí (jede 1×) a průměr se tím rozředí —
        // první verze testu čekala 37,5 % na 600snímkovém klipu a dostala
        // 14,9 %, což byl správný výsledek špatně postavené otázky.
        try project.trimEnd(clipID: clip.id, to: Frames(240))
        clip = try XCTUnwrap(project.timeline.clip(clip.id))

        let share = try XCTUnwrap(project.duplicatedFrameShare(of: clip))
        XCTAssertEqual(share, 0.375, accuracy: 0.02)
    }

    /// Zdroj 120 fps při výstupu 30 fps utáhne 0,25× beze zbytku —
    /// duplikovat se nesmí nic.
    func testNoDuplicationWhenSourceHasEnoughFrames() throws {
        var project = Project.empty()
        let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/b.mp4"),
                          duration: SourceTime(seconds: 20),
                          measuredFrameRate: 120,
                          hasVideo: true, hasAudio: false)
        project.addAsset(asset)
        var clip = try project.makeClip(assetID: asset.id)
        try project.insert(clip, onTrack: project.timeline.tracks[0].id)
        try project.setSpeedRamp(clipID: clip.id,
                                 ramp: .classicSlowMotion(from: .zero,
                                                          spanning: SourceTime(seconds: 5),
                                                          slowSpeed: 0.25))
        clip = try XCTUnwrap(project.timeline.clip(clip.id))

        XCTAssertEqual(try XCTUnwrap(project.duplicatedFrameShare(of: clip)), 0, accuracy: 0.001)
    }

    /// Klip bez rampy nemá co hlásit — `nil`, ne nula. Nula by v UI znamenala
    /// „spočítáno a je to v pořádku", což je jiná informace než „netýká se".
    func testNilWithoutRamp() throws {
        var project = Project.empty()
        let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/c.mp4"),
                          duration: SourceTime(seconds: 20),
                          measuredFrameRate: 60,
                          hasVideo: true, hasAudio: false)
        project.addAsset(asset)
        let clip = try project.makeClip(assetID: asset.id)
        try project.insert(clip, onTrack: project.timeline.tracks[0].id)
        XCTAssertNil(project.duplicatedFrameShare(of: clip))
    }
}
