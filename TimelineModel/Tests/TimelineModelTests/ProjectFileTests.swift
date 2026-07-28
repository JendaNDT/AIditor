//
//  ProjectFileTests.swift
//  TimelineModel — Projekt Krása
//
//  Formát souboru .projektkrasa: round-trip beze ztráty, deterministické
//  bajty, jasné odmítnutí novější verze.
//

import XCTest
@testable import TimelineModel

final class ProjectFileTests: XCTestCase {

    /// Projekt se vším, co umí nést: svázané klipy, rampa, proxy, trim.
    private func richProject() throws -> Project {
        var f = Fixture(seconds: 10)
        let (video, audio) = try f.project.makeLinkedClips(assetID: f.assetID)
        try f.project.insertLinked(video: video, onVideoTrack: f.v1,
                                   audio: audio, onAudioTrack: f.a1)
        try f.project.setSpeedRamp(clipID: video.id, ramp:
            .classicSlowMotion(from: .zero, spanning: SourceTime(seconds: 3.125)))
        try f.project.split(clipID: video.id, at: Frames(70))
        f.project.usesProxies = true
        var asset = f.project.assets[0]
        asset.proxyURL = URL(fileURLWithPath: "/tmp/proxy.mov")
        asset.bookmark = Data([1, 2, 3])
        f.project.addAsset(asset)
        return f.project
    }

    func testRoundTripBezeZtraty() throws {
        let project = try richProject()
        let file = ProjectFile(project: project, name: "Svatba test")
        let decoded = try ProjectFile.decode(try file.encoded())

        XCTAssertEqual(decoded.project, project,
                       "co se uloží, to se přečte — do posledního ticku a uzlu")
        XCTAssertEqual(decoded.name, "Svatba test")
        XCTAssertEqual(decoded.formatVersion, ProjectFile.currentFormatVersion)
        XCTAssertTrue(decoded.project.validate().isEmpty)
    }

    func testStejnyProjektDaStejneBajty() throws {
        let project = try richProject()
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let a = try ProjectFile(project: project, name: "X",
                                createdAt: stamp, modifiedAt: stamp).encoded()
        let b = try ProjectFile(project: project, name: "X",
                                createdAt: stamp, modifiedAt: stamp).encoded()
        XCTAssertEqual(a, b, "deterministický zápis — jinak nejde poznat skutečná změna")
    }

    func testNovejsiVerzeSeOdmitneSrozumitelne() throws {
        let file = ProjectFile(project: Project.empty(), name: "X")
        var text = String(data: try file.encoded(), encoding: .utf8)!
        text = text.replacingOccurrences(
            of: "\"formatVersion\" : \(ProjectFile.currentFormatVersion)",
            with: "\"formatVersion\" : 999")
        XCTAssertThrowsError(try ProjectFile.decode(Data(text.utf8))) { error in
            XCTAssertEqual(error as? ProjectFileError,
                           .unsupportedVersion(found: 999,
                                               supported: ProjectFile.currentFormatVersion))
        }
    }

    func testRozbityObsahHlasiPoskozeni() {
        XCTAssertThrowsError(try ProjectFile.decode(Data("nesmysl".utf8))) { error in
            guard case .corrupted = error as? ProjectFileError else {
                return XCTFail("čekala se .corrupted, přišlo \(error)")
            }
        }
    }
}
