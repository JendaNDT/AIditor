//
//  LibraryChecks.swift
//  Projekt Krása
//
//  Kontrola knihovny médií a přetažení na osu — fáze 18, modul 9
//  (`--library-check`).
//
//  ⚠️ Drag session se dělá SKUTEČNOU cestou protokolu `NSDraggingDestination`,
//  ne zkratkou do vnitřní funkce: `registerForDraggedTypes` → pasteboard →
//  `draggingEntered` → `draggingUpdated` → `performDragOperation`. Právě ta
//  cesta je na modulu nová a právě v ní se dá udělat chyba, kterou by zkratka
//  neodhalila (zapomenutá registrace typu, špatný typ na pasteboardu,
//  souřadnice v soustavě okna místo view).
//
//  A) **Filtry** vracejí očekávané počty a řazení je chronologické.
//  B) **Drop na V1** vloží klip tam, kam ukazoval NÁHLED, jedním undo krokem,
//     a projekt zůstane bez porušených invariantů.
//  C) **Video se zvukem** se položí jako svázaná dvojice se společným `LinkID`.
//  D) **Odmítnutí:** hudba na V1, video na A2, obsazené místo — a po každém
//     odmítnutí se v projektu NESMÍ změnit nic.
//

import AppKit
import Foundation
import TimelineModel

/// Falešná drag session. `NSDraggingInfo` je protokol, takže se dá postavit
/// bez okna i bez myši — jen se musí vyplnit všechno, co AppKit vyžaduje.
final class FakeDraggingInfo: NSObject, NSDraggingInfo {

    private let board: NSPasteboard
    var draggingLocation: NSPoint

    init(assetID: AssetID, at point: NSPoint) {
        // Vlastní jmenovaný pasteboard, ať se měření netahá se systémovou
        // schránkou uživatele.
        board = NSPasteboard(name: NSPasteboard.Name("cz.projektkrasa.libraryCheck"))
        board.clearContents()
        // TÝŽ zápis, jaký na druhé straně dělá `NSItemProvider(object: NSString)`
        // v `LibraryCard.onDrag`.
        board.setString(assetID.rawValue, forType: .string)
        draggingLocation = point
        super.init()
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggedImageLocation: NSPoint { draggingLocation }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { board }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var animatesToDestination: Bool = false
    var numberOfValidItemsForDrop: Int = 1
    var draggingFormation: NSDraggingFormation = .default
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions,
                                for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}

extension AppModel {

