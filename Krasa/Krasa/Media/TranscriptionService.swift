//
//  TranscriptionService.swift
//  Projekt Krása
//
//  Fáze 8, modul 2: přepis řeči přes WhisperKit (balíček
//  `argmaxinc/argmax-oss-swift`, dřív `WhisperKit`). Model
//  `large-v3-turbo` — rozhodnutí z plánu: small má pro češtinu
//  34–38 % chybovost, turbo je menší i rychlejší než medium a přesnější.
//
//  Model (~1,5 GB) se stahuje při PRVNÍM použití do kontejneru aplikace
//  a pak už se jen načítá z disku. Přepis samotný běží 100% lokálně.
//
//  Vstup: mono 16 kHz Float — formát, který Whisper očekává; dělá ho
//  `MonoAudioReader` (přes AVComposition, kvůli edit listu).
//

import Foundation
import TimelineModel
import WhisperKit

@MainActor
final class TranscriptionService: ObservableObject {

    /// Průběh pro UI; `nil` = nic neběží.
    @Published private(set) var statusText: String?

    /// Načtený model se drží po celý běh — načtení trvá desítky sekund
    /// a uživatel typicky přepisuje víc klipů po sobě.
    private var loadedWhisper: WhisperKit?

    /// ⚠️ Past v názvosloví: OpenAI model „large-v3-turbo" se v repozitáři
    /// `argmaxinc/whisperkit-coreml` jmenuje podle DATA VYDÁNÍ, ne „turbo".
    /// Přípona `_turbo` tam značí komprimované varianty WhisperKitu — jiná
    /// věc. Ověřeno výpisem repozitáře 28. 07. 2026; s "large-v3-turbo"
    /// stahování spadne na modelsUnavailable.
    static let modelName = "openai_whisper-large-v3-v20240930"

    // MARK: - Správa modelu (fáze 16, modul 3)

    /// Velikost staženého modelu v bajtech a kde leží; `nil` = nestažený.
    @Published private(set) var modelSizeBytes: Int64?
    /// Kam se model ukládá — pro UI.
    @Published private(set) var modelLocationName = "výchozí složka aplikace"

    /// Vlastní umístění modelu (např. externí disk) se drží
    /// security-scoped bookmarkem — vzorec `ProxyStore`.
    private static let locationBookmarkKey = "cz.projektkrasa.whisperModelDirectory"
    private var customRoot: URL?

    /// Výchozí umístění: `Documents/huggingface` v kontejneru — tam
    /// stahuje WhisperKit, když `downloadBase` nedostane
    /// (ověřeno v `WhisperKitConfig`/`HubApi` a na disku po fázi 8).
    private static var defaultBase: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// Kořen, který dostane WhisperKit jako `downloadBase`. Uvnitř si sám
    /// dělá `huggingface/models/…`.
    private var downloadBase: URL? {
        customRoot ?? Self.defaultBase
    }

    /// Složka, ve které model fyzicky leží (to, co se měří a maže).
    private var modelDirectory: URL? {
        downloadBase?.appendingPathComponent("huggingface", isDirectory: true)
    }

    init() {
        restoreCustomLocation()
        refreshModelSize()
    }

    /// Přepočítá velikost stažených souborů modelu.
    func refreshModelSize() {
        guard let directory = modelDirectory,
              let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            modelSizeBytes = nil
            return
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        modelSizeBytes = total > 0 ? total : nil
    }

    /// Smaže stažený model. Příště se stáhne znovu — proto se volající
    /// musí zeptat. Načtený model v paměti se zahodí taky, jinak by
    /// aplikace dál přepisovala z něčeho, co na disku není.
    func deleteModel() {
        guard let directory = modelDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
        loadedWhisper = nil
        refreshModelSize()
    }

    /// Přemístí model do zvolené složky (typicky na externí disk).
    /// Stažené soubory se PŘESUNOU, ne stáhnou znovu — 1,5 GB po síti
    /// kvůli změně cesty by byla neomluvitelná daň.
    func relocateModel(to url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        let oldDirectory = modelDirectory
        _ = url.startAccessingSecurityScopedResource()
        let newDirectory = url.appendingPathComponent("huggingface", isDirectory: true)

        if let oldDirectory, oldDirectory != newDirectory,
           FileManager.default.fileExists(atPath: oldDirectory.path) {
            try? FileManager.default.removeItem(at: newDirectory)   // zbytek po dřívějším pokusu
            do {
                try FileManager.default.createDirectory(
                    at: url, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: oldDirectory, to: newDirectory)
            } catch {
                // Přesun neprošel (jiný svazek bez práv, plný disk) —
                // zůstat u staré složky, ne se tvářit, že je přesunuto.
                url.stopAccessingSecurityScopedResource()
                return
            }
        }

        UserDefaults.standard.set(data, forKey: Self.locationBookmarkKey)
        customRoot = url
        modelLocationName = url.path
        loadedWhisper = nil   // příště se načte z nové cesty
        refreshModelSize()
    }

    private func restoreCustomLocation() {
        guard let data = UserDefaults.standard.data(forKey: Self.locationBookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else {
            // Odpojený disk: spadnout na výchozí složku. Model se pak
            // stáhne znovu, ale aplikace poběží (vzorec `ProxyStore`).
            return
        }
        if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil,
                                                    relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.locationBookmarkKey)
        }
        customRoot = url
        modelLocationName = url.path
    }

    /// Přepíše zvuk souboru na úseky ve zdrojovém čase. Prázdné pole =
    /// v nahrávce se nenašla žádná řeč.
    func transcribe(url: URL) async throws -> [TranscriptSegment] {
        defer { statusText = nil }

        let whisper: WhisperKit
        if let loadedWhisper {
            whisper = loadedWhisper
        } else {
            statusText = "Připravuju model přepisu… (poprvé se stahuje ~1,5 GB)"
            // `downloadBase` respektuje volbu umístění (fáze 16, modul 3);
            // `nil` = výchozí Documents v kontejneru, jako dosud.
            let config = WhisperKitConfig(model: Self.modelName,
                                          downloadBase: customRoot)
            whisper = try await WhisperKit(config)
            loadedWhisper = whisper
            refreshModelSize()
        }

        statusText = "Načítám zvuk…"
        guard let samples = try await MonoAudioReader.samples(url: url, sampleRate: 16_000),
              !samples.isEmpty else {
            return []
        }

        statusText = "Přepisuju řeč… (běží lokálně)"
        // Čeština natvrdo — detekce jazyka na svatbě s hudbou v pozadí
        // umí uletět a přepnout doprostřed nahrávky. Slovenština je F12.
        // VAD chunking: dlouhá nahrávka se dělí podle pauz v řeči, ne po
        // slepých 30 s oknech, která by řízla slovo vejpůl.
        let options = DecodingOptions(task: .transcribe,
                                      language: "cs",
                                      skipSpecialTokens: true,
                                      chunkingStrategy: .vad)
        let results = try await whisper.transcribe(audioArray: samples,
                                                   decodeOptions: options)

        var segments: [TranscriptSegment] = []
        for result in results {
            for segment in result.segments {
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty, segment.end > segment.start else { continue }
                segments.append(TranscriptSegment(
                    start: SourceTime(seconds: Double(segment.start)),
                    end: SourceTime(seconds: Double(segment.end)),
                    text: text))
            }
        }
        return segments
    }
}
