# FÁZE 18 — přestavba UI podle `design_handoff_krasa_ui`

*Sestaveno 29. 07. 2026. Zdroj zadání: `design_handoff_krasa_ui/README.md` + šest prototypů v `designs/`.*

Plán pokrývá **všech šest obrazovek návrhu do posledního prvku**. Není to seznam přání — je to
pořadí modulů, kde každý dál staví na hotovém a každý má vlastní kontrolu, kterou se pozná, že
funguje. Vzorec je tentýž jako u fází 10–17: **model a logika s testy → tenké UI nad tím →
CLI kontrola s čísly → screenshot**.

---

## 1. Co plán řeší

Šest potíží pojmenovaných v zadání:

| # | Potíž | Modul, který ji zavírá |
|---|---|---|
| 1 | sidebar mísil dokument, nastavení, dodávku i vývojářská měření | M1 (rám), M2 (stav), M9 (knihovna) |
| 2 | inspektor měl 132 px na křivku rychlosti i barvy | M7 (panel 452), M8 (záložky) |
| 3 | transport byl řada stejně velkých tlačítek bez hierarchie | M1 (pilulka) |
| 4 | stav běžících analýz nebyl vidět | M2 (čip + stavový řádek) |
| 5 | osa nesla všechny informace naráz | M3 (přepínače vrstev) |
| 6 | chyběla knihovna médií | M9 |

---

## 2. Tři rozhodnutí PŘED prvním modulem

Bez nich se nedá začít — každé mění, co se bude psát.

### 2.1 Kdy vůči KILL-GATE 1

`PROJECT_STATUS.md` říká: *„Do kill-gate se nepřidávají funkce."* Tenhle plán jich přidává devět
(knihovna, přetažení, přehled osy, dva fullscreeny, přepínače vrstev, citlivost, prázdný start,
plovoucí náhled snímku). Materiál na svatbu je ~konec srpna 2026.

**Doporučení: etapy A + C (moduly M1–M3, M7, M8) před svatbou, etapy B a D po ní.**
Ty moduly nepřidávají žádnou funkci — jen zviditelňují, co už appka umí, a dávají křivce rychlosti
místo. To je přesně to, co bude na svatbě bolet. Knihovna a fullscreen počkají: bez nich se svatba
sestříhat dá, bez 452px panelu na křivku hůř.

### 2.2 Světlý režim — zůstává, nebo padá?

Návrh má **jen tmavou variantu**. Dnešní kód má obě větve:
`TimelineDocumentView.swift:33` a `RampEditorView.swift:30` volí přes
`appearance.bestMatch(from: [.aqua, .darkAqua])`.

Tři cesty: **(a)** okno natvrdo `NSAppearance(named: .darkAqua)`, světlá větev se smaže — nejlevnější,
mínus je editor, který nectí systém; **(b)** světlá větev zůstane a doplní se o nové chrome tokeny —
dvojnásobek palety navíc a nikdo ji neotestuje; **(c)** zůstane jak je a nové chrome bude jen tmavé —
nejhorší, mix.

**Doporučení: (a).** Střihové aplikace jsou tmavé záměrně — světlé okolí posouvá vnímání jasu obrazu.

### 2.3 Pilulka transportu leží NA obraze — a to stojí GPU

Tohle je jediné místo, kde návrh naráží na naměřené číslo projektu.

`CLAUDE.md`: *„GPU rezidence náhledu nesleduje plochu obrazu, ale nutnost kompozice… tentýž klip dá
9,90 % s aplikací na pozadí a 0,25 % vpředu. Dokud je náhled holé video a nic přes něj neleží, jde na
displej jako samostatná vrstva."*

Návrh klade na obraz **natrvalo**: tři čipy vlevo nahoře, měřidlo LUFS vpravo, pilulku transportu
dole. Tím se náhled **trvale přepne do skládání** a baseline z fáze 1 v běžném provozu přestane platit.

Není to chyba návrhu — je to cena za vzhled. Ale musí se **změřit, ne odhadnout**, a musí být
ústupová cesta:

