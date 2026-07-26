# Projekt Krása (AIditor) – Project Status
*Naposled aktualizováno: 26. 07. 2026*

## 🎯 Co to je
Nativní macOS videoeditor pro svatební a rodinné filmy — plynulý speed ramping, 100 % lokální AI (obličeje, scény, český přepis) a integrovaný svatební asistent.
Stack (plán): Swift, SwiftUI (panely) + AppKit (timeline), AVFoundation, Metal, Vision, WhisperKit.
**Stav: specifikace a plán hotové, dva ověřené moduly (`SpeedRampEngine`, `MediaProbe`). Appka zatím neexistuje — žádné UI, žádný Xcode projekt.**

## ⏭️ Příští krok
**Spike 0, krok 4 — plynulá rychlostní křivka. Jádro celého spiku.**
Ramp **120 → 0,25× → 30 fps** segmentací na mikro-úseky. Segmenty spočítá hotový `SpeedRampEngine.segments(outputFrameRate:framesPerSegment:)`, kompozice přes `AVMutableVideoComposition`, export přes `AVAssetWriter`.

**Vstup je připravený:** `TestClips/flattened/20260725_203813_cfr.mov` — 120,0000 fps, `CFR`, kolísání 0,00 %, 1363 snímků, 11,358 s.

Žádné další nástroje se nepíšou. Sonda i zplošťovač jsou hotové a ověřené — teď jde o tu otázku, kvůli které spike vznikl: **jde plynulý ramp v AVFoundation vůbec udělat tak, aby zvuk neujel a export nespadl?**

⚠️ Hlavní riziko: **lupance na hranicích segmentů.** To je to, co se má změřit, ne jestli se ramp „povede".
⚠️ Při zápisu videa nastav `videoInput.mediaTimeScale` — viz technická rozhodnutí v `CLAUDE.md`.

Kroky 1 a 2 spiku (přehrávač, konstantní zpomalení) zůstávají otevřené. Až se bude zakládat Xcode projekt: **deployment target nastav ručně na macOS 14.0**, výchozí by byl 26.0.

## ✅ Hotovo
- **`SpeedRampEngine` — první modul, zkompilovaný a otestovaný.** 31 testů, 0 selhání, Swift 6.3.3. Bézier easing, integrace rychlostní křivky, inverzní mapování pro scrubbing, segmentace pro `scaleTimeRange` zarovnaná na hranice snímků, `Codable` pro `project.json`. Ověřeno proti nezávislé Python referenci na analyticky spočitatelných případech.
- **`MediaProbe` — sonda na vlastnosti klipů.** Rozlišení, orientace, kodeky, fps, edit list a hlavně **skutečné délky vzorků přes `AVSampleCursor`** (fallback `AVAssetReader`). Rozlišuje zaokrouhlení / zahozený snímek / proměnlivé časování. Naměřené hodnoty v `MediaProbe/RESULTS.md`. První kód, který sáhl na AVFoundation.
- **`Flatten` — zploštění VFR na pevnou snímkovou mřížku.** Krok 3 spiku. Cílová frekvence z měřeného modu, čtení přes `AVComposition` (edit list), zero-order hold převzorkování, ProRes 422 Proxy v plném rozlišení, zvuk LPCM. **Ověřeno na třech klipech: všechny `CFR` s kolísáním 0,00 %, synchron tlesknutí 0,00 ms, kódování 257–426 fps.**
- Produktová a technická specifikace v2.0 (HTML + PDF)
- **Implementační plán** — 12 fází, 3 kill-gates, modulová mapa, session protokol (`IMPLEMENTACNI_PLAN.md`)
- **Interaktivní tracker** — odškrtávací postup s progress barem (`krasa-tracker.html`)
- Rešerše tří rizikových oblastí: Whisper na macOS, face clustering, timeline UI a compositor
- Vyřešeno pozicování, cena (1 490 Kč jednorázově), distribuce, datový model `.projektkrasa`

## 🔄 Rozjeté (nedodělané)
- **Fáze 0 — Spike 0.** Matematika (`SpeedRampEngine`) a sonda (`MediaProbe`) hotové. Čeká: zploštění VFR→CFR (krok 3), přehrávač (1), konstantní zpomalení (2), ramp (4), měření (5).
- **Pozor:** v sekci 8.1 specifikace jsou položky MVP odškrtnuté `[x]`. Je to seznam *rozsahu*, ne stav.

