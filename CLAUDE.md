# Projekt Krása — kontext pro Claude Code

Nativní macOS videoeditor pro svatební a rodinné filmy. Swift, SwiftUI (panely) + AppKit (timeline), AVFoundation, Metal, Vision, WhisperKit.

**Komunikuj česky a tykej.** Autor projektu neprogramuje — staví appku s AI asistentem. Vysvětluj, co děláš, ale bez balastu.

## Zdroje pravdy

| Soubor | Na co |
|---|---|
| `Projekt_Krasa_Specifikace_Aplikace_v2.html` | **rozsah** — co má appka umět |
| `IMPLEMENTACNI_PLAN.md` | **pořadí a technologie** — v jakém pořadí to stavět |
| `PROJECT_STATUS.md` | **stav** — co je hotové, co je příští krok |
| `SPIKE_0.md` | zadání aktuální fáze |

Specifikace je starší než plán. **Kde si odporují, platí plán** — obsahuje opravy proti realitě července 2026.

## Pravidla práce

1. **Na začátku session si přečti `PROJECT_STATUS.md`.** Řekni, kde jsme, a čekej na potvrzení směru.
2. **Jeden modul na session.** Ne dva. Nikdy „celá timeline i s přehrávačem".
3. **Nejdřív logika a testy, potom UI.** Co jde napsat bez AVFoundation, napiš bez AVFoundation.
4. **`swift build` / `xcodebuild` musí projít, než kód odevzdáš.** Spusť to sám a chyby oprav.
5. **`git commit` po každé funkční drobnosti.** Krátká zpráva česky.
6. **Neexistující API je hlavní riziko.** U každého Apple API, které používáš poprvé, uveď odkaz na `developer.apple.com`. Když si nejsi jistý, řekni to místo odhadu — ve specifikaci se takhle našla tři smyšlená nebo špatně pojmenovaná API.
7. **Na konci session aktualizuj `PROJECT_STATUS.md`.**

## Technická rozhodnutí, která už padla

- **`AVVideoComposition.Configuration`**, ne `AVMutableVideoComposition` — ta je od macOS 26 deprecated.
- **Timeline v AppKitu** (NSView v NSScrollView, klipy jako CALayer), zbytek v SwiftUI. SwiftUI nemá recyklaci buněk ani viditelnost do drag session.
- **Export přes `AVAssetWriter`**, ne `AVAssetExportSession` — ta ignoruje `frameDuration`.
- **`scaleTimeRange` umí jen konstantní rychlost.** Plynulá křivka = segmentace na mikro-úseky. Hotové v `SpeedRampEngine.segments(outputFrameRate:framesPerSegment:)`.
- **Proxy: ProRes 422 Proxy (`'apco'`) v polovičním rozlišení**, a při generování zploštit VFR na CFR.
- **Jedna časová základna projektu.** Nikdy neodvozuj čísla snímků ze zdrojových časových značek.
- **Seek se zero tolerance + coalescing** podle Apple QA1820.
- **WhisperKit** (`argmaxinc/argmax-oss-swift`), model `large-v3-turbo`. Ne whisper-small — pro češtinu má 34–38 % chybovost.
- Minimální macOS 14.0 pro běh, novější API runtime gatovaná.

## Hotové moduly

### `SpeedRampEngine/`
Matematika rychlostní křivky. Čistý Swift, žádné závislosti. **31 testů, ověřeno.**

```swift
let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 8.0, slowSpeed: 0.25)
let segments = try ramp.segments(outputFrameRate: 60, framesPerSegment: 2)
```

Referenční hodnota: ramp 1,0 → 0,25 → 1,0 přes 5 s spotřebuje **přesně 3,125 s** zdroje. Když ti při stavbě kompozice vyjde jiné číslo, chyba je v převodu na `CMTime`, ne v matematice.

Testy pustíš přes `cd SpeedRampEngine && swift test`.

## Co do projektu nepatří

- Optical flow dopočet mezisnímků — škrtnuto, je to výzkumný problém.
- Rozpoznávání obličejů — až za v1.0 a jen po projití právního a licenčního gate (viz plán, fáze 11).
- Freeze frame a zpětné přehrávání v `SpeedRampEngine` — rozbilo by invertibilitu mapování.
