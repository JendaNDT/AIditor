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

- **Kompozice přes `AVMutableVideoComposition`.** Je od macOS 26 deprecated, ale funguje — a na macOS 14–25 je **jediná možnost**, protože `AVVideoComposition.Configuration` je `@available(macOS 26.0, *)`. Deprecation warning umlčuj cíleně u konkrétního volání, nikdy globálně.
  *(Dřívější verze tohohle souboru tvrdila opak — „stavět na `Configuration`, ne na `AVMutableVideoComposition`". Byla to chyba: nezohlednila, že `Configuration` na deployment targetu projektu vůbec neexistuje.)*
- **`AVVideoComposition.Configuration` se speed rampingem nesouvisí.** Neobsahuje žádné časování — jen instrukce, transformace, průhlednost, ořez a barvy. I rampy, které v ní jsou (`OpacityRamp`, `TransformRamp`, `CropRectangleRamp`), jsou lineární a prostorové, ne časové. Migrace na `Configuration` a speed ramping jsou dva nezávislé úkoly.
- **Dvojí implementace přes `if #available(macOS 26.0, *)` je úkol před vydáním, ne teď.** Zapsané ve fázi 9 plánu. Do spiku ani MVP nepatří.
- **Timeline v AppKitu** (NSView v NSScrollView, klipy jako CALayer), zbytek v SwiftUI. SwiftUI nemá recyklaci buněk ani viditelnost do drag session.
- **Export přes `AVAssetWriter`**, ne `AVAssetExportSession` — ta ignoruje `frameDuration`.
- **`scaleTimeRange` umí jen konstantní rychlost.** Plynulá křivka = segmentace na mikro-úseky. Hotové v `SpeedRampEngine.segments(outputFrameRate:framesPerSegment:)`.
- **Vlastní `AVVideoCompositing` speed ramping neřeší — segmentace je jediná cesta.** Compositor dostane přes `sourceFrame(byTrackID:)` snímek, který kompozice pro daný `compositionTime` **už vybrala**; požádat o jiný zdrojový čas nejde. Časování určuje `CMTimeMapping` stopy, a ten je dvojice `CMTimeRange` — afinní z definice. Compositor je na pixely (efekty, prolínačky, Metal), ne na čas.
- **Proxy: ProRes 422 Proxy (`'apco'`) v polovičním rozlišení**, a při generování zploštit VFR na CFR.
- **Jedna časová základna projektu.** Nikdy neodvozuj čísla snímků ze zdrojových časových značek.
- **Seek se zero tolerance + coalescing** podle Apple QA1820.
- **WhisperKit** (`argmaxinc/argmax-oss-swift`), model `large-v3-turbo`. Ne whisper-small — pro češtinu má 34–38 % chybovost.
- Minimální macOS 14.0 pro běh, novější API runtime gatovaná.

## Prostředí (ověřeno 25. 07. 2026)

- **Swift 6.3.3** (`swiftlang-6.3.3.1.3`), target `arm64-apple-macosx26.0`.
- **Xcode nainstalovaný**, aktivní v `/Applications/Xcode.app`. SDK `MacOSX26.5.sdk`.
- ⚠️ **Deployment target nového Xcode projektu nastav ručně na macOS 14.0.** Výchozí hodnota by byla 26.0, což je proti rozhodnutí výše a tiše by ti povolilo API, které na cílových strojích neexistuje. V SwiftPM balíčcích totéž přes `platforms: [.macOS(14)]`.
- Testovací klipy jsou v `TestClips/` — gitem ignorované, do repozitáře nepatří.

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
