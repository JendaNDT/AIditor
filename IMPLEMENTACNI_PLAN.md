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
| 1 | **`AVMutableVideoComposition` je od macOS 26 deprecated.** Náhrada `AVVideoComposition.Configuration` (struct, `Sendable`) je ale `@available(macOS 26.0, *)`. | **Píšeš dál proti `AVMutableVideoComposition`.** Deployment target je 14.0, kde `Configuration` neexistuje — na macOS 14–25 je deprecated API jediná možnost. Deprecated ≠ odstraněné. Warning umlčuj cíleně u konkrétního volání, nikdy globálně. Dvojí větev pod `if #available(macOS 26.0, *)` je úkol pro fázi 9, ne pro teď. |
| 2 | **Whisper-small je pro češtinu nepoužitelný** — 34–38 % WER, každé třetí slovo špatně. | Model ze specifikace se mění na **large-v3-turbo** (~13 % WER, stejná velikost jako medium, násobně rychlejší). Medium nemá důvod existovat. |
| 3 | **`SpeechAnalyzer` češtinu nepodporuje.** V seznamu 42 locale není `cs_CZ` ani `pl_PL`. | Sekce 4.3.1 specifikace („sledovat vývoj, mohlo by nahradit Whisper") se ruší. Whisper je jediná cesta, ne dočasné řešení. |
| 4 | **Modely pro rozpoznávání obličejů jsou z velké části komerčně zakázané.** InsightFace/ArcFace/buffalo\_l: *„non-commercial research purposes only"*. | Face grouping se odsouvá až za v1.0 a stává se podmíněnou fází. Jediný čistý model je **AuraFace-v1** (Apache 2.0). |
| 5 | **EU AI Act: výjimka pro osobní použití nechrání tebe.** Čl. 2(10) je výslovně jen pro *deployera*. Jako dodavatel software jsi mimo. | Face grouping dostává právní gate. Termín pro Annex III je po Digital Omnibus **2. 12. 2027**, ne 2026 — máš čas, ale ne bianko šek. |
| 6 | **MacBook Air M4 má hardwarový ProRes engine.** Chyběl jen základnímu M1. | Proxy workflow v ProRes 422 Proxy je na tvém stroji reálný. Dobrá zpráva — jedna obava padá. |
| 7 | **`AVAssetExportSession` ignoruje `frameDuration`.** Kompozice, která hraje v 60 fps, se vyexportuje ve 30. | Export se od začátku píše přes `AVAssetWriter`, ne `AVAssetExportSession`. |

Plus dvě věci z minula, které zůstávají v platnosti:

- `scaleTimeRange` dělá **konstantní** změnu rychlosti. Plynulá křivka = **segmentace, a nic jiného.** `CMTimeMapping` je dvojice `CMTimeRange`, takže mapování je afinní z definice. Vlastní compositor to neřeší: `sourceFrame(byTrackID:)` mu vrátí snímek, který kompozice pro daný `compositionTime` už vybrala, a požádat o jiný zdrojový čas nejde. Compositor je na pixely, ne na čas.
- `AVVideoComposition.Configuration` **neobsahuje žádné časování** — jen instrukce, transformace, průhlednost, ořez a barvy. S rychlostní křivkou nemá nic společného a nikdy mít nebude. Ať to nikoho příště nemate.

A jedno zjištění z měření ve Spiku 0 (26. 07. 2026), které mění produkt, ne jen kód:

- **Zpomalení potřebuje dost snímků ve zdroji: `zdrojFps × nejnižšíRychlost ≥ výstupFps`.** Jinak se snímky duplikují a zpomalený úsek trhá. Naměřeno: 120 fps zdroj → 0 % duplikátů, 59,7 fps → 13,5 %, 30,0 fps → 37,5 %. Teorie (`průměr z max(0, 1 − v(t)·zdrojFps/výstupFps)`) sedí na 0,04 %.
  - **Plyne z toho tvrdý limit, ne varování:** `maximální čisté zpomalení = výstupFps / zdrojFps`. Posuvník rychlosti dostane pod tou hranicí **žlutou zónu**. Při výstupu 30 fps: zdroj 60 → 0,5×, 120 → 0,25×, 240 → 0,125×.
  - **Nižší výstupní frekvence by dala hlubší čisté zpomalení** (při 24 fps: 60 → 0,4×, 120 → 0,2×). **Zvažovalo se a zamítlo:** základna je 30 fps, protože 60 → 24 je poměr 2,5:1 a trhalo by to při panorámování. Viz tabulka v `CLAUDE.md`.
  - **Filipa to řeší, Alenu ne.** Filip točí sám a může se zařídit — jemu stačí limit říct dopředu (říká mu ho žlutá zóna v editoru křivek; checklist svatebního asistenta, který to měl říkat týden před svatbou, byl škrtnut — viz fáze 6). Alena skládá film z cizích videí od hostů na 30 fps a zařídit se nemůže. Pro ni je duplikace s přiznaným varováním **legitimní chování, ne nedodělek** — ale musí být v UI přiznané. Tvrdit jí, že výstup je plynulý, když není, je horší než ta duplikace sama.
- Vision **nemá** veřejné API pro otisk obličeje. `VNGenerateFaceCaptureQualityRequest` navíc neexistuje — správně je `VNDetectFaceCaptureQualityRequest`.

---

## 2. Realita rozsahu

Při 30 h týdně:

| Meta | Co to je | Odhad | Po korekci ×1,7 |
|---|---|---|---|
| **v0.5 „MVP nula"** | Import, timeline, střih, speed ramp, proxy, export, projekt | ~15 týdnů | **~6 měsíců** |
| **v1.0** | + audio engine, titulky, distribuce | +8 týdnů | **~9 měsíců** |
| **v1.2** | + AI analýza scén a obličejů | +12 týdnů | **~12 měsíců** |
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
| `ClusterEngine` | DBSCAN nad vektory (až fáze 11) | ★★★☆☆ |

**Tohle je tvoje bezpečná zóna.** Čistý Swift, unit testy, žádné „ono se to nějak chová". Piš sem co nejvíc logiky.

### Vrstva 2 — Média

| Modul | Co dělá | Obtížnost |
|---|---|---|
| `MediaImporter` | NSOpenPanel, Security-Scoped Bookmarks, sonda formátu | ★★☆☆☆ |
| `VFRDetector` | Rozpozná variable frame rate čtením délek vzorků | ★★★☆☆ |
| `ProxyGenerator` | AVAssetReader→Writer, ProRes 422 Proxy, půlrozlišení, VFR→CFR | ★★★☆☆ |
| `CompositionBuilder` | TimelineModel → `AVMutableComposition` + `AVMutableVideoComposition` | ★★★★☆ |
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
| Vše ostatní | Panely, inspektor, nastavení | **SwiftUI** |

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

### FÁZE 0 — Spike (1 týden) ✅ UZAVŘEN 26. 07. 2026
Zadání v `SPIKE_0.md`. Nezkracuj ho.

**Hotovo když:** máš vyplněnou tabulku sedmi kritérií.
**Gate:** pokud se nedostaneš ke kroku 4 (rampu), přejdi na plán „mini-appka" (sekce 8).

**Pozor na pořadí:** zploštění VFR→CFR je v `SPIKE_0.md` nově krok 3, tedy **před** rampem. Sonda `MediaProbe` naměřila, že ani jeden testovací klip nemá konstantní časování — pouštět ramp na VFR zdroji znamená měřit dvě proměnné najednou.

---

### FÁZE 1 — Kostra a přehrávač (2 týdny) → v0.1 ✅ HOTOVÁ 27. 07. 2026

Xcode projekt, sandbox entitlements, `MediaImporter`, `PlaybackController`, `VFRDetector`.

Klíčové detaily:
- Seek podle Apple QA1820: `toleranceBefore: .zero, toleranceAfter: .zero` + **coalescing** (drž `chaseTime` a `isSeekInProgress`, nikdy nevystřel seek, když jeden běží).
- `VFRDetector` musí existovat hned. Apple nemá API, které ti řekne „tohle je VFR" — musíš číst délky vzorků a hledat rozptyl. Bez toho ti mobilní klipy budou tiše rozjíždět zvuk celý projekt.

**Hotovo když:** otevřeš 4K/60 klip, krokuješ po snímcích, appka ti řekne CFR/VFR a snímkovou frekvenci.

#### Naměřeno 26. 07. 2026 — utáhne `AVPlayer` náhled 4K?

Otázka, kterou Spike 0 nemohl zodpovědět, protože přehrávač neexistoval.

| soubor | zdroj | ustálený stav | odchylka | medián seeku | p95 |
|---|---|---|---|---|---|
| `202947.mp4` | HEVC 4K/60 | **60,3 fps** | 3,6 | **48,3 ms** | 92,3 ms |
| `202947_cfr.mov` | ProRes Proxy 4K/60 | **60,1 fps** | 3,6 | **6,2 ms** | 7,5 ms |
| `203813.mp4` | HEVC 4K/120 | **60,7 fps** | 5,0 | **97,0 ms** | 170,8 ms |

**Ano, utáhne.** Všechny tři na stropu 60Hz displeje, doručování vyrovnané — v ustáleném stavu nespadlo žádné jednosekundové okno pod 59.

**Omezení, se kterými ta čísla platí:**

- ⚠️ **Okno bylo 640×596 bodů, tedy 1280×1192 px.** Přehrávač dostal jen část minimálního okna. Škálování 4K na 1280 je míň GPU práce než na celou obrazovku — **na celoobrazovkovém náhledu můžou být čísla horší. PŘEMĚŘIT VE FÁZI 2**, až timeline zabere zbytek plochy.
- **Strop je 60 Hz displeje.** U 120fps klipu se nedá zjistit, kolik by doručil na rychlejším panelu — jen že drží 60. Pro editaci na 30fps základně je to jedno.
- **Závěr platí i pod škrcením.** První běh proběhl na baterce se zapnutým úsporným režimem a dal 58,5 fps, tedy pořád ✅. Finální čísla jsou ze sítě bez škrcení.

> #### Poučení: bez předem napsaného prahu by z toho vyšel věrohodný nesmysl
>
> První běh dal u 120fps klipu **45,5 fps** a verdikt „použitelné, ale proxy pomůže".
>
> Bylo to špatně. Měřilo se 15 s, ale klip má 11,36 s — poslední tři jednosekundová okna (`0 0 0`) nebyly zádrhely, ale **konec videa**. Průměr je stáhl dolů.
>
> **Nebezpečné na tom je, že to znělo věrohodně.** „120 fps je náročnější, proto míň snímků" dává smysl, sedí to na intuici a zapsalo by se to jako nález. Odhalilo to jen porovnání s **prahem napsaným dopředu**: 45,5 nesedělo do žádné kategorie, která by u téhle třídy souborů dávala smysl, a to donutilo podívat se na syrová data místo na průměr.
>
> Po opravě: **60,7 fps**. Verdikt se otočil.
>
> Praxe, která z toho plyne: **napiš prahy dřív, než uvidíš čísla** — a když číslo nesedí do očekávání, nejdřív zkontroluj měřidlo, teprve pak vykládej výsledek.

---

### FÁZE 2 — Timeline (4–5 týdnů) → v0.2 ✅ HOTOVÁ 28. 07. 2026

Nejtěžší UI v celém projektu. Nepodceňuj to.

`TimelineModel` (čistá logika, testy první), pak `TimelineView` v AppKitu.

> ### 🚩 PODMÍNKA, ne nápad: dvojí cesta k assetu od začátku
>
> **Datový model musí u každého assetu nést dvě cesty — originál a volitelnou proxy — a přehrávání musí umět vybrat, kterou použije.**
>
> Proxy se **generovat nemusí** až do fáze 4. Ale ta struktura tam musí být **hned**, protože doplnit ji dodatečně znamená přepsat datový model i playback, a to je v půlce nejtěžší fáze projektu.
>
> Konkrétně:
> - `Asset` má `originalURL` a `proxyURL: URL?`
> - k tomu volbu, která se má použít — per projekt, ne per klip (přepínač „pracovat s proxy" je jedna věc, ne tisíc)
> - `PlaybackController` a `CompositionBuilder` berou **rozhodnutou URL**, ne asset — ať se ta volba dělá na jednom místě
> - časová základna se bere z **originálu**, ne z proxy; proxy je jen jiná reprezentace téhož
>
> Důvod je měřený: proxy je kvůli odezvě seeku (6 ms vs 48 ms, viz fáze 4), a odezva seeku je přesně to, co dělá timeline použitelnou nebo nepoužitelnou. Bez dvojí cesty v modelu se ta výhoda nedá zapnout, až bude potřeba.

Klíčové detaily:
- Jeden `NSView` v `NSScrollView`, klipy jako `CALayer`. Ne `drawRect:` per klip.
- Pravítko a hlavičky stop jako samostatné views synchronizované přes `NSViewBoundsDidChangeNotification` na `contentView.bounds.origin`.
- Vlnové průběhy **předrenderuj do `CGImage` dlaždic per úroveň zoomu** a cachuj. Nikdy nekresli waveform za běhu.
- Operace střihu (split, trim, ripple delete) piš do `TimelineModel` s testy, ne do view.

**Hotovo když:** naimportuješ 10 klipů, poskládáš je, rozstřihneš, přetáhneš, zazoomuješ — a je to plynulé.

---

### FÁZE 3 — Speed ramping ostrý (3 týdny) → v0.3 ✅ HOTOVÁ 28. 07. 2026

`SpeedRampEngine` (už máš ze spiku) + `CompositionBuilder` + `SpeedRampEditor` UI.

Klíčové detaily:
- **Stav proti `AVMutableVideoComposition`.** Je deprecated od macOS 26, ale `AVVideoComposition.Configuration` je `@available(macOS 26.0, *)` a deployment target je 14.0 — na macOS 14–25 by ti appka s `Configuration` spadla při startu. Warning umlč cíleně u konkrétního volání (`@available(macOS, deprecated:)` obálka nebo lokální `#pragma`/diagnostic push), **ne globálním vypnutím deprecation warningů** — to bys přišel o varování u všeho ostatního.
- **Rychlostní křivku dělej segmentací.** Vlastní compositor ti s časováním nepomůže (viz sekce 1) — má smysl jen pro efekty a Metal. Segmenty ti spočítá `SpeedRampEngine.segments(outputFrameRate:framesPerSegment:)`.
- **Segmentuj podle meze skoku rychlosti: `segmentation(outputFrameRate:maxSpeedStep:)`, výchozí mez 0,015.** Spike 0 změřil, že **zvuk je na jemnosti segmentace nezávislý** (lupance nejsou ani při 545 segmentech), takže rozhoduje velikost kompozice. Pevný `framesPerSegment` je ale špatná veličina — skok závisí na délce klipu, `8` dá na 45s klipu 0,96 % a na 11s klipu 3,79 %. Engine si počet úseků dopočítá sám z maximální strmosti křivky: 11s klip dostane 3 snímky na úsek, 45s klip 12, oba skok ~1,43 %.
  ⚠️ **Mez nemusí být dosažitelná** — při jednom snímku na úsek je podlaha `max|dv/dt| / fps`. `SegmentationPlan.limitedByFrameRate` to hlásí a **UI to musí zobrazit**, ne spolknout.
- **Korekce výšky: `.timeDomain` výchozí, ale volitelná.** `.spectral` je fázový vokodér a rozmazává transienty — na ráně sekerou je to slyšet jako plechovost. `.timeDomain` je zachovává. Na drženém hudebním tónu by to dopadlo obráceně, proto volitelné: `.spectral` i `.varispeed` (bez korekce). Sedí na `AVAssetReaderTrackOutput.audioTimePitchAlgorithm`.
  Ve svatebních filmech se zpomalené záběry **typicky podkládají hudbou, ne původním zvukem**, takže kvalita 4× roztaženého zvuku je v praxi méně kritická, než vypadá — ta stopa ve výsledku často vůbec nebude. Neznamená to, že na tom nezáleží: kdo nechá původní zvuk (proslov, přípitek, smích), pro toho je volba algoritmu důležitá.
- Na klipech bez efektu nastav **`passthroughTrackID`** — compositor se pro ně vůbec nespustí. Zadarmo získaný výkon.
- Pokud tvoje instrukce potřebuje volání pro každý snímek, nastav **`containsTweening = true`**. Tohle je vysvětlení „vynechaných snímků", na které lidé naráží a hlásí je jako bug — AVFoundation správně přeskakuje volání, když ví, že by výstup byl identický.
- Pro náhled nastav **`renderScale < 1.0`**. Největší jediný výkonový zisk u 4K. Funguje jen na `AVPlayerItem`, export renderuje vždy plně.
- **`SpeedRampEditor` musí kreslit žlutou zónu pod `výstupFps / zdrojFps`.** Pod tou hranicí se snímky duplikují (viz sekce 1). Limit se počítá per klip ze změřené frekvence zdroje, ne z nominální — `MediaProbe`/`VFRDetector` ji už umí. Uživatel to má vidět při tažení křivky, ne až po exportu.

**Hotovo když:** nakreslíš křivku myší, náhled ji ukáže, zvuk drží.

---

### FÁZE 4 — Proxy a výkon (2 týdny) → v0.4 ✅ HOTOVÁ 28. 07. 2026 (kritérium 200GB reálného materiálu se ověří při kill-gate)

`ProxyGenerator`. Tahle fáze řeší tři problémy jedním rozhodnutím.

> **⚠️ Zdůvodnění proxy se po měření ve fázi 1 změnilo. Ne kvůli přehrávání — kvůli scrubování.**
>
> `AVPlayer` utáhne 4K/60 i 4K/120 HEVC bez problémů: **60,3 a 60,7 fps** ustáleného stavu, tedy strop 60Hz displeje. Proxy kvůli plynulosti přehrávání **není potřeba**.
>
> Rozdíl je v **odezvě seeku**:
>
> | zdroj | medián seeku |
> |---|---|
> | HEVC 4K/60 | **48,3 ms** |
> | ProRes 422 Proxy 4K/60 | **6,2 ms** |
> | HEVC 4K/120 | **97,0 ms** |
>
> **Osmkrát rychleji.** ProRes je intra-only — každý snímek je samostatný. HEVC musí při skoku dekódovat od nejbližšího klíčového snímku dopředu, a se zero tolerance (kterou v editoru mít musíme, jinak skáče na klíčové snímky) se to obejít nedá.
>
> 48 ms je pořád svižné, ale u timeline s tisíci klipy se to sčítá — a 97 ms u 120fps zdroje je už na hraně prahu. **Proxy je tedy o odezvě editace, ne o plynulosti obrazu.** Argumentovat jinak by znamenalo řešit problém, který neexistuje.

Klíčové detaily:
- **ProRes 422 Proxy (`'apco'`) v polovičním rozlišení.** Ne plné — plné 4K proxy má 182 Mbit/s, což není žádná úspora. FCP dělá půlrozlišení, dělej to taky.
- **Při generování proxy zároveň zploštit VFR na CFR.** Tím se ti vyřeší: proměnlivé snímkování, drahé seekování v dlouhých GOP (ProRes je all-intra, seek je skoro zdarma) a nespolehlivá identita snímků. Jedno rozhodnutí, tři problémy.
- Přes `AVAssetReader` → `AVAssetWriter`, ne `AVAssetExportSession`.
- Zaveď **jednu časovou základnu projektu** a nikdy neodvozuj čísla snímků ze zdrojových časových značek.

**Hotovo když:** 200 GB projekt se stříhá plynule a proxy jde vygenerovat na externí disk.

---

### FÁZE 5 — Projekt a export (3 týdny) → **v0.5 = MVP NULA** ✅ HOTOVÁ 28. 07. 2026

`ProjectModel`, `.projektkrasa` bundle, autosave, `UndoStack`, `ExportEngine`.

Klíčové detaily:
- Export přes `AVAssetWriter` — `AVAssetExportSession` ignoruje `frameDuration`.
- Autosave testuj **vypnutím napájení uprostřed exportu**. Ne teoreticky. Reálně.

**Hotovo když:** projekt přežije pád appky.

---

## 🚧 KILL-GATE 1 — ~~po v0.5~~ PŘESUNUT na konec vývoje

**Rozhodnutí autora 28. 07. 2026:** svatební materiál bude až ~koncem srpna 2026, vývoj mezitím pokračuje vylepšovacími fázemi 10–16. Gate v plné podobě je zapsaný za fází 16; kritéria („zvládl / bolelo / nezvládl") platí beze změny, jen se vyhodnotí nad kompletnější aplikací.

---

### ~~FÁZE 6 — Svatební asistent~~ — ŠKRTNUTO 28. 07. 2026

**Rozhodnutí autora: produkt je čistě videoeditor.** Checklist, záběrový plán ani BPM plánovač se stavět nebudou. Číslování fází se kvůli odkazům v ostatních dokumentech nemění — po fázi 5 následuje rovnou fáze 7 (a verze v0.6 se přeskakuje).

**Co ze škrtnuté fáze přežívá, protože to není „funkce asistenta", ale podmínka funkčnosti rampingu:** pravidlo „záběry na zpomalení toč na 120 fps" (hod kyticí, first look, první polibek, prstýnky, první tanec). Důvod je měřený: ramp na 0,25× při výstupu 30 fps potřebuje zdroj 120 fps, jinak se každý třetí až osmý snímek duplikuje (viz sekce 1). Asistent to měl říkat týden **před** svatbou; bez něj to musí unést editor sám:

- **Žlutá zóna v editoru rychlostních křivek** (hotová ve fázi 3) ukazuje mez čistého zpomalení z naměřené frekvence zdroje.
- **Varování `limitedByFrameRate` a duplikace** musí zůstat v UI přiznané — pro Alenu (cizí klipy na 30 fps) je duplikace legitimní výsledek, ale nikdy se nesmí tvářit jako plynulý.

Jako samostatný produkt mimo tuhle aplikaci zůstává myšlenka v sekci 8 (Plán B — PWA, nula Swiftu).

---

### FÁZE 7 — Audio engine (3 týdny) → v0.7 ✅ HOTOVÁ 28. 07. 2026

32-bit float přes `AVAudioEngine`, `AVAudioUnitTimePitch`, LUFS normalizace, cross-korelační sync.

Profily hlasitosti dle opravy ve specifikaci: **Web/sociální sítě −14 LUFS** (výchozí), **Vysílání −23 LUFS**.

---

### FÁZE 8 — Titulky (2 týdny) → v0.8 ✅ HOTOVÁ 28. 07. 2026

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

### FÁZE 9 — Distribuce (3 týdny) → **v1.0** ✅ UZAVŘENA 28. 07. 2026 v rozsahu osobní aplikace (podpis/notarizace/Sparkle odloženy; migrace na Configuration NEPROBĚHLA — viz níž)

~~Developer ID, hardened runtime, `notarytool`, `stapler`, Sparkle.~~

**CELÁ DISTRIBUCE ODLOŽENA — rozhodnutí autora 28. 07. 2026: aplikace je zatím jen pro něj, Developer účet (99 USD/rok) se neplatí.** Bez účtu není podpis ani notarizace, bez šíření nemá smysl Sparkle. Appka se spouští z vlastního buildu na vlastním stroji. Z fáze 9 se neudělalo nic — ani migrace kompozice (viz opravu níž). Kdyby se autor někdy rozhodl appku šířit, tahle sekce je návod, co bude potřeba.

**Licencování a freemium limit VYNECHÁNY — rozhodnutí autora 28. 07. 2026: aplikace bude free.** Cena 1 490 Kč ze specifikace (sekce o monetizaci) neplatí.

**+ Migrace kompozice na `AVVideoComposition.Configuration` — NEHOTOVÁ, a je to správně.**
⚠️ **Oprava zápisu 30. 07. 2026:** dřívější verze tohohle odstavce tvrdila, že migrace „hotová" je.
Není — ověřeno grepem, v `Krasa/` není ani jedno `#available(macOS 26.0, *)` a `CompositionBuilder`
staví výhradně na `AVMutableVideoComposition`. A tak to má zatím zůstat: deployment target je 14.0,
kde `Configuration` NEEXISTUJE, takže migrace znamená přidat druhou větev, ne vyměnit první
(pravidlo v `CLAUDE.md`). Je to úkol před vydáním; dokud se appka nešíří, nemá kdo z něj mít užitek.

- `CompositionBuilder` dostane dvě větve pod `if #available(macOS 26.0, *)`: novou přes `AVVideoComposition(configuration:)`, starou přes `AVMutableVideoComposition`. Obě za jedním vlastním rozhraním, ať se to nerozlézá po kódu.
- Totéž pro `AVVideoCompositionInstruction.Configuration` a `AVVideoCompositionLayerInstruction.Configuration`.
- **Starou větev nesmíš smazat**, dokud je deployment target 14.0. Motivace je odklidit warningy a být připravený na den, kdy Apple API opravdu odstraní — ne zbavit se funkčního kódu.
- Napsat se to musí dvakrát, ale jen jednou a na jednom místě. Odhad: 2–3 dny, ne týden.
- **Netýká se speed rampingu.** `Configuration` časování neobsahuje, segmentace zůstane beze změny.

**Korekce specifikace:** stahování modelů za běhu **není** překážkou pro Mac App Store. FreeChat (7,9 MB, stahuje GGUF), Whisper Mate i Whisper Transcription tam takhle běží dnes. Apple DTS to potvrdil.

Co appky z App Store vyhazuje, je **Accessibility API pro vkládání textu do cizích aplikací**. To nedělej a MAS je otevřený.

Přímá distribuce ale zůstává primární: notarizace **není** App Review, jsou to jen automatické bezpečnostní skeny.

Apple Developer Program: 99 USD/rok, pokrývá obojí.

---

## 🚧 KILL-GATE 2 — po v1.0

**ODLOŽEN spolu s distribucí (28. 07. 2026): appka je zatím jen pro autora, takže gate „ověř zájem cizích lidí" nemá co měřit.** Kdyby se někdy šířila, platí přeformulovaná verze: dostaň ji k deseti lidem, kteří tě neznají, a ať s ní sestříhají vlastní video. Jediný gate, který teď platí, je KILL-GATE 1 — sestříhat s ní vlastní reálnou svatbu.

---

## Vylepšovací fáze 10–16 (sestaveno 28. 07. 2026)

**Kontext:** kill-gate 1 se přesouvá NA KONEC vývoje — svatební materiál bude ~za měsíc (konec srpna 2026). Fáze 10–16 vznikly výběrem z dokumentu `Projekt_Krasa_navrh_implementace.docx` (vzat zásobník nápadů, ne jeho plán — neznal stav projektu) + z našich odložených drobností. Nevybrané nápady dokumentu jsou v podmíněných fázích a backlogu s důvodem.

**Přejatá produktová zásada (dobrá):** automatická analýza NIKDY sama nestříhá — všechno jsou značky a návrhy, které uživatel přijme nebo zahodí.

Pořadí: nejdřív díry v základní výbavě filmu (přechody, texty, barvy — bez nich hotový svatební film nejde odevzdat), pak vlajková hudební synchronizace, pak analýzy. Odhady neuvádím v týdnech — dosavadní tempo je fáze za den až dva; platí ale korekce ×1,7 na hledání „proč to nefunguje".

---

### FÁZE 10 — Přechody → v0.10 ✅ HOTOVÁ 28. 07. 2026

Prolínačka, zatmívačka (černá/bílá) a zvukový crossfade na střihu.
*Dopadlo podle plánu; GPU skok video kompozice změřen (klid 0–3 %, bez kompozice 0–10 %, s kompozicí 8–16 %, medián ~12 % — `ioreg`, srovnatelné jen mezi sebou). Detaily v `PROJECT_STATUS.md`.*

- **Model nejdřív:** `Transition` patří STŘIHU mezi sousedy (typ, délka v snímcích). Klíčová validace: prolínačka spotřebovává zdroj ZA hranou střihu na obou stranách — meze přes `remainingSourceFrames`/`availableSourceFramesBefore` (s rampou je už umí přepočítávat). První verze: přechod na rampovaném střihu zakázat (kombinace = zvláštní případy; povolit až bude důvod).
- **Kompozice:** dvě obrazové stopy střídavě (A/B roll) + instrukce `AVVideoComposition` s opacity rampou přes překryv; zvuk crossfade přes `AVAudioMix` volume rampy (`setVolumeRamp`). Tady **poprvé vznikne video kompozice v přehrávání** — ⚠️ podle měření z fáze 1 to přepne náhled ze samostatné vrstvy do skládání přes GPU (0,25 % → skok). Změřit HNED v modulu kompozice a zapsat čísla; je to očekávaný, plánovaný skok, ne regrese.
- **UI:** přechod z kontextového menu střihu, kreslení na ose (lichoběžník přes hranu), délka tažením okraje.

---

### FÁZE 11 — Texty, titulky a stopa T1 → v0.11 ✅ HOTOVÁ 29. 07. 2026

Jména, datum, kapitoly, závěrečné poděkování — grafické titulky s českými šablonami.

- **Model:** nový druh stopy `.title` (T1) a titulkový klip (text, šablona, zarovnání). Stopa se přidá do výchozího projektu; starší projektové soubory bez ní se dál načtou.
- **Náhled:** overlay vzorcem `SubtitleOverlay` (kreslí se jen když má co říct — chrání GPU baseline). ~~**Export:** `AVVideoCompositionCoreAnimationTool`~~
  ⚠️ **Oprava proti původnímu znění (29. 07. 2026):** `AVVideoCompositionCoreAnimationTool` se NEPOUŽIL. Je dokumentovaný pro `AVAssetExportSession`, kterou projekt schválně nepoužívá (ignoruje `frameDuration` — celý důvod existence `CFRRendereru`); jeho chování na cestě `AVAssetReader`+`AVAssetWriter` dokumentace nepopisuje — pravidlo 6. Titulky vypaluje `frameDecorator` v `CFRRendereru` (CoreImage nad NV12, jen na snímcích s titulkem; ostatní projdou bajt po bajtu — změřeno, odchylka mimo titulek 0,14). Zapsáno i v `CLAUDE.md`.
- **Splácí dvě odložené drobnosti:** pruh T1 na ose kreslí i titulky z řeči (fáze 8) a přibude editace textu titulků (inspektor vybraného titulku). *Obojí splaceno; navíc editace textu titulků z řeči přímo z pásku na T1.*

---

### FÁZE 12 — Fotky a Ken Burns → v0.12 ✅ HOTOVÁ 29. 07. 2026

- Import fotek (HEIC/JPEG) jako asset bez zvuku; klip s volnou délkou na V1.
- **Ken Burns:** počáteční a koncový výřez → `TransformRamp` v instrukcích kompozice (lineární rampy stačí — pohyb je pomalý a krátký).
- **Freeze frame jako fotka:** „zmrazit snímek" vytáhne aktuální snímek do fotky na ose. ⚠️ NE přes `SpeedRampEngine` — zákaz nulové rychlosti kvůli invertibilitě mapování platí dál; fotka na ose je čistší cesta.
- *Doplněk z realizace: fotka hraje přes „still movie" mezisoubor (`StillMovieStore` — jeden ProRes snímek v rozměru plátna s vpáleným aspect-fitem, roztažený `scaleTimeRange`); bez Ken Burns a přechodů tak nevzniká video kompozice a GPU baseline platí i s fotkami. Výřezy KB jsou normalizované vůči plátnu.*

---

### FÁZE 13 — Barevné presety → v0.13 ✅ HOTOVÁ 29. 07. 2026

Jemný svatební vzhled, teplý film, čistá pleť, ČB — per klip, intenzita 0–100 %.

- Technika: Core Image filtry v kompozici. Rozhodnout v modulu 1 mezi `AVVideoComposition(applyingCIFiltersWith:)` (handler zná čas → umí per-klip řízení) a vlastním compositorem; kritérium je shoda náhled/export a výkon. ⚠️ Další kandidát na GPU skok — měřit.
- LUT soubory (.cube) až v backlogu; presety stačí jako pojmenované řetězce CIFilterů.

---

### FÁZE 14 — Hudební synchronizace → v0.14 (vlajková funkce) ✅ HOTOVÁ 29. 07. 2026

Střihy a rychlosti reagující na hudbu. Sedí na hotové jádro: FFT máme vlastní (`AudioEngine`), rychlostní matematiku taky (`SpeedRampEngine`).

- **Modul 1 — `BeatGrid` v `AudioEngine`:** onsety (energie + spektrální tok přes vlastní FFT), odhad tempa, mřížka hlavních/vedlejších dob, ruční korekce prvního taktu a násobku tempa. Čistý Swift, testy na syntetických klikových stopách se známým tempem.
- **Modul 2 — hudební mapa na ose:** doby z klipu na A2 jako značky v pravítku; **magnetické přichytávání** střihů a klipů na doby = nový druh kandidáta v `TimelineGeometry` (otestovatelné bez UI, síla kandidáta mezi „hrana klipu" a „mřížka snímků").
- **Modul 3 — dopasování na dobu:** „přizpůsobit klip" = konstantní změna rychlosti v mezích 90–115 %, ⚠️ **vždy nad limitem čistého zpomalení** (`výstupFps/zdrojFps` — žlutá zóna platí i tady); „rampa na úder" = preset `SpeedRampEngine` končící zpomalením přesně na době. **Při velké odchylce nevynucovat** — nabídnout trim nebo jiný bod (zásada přiznaných mezí).

---

### FÁZE 15 — Analýzy kvality záběrů → v0.15 ✅ HOTOVÁ 29. 07. 2026

Nahrazuje původní fázi „AI analýza scén". Návrhová vrstva, žádné automatické zásahy.

- **Detekce neostrosti:** Laplaceova ostrost + hrany přes vImage/Accelerate na zmenšených náhledech, 2–5 vzorků/s, cache otiskem souboru (vzorec vln). Barevné značky na klipu (zelená/oranžová/červená), klik = seek. Pohybové rozmazání řešit konzervativně: nastavitelná citlivost, ne chytristika.
- **Detekce ticha a prázdna:** RMS + přítomnost řeči (máme K-váhování) × jas/entropie/pohyb obrazu; minimální délka úseku 3–10 s. Tichý statický záběr na dekoraci NENÍ chyba — kombinovat oba signály.
- Generátor „48h teaseru" z původní fáze 10 → backlog (stojí na detekci momentů, která je podmíněná).

---

### FÁZE 16 — Vymazlení a technické dluhy → v1.0-osobní ✅ HOTOVÁ 29. 07. 2026

- Zvukové fade úchyty na klipech (nájezd/dojezd per klip přes `AVAudioMix` rampy).
- Strop normalizace na **true peak (dBTP)** — 4× převzorkování ve špičkovém měření (`AudioEngine`), místo dnešní špičky vzorků.
- Správa modelu Whisperu (zobrazit velikost, smazat, přemístit).
- Zbylé drobnosti z koukanců a co vyleze při používání. *(Splaceno: zarážka trimu o rameno přechodu a výběr přechodu klikem do těla. Co vyleze při koukancích a na svatbě, se řeší AŽ POTOM — viz pravidlo kill-gate níže.)*

---

## 🚧 KILL-GATE 1 — na KONCI vývoje (materiál ~konec srpna 2026)

> **Sestříhej touhle appkou celou reálnou svatbu. Od začátku do konce. Bez cheatů.**

Při tom se ověří i kritérium fáze 4 (plynulost na 200GB reálném materiálu), přepis na reálné řeči a všechny koukance najednou.

- **Zvládl jsi to a nebylo to utrpení** → hotovo; případně podmíněné fáze podle chuti.
- **Zvládl jsi to, ale bolelo to** → opravy toho, co bolelo. Žádné nové funkce, dokud to nebolí míň.
- **Nezvládl jsi to** → zastav a zúži. Tohle je nejdůležitější rozhodnutí v celém plánu.

---

## Třetí vlna: fáze 17–22 (sestaveno 29. 07. 2026, přečíslováno 30. 07. 2026)

**Stav k 30. 07. 2026:** ✅ **fáze 17 hotová** (ergonomie střihu — osa sleduje hlavu, JKL,
multi-výběr, schránka, chronologie, export výřezu). ✅ **Hotová je i fáze 18 — ale JINÁ, než
měla tahle vlna v plánu:** 29. 07. 2026 zařadil autor před svatbu přestavbu UI podle
`design_handoff_krasa_ui/` a ta dostala číslo 18 (plán v `FAZE_18_UI.md`, třináct modulů,
hotovo 30. 07. 2026).

⚠️ **Proto se zbytek vlny PŘEČÍSLOVAL o jedna nahoru** (V2 z 18 na 19, ducking na 20,
multikamera na 21, stabilizace na 22; podmíněné fáze na 23 a 24). Ustoupila nepostavená fáze,
ne postavená: číslo 18 je vypálené ve 45 zdrojových souborech aplikace, kdežto V2 zatím
neexistuje ani řádkem. Kdo narazí na starší zápis „fáze 18 = V2“, ať ví, že je to text
z 29. 07. 2026.

**Nic z fází 19–22 se nezačne před kill-gate 1.** Pořadí smí svatba přeházet — to je celý
smysl toho, že se stříhá dřív, než se tyhle fáze postaví.

Sestaveno z návrhu vylepšení po dokončení fází 10–16, na základě průzkumu kódu — ne z přání, ale z toho, co v appce po dostavění plánu opravdu chybí. Tři pravidla, která tuhle vlnu drží pohromadě:

1. **Fáze 17 je JEDINÁ, která smí přijít před kill-gate.** Nejsou to funkce, jsou to chybějící základy ovládání. Bez nich bude svatba bolet z důvodů, které s produktem nemají nic společného.
2. **Pořadí 19–22 není závazné.** Kill-gate ho smí přeházet: co bude na svatbě bolet, jde nahoru. To je celý smysl toho, že se svatba stříhá dřív, než se tyhle fáze postaví.
3. **Každá fáze má kvantitativní ověření** (CLI kontrola se změřenými čísly), stejně jako fáze 10–16. Screenshot je doplněk, ne důkaz.

### ✅ FÁZE 17 — Ergonomie střihu → v1.1 (PŘED kill-gate) · HOTOVÁ 29. 07. 2026

Cíl: appka, ve které se dá strávit den, ne jen předvést funkce. Všechno níže je díra ověřená v kódu, ne domněnka.

**Jak to dopadlo:** všechny tři moduly hotové, ověřené `--jkl-check`, `--select-check` a `--range-check`
(čísla v `PROJECT_STATUS.md`). Dvě věci dopadly jinak, než plán čekal: zpětné přehrávání naše kompozice
**umí** (`canPlayReverse` hlásí `true`), jen na 84 % rychlosti — krokovací fallback proto zůstává a kontrola
ho **vynucuje**, aby nespouštěná cesta tiše neshnila. A auto-scroll musel dostat víc vypínačů, než plán
předpokládal: vypíná se i během live scrollu, ne jen při scrubování a tažení.

- **Modul 1 — osa sleduje hlavu + JKL.**
  - **Auto-scroll STRÁNKOVACÍ, ne plynulé centrování.** Když hlava opustí pravý okraj, skočí se tak, aby seděla v levé třetině. Plynulé centrování překresluje osu na každý tik hlavy (30×/s) — přesně to, čemu se fáze 2 vyhnula zúžením odběrů — a opticky je nepříjemné. Logika do modelu jako čistá funkce (`TimelineGeometry.scrollToKeep(playhead:in:)`), testovatelná bez UI.
  - ⚠️ **Auto-scroll se MUSÍ vypnout, když uživatel scrubuje nebo táhne klip** (`isUserScrubbing`, běžící interakce). Jinak si appka s uživatelem přetahují scroll.
  - **JKL:** L zrychluje 1→2→4→8×, J totéž pozpátku, K pauza; jde to na `AVPlayer.rate`. ⚠️ Zpětné přehrávání není samozřejmost — `AVPlayerItem.canPlayReverse` a `canPlayFastReverse` (macOS 10.8+) se musí ZEPTAT a při `false` spadnout na krokování po snímcích. U 4K HEVC bez proxy čekej trhání (dekódování pozpátku od klíčového snímku — tentýž důvod, proč je proxy o scrubování); u ProRes proxy je reverse levný, protože je intra-only.
    <https://developer.apple.com/documentation/avfoundation/avplayeritem/canplayreverse>
- **Modul 2 — výběr a schránka.**
  - **Multi-výběr:** shift-klik rozšiřuje, ⌘-klik přepíná, tažení v prázdné ploše = rámečkový výběr. Do modelu čistá funkce „které klipy leží v obdélníku".
  - **Schránka ⌘C/⌘X/⌘V:** vkládá se na hlavu, na stopu téhož druhu. ⚠️ Svázané dvojice se kopírují JAKO DVOJICE a s čerstvým `LinkID` — jinak by tři klipy sdílely jednu vazbu a `validate()` ohlásí `brokenLink`. Je to táž past, kterou už jednou chytil split svázaného páru (fáze 2, krok 9).
  - **Hromadné operace:** barevný preset, fade i rampa se aplikují na CELÝ výběr. Tohle je vlastní odměna fáze — bez ní jsou funkce z F13 a F16 na projektu s dvěma sty klipy nepoužitelné.
- **Modul 3 — chronologie a export rozsahu.**
  - **Čas natočení:** `AVAsset.load(.creationDate)` → `AVMetadataItem?` → `.dateValue`. ⚠️ Synchronní `asset.creationDate` je od macOS 13 deprecated. Když metadata chybí, spadnout na datum souboru a ŘÍCT to (přiznané meze).
    <https://developer.apple.com/documentation/avfoundation/avasset/creationdate>
  - **Řazení podle času** v sidebaru a příkaz „Uspořádat chronologicky" na ose. Dnes se řadí podle JMÉNA — u jedné kamery to projde (název je timestamp), u druhé kamery nebo telefonu hostů se chronologie rozsype. Svatba je chronologická událost.
  - **Export rozsahu:** in/out na ose, exportuje se jen výřez. Kontrola kusu filmu bez čekání na celek.

**Hotovo když:** přehrání dvacetiminutové osy nevyžaduje sáhnout na scroll; preset na deset klipů je jedno kliknutí; klipy ze dvou kamer se poskládají v pořadí, ve kterém se natočily. ✅ **Splněno.**

### ✅ FÁZE 18 — Přestavba UI podle design handoffu → v1.2 · HOTOVÁ 30. 07. 2026

**Do plánu přibyla 29. 07. 2026 na pokyn autora**, mimo původní třetí vlnu — a s výslovným zrušením
pravidla „do kill-gate se nepřidávají funkce". Zadáním je `design_handoff_krasa_ui/` (šest hi-fi obrazovek,
rozměry v bodech na dodržení), plán a roadmapa všech třinácti modulů ve **`FAZE_18_UI.md`**.

Třináct modulů ve čtyřech etapách: **A** rám okna, stavový řádek, lišta osy · **B** výšky stop, miniatury
na klipech, přehled celé osy · **C** panel se záložkami, knihovna médií s přetažením · **D** list exportu,
panel přepisu řeči, prázdný start, fullscreen náhled. Každý modul měl vlastní CLI bránu (`--shell-check`
až `--fullscreen-ui-check`) a povinnou regresní sadu; **žádný se neodložil**.

Model se přitom skoro nehnul — `topInset` v geometrii (M4), `duplicatedFrameShare` pro varování o duplikaci
(M10) a `splitTranscriptSegment` + `speechCueRanges` pro editaci přepisu (M11), dohromady **+10 testů**.
Formát projektového souboru zůstal na verzi 2.

**Hotovo když:** šest potíží ze zadání je zavřených (sidebar mísící dokument a měření, 132 px na křivku
rychlosti, transport bez hierarchie, neviditelné analýzy, osa bez vypínačů, chybějící knihovna médií).
✅ **Splněno**, čísla u každého modulu v `PROJECT_STATUS.md`.

### FÁZE 19 — Druhá obrazová stopa (V2) → v1.3

Největší funkční díra: dnes je JEDNA obrazová stopa, takže neexistuje B-roll, druhá kamera ani obraz nad obrazem.

**Dobrá zpráva z průzkumu kódu:** vrstvení kompozice UŽ UMÍ — `CompositionBuilder.computeSpans` iteruje stopy pozpátku („pozdější stopa osy překrývá dřívější") a vrstvy instrukce se skládají odpředu dozadu. Vzniklo to pro A/B rozklad přechodů a pro V2 to platí beze změny.

- **Modul 1 — technický dluh: konec domněnky `tracks[0]`.** Aplikace si na šesti místech domýšlí V1 = `tracks[0]` a A1 = `tracks[1]` (zapsáno u `Project.empty` od fáze 11). S druhou obrazovou stopou to praskne. Náhrada: pojmenované přístupové cesty (`firstVideoTrack`, `firstAudioTrack`, `titleTracks`) a test, který drží projekt s V2 vloženou PŘED V1.
- **Modul 2 — přidání a odebrání stopy v UI.** Model `addTrack`/`removeTrack` existuje. Odebrání stopy s klipy se ptá; minimum je jedna obrazová a jedna zvuková stopa.
- **Modul 3 — vrstvení v kompozici a exportu.** ⚠️ **Kritická oprava:** video kompozice dnes vzniká jen kvůli přechodu, Ken Burns nebo presetu. **Překryv dvou obrazových stop ji musí vynutit taky** — jinak si AVFoundation vybere stopu sama a výsledek je nepředvídatelný. v1 = plné překrytí (horní stopa zakrývá spodní); obraz v obraze (měřítko a pozice) je samostatná položka backlogu, ne součást téhle fáze.
- **Ověření `--v2-check`:** export, kde klip na V2 překrývá V1 — změřený snímek v překryvu musí odpovídat zdroji z V2, snímek mimo překryv zdroji z V1.

### FÁZE 20 — Ducking hudby pod řečí + jednotná obálka mixu → v1.4

Nejotravnější ruční operace svatebního filmu. Všechny díly existují: přepis říká, KDE se mluví, mix umí volume rampy, `LoudnessMeter` umí měřit.

- **Modul 1 — model.** Z přepisů klipů na řečových stopách se spočítají „duck úseky" pro cílovou stopu (typicky A2 s hudbou): hloubka (výchozí −12 dB), náběh ~200 ms, doběh ~600 ms a **spojování úseků bližších než ~1 s**. To poslední je podstatné: bez něj by hudba mezi větami pumpovala nahoru a dolů a bylo by to horší než bez duckingu. Čistá funkce s testy na kotvách (překryv, krátké mezery, řeč přes celý klip).
- **Modul 2 — jednotná obálka mixu.** ⚠️ Dnes se do `AVMutableAudioMixInputParameters` sypou rampy ze tří nezávislých zdrojů (hlasitost stopy, crossfade, fade po klipech) a drží to pravidlo „hrana pod crossfadem fade nedostane". S duckingem jako čtvrtým zdrojem to přestane jít uhlídat. Správné řešení: spočítat pro každou stopu kompozice **JEDNU po částech lineární obálku** ze všech zdrojů a vydat ji jako uspořádanou sekvenci ramp. Je to úklid, který udělá mix správný konstrukcí místo pravidly — a je předpokladem, ne vedlejším produktem.
- **Ověření `--duck-check`:** export hudby s řečí; RMS hudebního pásma během řeči proti RMS mimo ni, a kontrola, že se hlasitost vrací (nezůstane stažená).

### FÁZE 21 — Multikamera, markery a třídění materiálu → v1.5

Tři nezávislé věci, které dohromady dělají práci s velkým materiálem snesitelnou. Každá stojí na něčem hotovém.

- **Modul 1 — synchronizace dvou KAMER podle zvuku.** `WaveformSync` už páruje klopák s kamerou na vzorek přesně; dvě kamery jsou totéž zadání s jiným vstupem. Výsledek posune klip na V2 tak, aby zvuky seděly. Nízká jistota se hlásí dialogem — pravidlo z fáze 7 platí beze změny.
- **Modul 2 — markery.** `SnapCandidate.Kind.marker` je v modelu připravený a dosud nepoužitý. Marker patří OSE (ne stopě): čas, jméno, barva. M ho položí na hlavu, kreslí se v pravítku, přichytávání dostane zadarmo, seznam umí skákat. Při procházení hodin materiálu je to způsob, jak si dělat poznámky („polibek", „proslov"), aniž bys musel stříhat.
- **Modul 3 — třídění a navigace podle kvality.** Fáze 15 už spočítala ostrost i hluchá místa a drží je v cache. Nad hotovými daty: filtr v sidebaru („jen ostré klipy"), skok na další problém klávesou, souhrn na klipu („12 s neostrého").

### FÁZE 22 — Stabilizace obrazu → v1.6 — **SPIKE PRVNÍ, s právem přestat**

**Zařazeno na výslovné přání autora 29. 07. 2026.** Do té doby byla podmíněná a plán ji odkládal se třemi výhradami. Ty výhrady NEZANIKLY: „gumový obraz" (vlnění z rolling shutteru globální transformací opravit NELZE), nutnost předvýpočtu, a možnost, že gimbal řeší problém líp než software. Proto fáze **začíná měřením, ne stavbou** — a modul 1 smí celou fázi zastavit.

⚠️ **Stabilizace je jediná funkce v celém plánu, která umí obraz ZHORŠIT.** Z toho plyne: výchozí stav vypnuto, ořez viditelný v UI, a zásahy se přiznávají.

**Technická cesta (API ověřená proti dokumentaci 29. 07. 2026):**
- **Analýza pohybu:** Vision, `VNTranslationalImageRegistrationRequest` → `VNImageTranslationAlignmentObservation.alignmentTransform` (`CGAffineTransform`), macOS 10.13+. Homografická varianta (`VNHomographicImageRegistrationRequest` → `VNImageHomographicAlignmentObservation`) existuje, ale pro v1 se NEPOUŽIJE: perspektivní warp je přesně ta cesta ke gumovému obrazu.
  <https://developer.apple.com/documentation/vision/vntranslationalimageregistrationrequest>
  <https://developer.apple.com/documentation/vision/vnimagetranslationalignmentobservation>
- **Vyhlazení:** z transformací sousedních snímků se složí absolutní dráha kamery, vyhladí se klouzavým oknem (~1 s) a korekce = vyhlazená dráha minus původní.
- ⚠️ **Kde se korekce APLIKUJE, je architektonicky nejdůležitější rozhodnutí téhle fáze.** Per-snímková transformace by přes instrukce video kompozice znamenala jednu instrukci na snímek — tisíce instrukcí na klip. Správné místo je **vlastní compositor** (`ColorVideoCompositor` z fáze 13), který dostává `compositionTime` a transformaci si najde v tabulce. Pořadí uvnitř compositoru: **stabilizace → ořez → aspect-fit → barevný preset → průhlednost.**
- **Ořez:** pevné rameno, výchozí 10 % (zoom 1,11×), nastavitelné 5–20 %, VIDITELNÉ v UI. Korekce se o rameno zaráží; když se zaráží často, řekne se to (vzorec žluté zóny z limitu zpomalení).
- **Kde běží:** nad proxy nebo podvzorkovaným obrazem ~480×270 (192×108 z fáze 15 je na registraci málo), na pozadí, s cache otiskem — vzorec `SharpnessStore` včetně verze výpočtu v otisku.

**Moduly:**
- **Modul 1 — SPIKE.** Syntetické video se ZNÁMÝM třesem (statický bohatý obraz posouvaný známou funkcí) → analýza → změřený zbytkový pohyb. **Kritéria k pokračování: zbytkový pohyb klesne aspoň 5×, analýza běží aspoň v reálném čase nad proxy, a na reálném svatebním záběru není okem vidět vlnění.** Když neprojde, fáze KONČÍ a zapíše se proč. To je legitimní výsledek, ne selhání — přesně proto se spike dělá první.
- **Modul 2 — `StabilizationStore` a model.** Tabulka transformací per asset s diskovou cache; `Clip.stabilization` (zapnuto, síla vyhlazení, ořezové rameno) jako volitelné pole, formát beze změny verze.
- **Modul 3 — aplikace v compositoru a v exportu.** `--stab-check`: syntetický třes → po stabilizaci změřený zbytkový pohyb, PLUS kontrola, že nestabilizovaný klip projde nedotčený (vzorec pas-through z `--color-check`).
- **Modul 4 — UI.** Přepínač a posuvníky v inspektoru, průběh analýzy na pozadí, přiznané meze při zaražení o ořez.

---

## Podmíněné fáze (po kill-gate 1, podle chuti)

*(Stabilizace odsud 29. 07. 2026 ODEŠLA — autor ji zařadil do třetí vlny; po přečíslování je to fáze 22.)*

### FÁZE 23 — Detekce momentů (bez biometrie) — **PODMÍNĚNÁ**

Polibek, potlesk, tanec přes Vision detekci (obličeje-DETEKCE, pózy, pohyb) + pravidla — bez rozpoznávání identity, takže bez právního gate. Přesnost nebude vysoká (dokument to u prstenů sám přiznává); dělat jen, když po svatbě bude jasné, že ruční procházení bolí.

### FÁZE 24 — Rozpoznávání obličejů (8–12 týdnů) — **PODMÍNĚNÁ, tři gaty**

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

### Backlog (nezařazené, bez čísla)

Automatický reframe 16:9 → 9:16 (Vision + dynamický crop), masky a sledování objektu (rozmazání SPZ/obličeje), **obraz v obraze** (měřítko a pozice klipu na V2 — navazuje na fázi 19), přepínání úhlů multikamery (sync řeší fáze 21), HDR end-to-end, slovenština, LUT soubory (.cube), generátor 48h teaseru, odšumění (`AVAudioEngine` — první skutečný důvod ho nasadit), zvuková obálka po klipech nad rámec fade. Optical flow zůstává škrtnutý. *(Ducking odsud 29. 07. 2026 odešel — je z něj fáze 20.)*

**Z dokumentu vědomě NEpřevzato:** SQLite/Core Data místo projektového souboru (náš JSON formát je hotový, deterministický a verzovaný — migrace bez užitku), přestavba UI na čtyři pracovní režimy (velká přestavba bez jasného přínosu pro jednoho uživatele; jednotlivé prvky — inspektor, režim exportu — můžou přijít postupně) a „učení z potvrzení uživatele" u momentů (nejasná hodnota, dost práce).

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
| ~~24 nebo 30 fps jako výchozí~~ **✅ 30 fps** | rozhodnuto 26. 07. 2026 | 24 dá hlubší čisté zpomalení, ale 60 → 24 je poměr 2,5:1 = trhání při panorámování. 60 → 30 je 2:1, 120 → 30 je 4:1. Většina zdrojů je 60 fps. |
| `AVMutableVideoComposition` jako hlavní cesta | Fáze 3 | `Configuration` na macOS 14–25 neexistuje |
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

- **Nikdo nikdy nepublikoval benchmark vlastního `AVVideoCompositing` držícího 4K/60 náhled.** Ani pozitivní, ani negativní. **Spike 0 to nezodpověděl** — vlastní compositor se nestavěl, protože se ukázalo, že do časování nevidí a pro speed ramping je zbytečný. Pro efekty a Metal (fáze 2–3) otázka zůstává otevřená.
- Ze čtyř komerčních macOS video appek, jejichž binárky šly rozebrat, **žádná nekompozituje přes `AVVideoComposition`** — všechny mají vlastní engine. To může znamenat, že to nestačí, nebo že chtěly Windows. Nevíme.
- Odhady časů jsou moje, ne měřené. Násobek 1,7 je odhad odhadu.
- ~~Zda `AVAssetWriter` s ProRes Proxy skutečně zapne hardwarový engine, nejde přes API zjistit. Změř to.~~ **✅ Změřeno 26. 07. 2026:** zploštění do ProRes 422 Proxy ve 4K běželo **257–426 fps** podle klipu, tedy 4–7× reálný čas. Softwarové kódování by tohle nedalo. Přes API to pořád zjistit nejde, ale číslo mluví jasně.
- Rychlost Whisperu na bezventilátorovém Airu — všechna publikovaná čísla jsou z aktivně chlazených strojů. Počítej s horším koncem rozsahu.
- **Výkon náhledu na celou obrazovku.** Změřeno jen v okně 1280×1192 px (fáze 1). Přeměřit ve fázi 2.

### Známé drobnosti, které nikoho netlačí

Věci, na které se narazilo a nechaly se být. Ne chyby k opravě dnes, ale ať se na ně nezapomene.

- **`open Krasa.app --args --benchmark` se zasekne.** Appka nastartuje, ale měření nedoběhne a report nevznikne — po 15 minutách pořád běžela. Spuštění binárky přímo (`Krasa.app/Contents/MacOS/Krasa --benchmark …`) funguje spolehlivě a navíc je vidět stdout. Příčina nezjištěná. Netlačí to, protože přímé spuštění stačí — ale kdyby se měření mělo pouštět pravidelně nebo z CI, bude to potřeba vyřešit.

---

*Plán se reviduje po každém kill-gate. Ne dřív, ne později.*
