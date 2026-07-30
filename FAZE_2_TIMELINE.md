# Fáze 2 — návrh `TimelineModel`

*Návrh před psaním kódu. 27. 07. 2026, druhá verze po nezávislé revizi.*

> **Historický dokument.** Tohle je návrh `TimelineModelu` z 27. 07. 2026, napsaný PŘED kódem.
> Modul je dávno postavený a od té doby ho rozšířily fáze 3 a 10–18 (rampy, přechody, titulky,
> fotky, barvy, hudba, kvalita, fade, schránka, chronologie). **Aktuální stav modelu je
> v `CLAUDE.md` (sekce `TimelineModel/`) a v `PROJECT_STATUS.md`**; tenhle text zůstává kvůli
> zdůvodnění návrhu — proč jsou invarianty takové, jaké jsou, a proč model nezná AVFoundation.

Čistá logika časové osy: typy, invarianty, operace, undo a seznam testů. **Žádné AVFoundation, žádné UI.** Modul musí jít přeložit a otestovat sám o sobě, stejně jako `SpeedRampEngine`.

---

## 1. Rozsah

**Ve fázi 2 je:** stopy a klipy, pozice na ose, vazba obrazu na zvuk, výběr, střih (split), zkrácení (trim), přesun, přepis, slip, ripple, roll, undo.

**Ve fázi 2 není:** rychlostní křivka (jen připravené místo — fáze 3), generování proxy (jen dvojcesta — fáze 4), přechody, barvy, titulky, vlnové průběhy, `AVComposition`.

Specifikace v sekci 8.1 chce pro MVP **1 obrazovou a 2 zvukové stopy**. Model umí N stop — omezení patří do UI, ne do datového modelu.

---

## 2. Rozhodnutí, na kterých návrh stojí

### 2.1 Časy v celých snímcích

Specifikace ukládá `timeline_start_sec` a spol. jako desetinná čísla. **Pro výpočty uvnitř modelu je to špatná jednotka.**

Klip trvá 8 s a další začíná tam, kde předchozí končí. S desetinnými čísly vyjde `7,999999` nebo `8,000001` — klipy se buď o mikrosekundu překryjí, nebo mezi nimi zůstane neviditelná mezera, která se projeví až v exportu. Po padesáti klipech je chyba nasčítaná.

Není to nový nápad: **Spike 0 přesně tohle řešil u rampu** — časy se skládají kumulativně v celých tickách. A `AVAssetWriter` si bez instrukce zvolí timescale 600 a kvantizuje do ní, což u 29,97 nebo 30,01 fps vyrobí rozptyl. Stejná třída chyby, stejná obrana.

Třetí možnost — `CMTime` s pevnou timescale, jak to dělá AVFoundation — by taky fungovala. Celá čísla ale mají jednu výhodu navíc: v testech i v logu si je zkontroluješ okem.

**Cena, kterou to má, a je poctivé ji přiznat:** všechno se kvantizuje na 1/30 s, tedy i zvukové střihy na 33 ms. Je to legitimní kompromis (dělá ho i Premiere) a pro střih obrazu neznamená nic, ale u BPM markerů ve fázi 6 a u audio enginu ve fázi 7 se to připomene.

### 2.2 Dvě časové soustavy a jediná hranice mezi nimi

Model má dvě soustavy a **žádný kód je nesmí míchat jinde než na jednom místě**:

| soustava | co v ní žije | typ |
|---|---|---|
| **osa projektu** | pozice a délky klipů, 30 fps | `Frames` (celé číslo) |
| **zdrojový čas** | odkud se ve zdroji bere, edit list, délka assetu | `SourceTime` (zlomek) |

Zdroje mají vlastní frekvenci — 30,01 / 59,68 / 120 fps — a míchat ji se základnou projektu je přesně ta chyba, před kterou varuje pravidlo *„nikdy neodvozuj čísla snímků ze zdrojových časových značek"*.

