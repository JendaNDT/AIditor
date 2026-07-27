# TimelineModel

Logika časové osy pro Projekt Krása. **Čistý Swift, žádné AVFoundation, žádné UI.**

```
swift test
```

**143 testů, 0 selhání, Swift 6.1.2 (Linux) i 6.3.3 (macOS).** Modul nesahá na nic
kromě Foundation, takže se dá přeložit a otestovat i mimo macOS — což je právě to,
co dovoluje ověřit ho dřív, než se sáhne na AppKit.

Tři části:

| část | co řeší |
|---|---|
| **model** | dokument, střihové operace, invarianty, undo |
| **geometrie** | matematika osy — zoom, viditelný rozsah, hit testing, přichytávání |
| **interakce** | co se stane při tažení: náhled, meze, výsledná operace |

Na `TimelineView` pak zbude kreslení a předávání událostí.

Návrh a zdůvodnění jednotlivých rozhodnutí je v `FAZE_2_TIMELINE.md` v kořeni projektu.

---

## Rychlý přehled

```swift
var project = Project.empty()          // V1 + A1 + A2

let asset = Asset(originalURL: url,
                  duration: SourceTime(seconds: 14.517),
                  measuredFrameRate: 59.94)   // MĚŘENÁ, ne nominalFrameRate
project.addAsset(asset)

let clip = try project.makeClip(assetID: asset.id)   // model razí ID i délku
try project.insert(clip, onTrack: project.timeline.tracks[0].id)

try project.split(clipID: clip.id, at: Frames(120))
try project.trimEnd(clipID: clip.id, to: Frames(90))
try project.rippleRemove(clipID: clip.id)

assert(project.validate().isEmpty)
```

## Dvě časové soustavy

| soustava | co v ní žije | typ |
|---|---|---|
| **osa projektu** | pozice a délky klipů, 30 fps | `Frames` (celé číslo) |
| **zdrojový čas** | odkud se ve zdroji bere, délka assetu | `SourceTime` (zlomek) |

Hranice mezi nimi je **jen na dvou místech**:

```swift
timeline.sourceTime(_ frames: Frames) -> SourceTime        // osa → zdroj, v celých tickách
timeline.availableFrames(from: SourceTime) -> Frames       // zdroj → osa, VŽDY dolů
```

Zaokrouhlení nahoru by dovolilo trim o snímek za konec souboru a poslední snímek
by zamrzl. U VFR zdrojů je `availableFrames` **záruka nejmenšího počtu**, ne odhad.

Převod `Frames` na sekundy záměrně neexistuje — kdyby existoval, nic by nebránilo
převést osové snímky frekvencí assetu, tedy přesně tou záměnou, které se model brání.

## Co se snadno rozbije

- **`split` a `trim` musí jít přes `sourceOffset(in:atFrame:)`**, ne přes „délku
  převedenou na zdrojový čas". Ten vzorec platí jen při rychlosti 1× a od fáze 3
  přestane. Kdo ho použije, dostane opakující se záběr a nevšimne si toho, dokud
  to nepustí.
- **Spotřebu zdroje počítá jen `sourceConsumption(of:)`.** Fáze 3 vymění vnitřek
  jedné funkce; kdyby to počítala každá operace po svém, přepisuje se jich šest.
- **Ripple se týká stopy klipu a jeho svázaných dvojčat, nikdy ostatních.** Hudba
  na A2 je páteř, ke které se stříhá.
- **`sourceStart` je prezentační čas s respektovaným edit listem.** Všech pět
  měřených klipů zahazuje na zvuku prvních 44 ms, což je na 30fps základně víc
  než jeden snímek.
- **Undo snímkuje celý `Project`, ne jen `Timeline`** — jinak undo/redo přes
  import nechá klip odkazovat na neexistující asset.

## Invarianty

`project.validate()` vrací **všechna** porušení, ne první. Deset pravidel:
seřazenost, nepřekrývání (dotyk překryv není), kladná délka, nezáporný začátek,
spotřeba do délky assetu, existující asset, jedinečné `ClipID`, správný druh stopy,
platná vazba obraz–zvuk, platné časy.

