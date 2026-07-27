# Fáze 2 — návrh `TimelineView`

*Napsáno 27. 07. 2026. Navazuje na `FAZE_2_TIMELINE.md`, který popisuje hotový a otestovaný `TimelineModel`.*

`TimelineModel` je hotový: 143 testů, žádná závislost na AppKitu ani AVFoundation.
Zbývá poslední kus fáze 2 — **view**. Je to jediná část projektu, kterou nejde
otestovat jinak než okem na běžící aplikaci, a proto je jediné rozumné zadání
**udělat ji co nejtenčí**.

---

## 1. Rozsah

**Je v rozsahu:**

- `NSView` v `NSScrollView`, klipy jako `CALayer` s recyklací
- pravítko (timecode) a hlavičky stop, synchronizované se scrollem
- přehrávací hlava, obousměrně svázaná s `PlaybackControllerem`
- tažení: přesun, trim začátku a konce, roll, slip — přes `TimelineInteraction`
- výběr klipů, kontextové menu, klávesové zkratky, kurzory
- zoom (pinch a ⌘+kolečko), vodorovný
- vlnové průběhy jako předrenderované dlaždice

**Není v rozsahu fáze 2:**

- miniatury na obrazových klipech *(dražší než vlnové průběhy a ke střihu nejsou nutné — fáze 4, spolu s proxy)*
- rychlostní křivka a její editor *(fáze 3)*
- přechody, efekty, klíčové snímky *(fáze 3+)*
- přetahování z knihovny médií *(až bude knihovna — fáze 5)*

---

## 2. Rozhodnutí, na kterých návrh stojí

### 2.1 Model, geometrie a interakce mají **jednoho vlastníka**, a není jím view

`TimelineGeometry` je struktura, tedy **hodnota**. `TimelineInteraction` si ji drží
jako `var geometry`. Kdyby si ji view drželo taky, vznikly by dvě kopie a při
změně zoomu by se rozešly — hit testing by počítal s jedním měřítkem
a přichytávání během tažení s druhým. Taková chyba se neprojeví pádem; projeví
se tím, že klip skáče jinam, než kam uživatel míří, a hledá se týdny.

**Proto vzniká `TimelineController` — `@MainActor final class`, který vlastní:**

| co | typ | proč tam |
|---|---|---|
| `project` | `Project` | dokument |
| `undo` | `UndoStack` | historie |
| `interaction` | `TimelineInteraction` | **a v ní jediná kopie geometrie** |
| `playhead` | `Frames` | v modelu není a nemá být — je to stav UI |
| `selection` | `Set<ClipID>` | totéž |
| `waveforms` | `WaveformStore` | mezipaměť, ne dokument |

Geometrie **se nekopíruje**. Controller ji vystaví jen průchodem:

```swift
var geometry: TimelineGeometry {
    get { interaction.geometry }
    set { interaction.geometry = newValue }
}
```

Jedno úložiště, žádná synchronizace. View si geometrii **nikdy neuloží do vlastnosti** —
vždycky si o ni řekne v okamžiku použití.

### 2.2 ⚠️ `isFlipped` musí být `true`, jinak je celá svislá osa vzhůru nohama

`TimelineGeometry.y(ofTrackAt:)` sčítá výšky stop **odshora dolů** — stopa
s indexem 0 má `y = 0`. AppKit má ale ve výchozím stavu počátek **vlevo dole**
a `y` roste **nahoru**.

```swift
override var isFlipped: Bool { true }
```

Bez tohohle řádku vrátí `trackIndex(atY:)` při kliknutí na V1 poslední zvukovou
stopu, klipy se nakreslí v obráceném pořadí stop a `hitTest` bude trefovat
sousedy. Nespadne to a nevyhodí to warning — jen to bude celé špatně.

> `isFlipped` je `var isFlipped: Bool { get }`, výchozí `false`, počátek vlevo dole;
> při `true` je počátek vlevo nahoře a `y` roste dolů.
> <https://developer.apple.com/documentation/appkit/nsview/isflipped>

### 2.3 Klipy jsou vrstvy z fondu, ne podviews