```swift
extension Timeline {
    /// Jediná dvě místa v projektu, kde se hranice soustav překračuje.
    /// Nikde jinde se nesmí objevit převod přes Double — jinak se vrací
    /// plovoucí drť, kvůli které se počítá v celých snímcích.

    /// Osa → zdroj. Násobí se v celých tickách projektové timescale,
    /// nikdy přes sekundy.
    func sourceTime(_ frames: Frames) -> SourceTime

    /// Zdroj → osa. Vždy DOLŮ. Zaokrouhlení nahoru by dovolilo trim
    /// o snímek za konec souboru a poslední snímek by zamrzl nebo
    /// by kompozice vrátila černou.
    func availableFrames(from time: SourceTime) -> Frames
}
```

Projektová timescale je **90000** — sedí na to, co už používá `PlaybackController`, a je dělitelná 30 i 25.

⚠️ **U VFR zdrojů znamená „zbývá 0,5 s" míň snímků, než by odpovídalo.** Ani jeden z pěti měřených klipů nemá konstantní časování, takže tohle není okrajový případ. `availableFrames` proto vrací **záruku nejmenšího počtu**, ne odhad.

### 2.3 Spotřeba zdroje se počítá na jednom místě — kvůli fázi 3

Bez rychlostní křivky platí, že klip dlouhý na ose 30 snímků spotřebuje 1 s zdroje. **Od fáze 3 to přestane platit** a spotřeba bude `∫v(t)dt`.

Kdyby operace počítaly spotřebu každá po svém, znamenala by fáze 3 přepsat šest z nich a jednu validaci. Proto už teď:

```swift
extension Project {
    /// Kolik zdrojového materiálu klip spotřebuje.
    /// Fáze 2: sourceTime(clip.duration).
    /// Fáze 3: integrál rychlostní křivky ze SpeedRampEngine.
    /// ŽÁDNÁ operace ať nepočítá spotřebu jinak než touhle funkcí.
    func sourceConsumption(of clip: Clip) -> SourceTime

    /// Kde ve zdroji leží daný snímek klipu. Split i trim jdou přes tohle,
    /// ne přes „délku převedenou na zdrojový čas" — ten vzorec platí jen při 1×.
    func sourceOffset(in clip: Clip, atFrame offset: Frames) -> SourceTime
}
```

Ve fázi 3 se vymění vnitřek dvou funkcí místo šesti operací.

### 2.4 Rychlostní křivka: uzly ve zdrojovém čase

Rozhodnuto teď, protože to mění chování trimu. Specifikace si v tom protiřečí — sekce 6.2 má `time_offset_sec` uvnitř klipu, sekce 4.2 `source_timestamp_sec`.

**Uzly patří ke zdrojovému času.** Když zpomalení sedí na hodu kyticí a ty klip zepředu zkrátíš, zpomalení má zůstat na hodu kyticí. Kdyby uzly visely na ose, ujelo by to na jiný okamžik a uživatel by nechápal proč.

**Přidání křivky mění délku klipu na ose**, takže to není přiřazení do pole, ale plnohodnotná operace, která může narazit do souseda.

### 2.5 Dvojcesta originál/proxy, rozhodnutá na jednom místě

Podmínka z plánu. Volba „pracovat s proxy" je **per projekt**:

```swift
extension Asset {
    /// Jediné místo v celém projektu, kde se rozhoduje, se kterým souborem
    /// se pracuje. PlaybackController i CompositionBuilder dostanou hotovou
    /// URL, ne asset — jinak se to rozhodování rozleze na deset míst.
    func url(usingProxies: Bool) -> URL {
        (usingProxies ? proxyURL : nil) ?? originalURL
    }
}
```

**Časová základna se bere z originálu**, nikdy z proxy.

Z toho plyne podmínka na `ProxyGenerator` ve fázi 4, kterou je potřeba zapsat hned: **proxy musí na čase `t` ukazovat totéž co originál na čase `t`.** Přepnutí `usesProxies` nesmí posunout ani jeden snímek. Proxy se přitom zplošťuje z VFR na CFR, takže to není samozřejmé — je to zadání.

### 2.6 Obraz a zvuk jsou dva svázané klipy

Video se zvukem se na osu vloží jako **dva klipy se sdíleným `linkID`** — obraz na obrazovou stopu, zvuk na zvukovou.

Důvod je střihový: bez toho nejde **J/L cut**, tedy nechat zvuk doběhnout přes střih obrazu. U proslovů a slibů je to základní technika, a to je přesně to, co ve svatebním filmu nese emoci. Vazba jde rozpojit, když se má zvuk chovat samostatně.

