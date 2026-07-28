import XCTest
@testable import TimelineModel

/// Přechody na střihu (fáze 10, modul 1).
///
/// Prostředí většiny testů: asset 10 s (= 300 snímků osy), na V1 dva sousedi
/// L = [0, 100) se zdrojem od 0 a R = [100, 200) se zdrojem od snímku 120.
/// Zdrojové přesahy: za koncem L zbývá 200 snímků, před začátkem R je 120.
final class TransitionTests: XCTestCase {

    // MARK: Prostředí

    private struct Cut {
        var fx: Fixture
        let left: ClipID
        let right: ClipID

        init(leftDuration: Int = 100, rightDuration: Int = 100,
             leftSourceStart: Int = 0, rightSourceStart: Int = 120) throws {
            fx = Fixture()
            left = try fx.addClip(start: 0, duration: leftDuration,
                                  sourceStartFrames: leftSourceStart)
            right = try fx.addClip(start: leftDuration, duration: rightDuration,
                                   sourceStartFrames: rightSourceStart)
        }
    }

    // MARK: Dělení oblasti

    func testDeleniOblastiPredAZaStrihem() {
        let t = Transition(kind: .dipToBlack, leftClipID: ClipID(), rightClipID: ClipID(),
                           duration: Frames(1))
        XCTAssertEqual(t.framesBeforeCut, Frames(0))
        XCTAssertEqual(t.framesAfterCut, Frames(1))

        let sudy = Transition(kind: .dipToBlack, leftClipID: ClipID(), rightClipID: ClipID(),
                              duration: Frames(30))
        XCTAssertEqual(sudy.framesBeforeCut, Frames(15))
        XCTAssertEqual(sudy.framesAfterCut, Frames(15))

        // Lichá délka: snímek navíc jde ZA střih — pevně, ne podle nálady.
        let lichy = Transition(kind: .dipToBlack, leftClipID: ClipID(), rightClipID: ClipID(),
                               duration: Frames(31))
        XCTAssertEqual(lichy.framesBeforeCut, Frames(15))
        XCTAssertEqual(lichy.framesAfterCut, Frames(16))
    }

    // MARK: Nastavení přechodu