Jeden `CALayer` na klip, ale **jen na ten viditelný**. Při 1000 klipech
a odzoomované ose by 1000 vrstev znamenalo 1000 objektů, které WindowServer
skládá při každém scrollnutí.

`TimelineGeometry` už má obojí, co je k tomu potřeba:
`visibleFrameRange(scrollX:width:overscanPoints:)` a `visibleClips(on:in:)`,
a ta druhá hledá **binárním půlením**, ne průchodem pole. Chybí jen rozhodnutí,
**které vrstvy připojit a které vrátit do fondu** — a to je čistá logika, viz 2.4.

`overscanPoints` (výchozí 200) je tam právě proto, aby klip existoval už kousek
před hranou okna a při scrollování nenaskakoval.

### 2.4 🚩 Rozhodnutí o recyklaci patří do modelu, ne do view

Recyklace vrstev je místo, kde v editorech vznikají nejotravnější chyby: klip
zůstane viset po smazání, dva klipy sdílí jednu vrstvu, po zoomu se vrstva
nepřepočítá. Všechny jsou to chyby v **množinové logice**, ne v kreslení.

Proto do `TimelineModel` přibude jeden malý čistý typ:

```swift
public struct LayerDiff: Hashable, Sendable {
    public let toMount: [ClipID]     // připojit z fondu
    public let toRecycle: [ClipID]   // vrátit do fondu
    public let toUpdate: [ClipID]    // zůstávají, ale změnil se rámec
}

public struct TimelineLayout: Sendable {
    public struct Placement: Hashable, Sendable {
        public let clipID: ClipID
        public let trackID: TrackID
        public let x: Double, y: Double, width: Double, height: Double
        public let isSelected: Bool
    }
    public static func placements(project: Project, geometry: TimelineGeometry,
                                  scrollX: Double, width: Double,
                                  selection: Set<ClipID>) -> [Placement]
    public static func diff(previous: Set<ClipID>, next: [Placement]) -> LayerDiff
}
```

**Do view pak zbude jediná smyčka**: vezmi `placements`, spočítej `diff`, odpoj
vrácené vrstvy, připoj nové z fondu, přepiš rámce. Ta smyčka má deset řádků
a nedá se v ní ztratit. Všechno ostatní má testy.

*Tohle je jediné rozšíření `TimelineModelu` navržené v tomhle dokumentu — počítá se
s ním jako s prací fáze 2, ne jako s hotovou věcí.*

### 2.5 Pravítko a hlavičky jsou samostatná views, ne `NSRulerView`

`NSRulerView` existuje a umí vlastní jednotky, ale registrují se globálně
metodou `registerUnit(withName:abbreviation:unitToPointsConversionFactor:stepUpCycle:stepDownCycle:)`,
a ten převodní faktor je **konstanta**. Náš `pointsPerFrame` se mění při každém
zoomu, takže bychom museli při každém pinchi přeregistrovat globální jednotku
sdílenou se všemi ostatními pravítky v aplikaci. Navíc popisky nejsou čísla
s jednotkou, ale timecode `00:01:23:14`.

<https://developer.apple.com/documentation/appkit/nsrulerview>

Takže vlastní `NSView`, jak říká plán. Synchronizace se scrollem přes:

```swift
scrollView.contentView.postsBoundsChangedNotifications = true
NotificationCenter.default.addObserver(
    self, selector: #selector(clipViewBoundsChanged(_:)),
    name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
```

> Swift název je `NSView.boundsDidChangeNotification` (ne `NSViewBoundsDidChangeNotification`,
> jak stojí v plánu — to je starý ObjC název). **Posílá se jen když je
> `postsBoundsChangedNotifications == true`**; při změně `frame` se neposílá vůbec.
> <https://developer.apple.com/documentation/appkit/nsview/boundsdidchangenotification>

Pravítko bere z notifikace jen `contentView.bounds.origin.x`, hlavičky stop jen `.y`.

### 2.6 ⚠️ Během tažení se nezapisuje do modelu **ani se nemění zoom**

První polovinu už hlídá `TimelineInteraction` — `preview(atX:y:)` je čistá funkce
a model se dozví výsledek až přes `commit`. Druhá polovina je na view:

`TimelineDrag.candidates` se počítají **jednou při `begin`** a jsou v nich
souřadnice ve snímcích. Kdyby se během tažení změnil zoom, tolerance
přichytávání (v bodech!) by najednou odpovídala jinému počtu snímků a klip by
se přichytil někam, kam uživatel nemířil.

**Pravidlo: dokud `interaction.isDragging`, `magnify(with:)` i ⌘+kolečko se ignorují.**

### 2.7 Vlnové průběhy: dvě vrstvy mezipaměti, žebřík zoomu po mocninách dvou

Nikdy nekreslit vlnu za běhu — to říká plán a je to správně. Ale „předrenderuj
dlaždice per úroveň zoomu" má past: úrovní zoomu je spojité kontinuum od 0,02
do 120 bodů na snímek. Kdyby se dlaždice cachovaly podle aktuálního
`pointsPerFrame`, každý snímek pinch gesta by zahodil celou mezipaměť.

**Proto dvě vrstvy:**

1. **Špičky (peaks)** — spočítají se jednou na asset, `AVAssetReader` nad
   `AVComposition`, dvojice min/max na okno ~256 vzorků. Uloží se na disk vedle
   proxy. Je to jediná drahá operace a dělá se na pozadí.
2. **Dlaždice (`CGImage`)** — renderují se z těch špiček líně, na pozadí,
   a cachují se klíčem `(AssetID, úroveňZoomu, indexDlaždice)`, kde
   **úroveň zoomu je zaokrouhlená na mocninu dvou**, ne aktuální hodnota.
   Mezi úrovněmi se dlaždice natáhne — během pinche je tedy o kousek
   rozmazaná a po ustálení ostrá. To je běžné chování a nikdo si ho nevšimne;
   zahazování mezipaměti šedesátkrát za sekundu by si všiml každý.

**🚩 Špičky se musí číst přes `AVComposition`, ne ze syrové tabulky vzorků.**
Všech pět naměřených klipů má na zvuku edit list, který zahazuje prvních **44 ms**
(priming AAC kodéru). To je na 30fps základně **víc než jeden snímek**. Kdo ho
ignoruje, dostane vlnu posunutou proti zvuku — a protože se podle vlny stříhá,
bude výsledek znít o snímek vedle a chyba se bude hledat v přehrávání místo
v kreslení. Je to přesně ta chyba, kterou `MediaProbe` už jednou našel;
podruhé ať se neopakuje.

**`CATiledLayer` se nepoužije.** Umí líné dlaždice a úrovně detailu
(`tileSize`, `levelsOfDetail`, `levelsOfDetailBias`, macOS 10.5+), ale kreslí
si sám přes `draw(in:)` a jeho úrovně detailu jsou vázané na měřítko vrstvy —
což je přesně to, co u vodorovného-jen zoomu nechceme. Vlastní mezipaměť
`CGImage` je jednodušší a víc pod kontrolou.
<https://developer.apple.com/documentation/quartzcore/catiledlayer>

### 2.8 Rozhodnutí originál/proxy se v celém view nedělá ani jednou

`Asset.url(usingProxies:)` je jediné místo v projektu, kde se vybírá soubor.
View o `proxyURL` nesmí vědět. Platí i pro čtení špiček vlny — ty se berou
z originálu, protože jsou to zvuková data a proxy je má jako LPCM, ale
i tak přes tu jednu funkci.

---

## 3. Struktura

```
TimelineController                      @MainActor, vlastní veškerý stav
│
└── TimelinePane : NSView               kompozitní kořen (do SwiftUI přes NSViewRepresentable)
    ├── TimelineRulerView : NSView      timecode, posun podle contentView.bounds.origin.x
    ├── TrackHeadersView : NSView       jména stop, mute/solo, posun podle .y
    └── NSScrollView
        └── TimelineDocumentView        ⚠️ isFlipped = true, wantsLayer = true
            ├── backgroundLayer         pruhy stop, mřížka
            ├── clipsLayer              kontejner recyklovaných ClipLayer
            │   └── ClipLayer …         body + waveform + title
            ├── overlayLayer            náhled tažení, vodicí čára přichytávání
            └── playheadLayer           svislá čára přes celou výšku
```