**Z toho plyne dosah ripplu**, který jinak zůstane nedefinovaný a rozbije se na něm synchron:

> `rippleRemove` a ripple trim posouvají klipy **na stopě zasaženého klipu a na stopách jeho svázaných dvojčat**. Nikdy na ostatních.

Hudební podkres na A2 je pevná páteř, ke které se stříhá — kdyby ho ripple posouval, rozsype se celý film. A kdyby ripple naopak neposunul svázaný zvuk, rozejde se s obrazem. Obojí by přitom prošlo validací jako platný stav.

---

## 3. Typy

```swift
/// Čas na časové ose projektu, v celých snímcích základny (30 fps).
/// Používá se pro pozici i pro délku — stejně jako CMTime.
/// Konce rozsahů jsou VŽDY exkluzivní: klip [10, 20) sousedí s [20, 30)
/// a nepřekrývají se.
struct Frames: Hashable, Comparable, Codable, Sendable {
    var count: Int
    static let zero = Frames(count: 0)
    // + - < …
}
```

Převod na sekundy na `Frames` **záměrně není**. Kdyby tam byl, nic by nebránilo převést osové snímky frekvencí *assetu* — tedy přesně tou záměnou, které se model brání. Převod žije na `Timeline`, která zná základnu projektu.

```swift
/// Zdrojový čas jako zlomek. Vlastní typ, ne CMTime — CMTime NENÍ Codable
/// (ověřeno v dokumentaci), takže by se struktura s ním nepřeložila.
/// https://developer.apple.com/documentation/coremedia/cmtime
/// Navíc formát na disku pak nezávisí na tom, co Apple vygeneruje.
struct SourceTime: Hashable, Comparable, Codable, Sendable {
    var value: Int64
    var timescale: Int32
    // převod na CMTime až na hranici s AVFoundation
}

/// ID jako RawRepresentable — jinak se zakóduje jako {"raw": "…"}
/// místo holého řetězce.
struct AssetID: Hashable, Codable, Sendable, RawRepresentable { let rawValue: String }
struct ClipID:  Hashable, Codable, Sendable, RawRepresentable { let rawValue: String }
struct TrackID: Hashable, Codable, Sendable, RawRepresentable { let rawValue: String }
struct LinkID:  Hashable, Codable, Sendable, RawRepresentable { let rawValue: String }

struct Asset: Identifiable, Codable, Sendable {
    let id: AssetID
    var originalURL: URL
    var proxyURL: URL?
    /// Security-scoped bookmark — bez něj se po restartu k souboru nedostaneme.
    var bookmark: Data?
    var duration: SourceTime
    /// NAMĚŘENÁ frekvence z VFRDetectoru, ne nominalFrameRate.
    /// Ta na slow-mo klipu hlásí 119,369 místo skutečných 120,000.
    var measuredFrameRate: Double
    var hasVideo: Bool
    var hasAudio: Bool
    /// Soubor zmizel nebo se přejmenoval. Klipy zůstávají, drží si poslední
    /// známou délku a operace na nich běží normálně — smazat cizí práci kvůli
    /// přejmenované složce je horší chyba než prázdné místo v náhledu.
    var isOffline: Bool
}
```

Zbytek výsledku sondy — verdikt CFR/VFR, rozlišení, orientace, kodek — **v modelu není**. Model drží identitu a časování; ostatní žije v `MediaIndex.json` vedle. Orientaci si `TimelineView` vyžádá odtamtud.