    func verifyLibrary() async {
        guard !clips.isEmpty else {
            print("❌ nejsou naskenované klipy — knihovna by byla prázdná"); return
        }

        var failures = 0
        func check(_ ok: Bool, _ text: String) {
            if !ok { failures += 1 }
            print("\(ok ? "✅" : "❌") \(text)")
        }

        skipsCompositionRebuild = true
        defer { skipsCompositionRebuild = false }

        // Projekt: naskenované klipy (obraz + svázaný zvuk), plus fotka
        // a hudební soubor, ať mají filtry co rozlišovat.
        timeline.loadScannedClips(clips)
        var project = timeline.project
        if let photoURL = Self.writeLibraryTestPhoto() {
            project.addAsset(Asset.still(url: photoURL))
        }
        // ⚠️ Hudební asset se staví PŘESNĚ jako v `AppModel.importMusic`:
        // `measuredFrameRate` = základna projektu, ne nula. První verze téhle
        // kontroly tam dala nulu, `validate()` asset právem označil za neplatný
        // — a odhalilo to skutečnou chybu v kódu dropu (viz `dropPlan`).
        let musicURL = URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        let music = Asset(originalURL: musicURL,
                          duration: SourceTime(seconds: 3),
                          measuredFrameRate: Double(project.timeline.frameRate),
                          hasVideo: false, hasAudio: true)
        project.addAsset(music)
        timeline.project = project
        timeline.selectClips([])

        var geometry = timeline.geometry
        geometry.setZoom(5)
        timeline.geometry = geometry

        NSApp.activate(ignoringOtherApps: true)
        let deadline = Date().addingTimeInterval(10)
        while timelinePane?.window == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let pane = timelinePane, let window = pane.window else {
            print("❌ osa se nedostala do okna"); return
        }
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let view = pane.documentView

        print("=== A) filtry a řazení ===")
        let assets = timeline.project.assets
        let videoCount = assets.filter { LibraryFilter.video.matches($0) }.count
        let stillCount = assets.filter { LibraryFilter.stills.matches($0) }.count
        let musicCount = assets.filter { LibraryFilter.music.matches($0) }.count
        print("   celkem \(assets.count): video \(videoCount), fotky \(stillCount), "
              + "hudba \(musicCount)")
        check(videoCount == clips.count, "filtr Video vrací naskenované klipy (\(videoCount))")
        check(stillCount == 1, "filtr Fotky vrací jednu fotku (\(stillCount))")
        check(musicCount == 1, "filtr Hudba vrací jeden zvukový soubor (\(musicCount))")
        check(videoCount + stillCount + musicCount == assets.count,
              "filtry se nepřekrývají a pokrývají všechno")
        // Chronologie: video assety mají čas natočení z metadat (F17).
        let dated = assets.compactMap(\.creationDate)
        check(dated.count >= clips.count,
              "video assety mají čas natočení (\(dated.count) z \(assets.count))")

        print("")
        print("=== B) drop na V1 přistane tam, kam ukazoval náhled ===")
        // Prázdná osa se stejnými assety — vkládá se do volného místa.
        var empty = Project.empty()
        for asset in timeline.project.assets { empty.addAsset(asset) }
        timeline.project = empty
        timeline.undo = UndoStack()
        try? await Task.sleep(nanoseconds: 400_000_000)

        guard let videoAsset = timeline.project.assets
            .first(where: { $0.hasVideo && $0.hasAudio && !$0.isStill }) else {
            print("❌ žádný video asset se zvukem"); return
        }
        let tracks = timeline.project.timeline.tracks
        let v1 = tracks[0]
        let a1 = tracks[1]
        let targetFrame = Frames(120)
        let dropPoint = NSPoint(
            x: timeline.geometry.x(for: targetFrame),
            y: timeline.geometry.y(ofTrackAt: 0, in: timeline.project.timeline) + 20)

        let drag = FakeDraggingInfo(assetID: videoAsset.id, at: view.convert(dropPoint, to: nil))
        let entered = view.draggingEntered(drag)
        check(entered == .copy, "`draggingEntered` na V1 povolil kopii (\(entered.rawValue))")
        guard let preview = view.dropPreviewProbe else {
            print("❌ náhled vložení se nekreslí"); return
        }
        print(String(format: "   náhled: x %.0f, šířka %.0f, druhý duch %@, platný %@",
                     preview.frame.origin.x, preview.frame.width,
                     preview.partner == nil ? "ne" : "ano", preview.isValid ? "ano" : "ne"))
        check(preview.isValid, "náhled je platný (žlutý, ne červený)")
        check(preview.partner != nil, "náhled ukazuje i svázaný zvuk")

        let dropped = view.performDragOperation(drag)
        try? await Task.sleep(nanoseconds: 400_000_000)
        check(dropped, "`performDragOperation` vložil klip")

        let v1Clips = timeline.project.timeline.tracks[0].clips
        let a1Clips = timeline.project.timeline.tracks[1].clips
        check(v1Clips.count == 1 && a1Clips.count == 1,
              "na V1 i A1 je právě jeden klip (\(v1Clips.count) / \(a1Clips.count))")
        if let clip = v1Clips.first {
            print("   klip začíná na snímku \(clip.timelineStart.count), čekáno \(targetFrame.count)")
            check(clip.timelineStart == targetFrame,
                  "klip přistál na snímku pod kurzorem")
            let landedX = timeline.geometry.x(for: clip.timelineStart)
            check(abs(landedX - preview.frame.origin.x) < 0.5,
                  "a přistál PŘESNĚ tam, kde byl náhled")
        }
        check(timeline.project.validate().isEmpty,
              "projekt po dropu bez porušených invariantů")
        check(view.dropPreviewProbe == nil, "náhled se po puštění uklidil")

        print("")
        print("=== C) svázaná dvojice a jeden undo krok ===")
        if let video = v1Clips.first, let audio = a1Clips.first {
            check(video.linkID != nil && video.linkID == audio.linkID,
                  "obraz a zvuk mají společný `LinkID`")
        }
        timeline.undoStep()
        try? await Task.sleep(nanoseconds: 400_000_000)
        let afterUndo = timeline.project.timeline.tracks.reduce(0) { $0 + $1.clips.count }
        print("   po ⌘Z klipů na ose: \(afterUndo)")
        check(afterUndo == 0, "JEDEN undo krok vzal celou dvojici")

        print("")
        print("=== D) co se odmítá ===")
        // 1) hudba na V1
        guard let musicAsset = timeline.project.assets
            .first(where: { LibraryFilter.music.matches($0) }) else {
            print("❌ hudební asset chybí"); return
        }
        let musicOnV1 = FakeDraggingInfo(assetID: musicAsset.id,
                                         at: view.convert(dropPoint, to: nil))
        let musicOperation = view.draggingUpdated(musicOnV1)
        let musicPreview = view.dropPreviewProbe
        let beforeMusic = timeline.project
        let musicDropped = view.performDragOperation(musicOnV1)
        try? await Task.sleep(nanoseconds: 300_000_000)
        check(musicOperation == [], "hudba na V1: `draggingUpdated` odmítl")
        check(musicPreview?.isValid == false, "a náhled je ČERVENÝ, ne prostě žádný")
        check(!musicDropped && timeline.project == beforeMusic,
              "drop se neprovedl a projekt se nezměnil")

        // 2) video na A2
        let a2Point = NSPoint(
            x: timeline.geometry.x(for: targetFrame),
            y: timeline.geometry.y(ofTrackAt: 2, in: timeline.project.timeline) + 20)
        let videoOnA2 = FakeDraggingInfo(assetID: videoAsset.id,
                                         at: view.convert(a2Point, to: nil))
        let a2Operation = view.draggingUpdated(videoOnA2)
        let beforeA2 = timeline.project
        let a2Dropped = view.performDragOperation(videoOnA2)
        try? await Task.sleep(nanoseconds: 300_000_000)
        check(a2Operation == [] && !a2Dropped && timeline.project == beforeA2,
              "video na zvukovou stopu se odmítlo a nic se nezměnilo")

        // 3) obsazené místo: dvakrát totéž na týž snímek
        let first = FakeDraggingInfo(assetID: videoAsset.id, at: view.convert(dropPoint, to: nil))
        _ = view.draggingUpdated(first)
        _ = view.performDragOperation(first)
        try? await Task.sleep(nanoseconds: 400_000_000)
        let beforeSecond = timeline.project
        let second = FakeDraggingInfo(assetID: videoAsset.id, at: view.convert(dropPoint, to: nil))
        let secondOperation = view.draggingUpdated(second)
        let secondPreview = view.dropPreviewProbe
        let secondDropped = view.performDragOperation(second)
        try? await Task.sleep(nanoseconds: 300_000_000)
        check(secondOperation == [], "drop na obsazené místo se odmítl")
        check(secondPreview?.isValid == false, "a náhled to ukázal červeně")
        check(!secondDropped && timeline.project == beforeSecond,
              "obsazené místo: projekt se nezměnil")
        check(timeline.project.validate().isEmpty, "osa je pořád bez porušených invariantů")

        // 4) fotka na V1 projít MUSÍ — je to obrazový klip.
        if let photo = timeline.project.assets.first(where: { $0.isStill }) {
            // ⚠️ ZA konec osy, ne na pevný snímek: v části D3 se na osu položil
            // klip celého záběru (1348 snímků), takže „snímek 600" byl uvnitř
            // něj a drop se správně odmítl — kontrola pak hlásila chybu tam,
            // kde žádná nebyla.
            let freeFrame = timeline.project.duration + Frames(60)
            let photoPoint = NSPoint(
                x: timeline.geometry.x(for: freeFrame),
                y: timeline.geometry.y(ofTrackAt: 0, in: timeline.project.timeline) + 20)
            let photoDrag = FakeDraggingInfo(assetID: photo.id,
                                             at: view.convert(photoPoint, to: nil))
            let photoOperation = view.draggingUpdated(photoDrag)
            let photoDropped = view.performDragOperation(photoDrag)
            try? await Task.sleep(nanoseconds: 400_000_000)
            let stillOnV1 = timeline.project.timeline.tracks[0].clips
                .contains { timeline.project.asset($0.assetID)?.isStill == true }
            check(photoOperation == .copy && photoDropped && stillOnV1,
                  "fotka na V1 projde (je to obrazový klip)")
        }

        print("")
        print(failures == 0 ? "✅ KNIHOVNA A PŘETAŽENÍ SEDÍ" : "❌ neshod: \(failures)")
    }

    /// Fotka do kontejneru — v `TestClips/` žádná není a filtr Fotky by neměl
    /// co ukázat.
    private static func writeLibraryTestPhoto() -> URL? {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory,
                                                       in: .userDomainMask).first else { return nil }
        let folder = directory.appendingPathComponent("LibraryCheck", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("karta.png")

        guard let context = CGContext(data: nil, width: 800, height: 600,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }
}