- **M1 měří** `--fullscreen` a `--benchmark` se zapnutými overlay a bez nich a čísla zapíše.
- Když skok bude neúnosný (řekněme nad ~10 % GPU při přehrávání), zapne se **totéž chování, které
  návrh už má ve fullscreenu**: overlay mizí po ~2 s nečinnosti a vrací se pohybem myši. Vzhled
  zůstane, cena zmizí.
- Měřicí cesta (`chromeHidden` / `isMeasuring`) overlay **nesmí kreslit vůbec** — jinak přestanou
  být srovnatelné všechny starší benchmarky.

---

## 3. Inventura — co z návrhu už v kódu je

Ověřeno grepem, ne odhadem.

| Prvek návrhu | Stav | Kde |
|---|---|---|
| paleta osy, přechody, titulky, kvalita, doby | **je** | `TimelinePalette` (`TimelineDocumentView.swift:28`) |
| křivka rampy, žlutá zóna, uzly | **je** | `RampEditorView.swift` (462 ř.) |
| barevné presety + síla | **je** | `ColorGradePanel` (`ContentView.swift:4077`) |
| fade klíny a úchyty | **je** | `applyFades` (`TimelineDocumentView.swift:797`) |
| proužky kvality a hluchosti | **je** | `applyQualityMarks` (:820) |
| vlny | **je** | `WaveformStore` (341 ř.), `applyWaveform` (:848) |
| doby v pravítku | **je** | `TimelineRulerView` |
| výřez I/O | **je** (model + pravítko) | `TimelineController.setInPoint` (:76) |
| JKL, žebřík, krokovací fallback | **je** | `PlaybackController` |
| titulkový a řečový overlay | **je** | `TitleOverlay` (:4202), `SubtitleOverlay` (:4295) |
| export s progressem | **je**, ale jen tlačítko + `ProgressView` v sidebaru | `AppModel.exportProgress` (:424) |
| přepis řeči | **je** služba, UI je inspektor v pásu 132 px | `TranscriptionService`, `SpeechInspector` (:4155) |
| citlivost analýz | **model ano, UI ne** | `Quality.qualityThresholds(sensitivity:)` |
| stav běhů analýz | **běhy ano, UI ne** | `SharpnessStore`, `EmptinessStore` |
| **miniatury na klipech** | **není** | — |
| **knihovna médií** | **není** | — |
| **přetažení souborů / z knihovny** | **není** (`onDrop` ani `draggingEntered` nikde) | — |
| **přehled celé osy** | **není** | — |
| **přepínače vrstev osy** | **není** | — |
| **fullscreen aplikace / náhledu** | **není** (jen `FullScreenSwitch` pro měření) | `PlayerView.swift:217` |
| **prázdný start** | **není** | — |
| **rail, toolbar, stavový řádek** | **není** | — |

---

## 4. Čtyři rizika, která řídí pořadí modulů

**R1 — scroll benchmark fáze 2.** Kritérium *2000 klipů bez vypadlého tiku* platí dál. Miniatury (M5)
jsou nejdražší věc v celém plánu: dekódovaný snímek je řádově dražší než dlaždice vlny. Proto jsou
**přepínače vrstev (M3) PŘED miniaturami (M5)** — až budou miniatury hotové, musí jít vypnout, a to
tlačítko musí existovat dřív, než ho někdo bude potřebovat. Brána: `--timeline-bench` se zapnutými
miniaturami beze změny proti dnešku.

**R2 — GPU baseline náhledu.** Viz 2.3. Brána v M1.

**R3 — `ContentView.swift` má 4483 řádků** a plán se dotýká skoro každé jeho části. Kdyby se psalo
dovnitř, skončí to nad osmi tisíci. **Každý modul si odnese svůj kus do vlastního souboru**
(`UI/Shell/`, `UI/Panels/`, `UI/Library/`, `UI/Export/`, `UI/Transcript/`, `UI/Fullscreen/`);
v `ContentView.swift` zůstane `AppModel` a kořen. Ne jako úklid „někdy potom" — jako součást modulu.