```swift
enum TrackKind: String, Codable, Sendable { case video, audio }

struct AudioSettings: Codable, Sendable {
    var volume: Double   // 0…1
    var isMuted: Bool
}

struct Track: Identifiable, Codable, Sendable {
    let id: TrackID
    var kind: TrackKind
    var name: String
    /// Jen u zvukových stop. Optional, ne pole ignorované u poloviny
    /// instancí — takové pole je pozvánka k chybě.
    var audio: AudioSettings?
    /// VŽDY seřazené podle timelineStart a nepřekrývající se.
    private(set) var clips: [Clip]
}

struct Clip: Identifiable, Codable, Sendable {
    let id: ClipID
    var assetID: AssetID
    /// Sdílené s protějškem na druhé stopě. nil = samostatný klip.
    var linkID: LinkID?

    /// Kde klip začíná NA OSE.
    var timelineStart: Frames
    /// Jak dlouho trvá NA OSE. Spotřebu zdroje z toho neodvozuj přímo —
    /// od fáze 3 to nebude 1:1. Používej Project.sourceConsumption(of:).
    var duration: Frames

    /// Odkud se bere ve ZDROJI. Prezentační čas v originálu,
    /// S RESPEKTOVANÝM EDIT LISTEM — čte se přes AVComposition.
    /// Všech pět měřených klipů zahazuje na zvuku prvních 44 ms, a to je
    /// na 30fps základně víc než jeden snímek. Kdo edit list ignoruje,
    /// bude tu chybu hledat v synchronizaci místo ve čtení.
    var sourceStart: SourceTime

    /// Fáze 3. Uzly ve zdrojovém čase — viz 2.4.
    var speedRamp: SpeedRamp?

    /// Exkluzivní konec.
    var timelineEnd: Frames { timelineStart + duration }
}

struct Timeline: Codable, Sendable {
    /// Základna projektu. Pevných 30, ale pojmenované — ať se v kódu nikde
    /// neobjeví magická třicítka.
    let frameRate: Int
    /// Rozlišení plátna. Fáze 3 ho potřebuje pro renderSize, fáze 5 pro export.
    var canvasSize: CGSize
    /// Pořadí je významné: pozdější obrazová stopa překrývá dřívější.
    var tracks: [Track]
}

struct Project: Codable, Sendable {
    /// Pole, ne slovník. JSONEncoder kóduje slovník s ne-řetězcovým klíčem
    /// jako plochý seznam střídajících se klíčů a hodnot, ne jako objekt —
    /// a specifikace 6.2 chce objekt. Index se staví při načtení.
    var assets: [Asset]
    var timeline: Timeline
    /// Jedna věc na projekt, ne tisíc na klipy.
    var usesProxies: Bool

    /// Výchozí prázdný projekt: V1 + A1 + A2 podle specifikace 8.1.
    static func empty() -> Project
}
```

**Vláknový model:** všechny typy jsou hodnotové a `Sendable`. Projekt vlastní `@MainActor` — operace se volají z hlavního vlákna, protože je řídí UI. Se Swift 6 a striktní konkurencí to není kosmetika; dopsat to později znamená prolézt každou operaci.

**Výběr do modelu nepatří** — je to stav UI, do `project.json` se neukládá:

```swift
struct Selection: Sendable { var clips: Set<ClipID> }
```

⚠️ Po každé mutaci musí UI výběr pročistit od zmizelých `ClipID`. Je to nejčastější zdroj pádů v timeline UI.

---

## 4. Invarianty

Jádro testovatelnosti. Po **každé** operaci musí platit všechny:

1. Klipy na stopě jsou seřazené vzestupně podle `timelineStart`.
2. Žádné dva klipy na téže stopě se nepřekrývají. *(Dotyk konec == začátek překryv NENÍ.)*
3. `duration.count > 0`.
4. `timelineStart.count >= 0`.
5. `sourceStart + sourceConsumption(of:) <= asset.duration`.
6. `assetID` každého klipu existuje mezi assety.
7. `ClipID` je v celém projektu jedinečné.
8. Klip na stopě `.video` má asset s `hasVideo`, na `.audio` s `hasAudio`.
9. Svázané klipy (`linkID`) leží na stopách různého druhu a je jich nejvýš dvojice.
10. `sourceStart >= 0`, `asset.duration > 0`, `measuredFrameRate > 0`.

```swift
extension Project {
    enum Violation: Equatable { /* … jeden případ na každý invariant … */ }

    /// Vrací VŠECHNA porušení, ne první. Při ladění operace potřebuješ vidět
    /// celý rozsah škody.
    func validate() -> [Violation]
}
```

Každý test operace končí `XCTAssertTrue(project.validate().isEmpty)`.

---

## 5. Operace

Volné pozice, mezery jsou legální a samy se nezavírají. Ripple je zvláštní operace, o kterou si uživatel řekne.

