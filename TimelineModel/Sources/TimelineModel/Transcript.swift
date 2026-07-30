//
//  Transcript.swift
//  Projekt Krása — TimelineModel
//
//  Fáze 8, modul 1: datový model titulků. Přepis patří ASSETU a je
//  kotvený ve ZDROJOVÉM čase — stejné rozhodnutí jako uzly rychlostních
//  křivek: střih, trim ani přesun klipu titulky neposune, drží se na
//  slovech, ne na pozici osy. Na osu se PROMÍTAJÍ přes klipy
//  (`subtitleCues()`), včetně rychlostních křivek.
//
//  Kdo přepis vyrobí (WhisperKit, modul 2), je téhle vrstvě jedno —
//  tady jsou jen data, promítnutí a zápis SRT. Všechno čistý Swift.
//

import Foundation

/// Jeden úsek přepisu ve zdrojovém čase assetu.
public struct TranscriptSegment: Hashable, Codable, Sendable {
    public var start: SourceTime
    /// Exkluzivní konec; musí být za začátkem.
    public var end: SourceTime
    public var text: String

    public init(start: SourceTime, end: SourceTime, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Titulek promítnutý na osu, ve snímcích projektu.
public struct SubtitleCue: Hashable, Sendable {
    public let start: Frames
    /// Exkluzivní konec.
    public let end: Frames
    public let text: String

    public init(start: Frames, end: Frames, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Titulek z řeči s adresou úseku v přepisu — pro inspektor (fáze 11).
/// Text je snímek stavu v okamžiku dotazu; po editaci si volající říká znovu.
public struct SpeechCueRef: Hashable, Sendable {
    public let assetID: AssetID
    /// Index v `Asset.transcript` v okamžiku dotazu.
    public let segmentIndex: Int
    public let text: String
    public let start: Frames
    /// Exkluzivní konec.
    public let end: Frames

    public init(assetID: AssetID, segmentIndex: Int, text: String,
                start: Frames, end: Frames) {
        self.assetID = assetID
        self.segmentIndex = segmentIndex
        self.text = text
        self.start = start
        self.end = end
    }
}

extension Project {

    /// Uloží přepis assetu. Úseky se seřadí podle začátku; úseky
    /// s prázdným textem (artefakty přepisu) se zahazují. Úsek s koncem
    /// před začátkem je chyba dat, ne něco k tichému opravení.
    public mutating func setTranscript(assetID: AssetID,
                                       segments: [TranscriptSegment]) throws {
        guard let index = assets.firstIndex(where: { $0.id == assetID }) else {
            throw TimelineError.assetNotFound(assetID)
        }
        for segment in segments where segment.end <= segment.start {
            throw TimelineError.invalidTranscriptSegment
        }
        let cleaned = segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.start < $1.start }
        assets[index].transcript = cleaned.isEmpty ? nil : cleaned
    }

    /// Promítne přepisy na osu. Bere se JEN ze zvukových stop — řeč žije
    /// ve zvuku a svázaný pár obraz+zvuk sdílí asset: brát obojí by dalo
    /// každý titulek dvakrát.
    ///
    /// Mapování zdroj→osa jde přes inverzi `sourceOffset`, takže funguje
    /// i pod rychlostní křivkou (titulek na zpomaleném úseku se na ose
    /// patřičně natáhne — mluví se pomalu, titulek visí déle).
    public func subtitleCues() -> [SubtitleCue] {
        var cues: [SubtitleCue] = []
        for track in timeline.tracks where track.kind == .audio {
            for clip in track.clips {
                guard let asset = asset(clip.assetID),
                      let transcript = asset.transcript else { continue }
                let windowStart = clip.sourceStart
                let windowEnd = clip.sourceStart + sourceConsumption(of: clip)

                for segment in transcript {
                    guard segment.end > windowStart, segment.start < windowEnd else { continue }
                    let clampedStart = max(segment.start, windowStart)
                    let clampedEnd = min(segment.end, windowEnd)
                    let startFrame = clip.timelineStart
                        + frameOffset(forSource: clampedStart, in: clip)
                    let endFrame = clip.timelineStart
                        + frameOffset(forSource: clampedEnd, in: clip)
                    guard endFrame > startFrame else { continue }   // kratší než snímek
                    cues.append(SubtitleCue(start: startFrame, end: endFrame,
                                            text: segment.text))
                }
            }
        }
        // Deterministické pořadí i při shodných začátcích z více stop.
        return cues.sorted {
            ($0.start, $0.end, $0.text) < ($1.start, $1.end, $1.text)
        }
    }

    /// Titulek z řeči pod daným snímkem osy, S ADRESOU úseku v přepisu.
    /// Inspektor (fáze 11, modul 3) potřebuje vědět, KTERÝ úsek edituje —
    /// `subtitleCues` provenienci zahazuje, protože kreslení ji nepotřebuje.
    ///
    /// Průchod je týž jako v `subtitleCues` (zvukové stopy, ořez na okno
    /// klipu, mapování přes inverzi `sourceOffset`), první zásah vyhrává —
    /// pořadí stop je deterministické.
    public func speechCueRef(at frame: Frames) -> SpeechCueRef? {
        for track in timeline.tracks where track.kind == .audio {
            for clip in track.clips {
                guard clip.contains(frame: frame),
                      let asset = asset(clip.assetID),
                      let transcript = asset.transcript else { continue }
                let windowStart = clip.sourceStart
                let windowEnd = clip.sourceStart + sourceConsumption(of: clip)

                for (index, segment) in transcript.enumerated() {
                    guard segment.end > windowStart, segment.start < windowEnd else { continue }
                    let clampedStart = max(segment.start, windowStart)
                    let clampedEnd = min(segment.end, windowEnd)
                    let startFrame = clip.timelineStart
                        + frameOffset(forSource: clampedStart, in: clip)
                    let endFrame = clip.timelineStart
                        + frameOffset(forSource: clampedEnd, in: clip)
                    guard startFrame <= frame, frame < endFrame else { continue }
                    return SpeechCueRef(assetID: asset.id, segmentIndex: index,
                                        text: segment.text,
                                        start: startFrame, end: endFrame)
                }
            }
        }
        return nil
    }

    /// Přepíše text úseku přepisu. Prázdný text úsek MAŽE — oprava
    /// artefaktu přepisu i jeho odstranění jsou jedna cesta. Jde přes
    /// `setTranscript`, takže platí jeho validace a řazení.
    public mutating func setTranscriptText(assetID: AssetID, segmentIndex: Int,
                                           text: String) throws {
        guard let asset = asset(assetID) else {
            throw TimelineError.assetNotFound(assetID)
        }
        guard var segments = asset.transcript,
              segments.indices.contains(segmentIndex) else {
            throw TimelineError.invalidTranscriptSegment
        }
        segments[segmentIndex].text = text
        try setTranscript(assetID: assetID, segments: segments)
    }

    /// Rozdělí úsek přepisu v místě kurzoru v textu (fáze 18, modul 11).
    ///
    /// Čas řezu se odvozuje POMĚREM ZNAKŮ: kurzor v polovině textu dělí i čas
    /// v polovině. Je to heuristika, a je to vidět — ale lepší data nemáme:
    /// naše cesta WhisperKitu vrací časy na úsek, ne na slovo, a vymýšlet
    /// „přesný" čas z ničeho by bylo horší než přiznaný odhad. Uživatel obě
    /// půlky pak může doupravit.
    ///
    /// Kurzor na začátku nebo na konci textu nedělá nic (prázdná půlka by se
    /// v `setTranscript` stejně zahodila a druhá by se jen posunula v čase).
    @discardableResult
    public mutating func splitTranscriptSegment(assetID: AssetID, segmentIndex: Int,
                                                atCharacter offset: Int) throws -> Bool {
        guard let asset = asset(assetID) else { throw TimelineError.assetNotFound(assetID) }
        guard var segments = asset.transcript,
              segments.indices.contains(segmentIndex) else {
            throw TimelineError.invalidTranscriptSegment
        }
        let segment = segments[segmentIndex]
        let text = segment.text
        guard offset > 0, offset < text.count else { return false }

        let cut = text.index(text.startIndex, offsetBy: offset)
        let first = String(text[text.startIndex..<cut]).trimmingCharacters(in: .whitespaces)
        let second = String(text[cut...]).trimmingCharacters(in: .whitespaces)
        guard !first.isEmpty, !second.isEmpty else { return false }

        let span = segment.end.seconds - segment.start.seconds
        let ratio = Double(offset) / Double(text.count)
        let cutTime = SourceTime(seconds: segment.start.seconds + span * ratio)
        // Řez musí být uvnitř úseku, jinak by vznikl úsek nulové délky
        // a `setTranscript` by ho odmítl.
        guard cutTime > segment.start, cutTime < segment.end else { return false }

        segments[segmentIndex] = TranscriptSegment(start: segment.start, end: cutTime,
                                                  text: first)
        segments.insert(TranscriptSegment(start: cutTime, end: segment.end, text: second),
                        at: segmentIndex + 1)
        try setTranscript(assetID: assetID, segments: segments)
        return true
    }

    /// Kde na OSE leží úsek přepisu. Úsek může být vidět na víc klipech (týž
    /// zdroj položený dvakrát), proto pole. Používá to zvýraznění vybraného
    /// úseku na ose (fáze 18, modul 11).
    ///
    /// Průchod je týž jako v `subtitleCues` a `speechCueRef` — zvukové stopy,
    /// ořez na okno klipu, mapování inverzí `sourceOffset`.
    public func speechCueRanges(assetID: AssetID, segmentIndex: Int) -> [Range<Frames>] {
        guard let asset = asset(assetID), let transcript = asset.transcript,
              transcript.indices.contains(segmentIndex) else { return [] }
        let segment = transcript[segmentIndex]

        var ranges: [Range<Frames>] = []
        for track in timeline.tracks where track.kind == .audio {
            for clip in track.clips where clip.assetID == assetID {
                let windowStart = clip.sourceStart
                let windowEnd = clip.sourceStart + sourceConsumption(of: clip)
                guard segment.end > windowStart, segment.start < windowEnd else { continue }
                let startFrame = clip.timelineStart
                    + frameOffset(forSource: max(segment.start, windowStart), in: clip)
                let endFrame = clip.timelineStart
                    + frameOffset(forSource: min(segment.end, windowEnd), in: clip)
                guard endFrame > startFrame else { continue }
                ranges.append(startFrame..<endFrame)
            }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    /// Nejmenší snímek klipu, jehož zdrojová pozice je aspoň `target` —
    /// inverze `sourceOffset` binárním půlením (je monotónní; s rampou
    /// po úsecích, analyticky by se invertovala blbě).
    func frameOffset(forSource target: SourceTime, in clip: Clip) -> Frames {
        var low = 0
        var high = clip.duration.count
        while low < high {
            let mid = (low + high) / 2
            if sourceOffset(in: clip, atFrame: Frames(mid)) < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return Frames(low)
    }
}

// MARK: - SRT

/// Zápis titulků do SubRip (.srt) — nejrozšířenější formát, berou ho
/// YouTube, přehrávače i střižny.
public enum SRT {

    /// Čas ve formátu `HH:MM:SS,mmm` (SubRip používá čárku).
    static func timestamp(frame: Frames, frameRate: Int) -> String {
        let totalMilliseconds = Int((Double(frame.count) / Double(frameRate) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = totalMilliseconds / 60_000 % 60
        let seconds = totalMilliseconds / 1000 % 60
        let milliseconds = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }

    /// Celý soubor. Titulky s prázdným textem se přeskakují; číslování
    /// od jedničky bez děr. Konce řádků LF — CR-LF je relikt, dnešní
    /// nástroje berou obojí a LF je deterministické vůči gitu.
    public static func serialize(cues: [SubtitleCue], frameRate: Int) -> String {
        var blocks: [String] = []
        var number = 1
        for cue in cues {
            let text = cue.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, cue.end > cue.start else { continue }
            blocks.append("""
                \(number)
                \(timestamp(frame: cue.start, frameRate: frameRate)) --> \
                \(timestamp(frame: cue.end, frameRate: frameRate))
                \(text)
                """)
            number += 1
        }
        guard !blocks.isEmpty else { return "" }
        return blocks.joined(separator: "\n\n") + "\n"
    }
}