**R4 — měřicí cesty.** `chromeHidden` a `isMeasuring` dnes osu z hierarchie **odstraňují** (`if`, ne
nulový rámec — jednou to už natáhlo layout na 4398 bodů a měření to nepoznalo). Nový rám má šest
pater místo dvou. Ten `if` musí přežít každý modul; regresní brána je **`--benchmark` a `--timeline-bench`
po každém modulu etapy A a B**.

---

## 5. Roadmapa

Čtyři etapy, třináct modulů. **Jeden modul = jedna session** (pravidlo projektu).

### ETAPA A — rám a chrome *(nepřidává funkce; vhodné před svatbou)*

---

#### M1 · Nový rám okna

| | |
|---|---|
| **Cíl** | Toolbar 46 · rail 60 · stavový řádek 26 · přeskládané tělo. Přehrávač dostane pilulku transportu, čipy a měřidlo. |
| **Soubory** | nový `UI/Shell/AppShell.swift`, `UI/Shell/Toolbar.swift`, `UI/Shell/IconRail.swift`, `UI/Shell/TransportPill.swift`; `ContentView.swift` (kořen, `TransportBar` → pilulka) |
| **Práce** | Rozbití `HSplitView { sidebar \| playerPane }` na svislý stack toolbar → tělo → stavový řádek; tělo = rail \| obsah; obsah = horní pás 372 → lišta osy 32 (zatím prázdná) → osa. Rail šest položek 44×44 se SF Symbols. Pilulka 44 px na střed dole nad obrazem, kruh play/pauza 44, čip rychlosti jen když `shuttleRate != 0`, oranžový jen v `isSteppingFallback`. Tři čipy vlevo nahoře, měřidlo LUFS vpravo. Obraz `height:100%; width:auto` — jinak přeteče do transportu. |
| **Hotovo když** | Screenshot sedí na `01-hlavni-okno.png` v rozměrech na bod; sidebar je pryč, jeho obsah dočasně v položce railu **Nastavení**. |
| **Ověření** | `--benchmark`, `--fullscreen` (nové číslo s overlay i bez — **brána R2**), `--timeline-bench` beze změny, nový `--shell-check`: změří výšky pater a souřadnice osy proti tabulce návrhu. |
| **Riziko** | R2, R4. Vývojářská měření ze sidebaru se nesmí ztratit — přesouvají se, neruší. |

---

#### M2 · Stavový řádek a čip běžících analýz

| | |
|---|---|
| **Cíl** | Vidět, co běží. Dnes `startSharpnessAnalysis()` běží bez jakéhokoli UI. |
| **Soubory** | `Media/SharpnessStore.swift`, `Media/EmptinessStore.swift` (přidat `@Published` průběh), `Media/ProxyStore.swift`, `Media/TranscriptionService.swift`; nový `UI/Shell/StatusBar.swift`, `UI/Shell/AnalysisChip.swift` |
| **Práce** | Storům dát pozorovatelný stav (běží / ve frontě / hotovo / kolik z kolika). Čip v toolbaru 28 px s tečkou `warn`. Stavový řádek: tři tečky (Ostrost, Proxy, Model přepisu) + poslední akce vpravo — sem míří dnešní hook `onStatus` z osy. |
| **Hotovo když** | Import pěti klipů ukáže „Analyzuju kvalitu · 3/5" a po doběhnutí čip zmizí. |
| **Ověření** | `--status-check`: naimportuje klipy, odebírá publikované stavy a vypíše posloupnost přechodů (žádný stav nesmí zůstat viset po doběhnutí úlohy). |
| **Riziko** | Actor hop — stores jsou actory, publikace musí na hlavní vlákno (vzorec `WaveformStore`). |

---

#### M3 · Lišta osy — vrstvy, citlivost, výřez, zoom

