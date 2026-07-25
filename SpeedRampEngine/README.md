# SpeedRampEngine

První modul Projektu Krása. Čistá matematika rychlostní křivky — **žádné AVFoundation, žádné UI**.

Vzniklo ještě před Xcode záměrně: tohle je jediná část speed rampingu, která jde ověřit
bez videa, bez zvuku a bez Macu. Když je matematika špatně, žádné ladění compositoru to nespraví.

## Stav

**Zkompilováno a otestováno na Swiftu 6.0.3. 31 testů, 0 selhání.**

Předtím ověřeno proti nezávislé referenční implementaci v Pythonu na případech,
které jdou spočítat analyticky:

| Vlastnost | Přesnost |
|---|---|
| Konstantní rychlost: `t_src(t) == c·t` | přesné (chyba 0.0) |
| Lineární přechod: `∫ = v₀·T + (v₁−v₀)·T/2` | 1e-9 |
| `d(t_src)/dt == v(t)` | 3.3e-10 |
| Round-trip `outputTime(sourceTime(t)) == t` | 3.7e-12 |
| Monotonie mapování na 20 000 vzorcích | bez výjimky |

Referenční hodnota k zapamatování: **ramp 1,0 → 0,25 → 1,0 přes 5 s spotřebuje přesně 3,125 s zdroje.**

## Jak to použít

### V terminálu (i bez Xcode)

```bash
swift build
swift test
```

### V Xcode

Buď přetáhni `Sources/SpeedRampEngine/SpeedRampEngine.swift` do projektu
a `Tests/.../SpeedRampEngineTests.swift` do testovacího targetu,
nebo přidej celou složku jako lokální Swift Package
(*File → Add Package Dependencies → Add Local…*).

## API

```swift
// Klasický svatební ramp na 8 s zdrojového klipu
let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 8.0, slowSpeed: 0.25)

ramp.outputDuration          // jak dlouhý bude na časové ose
ramp.sourceConsumed          // kolik zdroje spotřebuje (== 8.0)
ramp.speed(atOutput: 2.0)    // rychlost v čase 2 s
ramp.sourceTime(atOutput: 2.0)   // odpovídající čas ve zdroji
ramp.outputTime(atSource: 1.5)   // inverze, pro scrubbing

// Mikro-úseky pro scaleTimeRange — tohle jde rovnou do AVMutableComposition
let segments = try ramp.segments(outputFrameRate: 60, framesPerSegment: 2)
for s in segments {
    // s.sourceStart, s.sourceDuration, s.outputDuration, s.speed
}

// Vzorky pro vykreslení křivky v UI
let points = ramp.speedSamples(count: 200)
```

Vlastní křivka:

```swift
let ramp = try SpeedRamp(nodes: [
    SpeedNode(outputOffset: 0.0, speed: 1.00, easeToNext: .easeInOut),
    SpeedNode(outputOffset: 2.5, speed: 0.25, easeToNext: .easeInOut),
    SpeedNode(outputOffset: 5.0, speed: 1.00, easeToNext: .easeInOut),
])
```

`SpeedRamp` je `Codable`, takže padne rovnou do `project.json` podle schématu ze specifikace.
Dekodér validuje — poškozený projekt vyhodí chybu, nenačte se rozbitá křevka.

## Proč zrovna segmentace

`AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)` umí jen **konstantní** změnu
rychlosti přes daný úsek — vytváří lineární časové mapování. Plynulá Bézierova křivka
se z jednoho volání udělat nedá.

`segments(outputFrameRate:framesPerSegment:)` proto křivku nakrájí na úseky zarovnané
na hranice výstupních snímků. Každý úsek dostane vlastní `scaleTimeRange`.

**Kompromis, který si musíš pohlídat:** čím jemnější dělení, tím hladší křivka —
ale tím víc hranic, kde může lupnout zvuk. Naměřené skoky rychlosti mezi sousedními
úseky u rampu 1,0 → 0,25 → 1,0 při 60 fps:

| snímků na úsek | počet úseků | největší skok rychlosti |
|---|---|---|
| 8 | 38 | 0,068× |
| 4 | 75 | 0,034× |
| **2** | **150** | **0,017×** |
| 1 | 300 | 0,009× |

Začni na 2 a poslouchej. Tohle je přesně to, co má Spike 0 změřit.

## Co tenhle modul záměrně nedělá

- Nesahá na AVFoundation. Převod na `CMTime` a stavba kompozice patří do `CompositionBuilder`.
- Neumí freeze frame (rychlost 0). Podržený snímek je jiná funkce a rozbil by invertibilitu mapování — konstruktor nulovou rychlost odmítne.
- Neumí zpětné přehrávání (záporná rychlost).

## Soubory

```
Package.swift
Sources/SpeedRampEngine/SpeedRampEngine.swift    ~380 řádků
Tests/SpeedRampEngineTests/…Tests.swift          31 testů
ref_speedramp.py                                 referenční implementace pro ověření
```