## 📝 TODO
### Cesta k v0.5 „MVP nula" (~6 měsíců při 30 h/týdně)
- **F0** Spike 0 — ověření speed rampingu *(1 týden)* — 🔄 matematika a sonda hotové, příští je zploštění VFR→CFR (krok 3)
- **F1** Kostra, import, přehrávač, VFRDetector *(2 týdny)*
- **F2** Timeline v AppKitu — nejtěžší UI v projektu *(4–5 týdnů)*
- **F3** Speed ramping ostrý *(3 týdny)*
- **F4** Proxy + zploštění VFR→CFR *(2 týdny)*
- **F5** Projekt, autosave, undo, export *(3 týdny)*
- 🚧 **KILL-GATE 1:** sestříhat touhle appkou celou reálnou svatbu

### Cesta k v1.0 (+~4 měsíce)
- **F6** Svatební asistent *(2 týdny)* — nejlevnější odlišení v produktu
- **F7** Audio engine, 32-bit float, LUFS *(3 týdny)*
- **F8** Titulky přes WhisperKit *(2 týdny)*
- **F9** Distribuce, notarizace, Sparkle, licence *(3 týdny)* — **+ migrace na `AVVideoComposition.Configuration`** jako druhá větev pod `if #available(macOS 26.0, *)`. Ne dřív.
- 🚧 **KILL-GATE 2:** prodat deseti lidem, kteří tě neznají

### Za v1.0 — podmíněné
- **F10** AI analýza scén a kvality záběrů *(2 týdny)* — bezpečná AI, žádné právní riziko
- **F11** Rozpoznávání obličejů *(8–12 týdnů)* — tři gaty: právní, licenční, poptávkový
- **F12+** Multicam, HDR, slovenština, LUTs

### Škrtnuto
- **Optical flow dopočet mezisnímků.** Ne odloženo — škrtnuto. Je to výzkumný problém, ne funkce na dopsání.

## ⚠️ Známá rizika a korekce specifikace
*(Detaily v `IMPLEMENTACNI_PLAN.md`, sekce 1.)*

- **`AVMutableVideoComposition` je od macOS 26 deprecated, ale používá se dál.** Náhrada `AVVideoComposition.Configuration` je `@available(macOS 26.0, *)`, a minimum projektu je macOS 14.0 — na macOS 14–25 tedy neexistuje. Deprecated ≠ odstraněné. Warning umlčovat cíleně u volání, ne globálně. *(Dřívější text tvrdil opak — byla to chyba, opraveno 25. 07. 2026.)*
- **`scaleTimeRange` neumí plynulou křivku** — dělá lineární časové mapování. `CMTimeMapping` je dvojice `CMTimeRange`, takže křivka do něj nejde zapsat z principu. **Ramp = segmentace, jiná cesta není** (vlastní compositor do časování nevidí). Navíc hlášené artefakty ve zvuku na hranicích segmentů.
- **Whisper-small je pro češtinu nepoužitelný** (34–38 % WER) → `large-v3-turbo` (~13 %, stejná velikost jako medium, násobně rychlejší).
- **`SpeechAnalyzer` češtinu nepodporuje** — v seznamu 42 locale není `cs_CZ`. Sekce 4.3.1 specifikace se ruší.
- **Vision nemá veřejné API pro otisk obličeje.** Face grouping = vlastní Core ML model + vlastní DBSCAN + UI pro ruční opravy. Ente na tom pracovalo 21 měsíců s placeným týmem.
- **Modely pro rozpoznávání obličejů jsou z velké části komerčně zakázané.** InsightFace, ArcFace, buffalo_l: *non-commercial research only*. Jediný čistý je AuraFace-v1 (Apache 2.0), a z jeho repa se smí stáhnout **pouze `glintr100.onnx`**.
- **EU AI Act čl. 2(10) nechrání dodavatele software**, jen koncového uživatele. Termín pro Annex III po Digital Omnibus: 2. 12. 2027.
- **`AVAssetExportSession` ignoruje `frameDuration`** → export přes `AVAssetWriter`.
- **`AVAssetWriter` si bez instrukce zvolí timescale 600 a kvantizuje do ní zapisované časy.** U 29,97 / 59,94 / 23,976 i naší 30,01 fps to vyrobí rozptyl a výstup vyleze jako `CFR≈` místo `CFR`. Vždy `videoInput.mediaTimeScale = frameDuration.timescale`; na zvuku NE, vyhodí výjimku. Odhaleno až ověřením na druhém klipu — na jednom by chyba prošla.
- **Zvuk v proxy a zploštěných souborech jen jako LPCM.** AAC by přidal vlastní priming delay a rozbil to, kvůli čemu ty soubory vznikají.
- **VFR z telefonu.** Apple nemá API pro detekci — musíš číst délky vzorků sám. **Změřeno 25. 07. 2026 na pěti klipech ze Samsungu (`MediaProbe/RESULTS.md`): ani jeden nemá čistě konstantní časování.** VFR je výchozí stav, ne okrajový případ.
- **Zvuk má edit list, který zahazuje prvních 44 ms.** Priming AAC kodéru, u všech pěti klipů. **Zvuk se nikdy nesmí číst ze syrové tabulky vzorků** — jen přes `AVComposition` nebo s respektováním `AVAssetTrack.segments`. Jinak je posunutý o 44 ms a chyba se hledá v synchronizaci místo ve čtení.
- **`nominalFrameRate` lže.** Slow-mo klip hlásí 119,369 fps, naměřeno 120,000. Metadata, ne měření — časovou základnu projektu z něj neodvozovat.
- **Zahozený snímek ≠ proměnlivé časování.** Vzorek jako celočíselný násobek délky snímku = zahozený snímek, opraví se duplikátem. Nepravidelná délka = přepočet časování. Rozdíl v ceně opravy je řádový, `MediaProbe` to rozlišuje.
- **Nikdo nikdy nepublikoval benchmark vlastního `AVVideoCompositing` na 4K/60.** Proto je Spike 0 fáze nula.
- **Vykonavatelské riziko.** Web stack z předchozích projektů se sem nepřenáší.