| | |
|---|---|
| **Cíl** | Pás 32 px: `Miniatury` `Vlny` `Doby` `Značky kvality` · `Citlivost` + slider · `Přichytávání` · výřez + `I` `O` · zoom + `Fit ⇧Z`. |
| **Soubory** | nový `UI/Shell/TimelineToolbar.swift`; `Timeline/TimelineDocumentView.swift` (respektovat vrstvy), `Timeline/TimelinePane.swift` (Fit), `Timeline/TimelineController.swift` (citlivost) |
| **Práce** | `timelineLayers` (4× bool) a `qualitySensitivity` (0–1, `UserDefaults`) na `TimelineController`. Vypnutá vrstva = **early-out v `rebuildClipInfo`/`layoutStrips`**, ne skrytá vrstva — smysl je ušetřit práci, ne ji udělat a schovat. Citlivost přepočítá značky přes `qualityMarks(samples:sensitivity:)` — **žádné nové vzorkování**, vzorky se nesahají. `Fit` dopočítá `pointsPerFrame` z délky osy a šířky výřezu. |
| **Hotovo když** | Vypnutí vln vlny odstraní a scroll je měřitelně levnější; posuvník citlivosti mění počet proužků bez čekání. |
| **Ověření** | `--layers-check`: postaví osu, změří `--timeline-bench` se všemi vrstvami zapnutými a všemi vypnutými (dvě čísla vedle sebe); citlivost 0,2 / 0,5 / 0,8 dá monotónně rostoucí počet značek na týchž vzorcích. |
| **Riziko** | R1 — tohle je pojistka pro M5, takže musí být hotová dřív. |

---

### ETAPA B — osa *(nová funkčnost; po svatbě)*

---

#### M4 · Výšky stop, hlavičky 104

| | |
|---|---|
| **Cíl** | V1 136 · A1 78 · A2 78 · T1 40, mezera 3, horní odsazení 3, součet **344**; hlavičky 104 px s obsahem. |
| **Soubory** | `TimelineModel/Sources/TimelineModel/Geometry.swift` (**+`topInset`**), `Timeline/TrackHeadersView.swift`, `Timeline/TimelineController.swift` |
| **Práce** | ⚠️ **Výchozí hodnoty v modelu nechat být** (64/44/28, spacing 2) a nové výšky předat konstruktorem z aplikace — jinak se rozsypou testy 453 kusů, které z výchozích čísel počítají odsazení. `topInset` je nová vlastnost s výchozí 0 (existující testy nedotčené) + 3 nové testy. Hlavičky: jméno 11/semibold + meta 9 px + `M` a slider hlasitosti u zvuku, dvě mini tlačítka u V1. **Řádky musí mít pevnou výšku**, jinak se rozjedou s pruhy. |
| **Hotovo když** | Klipy leží na `top` 3 / 142 / 223 / 304 a hit testing se trefuje na bod. |
| **Ověření** | Testy v `TimelineModel` (`topInset`, součet 344); `--layout-check`: projde všechny stopy a porovná `y(ofTrackAt:)` s tabulkou návrhu. |
| **Riziko** | Nízké — geometrie je otestovaná, mění se vstupní čísla, ne matematika. Pozor na minimální okno 1180×760: stopy (344) se do výšky nevejdou, svislý scroll osy musí fungovat. |

---

#### M5 · Miniatury na klipech, křivka rampy na klipu, badge

| | |
|---|---|
| **Cíl** | Dolních 96 px obrazového klipu = pás miniatur (2–4 dlaždice); křivka rampy kreslená na klipu; badge presetu / rampy / synchronizace. |
| **Soubory** | nový `Timeline/ThumbnailStore.swift`; `Timeline/TimelineDocumentView.swift` (`ClipLayer`, `refreshClips`) |
| **Práce** | `ThumbnailStore` vzorcem `WaveformStore`: actor, dlaždice, disková cache otiskem `v1\|cesta\|velikost\|mtime\|výška`, generování **z proxy, ne z originálu**. Batch API `AVAssetImageGenerator.images(for:)` — ⚠️ *pravidlo 6: před použitím ověřit v dokumentaci*; jednosnímkové `image(at:)` je v projektu prověřené (`ContentView.swift:461`). Klipová vrstva dostane `setThumbnailTiles`. Křivka rampy `rampCurve` 1,5 px v pásu 40 px, uzly 3 px. |
| **Hotovo když** | Osa vypadá jako screenshot a **scroll benchmark drží**. |
| **Ověření** | **`--timeline-bench` s miniaturami = brána R1** (2000 klipů, 0 vypadlých tiků). `--thumb-check`: první generování a druhé z cache (čas + shoda), miniatura odpovídá snímku ve zdrojovém čase (porovnání jasu proti `AVAssetImageGenerator` napřímo). |
| **Riziko** | **Nejvyšší v celém plánu.** Když benchmark spadne: dlaždice líně jen pro viditelný rozsah, hrubší dlaždice při odzoomování, v krajním případě miniatury **výchozí vypnuté** (M3 to umožňuje) a v README se to přizná. |

