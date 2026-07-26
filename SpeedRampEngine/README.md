# SpeedRampEngine

První modul Projektu Krása. Čistá matematika rychlostní křivky — **žádné AVFoundation, žádné UI**.

Vzniklo ještě před Xcode záměrně: tohle je jediná část speed rampingu, která jde ověřit
bez videa, bez zvuku a bez Macu. Když je matematika špatně, žádné ladění compositoru to nespraví.

## Stav

**Zkompilováno a otestováno na Swiftu 6.3.3. 41 testů, 0 selhání.**

Ověřeno proti nezávislé referenční implementaci v Pythonu (`ref_speedramp.py`) na případech,
které jdou spočítat analyticky:

| Vlastnost | Přesnost |
|---|---|
| Konstantní rychlost: `t_src(t) == c·t` | přesné (chyba 0.0) |
| Lineární přechod: `∫ = v₀·T + (v₁−v₀)·T/2` | 1e-9 |
| `d(t_src)/dt == v(t)` | 3.3e-10 |
| Round-trip `outputTime(sourceTime(t)) == t` | 3.7e-12 |
| Monotonie mapování na 20 000 vzorcích | bez výjimky |

Referenční hodnota k zapamatování: **ramp 1,0 → 0,25 → 1,0 přes 5 s spotřebuje přesně 3,125 s zdroje.**
Když ti při stavbě kompozice vyjde jiné číslo, chyba je v převodu na `CMTime`, ne tady.

**Ověřeno i na reálném videu.** Spike 0 (26. 07. 2026) prohnal tuhle matematiku přes
`AVMutableComposition` na tři klipy ze Samsungu. Délky výstupu sedí na očekávané hodnoty
do jednoho snímku, synchron zvuku drží na 0,00 ms. Podrobnosti v `../SPIKE_0.md`.

## Jak to použít

### V terminálu (i bez Xcode)

```bash
swift build
swift test
```

### V Xcode

Buď přetáhni `Sources/SpeedRampEngine/SpeedRampEngine.swift` do projektu
a `Tests/SpeedRampEngineTests/SpeedRampEngineTests.swift` do testovacího targetu,
nebo přidej celou složku jako lokální Swift Package
(*File → Add Package Dependencies → Add Local…*).

## API

```swift
// Klasický svatební ramp na 8 s zdrojového klipu
let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 8.0, slowSpeed: 0.25)

ramp.outputDuration              // jak dlouhý bude na časové ose
ramp.sourceConsumed              // kolik zdroje spotřebuje (== 8.0)
ramp.speed(atOutput: 2.0)        // rychlost v čase 2 s
ramp.sourceTime(atOutput: 2.0)   // odpovídající čas ve zdroji
ramp.outputTime(atSource: 1.5)   // inverze, pro scrubbing

// Vzorky pro vykreslení křivky v UI
let points = ramp.speedSamples(count: 200)
```

### Segmentace — hlavní cesta