Každý test operace končí `XCTAssertValid(project)`, takže se chytnou i chyby,
na které test přímo necílil.

## Geometrie — matematika pro `TimelineView`

`TimelineGeometry` je druhá polovina modulu. Obsahuje všechno, co timeline view
počítá, ale co není kreslení — a proto se to dá otestovat.

```swift
var g = TimelineGeometry(pointsPerFrame: 4)

g.x(for: Frames(100))                       // → 400 bodů
g.frame(atX: 406)                           // → snímek 102 (zaokrouhleno k nejbližšímu)
g.trackIndex(atY: 70, in: timeline)         // → 1
g.visibleClips(on: track, in: range)        // binárním půlením, ne průchodem
g.hitTest(x: 402, y: 10, in: timeline)      // → (clipID, .leadingEdge, offset)

let candidates = g.snapCandidates(in: timeline, playhead: head, excluding: [dragged])
g.snappedFrame(atX: 406, candidates: candidates)
```

**Pravidlo, na kterém celá geometrie stojí:** šířka úchopu okraje klipu
(`edgeGrabWidth`) a tolerance přichytávání (`snapTolerance`) jsou pevné
**v bodech** a na snímky se přepočítávají zoomem. Kdyby byly ve snímcích, po
odzoomování by okraj klipu zabíral zlomek pixelu a nešel by chytit, a po
přiblížení by přichytávání skákalo přes půl obrazovky. Uživatel má prst pořád
stejně velký, ať je zoom jakýkoli.

Dvě věci, které z toho plynou a jsou otestované:

- **U klipu užšího než dva úchopy** se plocha rozdělí napůl, aby šly chytit obě
  strany. Jinak by jedna překryla druhou.
- **Na vlastní hrany se tažený klip nepřichytává** — vyrobilo by to zaseknutí
  na místě.

Přichytávání má i pořadí síly (nula > playhead > hrana klipu > marker), aby při
shodné vzdálenosti výsledek nezávisel na pořadí v poli.

## Interakce — co se stane při tažení

`TimelineInteraction` je stavový automat mezi `mouseDown`, `mouseDragged`
a `mouseUp`, ale bez AppKitu.

```swift
var interaction = TimelineInteraction(geometry: geometry)

// mouseDown
if let hit = geometry.hitTest(x: p.x, y: p.y, in: project.timeline) {
    interaction.begin(hit: hit, in: project, playhead: playhead)
}

// mouseDragged — volá se desítkykrát za sekundu, model se NESAHÁ
if let preview = interaction.preview(atX: p.x, y: p.y, in: project,
                                     snapping: !event.modifierFlags.contains(.shift)) {
    drawGhost(preview)          // preview.isValid → jiná barva
    drawSnapGuide(preview.snappedTo)
}

// mouseUp
try interaction.commit(atX: p.x, y: p.y, into: &project)
```

Druh tažení se určí z toho, co bylo pod myší: tělo → přesun, okraj → trim.
`forcing:` ho přepíše na `roll` nebo `slip` podle modifikátoru.

Co je otestované a snadno by se udělalo špatně:

- **Klip drží tam, kde se chytil** — nesmí skočit počátkem pod kurzor.
- **Přichytává se začátek i konec klipu**, ne jen bod pod myší.
- **Roll bez souseda spadne na trim** místo aby se pokusil o nemožné.
- **Trim se zarazí na mezi**, ať ji určuje soused nebo konec zdroje.
- **Puštění bez pohybu nevyrobí změnu** — jinak by vznikl prázdný undo krok
  a Cmd+Z by zdánlivě nic neudělalo.
- **`preview` je čistá funkce.** Volá se při každém pohybu myši, takže nesmí
  do modelu zapsat ani omylem.

## Co v modelu záměrně není

Vlnové průběhy, výběr (stav UI), a vlastnosti média mimo časování — rozlišení,
orientace, kodek a verdikt CFR/VFR žijí v `MediaIndex.json`.

Model o přichytávání nic neví a vědět nemá: geometrie mu předá už zaokrouhlenou
a přichycenou pozici.