---

#### M6 · Přehled celé osy

| | |
|---|---|
| **Cíl** | Pás 46 px pod stopami: bloky klipů, hlava, rámeček viditelného výřezu, celková délka. Navigace na dvacetiminutové stopáži. |
| **Soubory** | nový `Timeline/TimelineOverviewView.swift`; `Timeline/TimelinePane.swift` (zapojení do layoutu) |
| **Práce** | Vlastní `NSView` s `CALayer`, **vlastní mapování celé osy na svou šířku** (ne `TimelineGeometry` — ta je o zoomu). Klik = skok hlavou, tažení rámečku = scroll osy. Přestavba jen při změně projektu, hlava a rámeček přepisem rámce jedné vrstvy (vzorec cílených odběrů v `TimelinePane`). |
| **Hotovo když** | Tažení rámečku scrolluje osu a auto-scroll (`scrollToKeep`) se s ním nepere. |
| **Ověření** | `--overview-check`: 60minutová syntetická osa, klik do 3/4 přehledu položí hlavu do 3/4 délky (tolerance 1 snímek); tažení rámečku dá očekávaný `scrollX`. |
| **Riziko** | Souboj s auto-scrollem — tažení v přehledu musí `followSuspended` zapnout stejně jako live scroll. |

---

### ETAPA C — panely *(řeší potíž #2; vhodné před svatbou)*

---

#### M7 · Připnutý panel 452 + záložka Rychlost

| | |
|---|---|
| **Cíl** | Konec 132px pásu. Panel vpravo od osy, záložky Rychlost · Barva · Zvuk · Info, `⌘4` skryje. |
| **Soubory** | nový `UI/Panels/PinnedPanel.swift`, `UI/Panels/SpeedTab.swift`; `Timeline/RampEditorView.swift` (rozměry), `ContentView.swift` (`InspectorStrip` zaniká) |
| **Práce** | Panel 452 px, hlavička 34 (jméno klipu + meta), tělo `min-height:0` + scroll, **rozpočet výšky 360**. Záložka Rychlost: presety `Bez rampy \| 0,5× \| 0,25× \| 0,125×` (nedostupné pod limitem zdroje **s důvodem**), editor křivky v boxu 150 px s gutterem popisků 46, žlutá zóna s popiskem „limit zdroje 0,25× — pod ním se snímky duplikují", čip segmentace `182 úseků · skok 1,42 %`, spotřeba zdroje, korekce výšky, sekce Dopasování na hudbu (`fitClipEndToBeat`, `rampClipToBeat` — vypnuté položky nesou důvod z `noBeatInReach(nearest:)` / `noCleanSlowdown`). |
| **Hotovo když** | Křivka se dá kreslit myší v boxu 150 px stejně přesně jako dnes ve 132px pásu. |
| **Ověření** | `--panel-check`: syntetickými událostmi přidá uzel dvojklikem, potáhne ho, Escape zruší, ⌘Z vrátí — a porovná výsledný `SpeedRamp` s očekáváním; `⌘4` skryje panel a šířku dostane osa. |
| **Riziko** | `RampEditorView` má souřadnice navázané na svou velikost; změna poměru stran musí projít jeho testy tažení. |

---

#### M8 · Záložky Barva, Zvuk, Info

