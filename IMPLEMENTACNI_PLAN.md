# Projekt Krása – Implementační plán
*Verze 1.0 · 25. 7. 2026 · režim 30+ h týdně*

---

## 0. Jak tenhle dokument používat

Specifikace v2.0 říká **co** stavět. Tenhle dokument říká **v jakém pořadí, čím a kdy přestat**.

Tři pravidla, která z něj dělají plán a ne seznam přání:

1. **Nikdy nepracuješ na dvou fázích zároveň.** Fáze má definici hotovo. Dokud není splněná, další nezačíná.
2. **Kill-gate se respektuje.** Jsou v plánu tři. Nejsou to formality — jsou to místa, kde se rozhoduje, jestli pokračovat, zúžit, nebo skončit. Skončit včas je úspěch.
3. **Claude Code čte tenhle soubor.** Na začátku každé session mu řekni: *„Přečti si IMPLEMENTACNI_PLAN.md a PROJECT_STATUS.md. Jsme ve fázi X, úkol Y."*

---

## 1. Co se změnilo oproti specifikaci v2.0

Rešerše z 25. 7. 2026 našla sedm věcí, které mění návrh. Řazeno podle dopadu.

| # | Zjištění | Dopad na plán |
|---|---|---|
| 1 | **`AVMutableVideoComposition` je od macOS 26 deprecated.** Náhrada je `AVVideoComposition.Configuration` (struct, `Sendable`). | Píšeš proti nové API hned. Deprecated ≠ nefunkční, ale nemá smysl začínat na mrtvé větvi. Zvedá to minimální macOS na 26 pro build, cíl běhu zůstává 14.0 s runtime gatováním. |
| 2 | **Whisper-small je pro češtinu nepoužitelný** — 34–38 % WER, každé třetí slovo špatně. | Model ze specifikace se mění na **large-v3-turbo** (~13 % WER, stejná velikost jako medium, násobně rychlejší). Medium nemá důvod existovat. |
| 3 | **`SpeechAnalyzer` češtinu nepodporuje.** V seznamu 42 locale není `cs_CZ` ani `pl_PL`. | Sekce 4.3.1 specifikace („sledovat vývoj, mohlo by nahradit Whisper") se ruší. Whisper je jediná cesta, ne dočasné řešení. |
| 4 | **Modely pro rozpoznávání obličejů jsou z velké části komerčně zakázané.** InsightFace/ArcFace/buffalo\_l: *„non-commercial research purposes only"*. | Face grouping se odsouvá až za v1.0 a stává se podmíněnou fází. Jediný čistý model je **AuraFace-v1** (Apache 2.0). |
| 5 | **EU AI Act: výjimka pro osobní použití nechrání tebe.** Čl. 2(10) je výslovně jen pro *deployera*. Jako dodavatel software jsi mimo. | Face grouping dostává právní gate. Termín pro Annex III je po Digital Omnibus **2. 12. 2027**, ne 2026 — máš čas, ale ne bianko šek. |
| 6 | **MacBook Air M4 má hardwarový ProRes engine.** Chyběl jen základnímu M1. | Proxy workflow v ProRes 422 Proxy je na tvém stroji reálný. Dobrá zpráva — jedna obava padá. |
| 7 | **`AVAssetExportSession` ignoruje `frameDuration`.** Kompozice, která hraje v 60 fps, se vyexportuje ve 30. | Export se od začátku píše přes `AVAssetWriter`, ne `AVAssetExportSession`. |

Plus dvě věci z minula, které zůstávají v platnosti:

- `scaleTimeRange` dělá **konstantní** změnu rychlosti. Plynulá křivka = segmentace nebo vlastní compositor.
- Vision **nemá** veřejné API pro otisk obličeje. `VNGenerateFaceCaptureQualityRequest` navíc neexistuje — správně je `VNDetectFaceCaptureQualityRequest`.

---

## 2. Realita rozsahu

Při 30 h týdně:

| Meta | Co to je | Odhad | Po korekci ×1,7 |
|---|---|---|---|
| **v0.5 „MVP nula"** | Import, timeline, střih, speed ramp, proxy, export, projekt | ~15 týdnů | **~6 měsíců** |
| **v1.0** | + svatební asistent, audio engine, titulky, distribuce | +10 týdnů | **~10 měsíců** |
| **v1.2** | + AI analýza scén a obličejů | +12 týdnů | **~13 měsíců** |
| **v2.0** | + multicam, HDR, optical flow, SK | +? | **2+ roky** |

**Ta korekce ×1,7 tam není z opatrnosti.** Odhady u vibecodovaných projektů této složitosti se podceňují systematicky, protože se počítá čas psaní kódu, ne čas hledání, proč to nefunguje. U videoeditoru je ten druhý čas dominantní.

**Optical flow doporučuju škrtnout úplně.** Ne odložit — škrtnout. Vision ti dá pohybové vektory, ale udělat z nich mezisnímky bez artefaktů je výzkumný problém, na kterém Twixtor a Resolve pracují roky. Není to funkce na dopsání, je to samostatný produkt.

---

## 3. Architektura: moduly

Rozdělení je navržené tak, aby se každý modul dal napsat a otestovat **izolovaně** — to je jediný způsob, jak s AI stavět něco velkého.

### Vrstva 1 — Čistá logika (žádné Apple frameworky, plně testovatelná)

| Modul | Co dělá | Obtížnost |
|---|---|---|
| `SpeedRampEngine` | Mapování timeline↔zdrojový čas, Bézier interpolace | ★★☆☆☆ |
| `ProjectModel` | Datové struktury projektu, Codable | ★☆☆☆☆ |
| `TimelineModel` | Stopy, klipy, operace střihu (split, trim, ripple) | ★★★☆☆ |
| `UndoStack` | Historie změn nad ProjectModel | ★★★☆☆ |
| `ShotPlanModel` | Svatební checklist, záběrový plán | ★☆☆☆☆ |
| `ClusterEngine` | DBSCAN nad vektory (až fáze 11) | ★★★☆☆ |

**Tohle je tvoje bezpečná zóna.** Čistý Swift, unit testy, žádné „ono se to nějak chová". Piš sem co nejvíc logiky.

### Vrstva 2 — Média

| Modul | Co dělá | Obtížnost |
|---|---|---|
| `MediaImporter` | NSOpenPanel, Security-Scoped Bookmarks, sonda formátu | ★★☆☆☆ |
| `VFRDetector` | Rozpozná variable frame rate čtením délek vzorků | ★★★☆☆ |
| `ProxyGenerator` | AVAssetReader→Writer, ProRes 422 Proxy, půlrozlišení, VFR→CFR | ★★★☆☆ |
| `CompositionBuilder` | TimelineModel → `AVVideoComposition.Configuration` | ★★★★☆ |
| `PlaybackController` | AVPlayer, seek coalescing, krokování | ★★★☆☆ |
| `ExportEngine` | AVAssetWriter, VideoToolbox, profily | ★★★☆☆ |
| `MetalCompositor` | `AVVideoCompositing` + Metal shadery | ★★★★★ |
| `AudioEngine` | 32-bit float, LUFS normalizace, pitch | ★★★★☆ |

### Vrstva 3 — UI

| Modul | Co dělá | Technologie |
|---|---|---|
| `TimelineView` | Časová osa | **AppKit** — NSView v NSScrollView, CALayer |
| `PlayerView` | Monitor | AppKit v NSViewRepresentable |
| `SpeedRampEditor` | Editor křivky | AppKit (kreslení) |
| Vše ostatní | Panely, inspektor, nastavení, asistent | **SwiftUI** |

**Proč timeline v AppKitu:** SwiftUI nemá recyklaci buněk, nedá ti viditelnost do drag session (nemůžeš ztlumit tažený klip) a nad tisíci prvky se seká. Riverside Studio — placený produkt s týmem — má SwiftUI chrome a timeline jako samostatný C++/Metal engine. Recut je celý AppKit. To je odpověď.

### Vrstva 4 — AI (až za v1.0)

| Modul | Co dělá | Obtížnost |
|---|---|---|
| `SceneDetector` | Detekce střihů přes histogramy | ★★★☆☆ |
| `QualityFilter` | `VNDetectFaceCaptureQualityRequest`, rozostření | ★★☆☆☆ |
| `TranscriptionEngine` | WhisperKit, stahování modelu | ★★★☆☆ |
| `FaceEmbedder` | AuraFace přes Core ML | ★★★★★ |

---

## 4. Fáze

### FÁZE 0 — Spike (1 týden)
Zadání v `SPIKE_0.md`. Nezkracuj ho.

**Hotovo když:** máš vyplněnou tabulku sedmi kritérií.
**Gate:** pokud se nedostaneš ke kroku 3, přejdi na plán „mini-appka" (sekce 8).

---

### FÁZE 1 — Kostra a přehrávač (2 týdny) → v0.1

Xcode projekt, sandbox entitlements, `MediaImporter`, `PlaybackController`, `VFRDetector`.

Klíčové detaily:
- Seek podle Apple QA1820: `toleranceBefore: .zero, toleranceAfter: .zero` + **coalescing** (drž `chaseTime` a `isSeekInProgress`, nikdy nevystřel seek, když jeden běží).
- `VFRDetector` musí existovat hned. Apple nemá API, které ti řekne „tohle je VFR" — musíš číst délky vzorků a hledat rozptyl. Bez toho ti mobilní klipy budou tiše rozjíždět zvuk celý projekt.

**Hotovo když:** otevřeš 4K/60 klip, krokuješ po snímcích, appka ti řekne CFR/VFR a snímkovou frekvenci.

---

### FÁZE 2 — Timeline (4–5 týdnů) → v0.2

Nejtěžší UI v celém projektu. Nepodceňuj to.

`TimelineModel` (čistá logika, testy první), pak `TimelineView` v AppKitu.

Klíčové detaily:
- Jeden `NSView` v `NSScrollView`, klipy jako `CALayer`. Ne `drawRect:` per klip.
- Pravítko a hlavičky stop jako samostatné views synchronizované přes `NSViewBoundsDidChangeNotification` na `contentView.bounds.origin`.
- Vlnové průběhy **předrenderuj do `CGImage` dlaždic per úroveň zoomu** a cachuj. Nikdy nekresli waveform za běhu.
- Operace střihu (split, trim, ripple delete) piš do `TimelineModel` s testy, ne do view.

**Hotovo když:** naimportuješ 10 klipů, poskládáš je, rozstřihneš, přetáhneš, zazoomuješ — a je to plynulé.

---

### FÁZE 3 — Speed ramping ostrý (3 týdny) → v0.3

`SpeedRampEngine` (už máš ze spiku) + `CompositionBuilder` + `SpeedRampEditor` UI.

Klíčové detaily:
- Stav proti `AVVideoComposition.Configuration`, ne proti deprecated `AVMutableVideoComposition`.
- Na klipech bez efektu nastav **`passthroughTrackID`** — compositor se pro ně vůbec nespustí. Zadarmo získaný výkon.
- Pokud tvoje instrukce potřebuje volání pro každý snímek, nastav **`containsTweening = true`**. Tohle je vysvětlení „vynechaných snímků", na které lidé naráží a hlásí je jako bug — AVFoundation správně přeskakuje volání, když ví, že by výstup byl identický.
- Pro náhled nastav **`renderScale < 1.0`**. Největší jediný výkonový zisk u 4K. Funguje jen na `AVPlayerItem`, export renderuje vždy plně.

**Hotovo když:** nakreslíš křivku myší, náhled ji ukáže, zvuk drží.

---

### FÁZE 4 — Proxy a výkon (2 týdny) → v0.4

`ProxyGenerator`. Tahle fáze řeší tři problémy jedním rozhodnutím.

Klíčové detaily:
- **ProRes 422 Proxy (`'apco'`) v polovičním rozlišení.** Ne plné — plné 4K proxy má 182 Mbit/s, což není žádná úspora. FCP dělá půlrozlišení, dělej to taky.
- **Při generování proxy zároveň zploštit VFR na CFR.** Tím se ti vyřeší: proměnlivé snímkování, drahé seekování v dlouhých GOP (ProRes je all-intra, seek je skoro zdarma) a nespolehlivá identita snímků. Jedno rozhodnutí, tři problémy.
- Přes `AVAssetReader` → `AVAssetWriter`, ne `AVAssetExportSession`.
- Zaveď **jednu časovou základnu projektu** a nikdy neodvozuj čísla snímků ze zdrojových časových značek.

**Hotovo když:** 200 GB projekt se stříhá plynule a proxy jde vygenerovat na externí disk.

---

### FÁZE 5 — Projekt a export (3 týdny) → **v0.5 = MVP NULA**

`ProjectModel`, `.projektkrasa` bundle, autosave, `UndoStack`, `ExportEngine`.

Klíčové detaily:
- Export přes `AVAssetWriter` — `AVAssetExportSession` ignoruje `frameDuration`.
- Autosave testuj **vypnutím napájení uprostřed exportu**. Ne teoreticky. Reálně.

**Hotovo když:** projekt přežije pád appky.

---

## 🚧 KILL-GATE 1 — po v0.5

> **Sestříhej touhle appkou celou reálnou svatbu. Od začátku do konce. Bez cheatů.**

Ne test, ne ukázka. Reálná zakázka nebo reálná rodinná svatba.

- **Zvládl jsi to a nebylo to utrpení** → pokračuj fází 6.
- **Zvládl jsi to, ale bolelo to** → další 3 týdny jen na opravy toho, co bolelo. Žádné nové funkce.
- **Nezvládl jsi to** → zastav. Zúži produkt (sekce 8). Tohle je nejdůležitější rozhodnutí v celém plánu.

---

### FÁZE 6 — Svatební asistent (2 týdny) → v0.6

`ShotPlanModel` + SwiftUI. Checklist, záběrový plán, BPM plánovač.

**Nejlevnější odlišení v celém produktu.** Čistý SwiftUI, žádné médiové API, žádné riziko. Zároveň je to jediná věc, kterou DaVinci ani CapCut nemají.

---

### FÁZE 7 — Audio engine (3 týdny) → v0.7

32-bit float přes `AVAudioEngine`, `AVAudioUnitTimePitch`, LUFS normalizace, cross-korelační sync.

Profily hlasitosti dle opravy ve specifikaci: **Web/sociální sítě −14 LUFS** (výchozí), **Vysílání −23 LUFS**.

---

### FÁZE 8 — Titulky (2 týdny) → v0.8

**Doporučení: WhisperKit, ne holý whisper.cpp.**

| | whisper.cpp | WhisperKit |
|---|---|---|
| Balíček | Oficiální XCFramework v1.9.1 jako SPM `binaryTarget` (v repu **není** `Package.swift`) | Normální SPM balíček |
| API | Céčkové — musíš psát Swift↔C lepidlo, resampling na 16 kHz | Swift async API |
| Stahování modelu | Píšeš sám | Automatické |
| Minimum | macOS 13.3 | macOS 14 |
| Licence | MIT | MIT |

Pro tebe je WhisperKit jasná volba. URL: `github.com/argmaxinc/argmax-oss-swift` (repo se přejmenovalo z `WhisperKit`).

**Model: `large-v3-turbo`.** Ne small (34–38 % WER = nepoužitelné), ne medium (~19–21 % a přitom pomalejší i větší než turbo).

Nepoužívej `SwiftWhisper` — je zamrzlý na whisper.cpp z jara 2023 a nemá Metal.

---

### FÁZE 9 — Distribuce (3 týdny) → **v1.0**

Developer ID, hardened runtime, `notarytool`, `stapler`, Sparkle, licencování, freemium limit 3 minuty.

**Korekce specifikace:** stahování modelů za běhu **není** překážkou pro Mac App Store. FreeChat (7,9 MB, stahuje GGUF), Whisper Mate i Whisper Transcription tam takhle běží dnes. Apple DTS to potvrdil.

Co appky z App Store vyhazuje, je **Accessibility API pro vkládání textu do cizích aplikací**. To nedělej a MAS je otevřený.

Přímá distribuce ale zůstává primární: notarizace **není** App Review, jsou to jen automatické bezpečnostní skeny.

Apple Developer Program: 99 USD/rok, pokrývá obojí.

---

## 🚧 KILL-GATE 2 — po v1.0

> **Prodej to. Deseti lidem, kteří tě neznají.**

- **Prodáš** → fáze 10.
- **Neprodáš, ale máš zpětnou vazbu proč** → oprav to, ne stavěj AI.
- **Neprodáš a nikdo neví proč** → problém je v pozicování, ne ve funkcích. Žádná AI to nespraví.

---

### FÁZE 10 — AI analýza scén (2 týdny) → v1.1

`SceneDetector`, `QualityFilter`, generátor 48h teaseru.

**Bezpečná AI** — žádná biometrika, žádné právní riziko, žádné licenční problémy. Vision API, `VNDetectFaceCaptureQualityRequest` (pozor na správný název).

---

### FÁZE 11 — Rozpoznávání obličejů (8–12 týdnů) — **PODMÍNĚNÁ**

Tohle není funkce. Je to samostatný projekt uvnitř projektu.

**Tři gaty, všechny musí projít, než začneš:**

1. **Právní.** Konzultace s právníkem k jedné otázce: spadá lokální seskupování obličejů v osobním médiovém organizéru pod Annex III(1)(a) jako *post* remote biometric identification? Recitál 17 zmiňuje *„soukromá zařízení"* explicitně, což je hák. **Čl. 2(10) tě nechrání — je výslovně jen pro uživatele, ne pro dodavatele.** Termín: 2. 12. 2027.
2. **Licenční.** Jediný komerčně čistý model je **AuraFace-v1** (Apache 2.0). ArcFace, InsightFace, buffalo\_l, EdgeFace, AdaFace — všechny *non-commercial research only*. ⚠️ Z AuraFace repa stáhni **jen `glintr100.onnx`**; zbytek souborů jsou byte-identické kopie InsightFace modelů pod špatnou licencí.
3. **Poptávkový.** Chtěl to aspoň jeden platící zákazník?

**Co to obnáší:** Vision detekce → vlastní zarovnání (Vision nemá špičku nosu, ArcFace ji potřebuje) → AuraFace přes Core ML → L2 normalizace ve Swiftu → cosine přes `cblas_sgemm` → **DBSCAN psaný od nuly** (ve Swiftu neexistuje žádná implementace) → **UI pro ruční slučování a rozdělování skupin**.

To poslední není leštění. Ente na tom pracovalo 21 měsíců s placeným týmem a jejich závěr zní: *„Největší problém je, že neexistuje ground truth, proti které to vyhodnotit."* Každý nasazený systém spoléhá na člověka v cyklu.

**Známé limity, které musíš zákazníkovi říct:** ~20bodový propad přesnosti u východoasijských obličejů (čísla od samotného výrobce modelu) a známý problém s dětmi — PhotoPrism kvůli tomu ships přepínač `SkipChildren`.

**Můj názor: odlož to za v1.2 a zvaž, že to neuděláš nikdy.** Hodnota pro svatebního tvůrce je „najdi mi záběry nevěsty", ale to samé z 80 % vyřeší detekce scén a ruční tagování za zlomek nákladů a s nulovým právním rizikem.

---

### FÁZE 12+ — Backlog

Multicam, HDR, slovenština, LUTs. Optical flow škrtnout.

---

## 5. Session protokol

Každá session:

1. *„Přečti IMPLEMENTACNI_PLAN.md a PROJECT_STATUS.md. Jsme ve fázi X."*
2. **Jeden modul.** Ne dva.
3. Nejdřív logika + testy, až pak UI.
4. `xcodebuild` musí projít, než přijmeš kód.
5. `git commit` po každé funkční drobnosti. Když se to rozbije, `git reset --hard`.
6. Na konci: aktualizuj `PROJECT_STATUS.md`.

**Pravidlo ověřování:** u každého Apple API, které vidíš poprvé, si vyžádej odkaz na `developer.apple.com`. Rešerše k tomuhle plánu našla ve specifikaci **tři** neexistující nebo špatně pojmenovaná API — a jedno z nich předchozí ověřovací průchod výslovně označil za potvrzené.

---

## 6. Testování

| Fáze | Co přibývá |
|---|---|
| 1–2 | Unit testy na `TimelineModel`, `SpeedRampEngine` |
| 3–4 | Výkonnostní testy v Instruments (Time Profiler, Allocations) |
| 5 | Regrese exportu — checksum výstupu po každé změně enginu |
| 5 | **Test vypnutím napájení uprostřed exportu** |
| 6+ | Beta na reálné svatbě |

Fixní testovací sada od fáze 1: 4K/60 CFR, 4K/30 VFR z mobilu, 120fps slow-mo, 32-bit float audio, klip s mluvenou češtinou.

---

## 7. Rozhodnutí, která nejdou odložit

| Rozhodnutí | Kdy | Proč teď |
|---|---|---|
| AppKit timeline | Fáze 2 | Přepis z SwiftUI později = týdny |
| Jedna časová základna projektu | Fáze 1 | Prorůstá vším |
| `AVVideoComposition.Configuration` | Fáze 3 | Nezačínej na deprecated API |
| VFR→CFR v proxy | Fáze 4 | Mění datový model |
| `AVAssetWriter` místo ExportSession | Fáze 5 | Jinak přepisuješ export |

Odložit naopak klidně můžeš: cenu, App Store vs DMG, slovenštinu, LUTs, název.

---

## 8. Plán B — když to nevyjde

Není to selhání, je to jiný produkt.

**„Krása Ramp"** — jedna mini-appka. Nahodíš klip, nakreslíš křivku, exportuješ. Fáze 0–1, 3, 5 bez timeline. Zhruba 6 týdnů místo 6 měsíců. Prodejné za 490 Kč. Dokončitelné.

**„Svatební asistent"** — checklist, záběrový plán, kalkulace dat a baterek jako PWA v Reactu, který umíš. Pár dnů. Ověří niku bez řádky Swiftu.

Obojí jde postavit i **vedle** hlavního projektu jako pojistka.

---

## 9. Co v tomhle plánu není ověřené

Poctivě, ať víš, kde stojíš na měkkém:

- **Nikdo nikdy nepublikoval benchmark vlastního `AVVideoCompositing` držícího 4K/60 náhled.** Ani pozitivní, ani negativní. Proto je Spike 0 fáze nula a ne příprava.
- Ze čtyř komerčních macOS video appek, jejichž binárky šly rozebrat, **žádná nekompozituje přes `AVVideoComposition`** — všechny mají vlastní engine. To může znamenat, že to nestačí, nebo že chtěly Windows. Nevíme.
- Odhady časů jsou moje, ne měřené. Násobek 1,7 je odhad odhadu.
- Zda `AVAssetWriter` s ProRes Proxy skutečně zapne hardwarový engine, nejde přes API zjistit. Změř to.
- Rychlost Whisperu na bezventilátorovém Airu — všechna publikovaná čísla jsou z aktivně chlazených strojů. Počítej s horším koncem rozsahu.

---

*Plán se reviduje po každém kill-gate. Ne dřív, ne později.*