## 🏗️ Klíčová rozhodnutí
- **Timeline v AppKitu, zbytek v SwiftUI.** SwiftUI nemá recyklaci buněk ani viditelnost do drag session. Riverside má SwiftUI chrome + samostatný timeline engine, Recut je celý AppKit.
- **Kompozice přes `AVMutableVideoComposition`** pro spike i MVP. `AVVideoComposition.Configuration` až jako druhá větev před vydáním (fáze 9), runtime gatovaná přes `if #available(macOS 26.0, *)`.
- **Speed ramping a `Configuration` spolu nesouvisí.** `Configuration` neobsahuje žádné časování — jen instrukce, transformace, průhlednost, ořez, barvy.
- **Jedna časová základna projektu.** Nikdy neodvozovat čísla snímků ze zdrojových časových značek.
- **VFR→CFR při generování proxy.** Jedno rozhodnutí řeší tři problémy naráz.
- **ProRes 422 Proxy v polovičním rozlišení**, ne plném. M4 Air má hardwarový ProRes engine — chyběl jen základnímu M1.
- **Export přes `AVAssetWriter`.**
- **WhisperKit místo holého whisper.cpp.** MIT, Swift async API, stahuje modely sám.
- **Nativní Swift, ne web/Electron.**
- **Minimální macOS 14.0** pro běh, funkce vyžadující novější API runtime gatované.
- **100 % lokální, žádná telemetrie** odesílající obrazová ani biometrická data.
- **Jednorázová platba 1 490 Kč**, žádné předplatné.
- **Hardware:** MacBook Air M3/M4, 16+ GB RAM. Režim 30+ h týdně.
- **Nejdřív spike, pak MVP, pak kill-gate.** Skončit včas je úspěch.

## 📁 Stav souborů
- `Projekt_Krasa_Specifikace_Aplikace_v2.html` / `.pdf` – specifikace, zdroj pravdy pro **rozsah**
- `IMPLEMENTACNI_PLAN.md` – zdroj pravdy pro **pořadí a technologie**
- `SPIKE_0.md` – zadání první fáze
- `krasa-tracker.html` – interaktivní tracker postupu
- `PROJECT_STATUS.md` – tenhle soubor
- `MediaProbe/` – **sonda na testovací klipy**, `swift run MediaProbe`
  - `Sources/MediaProbe/` – Model, Timing (čtení vzorků), Inspect, Report
  - `RESULTS.md` – **naměřené hodnoty**; klipy jsou v `.gitignore`, tohle je jediný záznam
- `TestClips/` – 5 klipů ze Samsungu, 2,1 GB, **ignorované gitem**
- `SpeedRampEngine/` – **první modul, hotový a otestovaný**
  - `Sources/SpeedRampEngine/SpeedRampEngine.swift` – ~380 řádků, žádné závislosti
  - `Tests/SpeedRampEngineTests/SpeedRampEngineTests.swift` – 31 testů
  - `Package.swift` – jde pustit `swift test` i bez Xcode
  - `README.md` – API, naměřené hodnoty, tabulka jemnosti segmentace
  - `ref_speedramp.py` – Python reference, proti které se to ověřovalo