**Každá operace pracuje na kopii a přiřadí ji až na konci.** Tím je zdarma splněné pravidlo, že chyba nechá projekt nezměněný — žádná polovičatá mutace.

### Vytváření a assety

| operace | co dělá |
|---|---|
| `addAsset(_:)` | zaeviduje zdrojový soubor |
| `removeAsset(id:)` | odebere; selže, dokud na něj odkazuje klip |
| `relink(assetID:to:)` | nová cesta k offline assetu |
| `makeClip(assetID:)` | vyrobí klip přes celou délku assetu — **model razí `ClipID` i výchozí délku**, ne UI |
| `makeLinkedClips(assetID:)` | dvojice obraz+zvuk se sdíleným `linkID` |
| `duplicate(clipID:)` | kopie s **novým** `ClipID` — jinak je invariant 7 nevymahatelný, protože kopie struktury si ID vezme s sebou |

### Stopy

`addTrack(kind:name:)`, `removeTrack(id:)`, `renameTrack(id:to:)`, `moveTrack(id:toIndex:)`.

### Klipy

| operace | co dělá | co se stane s ostatními |
|---|---|---|
| `insert(clip:onTrack:)` | vloží na danou pozici | nic; překryv = chyba |
| `overwrite(clip:onTrack:at:)` | vloží a **přepíše**, co je pod ním | sousedi se ořežou, plně překryté zmizí — **atomicky** |
| `remove(clipID:)` | smaže | nic, mezera zůstane |
| `rippleRemove(clipID:)` | smaže | vše za ním na jeho stopě a na stopách svázaných klipů se posune vlevo |
| `rippleInsert(clip:onTrack:at:)` | vloží a odsune | totéž doprava |
| `move(clipID:toTrack:start:)` | přesune (i na jinou stopu) | nic; překryv = chyba |
| `split(clipID:at:)` | rozdělí; `at` je **první snímek druhé poloviny** | nic |
| `join(leftID:rightID:)` | zase spojí, když na sebe navazují i ve zdroji | opak splitu — bez toho se špatný řez neopraví jinak než undo |
| `trimStart(clipID:to:)` | posune začátek | mění `timelineStart` i `sourceStart` |
| `trimEnd(clipID:to:)` | posune konec | mění jen `duration` |
| `slip(clipID:by:)` | posune, co se ze zdroje bere, **beze změny pozice a délky** | nic — takhle se opraví „ustřihl jsem to o vteřinu dřív" |
| `rollEdit(leftID:rightID:to:)` | posune hranici mezi sousedy; `to` je nová pozice hranice, posun doprava **prodlouží levý** | délka dvojice zůstává |
| `closeGap(afterClipID:)` | přitáhne následující | posune jen ten jeden |
| `setSpeedRamp(clipID:ramp:)` | fáze 3; **operace, ne přiřazení** — mění délku na ose | může narazit do souseda |
| `unlink(clipID:)` / `link(_:_:)` | rozpojí nebo spojí obraz se zvukem | — |

### Dotazy — bez nich si je UI dopočítá samo a pravidla se rozejdou

```swift
func legalRange(movingClip: ClipID, toTrack: TrackID) -> ClosedRange<Frames>
func maxTrimStart(clipID: ClipID) -> Frames
func maxTrimEnd(clipID: ClipID) -> Frames
func slipRange(clipID: ClipID) -> ClosedRange<Frames>
```

Tažení potřebuje vědět, **kam smí**, ne se dozvědět po překročení, že nesmělo.

### Chyby

```swift
enum TimelineError: Error, Equatable {
    case clipNotFound(ClipID), trackNotFound(TrackID), assetNotFound(AssetID)
    /// Nese i mez, na které se má tažení zarazit.
    case wouldOverlap(with: ClipID, nearestLegal: Frames)
    case negativePosition
    case zeroLength
    case exceedsSourceMaterial(availableFrames: Frames)
    case splitOutsideClip
    case notAdjacent(ClipID, ClipID)
    case wrongTrackKind(expected: TrackKind, got: TrackKind)
    case assetStillInUse(AssetID)
    case notJoinable(reason: String)
}
```