Hranice do SwiftUI je stejná jako u `PlayerView` — `NSViewRepresentable`
s `makeNSView` / `updateNSView`. **A se stejným poučením:** `updateNSView`
musí controlleru znovu předat referenci na živé view, protože SwiftUI ho může
kdykoli přetvořit. `PlayerView.swift` to řeší přes `onHostView?(nsView)`
i v `updateNSView` — a stálo to jedno vadné měření, než na to přišlo.

### `ClipLayer`

```
ClipLayer : CALayer              rámec, barva, zaoblení, okraj výběru
├── waveformLayer : CALayer      contents = CGImage dlaždice (jen zvuk)
└── titleLayer : CATextLayer     jméno souboru, ořezané
```

**⚠️ `contentsScale` se u ručně vytvořených vrstev nenastavuje samo.** Výchozí
hodnota je `1.0`; vrstva připojená k view ji dostane od view, ale
`CATextLayer` a vrstvy vytvořené ručně **ne**. Na Retina displeji z toho je
rozmazaný text a rozmazaná vlna. Nastavuje se z `window?.backingScaleFactor`
a **znovu při přesunu okna na jiný displej** (`viewDidChangeBackingProperties()`).
<https://developer.apple.com/documentation/quartzcore/calayer/contentsscale>

**⚠️ Implicitní animace.** `CALayer` animuje změnu `frame` 0,25 s. Při scrollování
to znamená, že klipy „plavou" za obsahem. `PlayerView.layout()` už tenhle problém
v projektu jednou řešil — stejným způsobem:

```swift
CATransaction.begin()
CATransaction.setDisableActions(true)
// … přepis rámců …
CATransaction.commit()
```

---

## 4. Cesta události

| událost | co view udělá | kdo počítá |
|---|---|---|
| `mouseDown` | `geometry.hitTest(x:y:in:)` → `interaction.begin(hit:in:forcing:playhead:)` | model |
| | u `trimStart/trimEnd/roll` navíc `undo.beginInteraction(project)` | |
| `mouseDragged` | `interaction.preview(atX:y:in:snapping:)` → **jen overlay vrstva** | model |
| `mouseUp` | `try interaction.commit(atX:y:into:&project)`, pak `undo.endInteraction` / `undo.record` | model |
| `Escape` | `interaction.cancel()`, případně `undo.cancelInteraction()` | model |
| `mouseMoved` | kurzor podle `hitTest(...).zone` | model |
| `magnify(with:)` | zoom, **pokud se netáhne** | view |
| `rightMouseDown` | `menu(for:)` podle `hitTest` | view |

**Undo se zapisuje dvěma různými způsoby a není to nedůslednost.** U `move`
neexistuje legální mezistav — model se dozví jen výsledek, takže stačí jeden
`record()`. U trimu a rollu jsou mezistavy legální, proto `beginInteraction`
/ `endInteraction`. Je to zapsané v komentáři u `TimelineInteraction.commit`
a view se toho má držet.

### Modifikátory

`TimelineInteraction.begin(forcing:)` umí vynutit `roll` nebo `slip`.
Návrh přiřazení — **k rozhodnutí, viz sekce 8**:

| modifikátor | co dělá | proč |
|---|---|---|
| ⇧ Shift | vypne přichytávání (`preview(snapping: false)`) | zavedená konvence napříč editory |
| ⌥ Option na okraji | `forcing: .roll` | roll je operace na hranici, tedy na okraji |
| ⌘ Command v těle | `forcing: .slip` | slip je operace na obsahu, tedy v těle |

### Kurzory

| zóna | kurzor |
|---|---|
| `.body` | `NSCursor.arrow`, při tažení `.closedHand` |
| `.leadingEdge` / `.trailingEdge` | svislý dělič |

**⚠️ Kurzor pro dělič má dvě jména podle verze systému.**
`NSCursor.resizeLeftRight` existuje od macOS 10.0, ale **je od macOS 27.0
deprecated**. Náhrada `NSCursor.columnResize` je **až od macOS 15.0** —
na našem deployment targetu 14.0 tedy neexistuje.

