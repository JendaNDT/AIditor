import XCTest
@testable import TimelineModel

/// Vkládání, mazání, ripple, přepis, split, join, přesun.
/// Testy 9–29 a 42–48 z návrhu.
final class OperationTests: XCTestCase {

    // MARK: Vkládání a mazání (9–21)

    // 9.
    func testInsertIntoEmptyTrack() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        XCTAssertEqual(f.clips(on: f.v1).count, 1)
        XCTAssertValid(f.project)
    }

    // 10.
    func testInsertIntoExactGap() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 200, duration: 100)
        try f.addClip(start: 100, duration: 100)
        XCTAssertEqual(f.clips(on: f.v1).map(\.timelineStart.count), [0, 100, 200])
        XCTAssertValid(f.project)
    }

    // 11.
    func testInsertOneFrameTooLongOverlaps() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 200, duration: 100)
        XCTAssertThrowsUnchanged(&f.project) { p in
            let clip = Clip(assetID: f.assetID, timelineStart: Frames(100),
                            duration: Frames(101), sourceStart: .zero)
            try p.insert(clip, onTrack: f.v1)
        }
    }

    func testOverlapErrorCarriesNearestLegalPosition() throws {
        var f = Fixture()
        try f.addClip(start: 100, duration: 100)
        let clip = Clip(assetID: f.assetID, timelineStart: Frames(150),
                        duration: Frames(50), sourceStart: .zero)
        do {
            try f.project.insert(clip, onTrack: f.v1)
            XCTFail("mělo hodit")
        } catch TimelineError.wouldOverlap(_, let nearest) {
            // Nejbližší legální je buď 50 (těsně před), nebo 200 (těsně za).
            XCTAssertTrue(nearest == Frames(50) || nearest == Frames(200), "dostal \(nearest)")
        }
    }

    // 12.
    func testNegativePositionRejected() throws {
        var f = Fixture()
        XCTAssertThrowsUnchanged(&f.project, .negativePosition) { p in
            let clip = Clip(assetID: f.assetID, timelineStart: Frames(-1),
                            duration: Frames(10), sourceStart: .zero)
            try p.insert(clip, onTrack: f.v1)
        }
    }

    // 13.
    func testZeroLengthRejected() throws {
        var f = Fixture()
        XCTAssertThrowsUnchanged(&f.project, .zeroLength) { p in
            let clip = Clip(assetID: f.assetID, timelineStart: .zero,
                            duration: .zero, sourceStart: .zero)
            try p.insert(clip, onTrack: f.v1)
        }
    }

    // 14.
    func testRemoveLeavesGapOfExactLength() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        let middle = try f.addClip(start: 100, duration: 50)
        try f.addClip(start: 150, duration: 100)
        try f.project.remove(clipID: middle)
        let starts = f.clips(on: f.v1).map(\.timelineStart.count)
        XCTAssertEqual(starts, [0, 150], "mezera musí zůstat")
        XCTAssertValid(f.project)
    }

    // 15.
    func testRippleRemoveShiftsFollowingOnly() throws {
        var f = Fixture()
        let first = try f.addClip(start: 0, duration: 100)
        let middle = try f.addClip(start: 100, duration: 50)
        try f.addClip(start: 150, duration: 100)
        try f.project.rippleRemove(clipID: middle)
        XCTAssertEqual(f.clips(on: f.v1).map(\.timelineStart.count), [0, 100])
        XCTAssertEqual(f.clip(first)?.timelineStart, .zero, "předchozí se hýbat nesmí")
        XCTAssertValid(f.project)
    }

    // 16.
    func testRippleRemoveOfLastBehavesLikeRemove() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        let last = try f.addClip(start: 100, duration: 50)
        try f.project.rippleRemove(clipID: last)
        XCTAssertEqual(f.clips(on: f.v1).map(\.timelineStart.count), [0])
        XCTAssertValid(f.project)
    }

    // 17. Ripple na V1 NESMÍ posunout hudbu na A2.
    func testRippleDoesNotTouchUnrelatedTracks() throws {
        var f = Fixture()
        let onV1 = try f.addClip(start: 0, duration: 100)
        try f.addClip(start: 100, duration: 100)
        let music = try f.addClip(start: 0, duration: 300, on: f.a2)

        try f.project.rippleRemove(clipID: onV1)

        XCTAssertEqual(f.clip(music)?.timelineStart, .zero,
                       "hudební podkres je páteř, ke které se stříhá — ripple s ním hýbat nesmí")
        XCTAssertEqual(f.clips(on: f.v1).map(\.timelineStart.count), [0])
        XCTAssertValid(f.project)
    }

    // 18. Ripple na V1 MUSÍ posunout svázaný zvuk na A1.
    func testRippleMovesLinkedAudio() throws {
        var f = Fixture()
        let pair = try f.project.makeLinkedClips(assetID: f.assetID, at: .zero)
        var v = pair.video; v.duration = Frames(100)
        var a = pair.audio; a.duration = Frames(100)
        try f.project.insertLinked(video: v, onVideoTrack: f.v1, audio: a, onAudioTrack: f.a1)

        let laterV = try f.addClip(start: 100, duration: 100)
        let laterA = try f.addClip(start: 100, duration: 100, on: f.a1)

        try f.project.rippleRemove(clipID: v.id)

        XCTAssertNil(f.clip(a.id), "svázaný zvuk musí zmizet s obrazem")
        XCTAssertEqual(f.clip(laterV)?.timelineStart, .zero)
        XCTAssertEqual(f.clip(laterA)?.timelineStart, .zero, "zvuk na A1 se musí posunout taky")
        XCTAssertValid(f.project)
    }

    // 19.
    func testOverwriteTrimsPartiallyCoveredNeighbour() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        let newClip = Clip(assetID: f.assetID, timelineStart: Frames(50),
                           duration: Frames(100), sourceStart: .zero)
        try f.project.overwrite(newClip, onTrack: f.v1)
        let clips = f.clips(on: f.v1)
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].duration, Frames(50), "soused se má oříznout")
        XCTAssertValid(f.project)
    }

    // 20.
    func testOverwriteDeletesFullyCoveredNeighbour() throws {
        var f = Fixture()
        try f.addClip(start: 50, duration: 20)
        let newClip = Clip(assetID: f.assetID, timelineStart: Frames(0),
                           duration: Frames(150), sourceStart: .zero)
        try f.project.overwrite(newClip, onTrack: f.v1)
        XCTAssertEqual(f.clips(on: f.v1).count, 1)
        XCTAssertValid(f.project)
    }

    func testOverwriteInsideClipSplitsIt() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 200)
        let newClip = Clip(assetID: f.assetID, timelineStart: Frames(50),
                           duration: Frames(50), sourceStart: .zero)
        try f.project.overwrite(newClip, onTrack: f.v1)
        let clips = f.clips(on: f.v1)
        XCTAssertEqual(clips.count, 3, "hlava, nový klip, ocásek")
        XCTAssertEqual(clips.map(\.timelineStart.count), [0, 50, 100])
        XCTAssertValid(f.project)
    }

    // 21.
    func testFailedOverwriteLeavesTimelineUntouched() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 200)
        XCTAssertThrowsUnchanged(&f.project, .zeroLength) { p in
            let bad = Clip(assetID: f.assetID, timelineStart: Frames(50),
                           duration: .zero, sourceStart: .zero)
            try p.overwrite(bad, onTrack: f.v1)
        }
    }

    func testRippleInsertPushesFollowing() throws {
        var f = Fixture()
        let a = try f.addClip(start: 0, duration: 100)
        let clip = Clip(assetID: f.assetID, timelineStart: .zero,
                        duration: Frames(30), sourceStart: .zero)
        try f.project.rippleInsert(clip, onTrack: f.v1)
        XCTAssertEqual(f.clip(a)?.timelineStart, Frames(30))
        XCTAssertValid(f.project)
    }

    // MARK: Split a join (22–29)

    // 22.
    func testSplitPreservesTotalDuration() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        let (l, r) = try f.project.split(clipID: id, at: Frames(40))
        XCTAssertEqual(f.clip(l)!.duration + f.clip(r)!.duration, Frames(100))
        XCTAssertValid(f.project)
    }

    // 23. Druhá polovina musí navázat ve zdroji.
    func testSplitSecondHalfContinuesInSource() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        let clip = f.clip(id)!
        let (_, r) = try f.project.split(clipID: id, at: Frames(40))
        let expected = clip.sourceStart + f.project.timeline.sourceTime(Frames(40))
        XCTAssertEqual(f.clip(r)?.sourceStart, expected,
                       "kdo sem dá původní sourceStart, dostane opakující se záběr")
    }

    // 24.
    func testSplitAtStartRejected() throws {
        var f = Fixture()
        let id = try f.addClip(start: 10, duration: 100)
        XCTAssertThrowsUnchanged(&f.project, .zeroLength) { p in
            try p.split(clipID: id, at: Frames(10))
        }
    }

    // 25.
    func testSplitAtEndIsOutside() throws {
        var f = Fixture()
        let id = try f.addClip(start: 10, duration: 100)
        XCTAssertThrowsUnchanged(&f.project, .splitOutsideClip) { p in
            try p.split(clipID: id, at: Frames(110))
        }
    }

    // 26. Split na poslední snímek je legální a dá jednosnímkový ocásek.
    func testSplitAtLastFrameGivesOneFrameTail() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        let (l, r) = try f.project.split(clipID: id, at: Frames(99))
        XCTAssertEqual(f.clip(l)?.duration, Frames(99))
        XCTAssertEqual(f.clip(r)?.duration, Frames(1))
        XCTAssertValid(f.project)
    }

    // 27.
    func testSplitOfOneFrameClipRejected() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 1)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.split(clipID: id, at: Frames(0))
        }
    }

    // 28.
    func testSplitThenJoinRestoresOriginal() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        let before = f.clip(id)!
        let (l, r) = try f.project.split(clipID: id, at: Frames(40))
        try f.project.join(leftID: l, rightID: r)
        let after = f.clips(on: f.v1)
        XCTAssertEqual(after.count, 1)
        XCTAssertEqual(after[0].duration, before.duration)
        XCTAssertEqual(after[0].sourceStart, before.sourceStart)
        XCTAssertValid(f.project)
    }

    // 29.
    func testJoinRejectsNonContiguousSource() throws {
        var f = Fixture()
        let a = try f.addClip(start: 0, duration: 50, sourceStartFrames: 0)
        let b = try f.addClip(start: 50, duration: 50, sourceStartFrames: 200)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.join(leftID: a, rightID: b)
        }
    }

    // MARK: Přesun (42–48)

    // 42.
    func testMoveWithinTrack() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 50)
        try f.project.move(clipID: id, toTrack: f.v1, start: Frames(200))
        XCTAssertEqual(f.clip(id)?.timelineStart, Frames(200))
        XCTAssertValid(f.project)
    }

    // 43.
    func testMoveToAnotherTrackOfSameKind() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 50, on: f.a1)
        try f.project.move(clipID: id, toTrack: f.a2, start: Frames(10))
        XCTAssertEqual(f.clips(on: f.a1).count, 0)
        XCTAssertEqual(f.clips(on: f.a2).count, 1)
        XCTAssertValid(f.project)
    }

    // 44.
    func testMoveVideoOntoAudioTrackRejected() throws {
        var f = Fixture(hasVideo: true, hasAudio: false)
        let id = try f.addClip(start: 0, duration: 50)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.move(clipID: id, toTrack: p.timeline.tracks[1].id, start: .zero)
        }
    }

    // 45.
    func testMoveOntoOccupiedPositionRejected() throws {
        var f = Fixture()
        let a = try f.addClip(start: 0, duration: 50)
        try f.addClip(start: 100, duration: 50)
        XCTAssertThrowsUnchanged(&f.project) { p in
            try p.move(clipID: a, toTrack: f.v1, start: Frames(120))
        }
    }

    // 46.
    func testMoveToSamePositionIsNoOp() throws {
        var f = Fixture()
        let id = try f.addClip(start: 40, duration: 50)
        try f.project.move(clipID: id, toTrack: f.v1, start: Frames(40))
        XCTAssertEqual(f.clip(id)?.timelineStart, Frames(40))
        XCTAssertValid(f.project)
    }

    // 47.
    func testMoveIntoExactGap() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 50)
        try f.addClip(start: 100, duration: 50)
        let mover = try f.addClip(start: 300, duration: 50)
        try f.project.move(clipID: mover, toTrack: f.v1, start: Frames(50))
        XCTAssertEqual(f.clips(on: f.v1).map(\.timelineStart.count), [0, 50, 100])
        XCTAssertValid(f.project)
    }

    // 48.
    func testMovingLinkedClipTakesPartnerAlong() throws {
        var f = Fixture()
        let pair = try f.project.makeLinkedClips(assetID: f.assetID, at: .zero)
        var v = pair.video; v.duration = Frames(100)
        var a = pair.audio; a.duration = Frames(100)
        try f.project.insertLinked(video: v, onVideoTrack: f.v1, audio: a, onAudioTrack: f.a1)

        try f.project.move(clipID: v.id, toTrack: f.v1, start: Frames(200))
        XCTAssertEqual(f.clip(a.id)?.timelineStart, Frames(200),
                       "zvuk musí jít s obrazem, jinak se rozejdou")
        XCTAssertValid(f.project)
    }

    // MARK: Ostatní (62–67)

    // 62.
    func testEmptyProjectHasThreeTracks() {
        let p = Project.empty()
        XCTAssertEqual(p.timeline.tracks.map(\.name), ["V1", "A1", "A2"])
        XCTAssertEqual(p.timeline.tracks.map(\.kind), [.video, .audio, .audio])
        XCTAssertValid(p)
    }

    // 63.
    func testTogglingProxiesChangesNoModelValue() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        let before = f.project.timeline
        f.project.usesProxies = true
        XCTAssertEqual(f.project.timeline, before)
    }

    // 64.
    func testRemoveAssetInUseRejected() throws {
        var f = Fixture()
        try f.addClip(start: 0, duration: 100)
        XCTAssertThrowsUnchanged(&f.project, .assetStillInUse(f.assetID)) { p in
            try p.removeAsset(id: f.assetID)
        }
    }

    // 65.
    func testOperationsWorkOnOfflineAsset() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        f.project.assets[0].isOffline = true
        try f.project.move(clipID: id, toTrack: f.v1, start: Frames(50))
        XCTAssertEqual(f.clip(id)?.timelineStart, Frames(50))
        XCTAssertValid(f.project)
    }

    // 66.
    func testDuplicateGetsNewID() throws {
        var f = Fixture()
        let id = try f.addClip(start: 0, duration: 100)
        let copy = try f.project.duplicate(clipID: id, onto: f.v1, at: Frames(200))
        XCTAssertNotEqual(copy, id)
        XCTAssertEqual(f.clips(on: f.v1).count, 2)
        XCTAssertValid(f.project)
    }

    // 67.
    func testRippleTouchesOnlyClipsAfterIt() throws {
        var f = Fixture(seconds: 600)
        var ids: [ClipID] = []
        for i in 0..<200 {
            ids.append(try f.addClip(start: i * 10, duration: 10, sourceStartFrames: 0))
        }
        let before = f.clips(on: f.v1).map(\.timelineStart)
        try f.project.rippleRemove(clipID: ids[100])
        let after = f.clips(on: f.v1).map(\.timelineStart)
        // Prvních 100 se nesmělo hnout.
        XCTAssertEqual(Array(after.prefix(100)), Array(before.prefix(100)))
        XCTAssertValid(f.project)
    }
}