    func testProlinackaNaStrihuProjdeAValidaceMlci() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        XCTAssertValid(c.fx.project)
        let t = c.fx.project.transition(betweenLeft: c.left, andRight: c.right)
        XCTAssertEqual(t?.id, id)
        XCTAssertEqual(t?.duration, Frames(30))
        // Oblast: střih na 100, D=30 → [85, 115).
        let region = c.fx.project.transitionRegion(of: id)
        XCTAssertEqual(region?.start, Frames(85))
        XCTAssertEqual(region?.end, Frames(115))
    }

    func testPrepsaniNaTemzeStrihuZachovaID() throws {
        var c = try Cut()
        let id1 = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                 betweenLeft: c.left, andRight: c.right)
        let id2 = try c.fx.project.setTransition(.dipToBlack, duration: Frames(10),
                                                 betweenLeft: c.left, andRight: c.right)
        XCTAssertEqual(id1, id2)
        let track = c.fx.project.timeline.tracks[0]
        XCTAssertEqual(track.transitions.count, 1)
        XCTAssertEqual(track.transitions[0].kind, .dipToBlack)
        XCTAssertValid(c.fx.project)
    }

    func testNesousediciKlipyOdmitne() throws {
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 100)
        let b = try fx.addClip(start: 150, duration: 100) // mezera 50
        XCTAssertThrowsUnchanged(&fx.project, .notAdjacent(a, b)) {
            try $0.setTransition(.crossDissolve, duration: Frames(10),
                                 betweenLeft: a, andRight: b)
        }
    }

    func testSpatnyDruhNaStopuOdmitne() throws {
        var c = try Cut()
        XCTAssertThrowsUnchanged(&c.fx.project,
                                 .wrongTrackKind(expected: .audio, got: .video)) {
            try $0.setTransition(.audioCrossfade, duration: Frames(10),
                                 betweenLeft: c.left, andRight: c.right)
        }
    }

    func testNulovaDelkaOdmitne() throws {
        var c = try Cut()
        XCTAssertThrowsUnchanged(&c.fx.project, .zeroLength) {
            try $0.setTransition(.crossDissolve, duration: Frames(0),
                                 betweenLeft: c.left, andRight: c.right)
        }
    }

    func testCrossfadeNaZvukoveStopeProjde() throws {
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 100, on: fx.a1)
        let b = try fx.addClip(start: 100, duration: 100, sourceStartFrames: 120, on: fx.a1)
        try fx.project.setTransition(.audioCrossfade, duration: Frames(20),
                                     betweenLeft: a, andRight: b)
        XCTAssertValid(fx.project)
    }

    // MARK: Největší legální délka

    func testMaxDelkuOmezujeZdrojovyPresah() throws {
        // Pravý klip má před sebou jen 10 snímků zdroje → před střih smí
        // nejvýš 10 → největší prolínačka 2·10+1 = 21 (rameno navíc jde za střih).
        var c = try Cut(rightSourceStart: 10)
        let maxD = c.fx.project.maxTransitionDuration(kind: .crossDissolve,
                                                      betweenLeft: c.left, andRight: c.right)
        XCTAssertEqual(maxD, Frames(21))
        try c.fx.project.setTransition(.crossDissolve, duration: Frames(21),
                                       betweenLeft: c.left, andRight: c.right)
        XCTAssertValid(c.fx.project)

        try c.fx.project.removeTransition(
            id: c.fx.project.transition(betweenLeft: c.left, andRight: c.right)!.id)
        XCTAssertThrowsUnchanged(&c.fx.project,
                                 .transitionTooLong(maxDuration: Frames(21))) {
            try $0.setTransition(.crossDissolve, duration: Frames(22),
                                 betweenLeft: c.left, andRight: c.right)
        }
    }

    func testZatmivackaNepotrebujePresahyProlinackaAno() throws {
        // Levý klip končí přesně na konci zdroje, pravý začíná přesně na
        // jeho začátku — pro prolínačku není ANI SNÍMEK, zatmívačka jede.
        var c = try Cut(leftSourceStart: 200, rightSourceStart: 0)
        XCTAssertEqual(c.fx.project.maxTransitionDuration(kind: .crossDissolve,
                                                          betweenLeft: c.left, andRight: c.right),
                       .zero)
        XCTAssertThrowsUnchanged(&c.fx.project,
                                 .transitionTooLong(maxDuration: .zero)) {
            try $0.setTransition(.crossDissolve, duration: Frames(2),
                                 betweenLeft: c.left, andRight: c.right)
        }
        XCTAssertEqual(c.fx.project.maxTransitionDuration(kind: .dipToBlack,
                                                          betweenLeft: c.left, andRight: c.right),
                       Frames(200))
        try c.fx.project.setTransition(.dipToBlack, duration: Frames(30),
                                       betweenLeft: c.left, andRight: c.right)
        XCTAssertValid(c.fx.project)
    }

    func testSousedniPrechodyseNesmiPrekryvat() throws {
        // Tři klipy, prostřední jen 20 snímků. Zatmívačka na prvním střihu
        // zabírá z prostředního 10 snímků → na druhý střih zbývá před hranu
        // jen 10 → max 2·10+1 = 21.
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 100)
        let m = try fx.addClip(start: 100, duration: 20, sourceStartFrames: 120)
        let b = try fx.addClip(start: 120, duration: 100, sourceStartFrames: 150)
        try fx.project.setTransition(.dipToBlack, duration: Frames(20),
                                     betweenLeft: a, andRight: m)
        let maxD = fx.project.maxTransitionDuration(kind: .dipToBlack,
                                                    betweenLeft: m, andRight: b)
        XCTAssertEqual(maxD, Frames(21))
        try fx.project.setTransition(.dipToBlack, duration: Frames(21),
                                     betweenLeft: m, andRight: b)
        XCTAssertValid(fx.project)
        // O snímek víc už by se oblasti dotkly přes sebe.
        XCTAssertThrowsUnchanged(&fx.project,
                                 .transitionTooLong(maxDuration: Frames(21))) {
            try $0.setTransition(.dipToBlack, duration: Frames(23),
                                 betweenLeft: m, andRight: b)
        }
    }

    // MARK: Mazání a změna délky

    func testRemoveASetDurationDrziID() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        try c.fx.project.setTransitionDuration(id: id, to: Frames(12))
        XCTAssertEqual(c.fx.project.transition(id: id)?.duration, Frames(12))
        XCTAssertValid(c.fx.project)

        try c.fx.project.removeTransition(id: id)
        XCTAssertNil(c.fx.project.transition(id: id))
        XCTAssertThrowsUnchanged(&c.fx.project, .transitionNotFound(id)) {
            try $0.removeTransition(id: id)
        }
    }

    // MARK: Rampa × přechod — zákaz oběma směry

    func testPrechodNaRampovanemStrihuOdmitne() throws {
        var c = try Cut()
        try c.fx.project.setSpeedRamp(clipID: c.left,
                                      ramp: SpeedRamp(nodes: [
                                          SpeedNode(sourceTime: .zero, speed: 0.5),
                                      ]))
        XCTAssertThrowsUnchanged(&c.fx.project, .transitionOnRampedCut) {
            try $0.setTransition(.crossDissolve, duration: Frames(10),
                                 betweenLeft: c.left, andRight: c.right)
        }
        XCTAssertEqual(c.fx.project.maxTransitionDuration(kind: .crossDissolve,
                                                          betweenLeft: c.left, andRight: c.right),
                       .zero)
    }

    func testRampaNaKlipuSPrechodemOdmitne() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        XCTAssertThrowsUnchanged(&c.fx.project, .blockedByTransition(id)) {
            try $0.setSpeedRamp(clipID: $0.timeline.clip(c.left)!.id,
                                ramp: SpeedRamp(nodes: [
                                    SpeedNode(sourceTime: .zero, speed: 0.5),
                                ]))
        }
        // Po smazání přechodu rampa projde.
        try c.fx.project.removeTransition(id: id)
        try c.fx.project.setSpeedRamp(clipID: c.left,
                                      ramp: SpeedRamp(nodes: [
                                          SpeedNode(sourceTime: .zero, speed: 0.5),
                                      ]))
        XCTAssertValid(c.fx.project)
    }

    // MARK: Zánik střihu → zánik přechodu

    func testSmazaniKlipuBerePrechodSSebou() throws {
        var c = try Cut()
        try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                       betweenLeft: c.left, andRight: c.right)
        try c.fx.project.remove(clipID: c.left)
        XCTAssertNil(c.fx.project.transition(betweenLeft: c.left, andRight: c.right))
        XCTAssertValid(c.fx.project)
    }

    func testPresunKlipuBerePrechodSSebou() throws {
        var c = try Cut()
        try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                       betweenLeft: c.left, andRight: c.right)
        try c.fx.project.move(clipID: c.right, toTrack: c.fx.v1, start: Frames(250))
        XCTAssertNil(c.fx.project.transition(betweenLeft: c.left, andRight: c.right))
        XCTAssertValid(c.fx.project)
    }

    func testTrimVytvoriMezeruAPrechodZanika() throws {
        var c = try Cut()
        try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                       betweenLeft: c.left, andRight: c.right)
        try c.fx.project.trimEnd(clipID: c.left, to: Frames(90))
        XCTAssertNil(c.fx.project.transition(betweenLeft: c.left, andRight: c.right))
        XCTAssertValid(c.fx.project)
        // Zpětné natažení přechod nevzkřísí — vrátí ho jen undo.
        try c.fx.project.trimEnd(clipID: c.left, to: Frames(100))
        XCTAssertNil(c.fx.project.transition(betweenLeft: c.left, andRight: c.right))
    }

    func testRippleRemoveProstredkuMazeJehoPrechodyAOstatniPosune() throws {
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 80)
        let b = try fx.addClip(start: 80, duration: 60, sourceStartFrames: 90)
        let c = try fx.addClip(start: 140, duration: 60, sourceStartFrames: 160)
        let d = try fx.addClip(start: 200, duration: 60, sourceStartFrames: 230)
        try fx.project.setTransition(.dipToBlack, duration: Frames(10),
                                     betweenLeft: a, andRight: b)
        try fx.project.setTransition(.dipToBlack, duration: Frames(10),
                                     betweenLeft: b, andRight: c)
        let survivor = try fx.project.setTransition(.dipToBlack, duration: Frames(10),
                                                    betweenLeft: c, andRight: d)
        try fx.project.rippleRemove(clipID: b)
        // Přechody na střihách smazaného klipu zanikly…
        XCTAssertNil(fx.project.transition(betweenLeft: a, andRight: b))
        XCTAssertNil(fx.project.transition(betweenLeft: b, andRight: c))
        // …ale přechod mezi dvěma POSUNUTÝMI sousedy jede dál, i s oblastí.
        XCTAssertNotNil(fx.project.transition(id: survivor))
        XCTAssertEqual(fx.project.transitionRegion(of: survivor)?.start, Frames(135))
        XCTAssertValid(fx.project)
    }

    func testCloseGapUtrhnePrechodNaPravemStrihu() throws {
        // closeGap přitáhne JEN následující klip — jeho pravý soused zůstává,
        // takže přechod mezi nimi ztrácí střih a zaniká.
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 80)
        let b = try fx.addClip(start: 100, duration: 60, sourceStartFrames: 90)
        let c = try fx.addClip(start: 160, duration: 60, sourceStartFrames: 160)
        try fx.project.setTransition(.dipToBlack, duration: Frames(10),
                                     betweenLeft: b, andRight: c)
        try fx.project.closeGap(afterClipID: a)
        XCTAssertNil(fx.project.transition(betweenLeft: b, andRight: c))
        XCTAssertValid(fx.project)
    }

    // MARK: Živý střih → operace se odmítá

    func testTrimZLevaPodRamenoPrechoduSeOdmitne() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        // Oblast [85, 115): levý klip zkrácený zepředu na [90, 100) by byl
        // kratší než rameno před střihem. Střih přitom žije — odmítnout.
        XCTAssertThrowsUnchanged(&c.fx.project, .blockedByTransition(id)) {
            try $0.trimStart(clipID: c.left, to: Frames(90))
        }
        // Trim, který ramenu místo nechá, projde.
        try c.fx.project.trimStart(clipID: c.left, to: Frames(80))
        XCTAssertNotNil(c.fx.project.transition(id: id))
        XCTAssertValid(c.fx.project)
    }

    func testTrimZPravaPodRamenoPrechoduSeOdmitne() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        XCTAssertThrowsUnchanged(&c.fx.project, .blockedByTransition(id)) {
            try $0.trimEnd(clipID: c.right, to: Frames(110))
        }
        try c.fx.project.trimEnd(clipID: c.right, to: Frames(120))
        XCTAssertNotNil(c.fx.project.transition(id: id))
        XCTAssertValid(c.fx.project)
    }

    func testSlipPodZdrojovyPresahSeOdmitne() throws {
        // Pravý klip má před sebou 120 snímků zdroje, prolínačka potřebuje 15.
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        // Slip o −105 nechá přesně 15 → projde.
        try c.fx.project.slip(clipID: c.right, by: Frames(-105))
        XCTAssertValid(c.fx.project)
        // Ještě o snímek dál by přesah padl pod 15 → odmítnout.
        XCTAssertThrowsUnchanged(&c.fx.project, .blockedByTransition(id)) {
            try $0.slip(clipID: c.right, by: Frames(-1))
        }
    }

    func testRollPodPrechodemJedeSHranici() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        try c.fx.project.rollEdit(leftID: c.left, rightID: c.right, to: Frames(150))
        // Přechod přežil a oblast se posunula se střihem: [135, 165).
        XCTAssertEqual(c.fx.project.transitionRegion(of: id)?.start, Frames(135))
        XCTAssertValid(c.fx.project)
        // Roll, po kterém by pravému klipu zbylo míň než rameno za střihem
        // (15), se odmítá: hranice 190 → pravý [190, 200) má jen 10.
        XCTAssertThrowsUnchanged(&c.fx.project, .blockedByTransition(id)) {
            try $0.rollEdit(leftID: c.left, rightID: c.right, to: Frames(190))
        }
    }

    // MARK: Split a join

    func testSplitVedleOblastiPrepojiPrechodNaPravouPolovinu() throws {
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 100)
        let b = try fx.addClip(start: 100, duration: 100, sourceStartFrames: 120)
        let id = try fx.project.setTransition(.crossDissolve, duration: Frames(20),
                                              betweenLeft: a, andRight: b)
        // Řez levého klipu daleko od oblasti [90, 110).
        let (_, rightHalf) = try fx.project.split(clipID: a, at: Frames(50))
        // Přechod teď sedí mezi PRAVOU polovinou a b.
        XCTAssertEqual(fx.project.transition(id: id)?.leftClipID, rightHalf)
        XCTAssertEqual(fx.project.transitionRegion(of: id)?.start, Frames(90))
        XCTAssertValid(fx.project)
    }

    func testSplitUvnitrOblastiSeOdmitne() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        // Řez na 110 vede oblastí [85, 115) — polovina [100, 110) by byla
        // kratší než rameno za střihem.
        XCTAssertThrowsUnchanged(&c.fx.project, .blockedByTransition(id)) {
            try $0.split(clipID: c.right, at: Frames(110))
        }
    }

    func testJoinSmazeVnitrniPrechodAPrepojiVnejsi() throws {
        var fx = Fixture()
        let a = try fx.addClip(start: 0, duration: 200)
        let b = try fx.addClip(start: 200, duration: 80, sourceStartFrames: 210)
        let (l, r) = try fx.project.split(clipID: a, at: Frames(100))
        let inner = try fx.project.setTransition(.dipToBlack, duration: Frames(10),
                                                 betweenLeft: l, andRight: r)
        let outer = try fx.project.setTransition(.dipToBlack, duration: Frames(10),
                                                 betweenLeft: r, andRight: b)
        try fx.project.join(leftID: l, rightID: r)
        XCTAssertNil(fx.project.transition(id: inner))
        XCTAssertEqual(fx.project.transition(id: outer)?.leftClipID, l)
        XCTAssertValid(fx.project)
    }

    // MARK: Serializace

    func testPrechodPrezijeUlozeniAOtevreni() throws {
        var c = try Cut()
        try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                       betweenLeft: c.left, andRight: c.right)
        let file = ProjectFile(project: c.fx.project, name: "test")
        let decoded = try ProjectFile.decode(file.encoded())
        XCTAssertEqual(decoded.project, c.fx.project)
        XCTAssertValid(decoded.project)
    }

    func testStopaBezPoleTransitionsSeNacte() throws {
        // Přesně takhle vypadají stopy v projektech uložených před fází 10 —
        // pole `transitions` neexistuje a soubor se přesto musí načíst.
        let json = """
        {"clips": [], "id": "T-stara", "kind": "video", "name": "V1"}
        """
        let track = try JSONDecoder().decode(Track.self, from: Data(json.utf8))
        XCTAssertTrue(track.transitions.isEmpty)
        XCTAssertEqual(track.name, "V1")
    }

    // MARK: Ručně rozbité stavy — validace je hlásí

    func testValidaceHlasiPrechodBezStrihu() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        // Rozbít napřímo, mimo operace (ty by to nedovolily).
        var tracks = c.fx.project.timeline.tracks
        tracks[0].clips[1].timelineStart = Frames(150)
        c.fx.project.timeline.tracks = tracks
        XCTAssertTrue(c.fx.project.validate().contains(.transitionWithoutCut(id)))
    }

    func testValidaceHlasiChybejiciPresahIRampu() throws {
        var c = try Cut()
        let id = try c.fx.project.setTransition(.crossDissolve, duration: Frames(30),
                                                betweenLeft: c.left, andRight: c.right)
        var broken = c.fx.project
        var tracks = broken.timeline.tracks
        // Zdroj pravého klipu posunutý na začátek souboru → přesah 0 < 15.
        tracks[0].clips[1].sourceStart = .zero
        broken.timeline.tracks = tracks
        XCTAssertTrue(broken.validate().contains(.transitionExceedsSource(id)))

        var ramped = c.fx.project
        tracks = ramped.timeline.tracks
        tracks[0].clips[0].speedRamp = SpeedRamp(nodes: [
            SpeedNode(sourceTime: .zero, speed: 0.5),
        ])
        ramped.timeline.tracks = tracks
        XCTAssertTrue(ramped.validate().contains(.transitionOnRampedCut(id)))
    }

    // MARK: Property test — setTransition na maximu vždy projde, nad ním nikdy

    func testNahodneStrihyDrziMaxDelku() throws {
        var rng = SeededRandom(seed: 0xF10_2026)
        for round in 0..<40 {
            let leftDur = Int.random(in: 1...60, using: &rng)
            let rightDur = Int.random(in: 1...60, using: &rng)
            let leftSrc = Int.random(in: 0...100, using: &rng)
            let rightSrc = Int.random(in: 0...100, using: &rng)
            let kind: TransitionKind = Bool.random(using: &rng) ? .crossDissolve : .dipToBlack

            var c = try Cut(leftDuration: leftDur, rightDuration: rightDur,
                            leftSourceStart: leftSrc, rightSourceStart: rightSrc)
            let maxD = c.fx.project.maxTransitionDuration(kind: kind,
                                                          betweenLeft: c.left,
                                                          andRight: c.right)
            let seedInfo = "kolo \(round), seed \(rng.seed)"

            if maxD.count >= 1 {
                XCTAssertNoThrow(
                    try c.fx.project.setTransition(kind, duration: maxD,
                                                   betweenLeft: c.left, andRight: c.right),
                    "maximum musí projít — \(seedInfo)")
                XCTAssertValid(c.fx.project)
                try c.fx.project.removeTransition(
                    id: c.fx.project.transition(betweenLeft: c.left, andRight: c.right)!.id)
            }
            XCTAssertThrowsError(
                try c.fx.project.setTransition(kind, duration: maxD + Frames(1),
                                               betweenLeft: c.left, andRight: c.right),
                "nad maximem musí spadnout — \(seedInfo)")
        }
    }
}