| | |
|---|---|
| **Cíl** | Zbylé tři záložky panelu. |
| **Soubory** | nové `UI/Panels/ColorTab.swift`, `AudioTab.swift`, `InfoTab.swift`; `ContentView.swift` (`ColorGradePanel`, `PhotoInspector`, `TitleInspector` se přesouvají) |
| **Práce** | **Barva**: náhled před/po (dvě dlaždice 52 px — skutečné snímky, ne gradienty), pět řádků presetů v pořadí `ColorPreset`, síla 0–100 %, čip „platí pro výběr · 3 klipy", kopie na výběr. **Zvuk**: fade slidery s hodnotou ve snímcích **i** sekundách, pravidlo „hrana pod crossfadem fade nedostane", stopa (M + hlasitost), klopák (posun + jistota), čipy LUFS a dBTP. **Info**: zdroj, VFR verdikt, čas natočení s přiznaným zdrojem, proxy. |
| **Hotovo když** | Preset na pěti klipech je jedno kliknutí a jeden krok ⌘Z (regrese na F17 M2). |
| **Ověření** | `--panel-check` rozšířený: preset na výběr = jeden undo krok; fade slider na výběru rozdá fade všem zvukovým klipům s vlastním zaříznutím. |
| **Riziko** | Nízké — obsah existuje, mění se rám. |

---

#### M9 · Knihovna médií a přetažení

| | |
|---|---|
| **Cíl** | Pás 330 px vpravo v horním pásu: hlavička, filtry, mřížka karet, patička s proxy. Přetažení do osy. |
| **Soubory** | nové `UI/Library/LibraryPane.swift`, `LibraryCard.swift`; `Timeline/TimelineDocumentView.swift` (cíl přetažení) |
| **Práce** | `LazyVGrid` 2 sloupce, **`grid-auto-rows` 94 px — karty musí mít pevnou výšku**, jinak je mřížka zmáčkne (past pojmenovaná v zadání). Karta: náhled 62 (z `ThumbnailStore`, M5) + popis 32; badge `VFR`, `120p`, délka, oranžová ryska měkké ostrosti; datum ze souboru **oranžově** (`creationDateSource == .fileSystem`). Filtry Vše/Video/Fotky/Hudba, řazení chronologicky. Patička: `Uspořádat na V1 chronologicky` (existuje) + stav proxy. **Přetažení**: zdroj `.onDrag { NSItemProvider(object: assetID.uuidString as NSString) }`, cíl `registerForDraggedTypes([.string])` + `draggingUpdated` (náhled vložení) + `performDragOperation` v `TimelineDocumentView` — protokol `NSDraggingDestination`, ⚠️ *pravidlo 6: ověřit v dokumentaci, v projektu se to dosud nepoužilo nikde*. Fotky a hudba padají na své druhy stop, jinam se drop odmítne. |
| **Hotovo když** | Záběr z knihovny se dá pustit na V1 a přistane tam, kam ukazoval náhled. |
| **Ověření** | `--library-check`: syntetická drag session (pasteboard + `draggingEntered/Updated/performDragOperation`) vloží klip na očekávaný snímek; drop hudby na V1 se odmítne; filtry vrací očekávané počty. |
| **Riziko** | Nová cesta do modelu mimo `TimelineInteraction`. Vložení musí jít **jedním undo krokem** a projít `validate()`. |

---

### ETAPA D — obrazovky *(po svatbě)*

---

#### M10 · List exportu

| | |
|---|---|
| **Cíl** | List 660 px, tři stavy `nastaveni / prubeh / hotovo`. |
| **Soubory** | nový `UI/Export/ExportSheet.swift`; `ContentView.swift` (export z `AppModel` zůstává, UI se odpojí od sidebaru) |
| **Práce** | **nastaveni**: Rozsah (Celý projekt / Jen výřez, s počty snímků), Obraz (+ čip `CFR`), Hlasitost (Bez / Web −14 / Vysílání −23 + poznámka o −1 dBTP), Titulky (vypálit T1 + `.srt`), Uložit jako, **varovný blok o duplikaci snímků** (30fps klip s rampou 0,25× → 37,5 %) s odkazem na klip. **prubeh**: procenta, snímky, rychlost, tři fáze, „můžeš dál stříhat". **hotovo**: kontrolní řádky — časování `CFR · kolísání 0,0 %`, hlasitost **včetně přiznání „gain omezen špičkami na +1,4 dB"**, titulky. |
| **Hotovo když** | Export výřezu i celého projektu jde z listu a čísla v hlavičce sedí na skutečný počet snímků. |
| **Ověření** | `--export-check` beze změny (regrese) + `--export-ui-check`: tři stavy se screenshotem, počet snímků v listu == počet zapsaných snímků. |
| **Riziko** | Varovný blok musí počítat duplikaci ze skutečných dat (`pureSlowdownLimit`), ne z konstanty v UI. |