```swift
let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015)

plan.segments             // [RampSegment] pro scaleTimeRange
plan.framesPerSegment     // kolik snímků na úsek engine zvolil
plan.achievedMaxStep      // skutečně dosažený největší skok
plan.limitedByFrameRate   // ⚠️ true = mez nešla dodržet, viz níž

for s in plan.segments {
    // s.sourceStart, s.sourceDuration, s.outputDuration, s.speed
}
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
Dekodér validuje — poškozený projekt vyhodí chybu, nenačte se rozbitá křivka.

## Proč zrovna segmentace

`AVMutableCompositionTrack.scaleTimeRange(_:toDuration:)` umí jen **konstantní** změnu
rychlosti přes daný úsek — vytváří lineární časové mapování. Plynulá Bézierova křivka
se z jednoho volání udělat nedá.

Není to volba mezi segmentací a něčím lepším. `CMTimeMapping` je pouhá dvojice
`CMTimeRange`, takže mapování je afinní z definice, a vlastní `AVVideoCompositing`
do časování vůbec nevidí. **Segmentace je jediná cesta.**

`segmentation(...)` proto křivku nakrájí na úseky zarovnané na hranice výstupních
snímků. Každý úsek dostane vlastní `scaleTimeRange`.

## Podle čeho se volí jemnost dělení

**Dřív tu stálo „začni na 2 snímky na úsek a poslouchej, jestli to lupe".
Ta otázka je zodpovězená a odpověď je jiná, než se čekalo.**

Spike 0 poslechem porovnal 8, 4, 2 a 1 snímek na úsek na dvou klipech
s vysokým podílem ticha (41 % a 38 % pauz — tedy materiál, kde by cvaknutí
bylo slyšet):

> **Všechny čtyři znějí stejně. Lupance nejsou ani při 545 segmentech.**

Hypotéza „víc hranic = víc lupanců" se nepotvrdila. **Zvuk jemnost dělení
neomezuje**, takže se nevolí podle sluchu, ale podle **velikosti kompozice**:
pětiminutový ramp při 30 fps je 9000 snímků, tedy 9000 volání `scaleTimeRange`
při jednom snímku na úsek oproti ~750 při dvanácti.

### Proč ne pevný počet snímků na úsek

Protože **skok rychlosti závisí na délce klipu**, takže stejná hodnota dá
pokaždé jinou kvalitu. Naměřeno při `framesPerSegment: 8`:

| klip | úseků | největší skok |
|---|---|---|
| 11,4 s | 69 | **3,79 %** |
| 38,6 s | 232 | 1,12 % |
| 44,9 s | 270 | 0,96 % |

Pevný počet snímků je **vstupní** veličina, ale zajímá nás **výstupní** vlastnost.
Proto `maxSpeedStep`: zadá se mez skoku a engine si počet úseků dopočítá sám
z maximální strmosti křivky. Při mezi 1,5 %:

| klip | snímků na úsek | úseků | dosažený skok |
|---|---|---|---|
| 11,4 s | **3** | 182 | 1,42 % |
| 38,6 s | **10** | 186 | 1,40 % |
| 44,9 s | **12** | 180 | 1,44 % |

Krátký klip dostane jemnější dělení, dlouhý hrubší, **oba stejnou kvalitu
a skoro stejný počet úseků** (180–186) přes čtyřnásobný rozdíl v délce.

**Výchozí mez je `0.015`** — nad naměřenými 0,96 a 1,12 % u klipů, které zněly
čistě, a pod 3,79 % u toho krátkého.

### ⚠️ Mez nemusí být dosažitelná

Úsek nemůže být kratší než jeden výstupní snímek, takže existuje podlaha
`max|dv/dt| / fps`. Krátký a strmý ramp na nízké snímkové frekvenci se pod ni
nedostane — **11s klip při 24 fps se nedostane pod 0,59 %**.

Není to chyba, je to hustota mřížky. Engine to hlásí přes
`SegmentationPlan.limitedByFrameRate` a **volající to musí umět zobrazit**.
Tiše vrátit něco horšího, než bylo zadané, je jediné, co je zakázané.

```swift
let plan = try ramp.segmentation(outputFrameRate: 24, maxSpeedStep: 0.005)
if plan.limitedByFrameRate {
    // plan.achievedMaxStep > plan.requestedMaxStep, plan.framesPerSegment == 1
    // Řekni to uživateli. Jemněji už to nejde.
}
```

Odhad počtu úseků vychází z **maximální** strmosti křivky, takže je konzervativní,
a pak se ještě ověří na skutečných úsecích a v případě potřeby zjemní. Z odhadu
prvního řádu se tím stává záruka.

### Legacy varianta

```swift
let segments = try ramp.segments(outputFrameRate: 30, framesPerSegment: 8)
```

Zůstala kvůli srovnávacím měřením. **Pro produkční kód sáhni po `segmentation(...)`.**

## Co tenhle modul záměrně nedělá

- Nesahá na AVFoundation. Převod na `CMTime` a stavba kompozice patří do `CompositionBuilder`.
- Neumí freeze frame (rychlost 0). Podržený snímek je jiná funkce a rozbil by invertibilitu mapování — konstruktor nulovou rychlost odmítne.
- Neumí zpětné přehrávání (záporná rychlost).
- **Neřeší, jestli má zdroj dost snímků.** Ramp na 0,25× při výstupu 30 fps potřebuje
  zdroj 120 fps, jinak se snímky duplikují a zpomalený úsek trhá
  (`zdrojFps × nejnižšíRychlost ≥ výstupFps`). Tohle je vlastnost materiálu, ne křivky —
  patří do UI a do svatebního asistenta. Viz `../SPIKE_0.md`.

## Soubory

```
Package.swift
Sources/SpeedRampEngine/SpeedRampEngine.swift    matematika křivky a segmentace
Tests/SpeedRampEngineTests/…Tests.swift          41 testů
ref_speedramp.py                                 referenční implementace pro ověření
```
