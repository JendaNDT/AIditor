//
//  TransitionTrimStopTests.swift
//  TimelineModel — Projekt Krása
//
//  Fáze 16, modul 3: zarážka trimu o rameno přechodu.
//
//  Kontrakt, který se tu vymáhá: **náhled tažení se zastaví PŘESNĚ tam,
//  kam operace ještě pustí.** Testy proto nekontrolují vypočtené číslo
//  proti jinému vypočtenému číslu, ale proti skutečnému chování
//  `trimStart`/`trimEnd` — hledáním hrany, kde operace začne odmítat.
//

import XCTest
@testable import TimelineModel

final class TransitionTrimStopTests: XCTestCase {

    /// Tři sousedi na V1: A = [0,100), B = [100,200), C = [200,300),
    /// zdroje s přesahy na obě strany. Přechody se sázejí na střihy A|B
    /// a B|C, takže prostřední klip B má rameno na obou hranách.
    private func makeFixture() throws -> (f: Fixture, a: ClipID, b: ClipID, c: ClipID) {
        var f = Fixture(seconds: 40)
        let a = try f.addClip(start: 0, duration: 100, sourceStartFrames: 0)
        let b = try f.addClip(start: 100, duration: 100, sourceStartFrames: 300)
        let c = try f.addClip(start: 200, duration: 100, sourceStartFrames: 600)
        return (f, a, b, c)
    }

    /// Nejzazší pozice, na kterou trim začátku klipu SKUTEČNĚ projde.
    private func realTrimStartLimit(_ project: Project, _ clipID: ClipID) -> Frames {
        guard let clip = project.timeline.clip(clipID) else { return .zero }
        var best = clip.timelineStart
        for candidate in clip.timelineStart.count..<clip.timelineEnd.count {
            var copy = project
            if (try? copy.trimStart(clipID: clipID, to: Frames(candidate))) != nil,
               copy.validate().isEmpty {
                best = Frames(candidate)
            }
        }
        return best
    }

    private func realTrimEndLimit(_ project: Project, _ clipID: ClipID) -> Frames {
        guard let clip = project.timeline.clip(clipID) else { return .zero }
        var best = clip.timelineEnd
        for candidate in stride(from: clip.timelineEnd.count,
                                through: clip.timelineStart.count + 1, by: -1) {
            var copy = project
            if (try? copy.trimEnd(clipID: clipID, to: Frames(candidate))) != nil,
               copy.validate().isEmpty {
                best = Frames(candidate)
            }
        }
        return best
    }

    /// Kam dojede duch při tažení hodně za mez.
    private func previewLimit(_ project: Project, _ clipID: ClipID,
                              zone: TimelineHit.Zone) -> Frames {
        var interaction = TimelineInteraction(geometry: TimelineGeometry(pointsPerFrame: 1))
        guard let at = project.timeline.locate(clipID) else { return .zero }
        let hit = TimelineHit(clipID: clipID,
                          trackID: project.timeline.tracks[at.trackIndex].id,
                          zone: zone,
                          offsetInClip: .zero)
        interaction.begin(hit: hit, in: project)
        // Tažení daleko za mez (zóna určuje směr).
        let x: Double = zone == .leadingEdge ? 100_000 : -100_000
        let preview = interaction.preview(atX: x, y: 0, in: project, snapping: false)
        guard let preview else { return .zero }
        return zone == .leadingEdge ? preview.start : preview.start + preview.duration
    }

    // MARK: - Zarážka sedí na skutečné mezi operace

    func testTrimStartStopsAtTransitionArm() throws {
        var (f, a, b, _) = try makeFixture()
        // Prolínačka 30 snímků na střihu B|C: 15 snímků leží v B před
        // střihem — o ně se trim začátku B musí opřít.
        try f.project.setTransition(.crossDissolve, duration: Frames(30),
                                    betweenLeft: b, andRight: f.clips(on: f.v1)[2].id)
        _ = a

        let real = realTrimStartLimit(f.project, b)
        let preview = previewLimit(f.project, b, zone: .leadingEdge)
        XCTAssertEqual(preview, real,
                       "duch se musí zastavit tam, kam trim ještě pustí")
        XCTAssertEqual(preview, Frames(185), "200 − 15 (rameno před střihem)")
    }

    func testTrimEndStopsAtTransitionArm() throws {
        var (f, _, b, c) = try makeFixture()
        // Prolínačka 30 na střihu A|B: 15 snímků leží v B za střihem.
        try f.project.setTransition(.crossDissolve, duration: Frames(30),
                                    betweenLeft: f.clips(on: f.v1)[0].id, andRight: b)
        _ = c

        let real = realTrimEndLimit(f.project, b)
        let preview = previewLimit(f.project, b, zone: .trailingEdge)
        XCTAssertEqual(preview, real)
        XCTAssertEqual(preview, Frames(115), "100 + 15 (rameno za střihem)")
    }

    func testWithoutTransitionNothingChanges() throws {
        let (f, _, b, _) = try makeFixture()
        // Bez přechodu drží meze zdroj a sousedi — zarážka nic nemění.
        XCTAssertEqual(previewLimit(f.project, b, zone: .leadingEdge),
                       realTrimStartLimit(f.project, b))
        XCTAssertEqual(previewLimit(f.project, b, zone: .trailingEdge),
                       realTrimEndLimit(f.project, b))
    }

    func testArmsReportedForBothEdges() throws {
        var (f, a, b, c) = try makeFixture()
        try f.project.setTransition(.crossDissolve, duration: Frames(30),
                                    betweenLeft: a, andRight: b)
        try f.project.setTransition(.dipToBlack, duration: Frames(21),
                                    betweenLeft: b, andRight: c)
        let arms = f.project.transitionArms(clipID: b)
        XCTAssertEqual(arms.leading, Frames(15), "za střihem A|B")
        XCTAssertEqual(arms.trailing, Frames(10), "před střihem B|C (⌊21/2⌋)")
        // Krajní klipy mají rameno jen na jedné straně.
        XCTAssertEqual(f.project.transitionArms(clipID: a).leading, .zero)
        XCTAssertEqual(f.project.transitionArms(clipID: c).trailing, .zero)
    }
}