---

#### M11 · Panel přepisu řeči

| | |
|---|---|
| **Cíl** | Rail `Řeč`, panel vpravo, stavy `prubeh / editace`, Zdroje řeči v horním pásu. |
| **Soubory** | nový `UI/Transcript/TranscriptPanel.swift`, `SpeechSourcesPane.swift`; `Media/TranscriptionService.swift` (průběžné úseky) |
| **Práce** | **prubeh**: procenta, tři fáze, **úseky přitékají průběžně** (poslední na `opacity .6`), „přepis běží ve stroji". **editace**: hledání + „jen pod hlavou", seznam úseků, vybraný jako karta s editovatelným polem, `Rozdělit v kurzoru` / `Smazat úsek`, poznámka „platí pro všechny klipy ze zdroje" (`setSpeechText` je na assetu). V ose: zvýrazněný rozsah úseku v A1 + vybraný pásek na T1. |
| **Hotovo když** | Oprava textu úseku se projeví v náhledu i v `.srt` a je to jeden undo krok. |
| **Ověření** | `--transcribe-check` beze změny + `--transcript-ui-check`: editace úseku → `.srt` nese nový text; „rozdělit v kurzoru" dá dva úseky se správnými časy. |
| **Riziko** | Průběžné doručování úseků z WhisperKitu — dnes se výsledek předává naráz. |

---

#### M12 · Prázdný start

| | |
|---|---|
| **Cíl** | Okno bez projektu: zóna přetažení, poslední projekty, **pruh obnovy zálohy místo modálního dialogu**. |
| **Soubory** | nový `UI/Shell/EmptyState.swift`; `Media/ProjectStore.swift` (seznam posledních projektů), `ContentView.swift` (`offerUnsavedRecovery` přestane být dialog) |
| **Práce** | Drop zóna s rámečkem `1.5px dashed`, `Vybrat soubory…` / `Vybrat složku…`, řádek formátů. Poslední projekty s délkou a počtem záběrů; **offline projekt oranžově „disk není připojený"** (bookmark se nerozbalí). Rail ztlumený na `.35`, lišta osy na `.4`, prázdné pruhy stop s návodem. |
| **Hotovo když** | Přetažení složky na prázdné okno naimportuje totéž co `Otevřít složku`. |
| **Ověření** | `--empty-start-check`: simulovaný drop souboru i složky; obnova zálohy z pruhu dá tentýž projekt jako dnešní dialog (porovnání `validate()` a počtu klipů). |
| **Riziko** | Sandbox — drop dává URL s přístupem, ale bookmark se musí uložit stejně jako z `NSOpenPanel`. |

---

#### M13 · Fullscreen aplikace a fullscreen náhledu

| | |
|---|---|
| **Cíl** | `⌃⌘F` celá aplikace (toolbar 48 bez puntíků, přehrávač 372 → 426); fullscreen náhled se stavy `cisty / ovladani / osa`. |
| **Soubory** | nové `UI/Fullscreen/FullscreenApp.swift`, `FullscreenPreview.swift`, `MiniTimeline.swift`; `Media/PlayerView.swift` (`FullScreenSwitch` se zobecní) |
| **Práce** | **Aplikace**: týž rám, jen jiné výšky — osa, hlavičky i panel si drží souřadnice, aby se nic nekreslilo dvakrát. **Náhled**: obraz 16:9 na střed (pillarbox), overlay 150 ms `ease-out`, mizí po ~2 s nečinnosti (`NSTrackingArea` + `.mouseMoved` + časovač). Stav `ovladani`: horní a dolní gradient, timecode 22 mono, scrub lišta s výřezem a dobami, transport s kruhem 52. **Řečový titulek se v tomhle stavu zvedá** na 212 px (v čistém 108). Stav `osa`: mini osa 76 px + **plovoucí náhled snímku 192×108 nad kurzorem** (z `ThumbnailStore`, M5). `⎋` zavírá a ruší rozjeté tažení. |
| **Hotovo když** | Přechod okno ↔ fullscreen nezaseká přehrávání a hlava zůstane na svém místě. |
| **Ověření** | `--fullscreen` (regrese měření) + `--fullscreen-ui-check`: tři stavy screenshotem, přepnutí tam a zpět zachová `playhead` i `rate`; overlay po 2 s zmizí a pohybem myši se vrátí. |
| **Riziko** | Návrat z fullscreenu přestavuje hierarchii — vzorec „odstranit, ne skrýt" platí i tady. Závislost na M5 (plovoucí náhled snímku). |