```swift
static var edgeCursor: NSCursor {
    if #available(macOS 15.0, *) { return .columnResize }
    return .resizeLeftRight
}
```

Je to **přesně stejný vzorec jako u `AVMutableVideoComposition`
a `AVVideoComposition.Configuration`**: novější API na cílovém minimu neexistuje,
starší je deprecated ale funkční, obojí se řeší runtime gatem a warning se
umlčuje cíleně u jednoho volání, nikdy globálně.

- <https://developer.apple.com/documentation/appkit/nscursor/resizeleftright> (10.0, deprecated 27.0)
- <https://developer.apple.com/documentation/appkit/nscursor/columnresize> (15.0+)

Kurzory se přepínají přes `NSTrackingArea` s `.cursorUpdate`, ne přes
`addCursorRect(_:cursor:)` — ta se smí volat **výhradně z `resetCursorRects()`**,
jinak se obdélník zahodí při nejbližší přestavbě, a u tisíce klipů by se stejně
musela přestavovat při každém scrollnutí.

Volby: `[.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect]`.
`.inVisibleRect` drží oblast automaticky srovnanou s viditelnou částí view,
takže se při scrollování nemusí přepočítávat.
**⚠️ `.cursorUpdate` se neposílá v kombinaci s `.activeAlways`** — proto
`.activeInKeyWindow`.
<https://developer.apple.com/documentation/appkit/nstrackingarea/options-swift.struct>

### Zoom

`magnify(with:)` je na `NSResponder` od macOS 10.5, `NSEvent.magnification`
je **přírůstek**, ne absolutní hodnota:

```swift
override func magnify(with event: NSEvent) {
    guard !controller.interaction.isDragging else { return }   // viz 2.6
    controller.setZoom(controller.geometry.pointsPerFrame * (1 + event.magnification),
                       anchoredAtX: convert(event.locationInWindow, from: nil).x)
}
```

`TimelineGeometry.setZoom(_:)` si sám zařízne rozsah na
`minPointsPerFrame` (0,02) … `maxPointsPerFrame` (120).

**Zoom musí kotvit na kurzoru, ne na levém okraji.** Bez toho odjede obsah
pryč a uživatel se musí doscrollovat zpátky. Kotvení je jeden řádek:
zapamatuj si snímek pod kurzorem před změnou a po změně nastav `scrollX` tak,
aby byl zase tam.

- <https://developer.apple.com/documentation/appkit/nsresponder/magnify(with:)>
- <https://developer.apple.com/documentation/appkit/nsevent/magnification>

---

## 5. Přehrávací hlava

Playhead je **stav UI, ne dokumentu** — v `TimelineModelu` schválně není
(`FAZE_2_TIMELINE.md`, sekce 8). Bydlí v `TimelineControlleru` a je to jediné
místo, kde se timeline potkává s `PlaybackControllerem` z fáze 1.

**Obousměrná vazba, ale s jasným pořadím:**

- **osa → přehrávač:** klik do pravítka nebo tažení hlavy →
  `playback.seek(to:)` se zero tolerance a coalescingem (QA1820, už hotové ve fázi 1)
- **přehrávač → osa:** při přehrávání se hlava posouvá podle času přehrávače

⚠️ **Ty dva směry se nesmí zapnout naráz**, jinak vznikne smyčka: seek posune
hlavu, hlava vyvolá seek. Řeší se příznakem „hlavu právě táhne uživatel" —
během něj se aktualizace z přehrávače ignorují.

Playhead je zároveň kandidátem na přichycení
(`SnapCandidate.Kind.playhead`, síla hned po nule osy) — proto se `interaction.begin`
volá s `playhead:`.

---

## 6. Výkon: rozpočet a jak se změří

**Rozpočet: `mouseDragged` a scroll musí doběhnout do 8 ms** — polovina
tiku 60Hz displeje. Druhá polovina patří přehrávači, který v editoru běží vedle.

**A na měření už infrastruktura existuje.** `PlayerHostView` má display link
a `PlaybackBenchmark` počítá vypadlé tiky. Z paměti projektu:

> Vypadlý tik znamená **zaseknuté hlavní vlákno naší aplikace**, ne přetížené GPU.

Pro měření přehrávače to byla nevýhoda — proto se čísla z fáze 1 musela
opravovat. **Pro timeline je to přesně ta správná metrika:** timeline se seká
právě tehdy, když si hlavní vlákno zablokujeme sami. Stejný kód, který u přehrávače
neměřil to, co jsme chtěli, tady měří přesně to, co chceme.

**Kritérium plánu:** *„naimportuješ 10 klipů, poskládáš je, rozstřihneš,
přetáhneš, zazoomuješ — a je to plynulé."* K němu jeden tvrdší test:
**1000 klipů, scroll přes celou osu, žádný vypadlý tik.**

Co rozpočet nejčastěji rozbije:

| příčina | řešení |
|---|---|
| kreslení vlny za běhu | dlaždice (2.7) |
| vrstva na každý klip | recyklace (2.3, 2.4) |
| implicitní animace při scrollu | `CATransaction.setDisableActions(true)` |
| čtení špiček na hlavním vlákně | `AVAssetReader` na pozadí |
| `drawsAsynchronously` jako první sáhnutí | **až po měření** — dokumentace sama říká měřit napřed, a default je `false` |

<https://developer.apple.com/documentation/quartzcore/calayer/drawsasynchronously>

**🚩 A jedno varování z fáze 1, které tady začne platit.** Holý náhled videa
stojí pod 0,3 % GPU rezidence, protože jde na displej jako samostatná vrstva
a nic se neskládá. **Timeline je první věc v projektu, která tuhle situaci
změní** — jakmile nad oknem leží vrstvy, které se musí složit, přepne se to
do dražší cesty. Čísla neporostou plynule, **skočí**. Až se to stane, není to
regrese timeline; je to ten dopředu ohlášený přechod. Výchozí hodnoty,
proti kterým se to pozná, jsou naměřené v `PROJECT_STATUS.md`.

---

## 7. Pořadí stavby

Jeden krok = jeden překlad = jedna věc, kterou je vidět. **Žádný krok nezačíná,
dokud předchozí neběží.**

| # | krok | hotovo když |
|---|---|---|
| 1 | `TimelineModel` jako lokální balíček v `Krasa.xcodeproj` | projekt se přeloží a `import TimelineModel` projde |
| 2 | `TimelineDocumentView` v `NSScrollView`, `isFlipped`, pruhy stop | vidíš tři prázdné pruhy V1/A1/A2 a jde jimi scrollovat |
| 3 | pravítko + hlavičky stop, synchronizace přes `boundsDidChange` | scrolluješ osou a timecode i jména jedou s ní |
| 4 | `TimelineLayout` + `LayerDiff` v modelu, **s testy** | `swift test` prochází, ve view zatím nic |
| 5 | klipy jako recyklované vrstvy | naimportuješ 10 klipů a vidíš je; scroll je plynulý |
| 6 | playhead + seek do přehrávače | klikneš do pravítka a monitor skočí na ten snímek |
| 7 | tažení: přesun a trim | přetáhneš klip, zkrátíš ho, ⌘Z to vrátí |
| 8 | zoom (pinch, ⌘+kolečko), kotvený na kurzoru, zamčený při tažení | zazoomuješ a obsah zůstane pod kurzorem |
| 9 | roll, slip, kontextové menu, zkratky, kurzory | ⌥ a ⌘ tažení dělají, co mají |
| 10 | vlnové průběhy: špičky na pozadí + dlaždice | vidíš vlnu, pinch neseká |

**Kroky 1–4 se dají udělat bez jediného klipu na ose.** Krok 4 je jediný,
který má testy — a je to schválně ten, ve kterém se dá nejvíc ztratit.

---

## 8. Zbývá rozhodnout