⚠️ **Pořadí kontrol musí být pevně dané.** Když trim narazí zároveň do souseda i do konce zdroje, musí vždycky vyhrát tatáž chyba — UI podle ní zaráží tažení a nedeterministické pořadí znamená, že se tažení zarazí pokaždé jinde. Pravidlo: **nejdřív zdrojový materiál, pak sousedi.**

Dvě věci, které se dělají snadno špatně:

- **`split` musí navázat ve zdroji** přes `sourceOffset(in:atFrame:)`. Kdo tam dá `sourceStart`, dostane opakující se záběr a nevšimne si toho, dokud to nepustí.
- **`trimStart` posouvá `sourceStart` současně s `timelineStart`.** Když se posune jen jedno, klip se ve zdroji „ujede" a při dalším trimu se chyba znásobí.

---

## 6. Undo

Snapshot stack, ne command pattern. `Project` je hodnotový typ, takže snapshot je jeho kopie a nemá vlastní kód, který by mohl mít chybu.

**Snímkuje se celý `Project`, ne jen `Timeline`.** Jinak: naimportuješ klip a vložíš ho (přibude asset i klip), undo smaže klip a asset zůstane; po redo se vrátí klip odkazující na asset, který se mezitím odstranil — porušený invariant 6 cestou, kterou žádná operace nehlídá. Stejně tak relink a přepnutí proxy by nešly vzít zpět.

```swift
struct UndoStack {
    private var past: [Project] = []
    private var future: [Project] = []
    var limit = 100
}
```

Cena je O(počet klipů na dotčené stopě) na krok — při tisíci klipech a limitu 100 jednotky MB. Command pattern by dával smysl u dat, která se nedají levně kopírovat; tady by jen přidal místo, kde se dá udělat chyba.

**Tažení klipu je jeden undo krok, ne šedesát.** Ale pozor na to, jak to funguje:

> Během tažení drží náhled **UI ve vlastním stavu** a do modelu zapisuje jen legální stavy. Jinak by každý mezistav při přetahování přes souseda byl překryv, tedy chyba, šedesátkrát za sekundu.
>
> `beginInteraction()` / `endInteraction()` slouží pro **trim a roll**, kde mezistavy legální jsou.

`endInteraction` bez skutečné změny **nesmí** vytvořit undo krok — jinak Cmd+Z dvakrát nic neudělá a vypadá to jako zamrznutí.

---

## 7. Testy

Podle vzoru `SpeedRampEngine` (41 testů).

**Invarianty**

1. Po každé operaci `validate()` vrací prázdno.
2. Náhodná posloupnost 100 operací neporuší invarianty. **Generátor s pevným semínkem, semínko vytisknout při selhání** — nereprodukovatelný červený test je horší než žádný.
3. Každá operace, která hodí chybu, nechá projekt bajt po bajtu nezměněný.

**Hranice soustav**

4. `sourceTime` a `availableFrames` jsou k sobě inverzní až na zaokrouhlení dolů.
5. Asset dlouhý 14,517 s dá 435 snímků, ne 436.
6. Dvojí vložení celého klipu z takového assetu dá identický výsledek.
7. VFR zdroj: klip má vždy přesně `duration.count` snímků na ose, ať zdroj časuje jakkoli.
8. `availableFrames` u VFR zdroje nikdy nenadhodnotí.

**Vkládání a mazání**

9. Vložení do prázdné stopy. 10. Vložení do mezery přesně na míru. 11. O snímek delší → `wouldOverlap` s korektním `nearestLegal`. 12. Záporná pozice → `negativePosition`. 13. Nulová délka → `zeroLength`. 14. Smazání prostředního nechá mezeru přesné délky. 15. `rippleRemove` posune následující a **žádný předchozí**. 16. `rippleRemove` posledního = obyčejné smazání. 17. **Ripple na V1 neposune klip na A2.** 18. **Ripple na V1 posune svázaný zvuk na A1.** 19. `overwrite` na částečný překryv ořeže souseda. 20. `overwrite` na plný překryv souseda smaže. 21. `overwrite`, který selže uprostřed, nechá timeline netknutou.

**Split a join**

