import XCTest
import Foundation
@testable import TimelineModel

/// Prostředí pro testy: projekt s jedním assetem a třemi stopami (V1, A1, A2).
struct Fixture {
    var project: Project
    let assetID: AssetID
    let v1: TrackID
    let a1: TrackID
    let a2: TrackID

    /// - Parameters:
    ///   - seconds: délka assetu ve zdrojovém čase
    ///   - hasVideo/hasAudio: pro testy druhu stopy
    init(seconds: Double = 10, hasVideo: Bool = true, hasAudio: Bool = true) {
        var p = Project.empty()
        let asset = Asset(originalURL: URL(fileURLWithPath: "/tmp/test.mov"),
                          duration: SourceTime(seconds: seconds),
                          measuredFrameRate: 60,
                          hasVideo: hasVideo,
                          hasAudio: hasAudio)
        p.addAsset(asset)
        self.project = p
        self.assetID = asset.id
        self.v1 = p.timeline.tracks[0].id
        self.a1 = p.timeline.tracks[1].id
        self.a2 = p.timeline.tracks[2].id
    }

    /// Vloží klip na V1 a vrátí jeho ID.
    @discardableResult
    mutating func addClip(start: Int, duration: Int, sourceStartFrames: Int = 0,
                          on track: TrackID? = nil) throws -> ClipID {
        let clip = Clip(assetID: assetID,
                        timelineStart: Frames(start),
                        duration: Frames(duration),
                        sourceStart: project.timeline.sourceTime(Frames(sourceStartFrames)))
        try project.insert(clip, onTrack: track ?? v1)
        return clip.id
    }

    func clip(_ id: ClipID) -> Clip? { project.timeline.clip(id) }

    func clips(on track: TrackID) -> [Clip] {
        project.timeline.track(id: track)?.clips ?? []
    }
}

/// Zkontroluje, že projekt splňuje všechny invarianty.
func XCTAssertValid(_ project: Project, file: StaticString = #filePath, line: UInt = #line) {
    let violations = project.validate()
    XCTAssertTrue(violations.isEmpty,
                  "porušené invarianty: \(violations)", file: file, line: line)
}

/// Zkontroluje, že volání hodí očekávanou chybu a projekt zůstane nezměněný.
func XCTAssertThrowsUnchanged(_ project: inout Project,
                              _ expected: TimelineError? = nil,
                              file: StaticString = #filePath, line: UInt = #line,
                              _ body: (inout Project) throws -> Void) {
    let before = project
    do {
        try body(&project)
        XCTFail("očekávala se chyba, ale operace prošla", file: file, line: line)
    } catch let error as TimelineError {
        if let expected {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
        XCTAssertEqual(project, before,
                       "operace selhala, ale projekt se změnil", file: file, line: line)
    } catch {
        XCTFail("neočekávaná chyba \(error)", file: file, line: line)
    }
}

/// Deterministický generátor pro property testy. Semínko se tiskne při selhání,
/// aby šel červený test zopakovat — nereprodukovatelný červený test je horší
/// než žádný.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    let seed: UInt64
    init(seed: UInt64) {
        self.seed = seed
        self.state = seed &* 6364136223846793005 &+ 1442695040888963407
    }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
