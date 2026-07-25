# Projekt Krása (AIditor) – Project Status
*Naposled aktualizováno: 25. 07. 2026*

## 🎯 Co to je
Nativní macOS videoeditor pro svatební a rodinné filmy — plynulý speed ramping, 100 % lokální AI (obličeje, scény, český přepis) a integrovaný svatební asistent.
Stack (plán): Swift, SwiftUI (panely) + AppKit (timeline), AVFoundation, Metal, Vision, WhisperKit.
**Stav: specifikace v2.0 + implementační plán hotové. Žádný kód.**

## ⏭️ Příští krok
**Spike 0, krok 1 — otevřít soubor a přehrát ho.**
`NSOpenPanel` se Security-Scoped Bookmarkem → `AVPlayer` v `NSViewRepresentable` → mezerník play/pauza, šipky krok po snímku.
Matematika křivky je hotová a otestovaná (`SpeedRampEngine/`), takže krok 3 spiku už staví na ověřeném základu.
Před tím ještě: Xcode, `git init`, testovací sada klipů. Detaily v `SPIKE_0.md`.

## ✅ Hotovo
- **`SpeedRampEngine` — první modul, zkompilovaný a otestovaný.** 31 testů, 0 selhání, Swift 6.0.3. Bézier easing, integrace rychlostní křivky, inverzní mapování pro scrubbing, segmentace pro `scaleTimeRange` zarovnaná na hranice snímků, `Codable` pro `project.json`. Ověřeno proti nezávislé Python referenci na analyticky spočitatelných případech.
- Produktová a technická specifikace v2.0 (HTML + PDF)
- **Implementační plán** — 12 fází, 3 kill-gates, modulová mapa, session protokol (`IMPLEMENTACNI_PLAN.md`)
- **Interaktivní tracker** — odškrtávací postup s progress barem (`krasa-tracker.html`)
- Rešerše tří rizikových oblastí: Whisper na macOS, face clustering, timeline UI a compositor
- Vyřešeno pozicování, cena (1 490 Kč jednorázově), distribuce, datový model `.projektkrasa`

## 🔄 Rozjeté (nedodělané)
- **Fáze 0 — Spike 0.** Matematika hotová, zbytek (přehrávač, kompozice, export, měření) čeká.
- **Pozor:** v sekci 8.1 specifikace jsou položky MVP odškrtnuté `[x]`. Je to seznam *rozsahu*, ne stav.

## 📝 TODO
### Cesta k v0.5 „MVP nula" (~6 měsíců při 30 h/týdně)
- **F0** Spike 0 — ověření speed rampingu *(1 týden)* — 🔄 matematika hotová
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
- **F9** Distribuce, notarizace, Sparkle, licence *(3 týdny)*
- 🚧 **KILL-GATE 2:** prodat deseti lidem, kteří tě neznají

### Za v1.0 — podmíněné
- **F10** AI analýza scén a kvality záběrů *(2 týdny)* — bezpečná AI, žádné právní riziko
- **F11** Rozpoznávání obličejů *(8–12 týdnů)* — tři gaty: právní, licenční, poptávkový
- **F12+** Multicam, HDR, slovenština, LUTs

### Škrtnuto
- **Optical flow dopočet mezisnímků.** Ne odloženo — škrtnuto. Je to výzkumný problém, ne funkce na dopsání.

## ⚠️ Známá rizika a korekce specifikace
*(Detaily v `IMPLEMENTACNI_PLAN.md`, sekce 1.)*

- **`AVMutableVideoComposition` je od macOS 26 deprecated** → stavět na `AVVideoComposition.Configuration`.
- **`scaleTimeRange` neumí plynulou křivku** — dělá lineární časové mapování. Ramp = segmentace nebo vlastní compositor. Navíc hlášené artefakty ve zvuku na hranicích segmentů.
- **Whisper-small je pro češtinu nepoužitelný** (34–38 % WER) → `large-v3-turbo` (~13 %, stejná velikost jako medium, násobně rychlejší).
- **`SpeechAnalyzer` češtinu nepodporuje** — v seznamu 42 locale není `cs_CZ`. Sekce 4.3.1 specifikace se ruší.
- **Vision nemá veřejné API pro otisk obličeje.** Face grouping = vlastní Core ML model + vlastní DBSCAN + UI pro ruční opravy. Ente na tom pracovalo 21 měsíců s placeným týmem.
- **Modely pro rozpoznávání obličejů jsou z velké části komerčně zakázané.** InsightFace, ArcFace, buffalo_l: *non-commercial research only*. Jediný čistý je AuraFace-v1 (Apache 2.0), a z jeho repa se smí stáhnout **pouze `glintr100.onnx`**.
- **EU AI Act čl. 2(10) nechrání dodavatele software**, jen koncového uživatele. Termín pro Annex III po Digital Omnibus: 2. 12. 2027.
- **`AVAssetExportSession` ignoruje `frameDuration`** → export přes `AVAssetWriter`.
- **VFR z telefonu.** Apple nemá API pro detekci — musíš číst délky vzorků sám.
- **Nikdo nikdy nepublikoval benchmark vlastního `AVVideoCompositing` na 4K/60.** Proto je Spike 0 fáze nula.
- **Vykonavatelské riziko.** Web stack z předchozích projektů se sem nepřenáší.

## 🏗️ Klíčová rozhodnutí
- **Timeline v AppKitu, zbytek v SwiftUI.** SwiftUI nemá recyklaci buněk ani viditelnost do drag session. Riverside má SwiftUI chrome + samostatný timeline engine, Recut je celý AppKit.
- **`AVVideoComposition.Configuration`**, ne deprecated API.
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
- `SpeedRampEngine/` – **první modul, hotový a otestovaný**
  - `Sources/SpeedRampEngine/SpeedRampEngine.swift` – ~380 řádků, žádné závislosti
  - `Tests/SpeedRampEngineTests/SpeedRampEngineTests.swift` – 31 testů
  - `Package.swift` – jde pustit `swift test` i bez Xcode
  - `README.md` – API, naměřené hodnoty, tabulka jemnosti segmentace
  - `ref_speedramp.py` – Python reference, proti které se to ověřovalo