---

## 6. Nové stavy UI a kam patří

Do `Project` (a tedy do projektového souboru) **nepatří nic z toho** — jsou to stavy sezení.

| Stav | Kde žije | Poznámka |
|---|---|---|
| `railSection` | `AppModel` | media / text / color / audio / speech / settings |
| `panelVisible`, `panelTab` | `AppModel` | `⌘4`; speed / color / audio / info |
| `timelineLayers` | `TimelineController` | osa si o ně říká při kreslení |
| `qualitySensitivity` | `TimelineController` + `UserDefaults` | přežívá restart, ne projekt |
| `libraryFilter`, `librarySearch` | `AppModel` | |
| `isFullscreen`, `fullscreenOverlay` | `AppModel` | clean / controls / timeline |
| `exportSheet` | `AppModel` | nastaveni / prubeh / hotovo + progress |
| `transcriptPanel` | `AppModel` | prubeh / editace + vybraný úsek |

---

## 7. Nové CLI kontroly

Projekt má pravidlo, že se čísla měří, ne odhadují. Každý modul přidá jednu:

`--shell-check` · `--status-check` · `--layers-check` · `--layout-check` · `--thumb-check` ·
`--overview-check` · `--panel-check` · `--library-check` · `--export-ui-check` ·
`--transcript-ui-check` · `--empty-start-check` · `--fullscreen-ui-check`

**Regresní sada, která musí projít po každém modulu etap A a B:**
`--timeline-bench`, `--benchmark`, `--export-check`, `--transition-check`, `--select-check`, `--range-check`.

---

## 8. Co plán vědomě NEDĚLÁ

- **Nemění model.** Jediná výjimka je `topInset` v `TimelineGeometry` (M4) — jedna vlastnost, výchozí 0,
  tři testy. Formát projektového souboru zůstává na verzi 2.
- **Nedělá tažení víc vybraných klipů naráz** ani kopírování přechodů — přiznané meze z F17 platí dál.
- **Nedělá ikony na míru.** SF Symbols (`film`, `textformat`, `paintpalette`, `waveform`, `text.bubble`,
  `gearshape` — ⚠️ ověřit názvy v aplikaci SF Symbols před prvním použitím), žádné bitmapy.
- **Nesahá na kompoziční vrstvu.** Vzhled presetů drží dál jen `ColorPresetFilter`, typografii titulků
  dvojice `TitleExportRenderer.font(for:)` + `TitleOverlay.font(for:)` — a ty se dál musí měnit SPOLU.

---

## 9. Souhrn

| Etapa | Moduly | Sessions | Přidává funkce? | Kdy |
|---|---|---|---|---|
| **A — rám a chrome** | M1–M3 | 3 | ne | **před svatbou** |
| **C — panely** | M7–M8 | 2 | ne | **před svatbou** |
| **B — osa** | M4–M6 | 3 | ano | po svatbě |
| **C — knihovna** | M9 | 1 | ano | po svatbě |
| **D — obrazovky** | M10–M13 | 4 | ano | po svatbě |
| | **13** | **13** | | |

**Doporučené pořadí: M1 → M2 → M3 → M7 → M8 → 🚧 KILL-GATE 1 → M4 → M5 → M6 → M9 → M10 → M11 → M12 → M13.**

Etapy A a C jsou pět sessions, po kterých je hotová celá potíž #2, #3 a #4 ze zadání a osa má
přepínače vrstev. Zbytek počká na to, co řekne svatba — a je dost pravděpodobné, že přeskládá
pořadí etapy D.