22. Split uprostřed: délky se sečtou na původní. 23. Druhá polovina začíná ve zdroji tam, kde první končí. 24. Split na `timelineStart` → `zeroLength`. 25. Split na `timelineEnd` → `splitOutsideClip`. 26. Split na poslední snímek klipu dá jednosnímkový ocásek a je **legální**. 27. Split jednosnímkového klipu → chyba. 28. Split + join = původní klip. 29. Join klipů, které na sebe nenavazují ve zdroji → `notJoinable`.

**Trim a slip**

30. `trimStart` posune `timelineStart` i `sourceStart` o stejný čas. 31. `trimEnd` mění jen `duration`. 32. Trim na nulu → `zeroLength`. 33. **Trim přesně na poslední snímek zdroje projde.** 34. **O jeden dál → `exceedsSourceMaterial` se správným zbytkem.** 35. Trim doleva u klipu se `sourceStart == 0` → `exceedsSourceMaterial`. 36. Prodloužení do mezery projde. 37. Prodloužení do souseda → `wouldOverlap`. 38. Trim narazí zároveň do souseda i do zdroje → vždy tatáž chyba (zdroj vyhrává). 39. `slip` nemění pozici ani délku, jen `sourceStart`. 40. `slip` za hranici zdroje → `exceedsSourceMaterial`. 41. Trim do místa, kde zdrojový vzorek pokrývá víc snímků (zahozený snímek ve VFR), použije pokrývající vzorek.

**Přesun**

42. Přesun v rámci stopy. 43. Přesun na jinou stopu téhož druhu. 44. Obrazový klip na zvukovou stopu → `wrongTrackKind`. 45. Přesun na obsazené místo → `wouldOverlap`. 46. Přesun na sebe je no-op, ne chyba. 47. Přesun do mezery přesně na míru. 48. Přesun svázaného klipu vezme dvojče s sebou.

**Roll**

49. Roll doprava prodlouží levý a zkrátí pravý o stejný počet. 50. Roll zachová délku dvojice. 51. Roll za konec zdroje **levého** klipu → `exceedsSourceMaterial`. 52. Totéž pro pravý. 53. Roll mezi nesousedy → `notAdjacent`.

**Undo**

54. Undo po jedné operaci vrátí přesně původní stav. 55. Undo/redo/undo skončí u undo. 56. Nová operace po undo zahodí redo větev. 57. Zásobník se zastaví na limitu. 58. Trim mezi `begin` a `endInteraction` je jeden krok. 59. `endInteraction` bez změny nevytvoří krok. 60. Nespárované `beginInteraction` nerozbije zásobník. 61. **Undo přes operaci, která přidala asset, vrátí i ten asset.**

**Ostatní**

62. Prázdný projekt z `empty()` má V1 + A1 + A2 a projde validací. 63. Přepnutí `usesProxies` nezmění v modelu žádnou hodnotu. 64. `removeAsset` s existujícím klipem → `assetStillInUse`. 65. Offline asset: operace na jeho klipech běží normálně. 66. `duplicate` dá nové `ClipID`. 67. Timeline s 1000 klipy: `move` se dotkne nejvýš dvou klipů, `rippleRemove` jen klipů za ním. *(Složitost se neasertuje — kontroluje se počet dotčených prvků.)*

---

## 8. Co záměrně není v modelu

- **Zoom, scroll, pixely** — věc `TimelineView`.
- **Přichytávání** — model dostane už zaokrouhlenou pozici; kam se přichytává, rozhoduje UI.
- **Vlnové průběhy** — předrenderované dlaždice per úroveň zoomu.
- **Výběr** — stav UI.
- **Vlastnosti média mimo časování** — rozlišení, orientace, kodek, verdikt CFR/VFR žijí v `MediaIndex.json`.

---

## 9. Zbývá rozhodnout

1. **Formát `project.json`.** Doporučení: doplnit snímkové hodnoty vedle sekundových, formát verzovat a zapsat pravidlo **při rozporu vyhrávají snímky**; sekundy jsou odvozené a při načtení se ignorují. Bez toho vznikne soubor se dvěma pravdami. Vratné, řeší se ve fázi 5.
2. **Chování offline assetu při exportu.** Model ho unese (drží poslední známou délku), ale co má dělat export — odmítnout, nebo vyrenderovat černou? Fáze 5.