1. **Modifikátory pro roll a slip.** Návrh v sekci 4 (⌥ na okraji = roll,
   ⌘ v těle = slip). Alternativa je režimový nástroj jako ve Final Cutu
   (klávesa přepne nástroj a drží ho). Modifikátory jsou rychlejší pro
   příležitostného uživatele, režim pro toho, kdo v tom sedí denně.
   **Filip stříhá po večerech, ne osm hodin denně** — proto návrh míří
   na modifikátory. Vratné.
2. **Kolik stop a jestli je jde ve fázi 2 přidávat.** Model umí `addTrack`
   i `removeTrack`. Návrh: **ve fázi 2 jen výchozí V1 + A1 + A2, bez přidávání** —
   je to UI navíc a ke střihu svatby to nechybí. Doplní se ve fázi 5.
3. **Miniatury na obrazových klipech.** Návrh: **až fáze 4**, spolu s proxy —
   generovat je z originálu ve 4K by bylo drahé a proxy je stejně bude mít.
   Do té doby klip nese jméno souboru a barvu.
4. **Chování při odzoomování pod čitelnost.** Pod ~1 bodem na snímek se
   z klipu stane čárka a jméno se nevejde. Návrh: pod prahem přestat kreslit
   text a vlnu úplně, ne je zmenšovat. K ověření okem, až to poběží.

---

## 9. Co do view nepatří

Zopakováno, protože je to jediné pravidlo, které tenhle dokument doopravdy vymáhá:

- **střihové operace** — `Project` (`split`, `trim`, `move`, `ripple*`, `roll`, `slip`)
- **meze tažení** — `Queries` (`maxTrimStart`, `maxTrimEnd`, `slipRange`, `legalRange`)
- **přichytávání** — `TimelineGeometry` (`snapCandidates`, `snap`)
- **co je pod myší** — `TimelineGeometry.hitTest`
- **který klip je vidět** — `TimelineGeometry.visibleClips`
- **které vrstvy připojit** — `TimelineLayout.diff` (nové, sekce 2.4)
- **volba originál/proxy** — `Asset.url(usingProxies:)`
- **spotřeba zdroje** — `Project.sourceConsumption(of:)`, kvůli fázi 3

Ve view zůstane: `CALayer` rámce a barvy, `CGContext` pro dlaždice, `NSEvent`
na souřadnice, `NSScrollView`, kurzory a menu. **Nic, co má návratovou hodnotu,
kterou by šlo porovnat s očekáváním.**

---

## 10. Ověřená API

Všechno, co tenhle návrh používá, s odkazem a dostupností. Deployment target
projektu je **macOS 14.0**.

