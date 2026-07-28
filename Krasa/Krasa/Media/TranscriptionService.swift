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

    /// Přepíše zvuk souboru na úseky ve zdrojovém čase. Prázdné pole =
    /// v nahrávce se nenašla žádná řeč.
    func transcribe(url: URL) async throws -> [TranscriptSegment] {
        defer { statusText = nil }

        let whisper: WhisperKit
        if let loadedWhisper {
            whisper = loadedWhisper
        } else {
            statusText = "Připravuju model přepisu… (poprvé se stahuje ~1,5 GB)"
            let config = WhisperKitConfig(model: Self.modelName)
            whisper = try await WhisperKit(config)
            loadedWhisper = whisper
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