| API | dostupnost | poznámka |
|---|---|---|
| [`NSView.isFlipped`](https://developer.apple.com/documentation/appkit/nsview/isflipped) | macOS 10.0+ | výchozí `false`, **musíme `true`** |
| [`NSView.boundsDidChangeNotification`](https://developer.apple.com/documentation/appkit/nsview/boundsdidchangenotification) | macOS 10.0+ | jen při `postsBoundsChangedNotifications == true` |
| [`NSResponder.magnify(with:)`](https://developer.apple.com/documentation/appkit/nsresponder/magnify(with:)) | macOS 10.5+ | |
| [`NSEvent.magnification`](https://developer.apple.com/documentation/appkit/nsevent/magnification) | macOS 10.5+ | **přírůstek**, ne absolutní hodnota |
| [`NSTrackingArea.Options`](https://developer.apple.com/documentation/appkit/nstrackingarea/options-swift.struct) | macOS 10.5+ | `.cursorUpdate` **ne** s `.activeAlways` |
| [`NSView.addCursorRect(_:cursor:)`](https://developer.apple.com/documentation/appkit/nsview/addcursorrect(_:cursor:)) | macOS 10.0+ | jen z `resetCursorRects()`; **nepoužijeme** |
| [`NSView.menu(for:)`](https://developer.apple.com/documentation/appkit/nsview/menu(for:)) | macOS 10.0+ | kontextové menu |
| [`NSCursor.resizeLeftRight`](https://developer.apple.com/documentation/appkit/nscursor/resizeleftright) | macOS 10.0+, **deprecated 27.0** | fallback pod macOS 15 |
| [`NSCursor.columnResize`](https://developer.apple.com/documentation/appkit/nscursor/columnresize) | **macOS 15.0+** | runtime gate |
| [`NSRulerView`](https://developer.apple.com/documentation/appkit/nsrulerview) | macOS 10.0+ | **nepoužijeme**, viz 2.5 |
| [`CALayer.contentsScale`](https://developer.apple.com/documentation/quartzcore/calayer/contentsscale) | macOS 10.7+ | ručně u vlastních vrstev |
| [`CALayer.drawsAsynchronously`](https://developer.apple.com/documentation/quartzcore/calayer/drawsasynchronously) | macOS 10.8+ | až po měření |
| [`CATiledLayer`](https://developer.apple.com/documentation/quartzcore/catiledlayer) | macOS 10.5+ | **nepoužijeme**, viz 2.7 |
| [`NSView.wantsUpdateLayer`](https://developer.apple.com/documentation/appkit/nsview/wantsupdatelayer) | macOS 10.8+ | pro pruhy stop v pozadí |
| [`NSView.displayLink(target:selector:)`](https://developer.apple.com/documentation/appkit/nsview/4200851-displaylink) | macOS 14.0+ | už používá `PlayerHostView` |
| [`CALayer.isGeometryFlipped`](https://developer.apple.com/documentation/quartzcore/calayer/isgeometryflipped) | macOS 10.6+ | **nastavuje AppKit sám**, viz níže |
| [`NSAppearance.performAsCurrentDrawingAppearance(_:)`](https://developer.apple.com/documentation/appkit/nsappearance/performascurrentdrawingappearance(_:)) | macOS 11.0+ | nutné pro barvy vrstev |
| [`NSView.viewDidChangeEffectiveAppearance()`](https://developer.apple.com/documentation/appkit/nsview/viewdidchangeeffectiveappearance()) | macOS 10.14+ | tam se barvy překládají znovu |
| [`NSScrollView.allowsMagnification`](https://developer.apple.com/documentation/appkit/nsscrollview/allowsmagnification) | macOS 10.8+ | výchozí `false`, **nechat** |

**Nic z toho není nové API na hraně dostupnosti — kromě `NSCursor.columnResize`,
a to je jediné, které potřebuje `if #available`.**

### ✅ Doměřeno při kroku 2 (27. 07. 2026)

**Podvrstvy `isFlipped` DĚDÍ.** Otázka, na které stojí celé svislé rozvržení:
platí souřadnice vrstev, které si do `backgroundLayer` přidáme sami, taky
odshora dolů? **Ano.** AppKit u převráceného layer-backed view sám nastaví
`layer.isGeometryFlipped = true` (změřeno) a SDK k té vlastnosti říká
*„geometry of the layer **and its sublayers** is flipped vertically"*.
`TimelineGeometry.y(ofTrackAt:)` jde tedy vrstvě předat rovnou.

⚠️ **Kdo si to bude ověřovat, ať nepoužije `CALayer.render(in:)` — ta metoda
`isGeometryFlipped` ignoruje** a vrátí výsledek, ze kterého plyne pravý opak.
Stejně nespolehlivý je `cacheDisplay(in:to:)` na obsah vrstev. Spolehlivé jsou
dvě věci: přečíst `isGeometryFlipped` a podívat se okem.

**Okem se to pozná podle výšek.** V1 má 64 bodů, A1 i A2 po 44 — při obráceném
převrácení leží vysoký pruh dole. Kontrolu čísel dělá skript v poznámkách
k session: `V1 y=0 h=64`, `A1 y=66 h=44`, `A2 y=112 h=44`.

**Barvy vrstev se samy nepřebarví.** `NSColor.cgColor` se vyhodnotí pro
appearance platnou v okamžiku volání, ne pro tu, ve které vrstva leží — barva
uložená do `CALayer.backgroundColor` tedy v tmavém režimu zamrzne na staré
hodnotě. Řeší se překladem uvnitř `performAsCurrentDrawingAppearance` a jeho
zopakováním ve `viewDidChangeEffectiveAppearance()`. **`NSColor` předaná
`NSScrollView.backgroundColor` tenhle problém nemá** — ta se překládá při
každém kreslení.
