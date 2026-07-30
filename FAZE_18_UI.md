# FÁZE 18 — přestavba UI podle `design_handoff_aiditor_ui`

*Sestaveno 29. 07. 2026. Zdroj zadání: `design_handoff_aiditor_ui/README.md` + šest prototypů v `designs/`.*

> ## ✅ HOTOVO 30. 07. 2026 — všech třináct modulů, každý za svou branou
>
> Fáze doběhla za dva dny. Žádný modul se neodložil, žádná brána nespadla natrvalo.
> **Co je pod tímhle rámečkem, je PLÁN, jak byl napsaný 29. 07.** — u každého modulu je
> pod tabulkou dopsané, jak to dopadlo a v čem se realita s plánem rozešla.
> Naměřená čísla, nálezy a přiznané meze jsou v `PROJECT_STATUS.md`.
>
> Co se z plánu vědomě NEUDĚLALO: přepínač „přehrávat jen výřez" ve fullscreen náhledu
> (změna v přehrávací cestě, ne v UI), popisek `sync −0,42 s` na klipu (model ten posun
> nedrží), viditelnost a zámek stopy v hlavičkách (model pro ně nemá stav).
> Odchylky od litery návrhu — kotvení miniatur ve zdrojovém čase, neztlumená ikona
> Nastavení na prázdném startu, širší timecode ve fullscreenu — jsou zdůvodněné u modulů 5, 12 a 13.

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

### 2.1 Kdy vůči KILL-GATE 1 — ✅ ROZHODNUTO 29. 07. 2026

`PROJECT_STATUS.md` říkalo: *„Do kill-gate se nepřidávají funkce."* Tenhle plán jich přidává devět
(knihovna, přetažení, přehled osy, dva fullscreeny, přepínače vrstev, citlivost, prázdný start,
plovoucí náhled snímku). Materiál na svatbu je ~konec srpna 2026.

**Rozhodnutí autora: jede se všech 13 modulů PŘED svatbou.** Svatba se bude stříhat už v novém UI
včetně knihovny a fullscreenů. Pravidlo „do kill-gate se nepřidávají funkce" je tím pro fázi 18
**výslovně zrušené** — nahrazuje ho pravidlo níž.

⚠️ **Co z toho plyne pro každý modul.** Do kill-gate půjde třináct sessions čerstvého kódu, který
nikdo neodzkoušel rukou na skutečné zakázce. Regresní sada (sekce 7) proto **není doporučení, ale
podmínka odevzdání každého modulu**, a moduly, které sahají na osu nebo na export, mají tvrdé brány
s čísly (R1, R2, R4). Kdyby se některý modul nepovedl uzavřít brankou, **odloží se za svatbu on sám**,
ne celá fáze — proto je pořadí sestavené tak, aby se dalo kdykoli useknout: ergonomické moduly jsou
napřed, kosmetické vzadu.

### 2.2 Světlý režim — ✅ ROZHODNUTO 29. 07. 2026: PADÁ

Návrh má **jen tmavou variantu**. Dnešní kód má obě větve:
`TimelineDocumentView.swift:33` a `RampEditorView.swift:30` volí přes
`appearance.bestMatch(from: [.aqua, .darkAqua])`.

**Rozhodnutí autora: okno bude natvrdo tmavé.** V M1 dostane `NSAppearance(named: .darkAqua)`
a světlá větev v `TimelineDocumentView` i `RampEditorView` se smaže. Střihové aplikace jsou tmavé
záměrně — světlé okolí posouvá vnímání jasu obrazu.

⚠️ Přepínač vzhledu tím **přestane fungovat**, i když ho systém nabídne. To je záměr, ne chyba —
`viewDidChangeEffectiveAppearance` v obou view se stane zbytečným a odstraní se s ním, aby po sobě
nenechal mrtvou cestu.

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

> ✅ **VYHODNOCENO 30. 07. 2026 (M5): brána drží, ale ne sama od sebe.** Kreslení pásu stojí
> **+0,10 až +0,13 ms** na tik (rozpočet 16,67) — to je zanedbatelné. Problém nebyl v kreslení, ale
> v **generování**: dekodéry na pozadí soutěží o výpočetní čas a scroll se studenou cache vypadl
> 2 tiky, přestože práce na tik byla 0,34 ms. Řešení je **odklad generování, dokud se osa hýbe**
> (`ThumbnailStore.deferGeneration`), nikoli žádný z ústupků, které plán připravoval.
> Ústupová cesta z plánu (hrubší dlaždice, výchozí vypnutí) se **nepoužila**.
>
> ⚠️ **A ještě jedna oprava:** vypadlé tiky nejsou na tomhle stroji deterministické. V témže sezení
> dal kód M4 dvakrát 2 výpadky, kód M5 sedmkrát 0–2. Kritérium se dá poctivě posuzovat jen
> **ABBA v jednom sezení** (tak se to v `--thumb-check` měří) a podle **práce na tik**, která je
> stabilní na 0,02 ms. Tvrzení M4 „kritérium platí, dřívější výpadky byly zátěž stroje" bylo správné
> v příčině, ale příliš silné v závěru.

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

## 4b. Hotové moduly

### ✅ M1 — nový rám okna (29. 07. 2026)

**Postaveno:** `UI/Shell/` — `AppShell` (toolbar → rail + obsah → stavový řádek), `AIditorToolbar`,
`IconRail`, `ViewerPane` (čipy, měřidlo, pilulka transportu), `ShellStatusBar`, `DesignTokens`,
`LegacySettingsPanel`. `ContentView` zhubl z 4483 na 4247 řádků a drží už jen `AppModel` a rozcestník
měřicích běhů.

**Fullscreen celé aplikace je hotový už teď.** Skořápka je postavená parametricky (`ShellMode`),
takže okno i celá obrazovka sdílejí jedno rozvržení a liší se jen třemi čísly (toolbar 46/48,
odsazení zleva 78/16, horní pás 372/426). M13 tím zbývá jen fullscreen **náhledu**.

**Ověřeno `--shell-check`** — geometrie měřená ze skutečných view v hierarchii (`TimelinePane`,
`PlayerHostView`), ne z konstant:

| | okno | celá obrazovka |
|---|---|---|
| osa zleva (rail) | **61** ✅ | **61** ✅ |
| osa shora (lišty) | **453** ✅ | **509** ✅ |
| osa zprava (panel) | **453** ✅ | **453** ✅ |
| osa zdola (stavový řádek) | **27** ✅ | **27** ✅ |
| obraz zleva / shora | **77 / 63** ✅ | **77 / 65** ✅ |

Plocha obrazu 1208×680 → **1400×788** ve fullscreenu (vzrostla, takže se přepnulo doopravdy —
bit `styleMask` se přepíná už na začátku přechodu a ptát se ho nestačí).

**⚠️ Dvě chyby, které chytilo až měření, ne oko:**
① `NSHostingView` je **flipped** — první verze kontroly měla odsazení shora a zdola prohozená,
a protože obě čísla vyšla „nějak rozumně", vypadalo to jako chyba v layoutu, ne v měření.
② SwiftUI si nad obsahem drží **bezpečnou zónu titulkového pruhu**: osa v okně začínala na 485
místo 453, ve fullscreenu (kde pruh není) správně na 509. Vyřešeno `.ignoresSafeArea()`
a `.windowStyle(.hiddenTitleBar)` — návrh chce puntíky uvnitř toolbaru.
③ Screenshot pak ukázal třetí: se samotným `.ignoresSafeArea()` zůstala horní třetina toolbaru
schovaná za pruhem (jméno projektu a horní půlky tlačítek nebyly vidět). Kontrola geometrie to
neviděla, protože měří vůči `contentView`, který sahá až k horní hraně okna. **Koukanec chytil,
co měření nemohlo.**

**Regrese beze změny:** `--timeline-bench` 2000 klipů, **0 vypadlých tiků**, medián práce 0,78 ms
(kritérium fáze 2 drží) · `--select-check` a `--range-check` prošly celé.

**Riziko R2 změřeno (`--shell-gpu`, dvě jízdy po čtyřech fázích):**

| pořadí | poz. 1 | poz. 2 | poz. 3 | poz. 4 |
|---|---|---|---|---|
| **ABBA** (A = s overlaji) | **34,31** fps, 371 mezer | 59,67 | 59,75 | **59,67**, 0 mezer |
| **BAAB** | 59,67 | 59,67 | 59,67 | 59,67 |

Ze sedmi ustálených měření se stav **s overlaji a bez nich neliší ani o setinu** (59,67 vs 59,67).
Ta jedna vybočená hodnota se **nezopakovala**: tentýž stav dal v pozici 4 první jízdy 59,67 fps
a nula dlouhých mezer.

⚠️ **Moje první vysvětlení bylo špatné a druhá jízda ho vyvrátilo.** Napsal jsem, že za to může
rozjezdová pozice 1 — v obráceném pořadí byla pozice 1 v pořádku. Byl to jednorázový výkyv, ne
vlastnost pozice ani overlajů. Pozice 1 se z průměru vyřazuje z opatrnosti, ne proto, že by se
prokázala jako vadná, a **vypisuje se**, aby to šlo přepočítat.

⚠️ **Co tím ale NENÍ zodpovězené.** Doručené snímky jsou zastropované 60Hz displejem, takže ukážou
až to, co se projeví trháním. **Vlastní otázka R2 — kolik GPU stojí trvale skládaný náhled — se
tímhle změřit nedá**; na to je `powermetrics` a ten potřebuje `sudo`. Kontrola proto tiskne značky
`FÁZE n/4 START/KONEC` s časy, aby šel log rozříznout. **Otevřená položka pro autora:** pustit
`sudo powermetrics --samplers gpu_power -i 1000 > ~/aiditor_shell_gpu.txt` vedle `--shell-gpu`
a doplnit číslo sem. Do té doby platí: overlaye **neprokazatelně nestojí plynulost**, o rezidenci
nevíme nic. Ústupová cesta (mizení overlajů po ~2 s nečinnosti) je popsaná v 2.3 a zůstává
připravená — `overlaysSuppressed` je už zapojené.

**Tmavý režim natvrdo:** okno dostává `.darkAqua`, z `TimelinePalette` a `RampEditorPalette` zmizelo
**22 světlých hodnot**. Obal `NSColor(name:dynamicProvider:)` zůstal — vrací pořád totéž, ale drží
jméno v debuggeru a jedno místo, kam by se světlá varianta vracela.

**Přiznaný dluh M1:** `viewDidChangeEffectiveAppearance` a `performAsCurrentDrawingAppearance`
zůstaly na místě, přestože jsou od zafixování tmavého režimu inertní. Odstraní je **M4**, který do
těch souborů stejně sahá kvůli výškám stop — vytrhávat je teď by znamenalo velký diff v modulu,
který o kreslení osy není. Editor rychlostní křivky sedí v panelu 452 px, ale jeho vnitřní layout je
pořád ten z pásu 132 px a nahoře se zařezává; přestaví ho **M7**.

### ✅ M2 — stavový řádek a čip běžících analýz (29. 07. 2026)

**Postaveno:** `UI/Shell/AnalysisProgress.swift` (stav + `AnalysisChip`), přepsaný `StatusBar.swift`
se třemi tečkami (kvalita · proxy · model přepisu), čip zapojený do toolbaru.

**Proč postup nežije ve storech.** `SharpnessStore` a `EmptinessStore` jsou actory nad JEDNÍM
souborem — o tom, že se zpracovává třetí asset z pěti, nevědí a vědět nemají. „3/5" je stav
**smyčky**, kterou drží `AppModel`, takže postup patří vedle ní. Do storů by se musel protlačit
shora, aby ho mohly hlásit zpátky dolů.

**⚠️ `defer`, ne zavolání na konci těla.** Kdyby smyčka spadla nebo se úloha zrušila, čip by zůstal
viset a tvrdil, že se pracuje. Přesně na to se ptá část C kontroly.

**Ověřeno `--status-check`:** 5 assetů, obě dimenze **5/5**, **10 startů = 10 dokončení**, po
doběhnutí `running == nil`, `chipText == nil`, jméno souboru uklizené, poslední přechod smyčky
„finish". **Ověřeno screenshotem:** čip „Analyzuju hluchá místa · 3/5" v toolbaru a oranžová tečka
„Hluchá místa 3/5" ve stavovém řádku.

**⚠️ Kontrola „čip byl vidět" musela přestat být vzorkovací.** První verze vzorkovala `chipText`
po 20 ms a hlásila chybu podle toho, jestli byla disková cache studená — se studenou prošla,
s teplou spadla, protože krok smyčky trval kratší dobu než perioda vzorkování. Kritériem je teď
**vlastnost stavu** (čip je vidět právě tehdy, když něco běží), vzorkované pozorování zůstalo jako
informační řádek. Ověřeno v obou režimech cache.

**Regrese:** `--timeline-bench` **0 vypadlých tiků**, `--shell-check` beze změny.

**Přiznaná mez M2:** tečka proxy se ukáže, až proxy existují; u projektu bez nich je levá strana
řádku prázdná. Je to záměr — tečka „Proxy 0/0" by uživatele naučila řádek nečíst.

### ✅ M3 — lišta osy: vrstvy, citlivost, přichytávání, výřez, zoom (29. 07. 2026)

**Postaveno:** `UI/Shell/TimelineLayerBar.swift` (pás 32 px), `TimelineLayers` a `qualitySensitivity`
na `TimelineControlleru`, early-outy v `rebuildClipInfo` / `applyWaveform` / `drawBeatMarks`,
`TimelinePane.zoomToFit()`, globální přepínač přichytávání, `⇧Z` na `keyDown` osy.

**Vypnutá vrstva se NEPOČÍTÁ, ne jen neukazuje.** Kdyby se jen skryla, přepínač by nic neušetřil —
a byl by to podvod na uživateli, který ho zmáčkl právě proto, že mu to jelo pomalu.

**Přichytávání dostalo globální přepínač.** Dosud existovala jen shiftová cesta, takže kdo chtěl
hodinu stříhat bez magnetu, musel hodinu držet shift. `snapping(for:)` je jedno místo, kde se obě
cesty slévají: přepínač na sezení, shift na jedno tažení.

**`⇧Z` visí na `keyDown` osy, ne na SwiftUI `keyboardShortcut`** — „Z" je při psaní titulku pořád jen
písmeno (vzorec JKL z F17).

**Miniatury: přepínač existuje, vrstva ne.** Je vypnutý a nese důvod v tooltipu. Existuje dřív než
miniatury schválně — je to **pojistka pro M5**, a pojistka nemá vznikat ve chvíli, kdy je zle.

**Ověřeno `--layers-check`:**
- ✅ vypnutá vrstva nenechá **ani jednu** dlaždici vlny a **ani jeden** proužek kvality (měřeno
  přes `drawnLayerCounts` na skutečných nasazených vrstvách, ne na příznaku);
- ✅ citlivost 0,2 / 0,5 / 0,8 → **0 / 289 / 289** značek, monotónně, **a vzorky zůstaly nedotčené**
  (posuvník přepočítává klasifikaci, analýzu nespouští).

**⚠️ Měření ceny odhalilo anomálii, a ta zůstává otevřená.** 2000 klipů, zoom 5, rozptyl uvnitř
konfigurace 0,00–0,01 ms (tedy deterministicky):

| konfigurace | medián práce na tik |
|---|---|
| všechny vrstvy zapnuté | 0,29 ms |
| jen vlny vypnuté | **0,26 ms** ✓ ušetří |
| jen značky vypnuté | **0,28 ms** ✓ ušetří |
| vlny + značky vypnuté | **0,25 ms** ✓ ušetří nejvíc |
| **jen doby vypnuté** | **0,70 ms** ⚠️ dvojnásobek |
| všechny vypnuté | 0,60 ms ⚠️ tažené příznakem dob |

Vlny a značky se chovají přesně podle záměru. Anomálie je **izolovaná na jediný příznak `beats`** —
a je tím divnější, že `drawBeatMarks` se s vypnutým příznakem vrací dřív, než vůbec zavolá
`beatMarks()`, a měřený projekt žádnou mřížku dob nemá, takže by obě větve měly stát nula.
Příčinu se vyčíst nepodařilo.

Prakticky to nevadí (0,70 ms proti rozpočtu 16,67 ms na tik; `--timeline-bench` dál hlásí **0
vypadlých tiků**), ale **v M5 to musí být vysvětlené** — tam se přepínač miniatur stane pojistkou,
na které záleží, a pojistka, která zdražuje, je horší než žádná.

⚠️ Kritérium plánu *„scroll je měřitelně levnější"* je tím **splněné jen zčásti**: levnější je
u vln a značek, u dob ne. Nepředstírám opak.

**Regrese:** `--timeline-bench` 0 vypadlých tiků, `--shell-check` i `--status-check` beze změny.

**Přiznaná mez M3:** citlivost 0,5 a 0,8 dávají na syntetických vzorcích týž počet značek — propad
je v nich skok (40 ze 100), takže oba prahy padnou nad něj. Na reálném materiálu se to liší; test
proto vymáhá jen monotonii a rozdíl krajních hodnot, ne rozdíl každého kroku.

### ✅ M7 — připnutý panel 452 + záložka Rychlost (29. 07. 2026)

**Postaveno:** `UI/Panels/PinnedPanel.swift` (hlavička s jménem klipu a metou, záložky, tělo se
scrollem), `UI/Panels/SpeedTab.swift`, `TimelineController.setClassicRamp(_:slowSpeed:)`,
`RampEditorView.nodePoints`. **Potíž #2 zadání je tím zavřená** — křivka má box 150 px v panelu
širokém 452 místo 132 bodů výšky dělených s panelem barev.

**Záložky jsou zatím dvě: Rychlost a Barva.** `Zvuk` a `Info` doplní M8 a do té doby se
**neukazují** — prázdná záložka je horší než chybějící.

**Korekce výšky je zapojená naostro**, ne jako ozdoba: mění náhled (nový `AVPlayerItem`) i export.
⚠️ **Je to nastavení PROJEKTU, ne klipu, a jinak to nejde** — `audioTimePitchAlgorithm` je vlastnost
`AVPlayerItem`u a výstupu čtečky, ne stopy ani segmentu. Přiznaná mez v1: drží se v `UserDefaults`,
ne v projektovém souboru.

**Tabulka důvodů „proč dopasování nejde" je teď jedna** (`TimelineError.beatFitReason`) pro kontextové
menu i pro panel. Dvě kopie téhož textu by se rozešly, jakmile v modelu přibude případ.

**⚠️ Tolerance 2 % u presetů — rozhodnutí, ne opomenutí.** Testovací klipy mají naměřeno **59,68 fps**,
takže `pureSlowdownLimit` vyjde **0,5027** a preset „0,5×" by byl trvale nedostupný kvůli propadu
0,54 % (asi jeden duplikovaný snímek z dvou set). Na 60fps materiálu — a ten je podle měření
většinový — by z celé řady presetů byla ozdoba. **Žlutá zóna v editoru zůstává přesná**; tolerance
platí jen pro presety.

**Ověřeno `--panel-check`** (syntetické události na skutečném editoru v okně):
- ✅ preset 0,5× dal rampu s nejnižší rychlostí 0,500× a spotřeba **33,700 s se vejde do zdroje
  44,938 s** (kotvení přes `(1+slow)/2` drží);
- ✅ „Bez rampy" rampu zruší, jeden preset = **jeden undo krok**;
- ✅ box má **150 bodů** výšky a **428** šířky (proti dosavadním 132 na výšku);
- ✅ dvojklik přidal uzel (3 → 4), tažení změnilo křivku (0,51 → 0,21), **⌘Z vrátil celé**,
  Escape rozjeté tažení zrušil a křivka zůstala;
- ✅ `⌘4` skryje panel a osa se rozšíří **z 666 na 1119 bodů**, tedy právě o 453 (panel + předěl).

**⚠️ Dvě chyby byly v mém MĚŘENÍ, ne v kódu** — a obě by test „prošly":
① tažení jsem porovnával přes `min()` rychlostí, ale přidaný uzel leží v nejnižším bodě křivky,
takže po posunutí nahoru zůstalo minimum stejné a test by prošel i u tažení, které nic neudělá;
② táhl jsem ze STŘEDU plochy, kde žádný uzel není — uzel leží tam, kam ho posadí mapování rychlosti
na `y`. Kvůli ② dostal editor měřicí okno `nodePoints`, takže se pozice **čte, nehádá**.

**Screenshot chytil, co měření nemohlo:** preset, který je zároveň aktivní i pod mezí, byl vykreslený
jako vybraný a současně zašedlý — vypadalo to jako chyba kreslení. Aktivní preset se teď nevypíná;
šedivět stav, který právě platí, uživatele mate. Vypnutá je jen volba, kterou by teprve zvolil.

**Regrese:** `--export-check` **4739 snímků** (číslo po číslu jako baseline — sáhl jsem do exportu
kvůli korekci výšky), `--timeline-bench` 0 vypadlých tiků, `--shell-check` i `--status-check` beze změny.

**Přiznaná nesrovnalost k rozhodnutí:** kontextové menu „Zpomalit 0,25×" (`toggleClassicRamp`) mez
čistého zpomalení **nekontroluje**, zatímco preset v panelu ji ctí. Na 60fps materiálu tedy jde přes
menu nastavit rampu, kterou panel odmítne nabídnout. Není to nové — `toggleClassicRamp` se tak chová
od F14 — ale teď je to vedle sebe vidět. Sjednotit to je věc rozhodnutí, ne úklidu, a M7 do něj nesahá.

### ✅ M8 — záložky Barva, Zvuk a Info (29. 07. 2026) · ETAPA C HOTOVÁ

**Postaveno:** `UI/Panels/ColorTab.swift`, `AudioTab.swift`, `InfoTab.swift`. Panel má všechny čtyři
záložky ze zadání.

**Barva:** náhled před/po **ze skutečného snímku klipu** (ne gradient) a vzorky u všech pěti presetů
renderované **týmž `ColorPresetFilter`em jako export**. Namíchaný barevný čtvereček by se s presetem
rozešel, jakmile by někdo sáhl do filtru — a nikdo by nepoznal, které z těch dvou lže. Zdrojový
snímek se drží dekódovaný, takže tažení posuvníku síly je jen render CoreImage, ne nové čtení souboru.

**Zvuk:** fade posuvníky s hodnotou **ve snímcích i v sekundách** — dosud se fade daly nastavit
**jen tažením úchytu na klipu** (F16) a kdo chtěl přesnou délku, neměl kde ji napsat. Délky se čtou
přes `effectiveAudioFades`, ne z `clip.audioFades`: trim smí klip zkrátit pod součet fade a model to
schválně nezařezává, takže panel musí ukazovat totéž, co je slyšet. Dál mute a hlasitost stopy
(s poznámkou, že posuvník **jen ztišuje** — rozsah `AVAudioMix.volume` je dokumentovaně 0–1)
a hlasitost dodávky z posledního exportu.

**Info:** zdroj, naměřené časování a verdikt VFR, mez čistého zpomalení, čas natočení **s přiznaným
zdrojem** (datum souboru oranžově a s vysvětlením), proxy s poznámkou, že export jde vždy z originálů.

**Ověřeno `--panel-check`, část D** (kritérium modulu):
- ✅ preset na **5 klipech = jeden krok ⌘Z** (regrese na F17/M2);
- ✅ fade z panelu se rozdá třem **různě dlouhým** klipům se zaříznutím per klip:
  **90 → 30/30, 40 → 10/30, 16 → 0/16**. Na tom se pozná, že se zařezává podle každého klipu,
  ne jednou hodnotou pro všechny.

**Screenshot chytil dvě věci, které měření nevidělo:** ① mez čistého zpomalení se v Info vypisovala
jako **„0,502667×"** — `%g` je pro UI špatný formát, `speedLabel` teď dává nejvýš tři desetinná místa
bez koncových nul; ② koukanec nešlo nasměrovat na konkrétní záložku, takže se fotila ta, na které
cyklus náhodou byl — `--shell-demo barva` teď na záložce zaparkuje.

**⚠️ `--timeline-bench` na tomhle stroji NEPROŠEL — a není to M8.** Hlásí 2–5 vypadlých tiků při
nejdelší mezeře 33,3 ms (jeden přeskočený tik), ale **práce na tik je jen 0,59 ms** proti rozpočtu
16,67 ms, takže hlavní vlákno zaneprázdněné nebylo. A/B na tomtéž stavu stroje:

| stav | vypadlé tiky (3 běhy) | medián práce |
|---|---|---|
| bez M8 (`git stash`) | 3 / 4 / 2 | 0,59 ms |
| s M8 | 3 / 3 / 2 | 0,59 ms |

Load average 1,9–2,1 — stroj má zátěž po desítkách buildů a spuštění appky v téhle session.
**Kritérium fáze 2 se tedy musí přeměřit na klidném stroji**; do té doby ho neprohlašuju za splněné
ani za rozbité. Je to zapsané jako otevřená položka, ne odmávnuté.

**Přiznané chování k rozhodnutí:** šestnáctisnímkový klip dostal při žádaných 30+30 fade **0/16** —
celý klip je dojezd a nájezd zmizel. Vychází to z `setAudioFadesOnSelection` (F17), který srazí
nájezd na `délka − dojezd`. Rozdělit zbytek napůl by bylo asi milejší, ale je to změna chování
hromadné operace, ne úklid.

### ✅ M11 — panel přepisu řeči (30. 07. 2026)

**Postaveno:** `UI/Transcript/TranscriptPanel.swift` a `SpeechSourcesPane.swift` (nové), průběžné
úseky v `Media/TranscriptionService.swift`, zvýraznění rozsahu na ose v `TimelineDocumentView`,
kontrola `Measure/TranscriptUIChecks.swift` (`--transcript-ui-check`, **21 ověření, 0 neshod**).
**Model: `splitTranscriptSegment(atCharacter:)` a `speechCueRanges` — +4 testy, celkem 463.**

**Riziko modulu (průběžné doručování) je vyřešené API, ne obcházením** — WhisperKit má
`segmentDiscoveryCallback`. Pravidlo 6: ověřeno ve zdrojácích balíčku, ne odhadem, a našly se
u toho **dvě pasti**:
① parametr `segmentCallback:` se při VAD chunkingu **nepoužije** — batchovaná cesta si staví closure
nad INSTANČNÍ vlastností `segmentDiscoveryCallback`, takže kdo předá jen parametr, nedostane nic;
② v té closure se posouvá jen pole `seek` (o offset kusu ve vzorcích), **ne `start`/`end`** — časy
v průběžném callbacku jsou tedy relativní ke kusu. Proto je průběžný seznam **NÁHLED** a uložené
úseky přijdou z návratové hodnoty, jako dosud. Procenta se počítají ze `seek`, který absolutní JE.

**Ověřeno naostro** (`--transcribe-check` na reálném klipu): **11 úseků průběžně, 11 ve výsledku**;
kontrola to hlídá zvlášť od výsledku, protože kdyby callback přestal chodit, výsledek dorazí stejně
a nikdo si toho nevšimne.

| ověření | naměřeno |
|---|---|
| oprava textu úseku | nový text na **obou** klipech zdroje i v `.srt`, **jeden** undo krok |
| rozdělit v kurzoru | „před" 4,00–4,43 s + „tímto shromážděním" 4,43–6,00 s, součet délek zachovaný |
| prázdný text | úsek smazán, `.srt` o něm neví, výběr zanikl |
| zvýraznění na ose | 30–90 a 630–690, tedy **dvakrát** (zdroj je na ose dvakrát) |

**Přiznaná heuristika:** čas řezu při „Rozdělit v kurzoru" se dělí **poměrem znaků**. Naše cesta
WhisperKitu vrací časy na úsek, ne na slovo — a vymýšlet „přesný" čas z ničeho by bylo horší než
přiznaný odhad, který si uživatel může doupravit.

**⚠️ Snímek panelu chytil past, na kterou tenhle projekt už jednou narazil, a její horší polovinu.**
`TranscriptPanel` pozoroval jen `AppModel`, ale `TimelineController` je **vnořený**
`ObservableObject` — změnu `selectedSpeech` panel neviděl, takže se vybraný úsek nepřekreslil na
kartu. Horší bylo, co se skrývalo za tím: pole s textem zůstalo **prázdné**, a protože prázdný text
úsek MAŽE, ⏎ by ho zahodilo. Text se teď plní z jednoho místa (`syncDraft`) při každé změně výběru
a `commit` má proti smazání nedopatřením pojistku (`loadedSelection`).
**Kontrola tuhle chybu chytit nemohla** — sama nastavovala výběr přímo, což je právě ta cesta, která
byla rozbitá. Obsah pole se dá ověřit jen okem, a proto se snímek dělá.

**Regrese:** `--transcribe-check` naostro (11 úseků), `--select-check` 15 ✅, `--range-check` 9 ✅,
`--library-check` 26 ✅, `--export-ui-check` ✅, `--shell-check` ✅, `--timeline-bench` medián 1,96 ms.

*Koukanec rukou (v seznamu): přepis naostro s panelem otevřeným (úseky přitékají), oprava textu
a ⏎, rozdělení v kurzoru, klik do pásku řeči na ose a hned ⏎.*

---

### ✅ M10 — list exportu (30. 07. 2026) · začátek etapy D

**Postaveno:** `UI/Export/ExportSheet.swift` (nový, list 660 bodů nad ztmaveným oknem),
stav a volby v `AppModel`, `Measure/ExportUIChecks.swift` (`--export-ui-check`, **20 ověření,
0 neshod**). Toolbar otevírá list místo save panelu. **Model dostal `duplicatedFrameShare(of:)`
(+3 testy, celkem 459).**

**⚠️ List nezakládá druhou exportní cestu.** Tlačítko volá tutéž `AppModel.export(to:)`, kterou
používají všechny CLI kontroly; volby listu (rozsah, vypalování titulků, `.srt`) se do ní propisují.
Kdyby si list exportoval po svém, „co dostane uživatel" a „co měří `--export-check`" by se rozešlo
a nikdo by si toho nevšiml.

**Varovný blok o duplikaci počítá z MATERIÁLU** (pojmenované riziko modulu): podíl duplikovaných
snímků je nová funkce modelu, ne konstanta v UI. Vzorec je pravidlo projektu — průměr
z `max(0, 1 − v(t)/limit)`. Ověřeno v obou směrech: **30fps zdroj s rampou 0,25× → 37,5 %**
(číslo z CLAUDE.md, naměřené na reálných klipech), **120fps zdroj tentýž ramp utáhne → varování
zmizí**.

| ověření | naměřeno |
|---|---|
| celý projekt: slíbeno v listu vs. zapsáno | **90 = 90** |
| výřez I—O: slíbeno vs. zapsáno vs. **v souboru** | **30 = 30 = 30** |
| stav „hotovo" | kontrolní řádky z výsledku, ne z přání |
| `--export-check` (regrese) | **4739 snímků**, MediaProbe: VFR 0 z 1, zahozených 0 |

**⚠️ NÁLEZ V MĚŘENÍ: počítat snímky v souboru přes buffery PŘECEŇUJE.**
`AVAssetReaderTrackOutput` vydá i buffery **bez dat** — naměřeno na obou exportech
**94 bufferů / 90 vzorků** a **34 / 30**, tedy pokaždé čtyři navíc. První verze kontroly hlásila
34 proti 30 a vypadalo to na chybu v exportu; délka souboru (1,000 s a 3,000 s) přitom vycházela
přesně. Počítat se musí `CMSampleBufferGetNumSamples`.

**⚠️ Kontroly si teď dělají snímek okna SAMY** (`NSView.cacheDisplay(in:to:)` do PNG v kontejneru).
`screencapture` fotil **Finder**, který nad oknem nechaly předchozí kontroly
(`activateFileViewerSelecting`), a `NSApp.activate(ignoringOtherApps:)` ho nepřebil. Snímek
z hierarchie se na z-order neptá — a je použitelný pro každý další modul.

**⚠️ Snímek listu chytil tři věci** (popáté v řadě): ① vybraná mohla být **zakázaná** karta „Jen
výřez I—O" (stane se, jakmile se výřez zruší) — zavedena efektivní volba `exportsRangeEffectively`;
čísla přitom celou dobu vycházela, protože `exportRange` je bez in/out bodů celý projekt;
② `ScrollView` si vzal celou nabídnutou výšku a třetina listu zůstala prázdná — obsah je ohraničený,
takže scroll view zmizel; ③ hláška o hlasitosti měla **tečku a ASCII pomlčku** („−35.4 LUFS")
místo české čárky a typografického minusu.

**Přiznaná mez:** odhad času se ukazuje **až po prvním exportu**, ze skutečně naměřené rychlosti.
Vymyšlené „~1 min" v listu, který má být kontrolní, je horší než přiznané „ukáže se po prvním
exportu".

**Regrese:** `--export-check` 4739 snímků, `--transition-check` číslo po čísle jako ve fázi 10
(79/0; 0,7/12,9/13,1), `--range-check` 9 ✅.

*Koukanec rukou (v seznamu): tři stavy listu na reálném projektu, varovný blok na 30fps klipu
s rampou, „Zobrazit klip na ose", export výřezu z listu.*

---

### ✅ M9 — knihovna médií a přetažení (30. 07. 2026) · ETAPA C HOTOVÁ

**Postaveno:** `UI/Library/LibraryPane.swift` a `LibraryCard.swift` (nové), cíl přetažení
v `Timeline/TimelineDocumentView.swift`, zapojení v `AppShell`. Kontrola
`Measure/LibraryChecks.swift` (`--library-check`, **23 ověření, 0 neshod**).
**Zavírá potíž #6 ze zadání** — dosud šel materiál vidět jen jako klipy na ose.

**Pravidlo 6 odškrtnuté před psaním kódu:** `registerForDraggedTypes(_:)`, override metod
`NSDraggingDestination` (`draggingEntered/Updated/Exited/Ended`, `performDragOperation`)
i SwiftUI `.onDrag { NSItemProvider(object: NSString) }` **existují a přeloží se** s deployment
targetem macOS 14 (typecheck proti `MacOSX26.5.sdk`). ⚠️ `namesOfPromisedFilesDropped` vyžaduje
`override` — je na `NSObject`, ne jen v protokolu.

**Karta 94 bodů** (náhled 62 + popis 32, pevná výška — past pojmenovaná v zadání): náhled
z `ThumbnailStore` s hranou **104** (vlastní kapsa mezipaměti, takže si knihovna a osa navzájem
nezahazují dlaždice; poster je DRUHÁ dlaždice ≈ 3,5 s, protože první snímek souboru bývá rozjezd
kamery), badge délky vpravo nahoře, `120p` a `VFR` vlevo dole, ryska měkké ostrosti vpravo dole,
datum ze souboru **oranžově**. Dvojklik ukáže materiál na ose (vybere první klip a přesune hlavu).

**Přetažení:** `AssetID.rawValue` na pasteboardu → osa si asset najde v projektu. Video se zvukem
se pokládá jako **svázaná dvojice** (jako při importu), fotka a hudba na své druhy stop, jinam se
drop odmítne. Náhled vložení používá **tytéž duchy** jako tažení klipu — jedno místo, kde se maže.

**⚠️ O odmítnutí rozhoduje ZKUŠEBNÍ BĚH operace na kopii projektu, ne vlastní tabulka pravidel**
(vzorec z F14: „o zapnutí položky menu rozhoduje zkušební běh"). Vložení je **jeden undo krok**
i u dvojice a odmítnutý drop nezmění v projektu nic.

| ověření | naměřeno |
|---|---|
| filtry Vše / Video / Fotky / Hudba | 7 / 5 / 1 / 1, nepřekrývají se a pokrývají všechno |
| drop na V1 | klip přistál na snímku **120** = přesně tam, kde byl náhled |
| svázaná dvojice | společný `LinkID`, **⌘Z vzal obojí jedním krokem** |
| odmítnutí (hudba na V1, video na A2, obsazené místo) | operace `[]`, náhled **červený**, projekt beze změny |
| fotka na V1 | projde (je to obrazový klip) |

**⚠️ Kontrola odhalila skutečnou chybu v kódu dropu.** První verze měla podmínku „projekt po
vložení musí být **bez** porušených invariantů". `validate()` ale hlídá i věci, které s dropem
nesouvisí — a když do projektu přišel asset bez naměřené frekvence, **zamknul se tím celý drop**,
bez vysvětlení proč. Porovnává se teď **počet** porušení před a po. (Ten neplatný asset si vyrobila
sama kontrola; chyba, kterou tím našla, byla naše.)

**⚠️ Screenshot chytil tři věci** (počtvrté v řadě): ① **badge se nekreslily vůbec** —
`Image.resizable().aspectRatio(.fill)` nahlásí větší velikost, než jaká mu byla nabídnutá, takže se
`ZStack` rozvrhl podle obrázku a `clipped()` odřízl i popisky; přesunuté do `overlay` ZA rámcem;
② naměřená frekvence („59,68 fps") vytlačovala z karty čas natočení — v kartě je teď `60p` a přesné
číslo v tooltipu, protože o nekonstantním časování mluví badge `VFR`; ③ slow-mo klip ukazoval `VFR`
**místo** `120p`, přestože důležitější je to druhé — teď se kreslí obojí.

**Regrese:** `--shell-check` dostal novou hlídanou hodnotu **obraz zprava 347** (knihovna 330 +
předěl + odsazení) a prošel v okně i na celé obrazovce; plocha obrazu zůstala **1208×680**, protože
náhled je omezený VÝŠKOU horního pásu, ne šířkou. `--timeline-bench` 0 vypadlých tiků,
`--overview-check`, `--select-check` (15) a `--range-check` (9) beze změny.

*Koukanec rukou (v seznamu): přetažení karty na V1, A2 a na obsazené místo, filtry, dvojklik na
kartu, patička s proxy.*

---

### ✅ M6 — přehled celé osy (30. 07. 2026) · etapa B hotová

**Postaveno:** `Timeline/TimelineOverviewView.swift` (nový) — pás 46 bodů pod stopami: popisek
„přehled", pás 26 bodů se slitými bloky klipů (obraz 9 nahoře, zvuk 8 pod ním), červená hlava,
rámeček viditelného výřezu a celková délka mono vpravo. Zapojení v `TimelinePane`.
Kontrola `Measure/OverviewChecks.swift` (`--overview-check`, **16 ověření, 0 neshod**).

**Vlastní mapování, ne `TimelineGeometry`** — geometrie je o zoomu, přehled ukazuje vždy celou osu
na své šířce. **Bloky se slévají:** sousedící klipy s mezerou pod bod jsou jeden blok, takže hodinová
osa s 2320 klipy má **2 bloky** místo 2320 vrstev; přehled říká „tady je materiál a tady díra".
Přestavba jen při změně otisku (délka, počet klipů, šířka) — **tři změny zoomu nepřestavěly nic**.

**Souboj s auto-scrollem (riziko modulu) je ošetřený a změřený ve třech krocích:** ① během tažení
rámečku se osa za hlavou netahá (hlava skočila do poloviny hodinové osy, scroll se nepohnul);
② po puštění platí pravidlo ručního scrollu — osa nechá být, dokud hlava sama nevjede do výřezu;
③ **klik do přehledu je výslovná navigace a odstavení ruší**, takže se osa za hlavou posune.

| ověření | naměřeno |
|---|---|
| klik na 0 / 25 / 75 / 100 % hodinové osy | hlava přesně na 0 / 26 970 / 80 910 / 107 880 (odchylka 0) |
| tažení rámečku na 50 % a 20 % | výřez začíná přesně na 53 940 a 21 576 snímku |
| cena aktualizace výřezu za tik (2000 klipů) | **0,001–0,002 ms** |

**⚠️ Plánovaná tolerance „1 snímek" je z konstrukce nedosažitelná** a kontrola to říká nahlas:
přehled mapuje hodinu (107 880 snímků) na 498 bodů, takže **jeden bod pásu = 218 snímků**.
Kritérium je proto „do jednoho bodu pásu" a to číslo se vypisuje.

**⚠️ NÁLEZ: `Project.duration` je O(klipů) a alokuje přitom dvě pole** (`flatMap` + `map`
v `Queries.swift`) — na 2000 klipech **~1,5 ms**. První verze modulu ji čtla při každém zápisu
rámečku výřezu, tedy při každém tiku scrollu, a medián práce na tik vyskočil **z 0,95 na 2,45 ms**
(A/B proti HEAD, třikrát každá varianta, rozptyl 0,02). Uložením do `cachedTotalFrames` se to
vrátilo na 0,96. **Táž past byla i v pravítku:** `drawExportRange` volal `hasExportRange`
a `exportRange`, tedy `duration` dvakrát za každé kreslení, jen aby zjistil, že výřez není
nastavený — kreslení pravítka spadlo z **0,88 na 0,08 ms**.

**⚠️ A ještě jednou ta obrácená závislost, tentokrát izolovaná na JEDEN ŘÁDEK.** Po opravě pravítka
`--timeline-bench` hlásí medián **1,95 ms** místo 0,97 — s méně prací. A/B na tom jediném řádku
(třikrát každá varianta, rozptyl 0,02 ms) to potvrzuje opakovaně. Vysvětlení je totéž jako
u anomálie `beats` z M3: ten údaj měří dobu `scroll(to:)` na hlavním vlákně, a **když vlákno mezi
tiky nemá co dělat, platí se za probuzení** (rampa frekvence, studená cache). Součet práce na snímek
se nezměnil (~2 ms z 16,67), vypadlé tiky zůstávají 0–1. **Kdo bude příště srovnávat s 0,95 ms,
musí vědět, že se srovnává s číslem, které bylo dražší.**

**Přiznaný důsledek podle předpovědi M4:** pás ukrajuje 46 bodů, takže se stopy (344) do okna
z návrhu už nevejdou a svisle se scrolluje. Vlastnost návrhu, ne chyba.

**⚠️ Vedlejší nález o ⇧Z:** `TimelineGeometry.minPointsPerFrame` je 0,02, takže do výřezu 562 bodů
se vejde nejvýš ~27 700 snímků, tedy **~15 minut**. Na hodinové ose fit dojede na podlahu a rámeček
výřezu správně zůstává — a je to přesně ten případ, pro který přehled vznikl. Snižovat podlahu
zoomu není v zájmu hit testingu (jeden bod by byl přes dvě sekundy); přehled tu roli přebírá.

**Regrese:** `--select-check` 15 ✅, `--range-check` 9 ✅ (včetně pruhu výřezu v pravítku, kterého
se oprava dotkla), `--shell-check` všech 16 hodnot, `--thumb-check` beze změny, `--timeline-bench`
0–1 vypadlých tiků.

*Koukanec rukou (v seznamu): tažení rámečku po dlouhé ose, klik do přehledu při přehrávání,
chování po ručním odscrollování.*

---

### ✅ M5 — miniatury na klipech, křivka rampy, popisky (30. 07. 2026) · brána R1 drží

**Postaveno:** `Timeline/ThumbnailStore.swift` (nový) a v `ClipLayer` pás miniatur, křivka rychlosti
a dva popisky. Přepínač `Miniatury` v liště osy je od teď zapojený naostro — pojistka z M3 se stala
funkcí. Kontrola `Measure/ThumbChecks.swift` (`--thumb-check`, **22 ověření, 0 neshod**).

**Pravidlo 6 odškrtnuté před psaním kódu:** `AVAssetImageGenerator.images(for:)` v SDK **existuje**
a přeloží se i s deployment targetem macOS 14 bez gatování; vrací `AsyncSequence` s případy
`.success(requestedTime:image:actualTime:)` a `.failure(requestedTime:error:)`. Ověřeno typecheckem
proti `MacOSX26.5.sdk`, ne odhadem.

**⚠️ Dlaždice jsou kotvené ve ZDROJOVÉM čase, ne v klipu — vědomá odchylka od litery návrhu.**
Návrh dělí pás na 2–4 rovnoměrné dlaždice přes šířku klipu. Vypadá to stejně, ale znamenalo by to, že
po každém trimu a slipu se změní čas *všech* dlaždic klipu a celá sada se zahodí — a to při tažení
úchytu šedesátkrát za sekundu. Kotvení ve zdroji (týž důvod, proč jsou ve zdroji kotvené uzly
rychlostní křivky) drží miniatury na místě; cenou je, že se dlaždice na hranách klipu **zařezávají**,
jak to dělá Premiere i Final Cut. Hustota je z návrhu: **jedna dlaždice na 96 bodů**, což na jeho
čtyřech ukázkových šířkách (150 / 172 / 250 / 130) dá **2 / 2 / 3 / 1** dlaždici, tedy přesně to,
co je na screenshotu.

**⚠️ Odklad generování, dokud se osa hýbe — bez něj BRÁNA R1 NEDRŽÍ.** Změřeno oběma směry
(`deferralEnabled` se dá vypnout, aby cesta bez odkladu netiše nehnila — vzorec
`forcesSteppingFallback` z `--jkl-check`):

| studená cache, 2000 klipů, zoom 5 | práce na tik | vypadlé tiky | vygenerováno za jízdy |
|---|---|---|---|
| odklad **vypnutý** | 0,34 ms | **2** | 199 dlaždic |
| odklad **zapnutý** | 0,48 ms | **0** | 0 dlaždic |

Nešlo o práci na hlavním vlákně (0,34 ms z rozpočtu 16,67), ale o **dekodéry na pozadí, které
soutěží o výpočetní čas**. S odkladem se za jízdy negeneruje nic a pás se doplní, jakmile osa stojí
(naměřeno 4,6 s na plný výřez ze 4K HEVC originálů). Takhle se chová každý NLE a je to i správná
odpověď na to, co uživatel při scrollování dělá: hledá místo, nekouká na miniatury.

**Cena pásu, ABBA (teplá cache):** při zoomu, ve kterém se stříhá, **+0,13 ms** (0,44 proti 0,31);
při zoomu formální brány **+0,10 ms** (1,00 proti 0,90). Rozpočet je 16,67 ms na tik.

**⚠️ Dva zásahy do výkonu, které se našly měřením a mají obecnou platnost:**
① `NSColor.cgColor` u dynamické barvy vyhodnocuje poskytovatele — první verze si v *early-out*
cestách brala barvy před guardem a stálo to ~0,3 ms na tik (opraveno: `hide()` / `hideRampCurve()`
o barvu nežádají); ② `CALayer.isHidden` a předávání `ClipDrawInfo` hodnotou nejsou zdarma — stínové
příznaky a zúžené volání ubraly dalších ~0,12 ms.

**⚠️ Screenshot chytil dvě věci, které měření nevidělo** (třetí modul v řadě, kde se to stalo):
① dlaždice byla renderovaná jako **čtverec**, ale slot na obrazovce je široký `hrana × zoom/úroveň`,
takže se obraz při běžném zoomu **dotahoval 1,25× a pás byl rozmazaný** → poměr dlaždice 1,5 a verze
diskové cache na `v2` (jinak by se tahaly staré čtverce); ② křivka rychlosti leží na miniaturách
a na světlém záběru se **světle modrá čára ztratila** → přechodové ztmavení pod pásem křivky
(plná plocha dělala viditelný vodorovný šev, tři zastávky ne).

**Dluh z M3 zavřený — anomálie příznaku `beats` je vysvětlená.** Naměřeno na 2000 klipech:

| | `refreshClips` | kreslení pravítka | součet | scrollovací tik (metrika M3) |
|---|---|---|---|---|
| doby zapnuté | 0,42 ms | **1,46 ms** | 1,88 ms | 1,03 ms |
| doby vypnuté | 0,43 ms | **0,88 ms** | 1,31 ms | 1,18 ms |

Práce dob žije v **kreslení pravítka** (`beatMarks()` prochází všechny zvukové klipy), a scrollovací
tik měří `scroll(to:)` + `reflectScrolledClipView`, tedy `refreshClips` a nastavení `needsDisplay` —
**pravítko se kreslí až v dalším průchodu smyčkou, vně měřeného okna**. `refreshClips` je na příznaku
nezávislý. Modul 3 tedy měřil tu část tiku, ve které o dobách nic není; přepínač ubírá práci tam, kde
ji dělá (0,6–1,2 ms na kresbu). Obrácený pohyb toho malého čísla je vlastnost mikroměření
sub-milisekundového okna na hlavním vlákně, ne cena vrstvy.

**⚠️ A tím se otevírá zpátky to, co M4 zavřel příliš rychle: „0 vypadlých tiků" NENÍ na tomhle
stroji deterministické.** V jednom sezení, na téže zátěži: kód M4 dal **2 a 2** vypadlé tiky
(medián práce 0,80 ms), kód M5 dal **0, 0, 0, 1, 0, 2, 2** (medián 0,95–1,00 ms) — tedy modul, který
práci PŘIDAL, vypadl méně často než baseline. Load average se přes sezení pohybuje 1,6–2,2.
**Důvěryhodná je práce na tik** (rozptyl 0,02 ms) **a ABBA srovnání v jednom sezení** (osm běhů,
0 vypadlých tiků ve všech). Absolutní „nula výpadků" je vlastnost klidného stroje, ne kódu.

**Co se NEDĚLÁ:** popisek `sync −0,42 s` z návrhu. Model posun z klopáku nikde nedrží —
synchronizace klip přesune a číslo zahodí; vymýšlet ho by znamenalo napsat na klip údaj, který nemá
odkud vzít (týž důvod, proč M4 nedělal viditelnost a zámek stopy). Místo něj má hudební klip
v názvu **tempo** (`Podklad_hudba.m4a · 110,0 BPM`), jak návrh na A2 ukazuje.

**Přiznaná mez:** mapování bodů na zdrojový čas je i na klipu s rampou **lineární** — jen se škáluje
skutečnou spotřebou (`sourceConsumption`), takže pás pokrývá přesně použitý úsek materiálu, ale
rozestupy uvnitř zpomaleného úseku křivce neodpovídají. Co se v klipu doopravdy děje s časem, říká
křivka nakreslená přes pás. Přesné mapování by znamenalo invertovat rampu pro každou dlaždici a to
`TimelineModel` veřejně neumí.

*Koukanec rukou (v seznamu): pás miniatur na reálném materiálu při různém zoomu, křivka rampy na
klipu, popisky presetu a rampy, přepínač Miniatury na dlouhé ose, fotka v pásu.*

---

### ✅ M4 — výšky stop a hlavičky 104 (30. 07. 2026) · začátek etapy B

**Model dostal `topInset`** (fáze 18, modul 4): výchozí **nula**, aby se nepohnulo nic, co na
geometrii stojí. Výchozí výšky **zůstaly 64/44/28 s mezerou 2** — na nich stojí testy balíčku
a aplikace si své rozvržení předává konstruktorem přes `TimelineGeometry.aiditor`.
**+3 testy, celkem 456, 0 selhání.**

**Hlavičky 104 px** (dřív 96): jméno stopy semibold **nahoře** (ne na středu — se stopou vysokou
136 bodů by V1 plavalo v prázdnu), pod ním meta řádek `obraz · 5 klipů` / `řeč` / `hudba` /
`titulky`, u zvuku navíc **hodnota hlasitosti v dB**. Řádek je karta se zaoblením jen vpravo.

**Uklizen dluh přiznaný v M1:** `viewDidChangeEffectiveAppearance` je odstraněné ze všech tří view
osy. Okno je natvrdo tmavé, takže se nikdy nespustilo — a nespouštěná cesta tiše shnije. Obaly
`performAsCurrentDrawingAppearance` zůstaly: jsou to no-opy, ale drží v kódu vidět, že barva vrstvy
se vyhodnocuje při zápisu.

**Ověřeno `--layout-check`:**

| | naměřeno | čekáno |
|---|---|---|
| V1 / A1 / A2 / T1 shora | **3 / 142 / 223 / 304** | 3 / 142 / 223 / 304 |
| součet výšky | **344** | 344 |
| výšky stop | **136 / 78 / 40** | 136 / 78 / 40 |
| mezera / odsazení / hlavičky | **3 / 3 / 104** | 3 / 3 / 104 |

Hit testing na bod: `y=138,9` je ještě V1, `y=140` už mezera, `y=344` pod poslední stopou — a to
hlavní: **`y=0` a `y=2,9` (horní odsazení) NENÍ stopa**, takže klik nad prvním klipem ho netrefí.
To je celý smysl `topInset`u.

**⚠️ Změřeno, co plán čekal: při minimálním okně se stopy do výřezu NEVEJDOU.** Výřez 286 bodů proti
dokumentu 344 — T1 je pod ohybem a musí se doscrollovat. Kontrola proto netvrdí, že se to vejde, ale
že se na to **dá dostat** (svislý scroller zapnutý). Při okně z návrhu (1470×900) je pro stopy
~347–352 bodů, takže 344 se vejde — ale **až přijde přehled celé osy z M6 (46 bodů), přestane se
vejít i tam**. Je to vlastnost návrhu, ne chyba: v NLE se svisle scrolluje.

**Regrese:** `--timeline-bench` **0 vypadlých tiků**, medián práce **0,80 ms** — tedy stopy dvakrát
vyšší (136 proti 64) **nestály nic měřitelného**. Tím se zároveň **zavírá otevřená položka z M8**:
kritérium fáze 2 platí, dřívější výpadky byly zátěž stroje. `--select-check` (15 ✅) a `--range-check`
(9 ✅) prošly celé, přestože se hit testing posunul o horní odsazení. `--panel-check` a `--shell-check`
beze změny.

**⚠️ `--shell-check` na M4 spadl, a bylo to správně.** Kontrola z M1 hlídala hlavičky na 96 bodech
s komentářem „návrh je nemění". M4 je záměrně rozšířil na 104, takže očekávání se opravilo — ale to,
že se kontrola ozvala, je přesně to, k čemu je: rozměr se nemá měnit náhodou.

**Přiznaný mezistav:** obrazový klip je teď 136 bodů vysoký a nese jen jméno, takže vypadá **prázdněji
než dřív**. Vyplní ho pás miniatur v M5 — což je zároveň důvod, proč M5 jde hned po tomhle modulu.
Návrh visibility a zámku stopy v hlavičce se **nedělá**: model pro ně nemá stav a dvě tlačítka, která
v1 nikdy nic neudělají, jsou horší než jejich absence.

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

#### M12 · Prázdný start ✅ *(hotovo 30. 07. 2026 — `--empty-start-check`, 31 kontrol)*

**Jak to dopadlo:** riziko se potvrdilo a bylo horší, než plán čekal — přetažené URL není
security-scoped a `startAccessingSecurityScopedResource()` na něm vrací `false`, takže vzorec
z `NSOpenPanel` by každý přetažený soubor zahodil (`MediaImporter.adopt(dropped:)`). Navíc
vyšlo najevo druhé pravidlo: cíl přetažení musí obsah zóny HOSTIT (vnořený `NSHostingView`),
protože AppKit hledá cíl hit testem odspodu nahoru — změřeno, ne odhadnuto. Podrobnosti
v `PROJECT_STATUS.md`.

| | |
|---|---|
| **Cíl** | Okno bez projektu: zóna přetažení, poslední projekty, **pruh obnovy zálohy místo modálního dialogu**. |
| **Soubory** | nový `UI/Shell/EmptyState.swift`; `Media/ProjectStore.swift` (seznam posledních projektů), `ContentView.swift` (`offerUnsavedRecovery` přestane být dialog) |
| **Práce** | Drop zóna s rámečkem `1.5px dashed`, `Vybrat soubory…` / `Vybrat složku…`, řádek formátů. Poslední projekty s délkou a počtem záběrů; **offline projekt oranžově „disk není připojený"** (bookmark se nerozbalí). Rail ztlumený na `.35`, lišta osy na `.4`, prázdné pruhy stop s návodem. |
| **Hotovo když** | Přetažení složky na prázdné okno naimportuje totéž co `Otevřít složku`. |
| **Ověření** | `--empty-start-check`: simulovaný drop souboru i složky; obnova zálohy z pruhu dá tentýž projekt jako dnešní dialog (porovnání `validate()` a počtu klipů). |
| **Riziko** | Sandbox — drop dává URL s přístupem, ale bookmark se musí uložit stejně jako z `NSOpenPanel`. |

---

#### M13 · Fullscreen aplikace a fullscreen náhledu ✅ *(hotovo 30. 07. 2026 — `--fullscreen-ui-check`, 29 kontrol)*

**Jak to dopadlo:** riziko „návrat z fullscreenu přestavuje hierarchii“ se nenaplnilo, protože
se nepřestavuje — náhled je TÁŽ hierarchie bez chrome (vzorec `chromeHidden` z M1), takže
`PlayerView` zůstává na místě stromu. Změřeno za běžícího přehrávání: `rate` se nezměnil
a hlava po návratu zůstala na svém snímku. `⌃⌘F` (celá aplikace) zůstal systémový — skořápka
ho umí od M1. Podrobnosti v `PROJECT_STATUS.md`.

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

Podle rozhodnutí z 2.1 jde **všech 13 modulů před svatbou**, v jednom sledu.

| # | Modul | Etapa | Riziko | Brána |
|---|---|---|---|---|
| M1 ✅ | nový rám okna (+ tmavý režim natvrdo) | A | **R2, R4** | `--benchmark`, `--fullscreen`, `--shell-check` |
| M2 ✅ | stavový řádek a čip analýz | A | nízké | `--status-check` |
| M3 ✅ | lišta osy — vrstvy, citlivost, výřez, zoom | A | nízké | `--layers-check` |
| M7 ✅ | panel 452 + záložka Rychlost | C | střední | `--panel-check` |
| M8 ✅ | záložky Barva, Zvuk, Info | C | nízké | `--panel-check` |
| M4 ✅ | výšky stop, hlavičky 104 | B | nízké | `--layout-check` |
| M5 ✅ | **miniatury na klipech** | B | **R1 — nejvyšší, BRÁNA DRŽÍ** | `--timeline-bench`, `--thumb-check` |
| M6 ✅ | přehled celé osy | B | střední | `--overview-check` |
| M9 ✅ | knihovna médií a přetažení | C | střední | `--library-check` |
| M10 ✅ | list exportu | D | střední | `--export-check`, `--export-ui-check` |
| M11 ✅ | panel přepisu řeči | D | střední | `--transcript-ui-check` |
| M12 ✅ | prázdný start | D | nízké | `--empty-start-check` |
| M13 ✅ | fullscreen aplikace a náhledu | D | střední | `--fullscreen-ui-check` |

**Pořadí: M1 ✅ → M2 ✅ → M3 ✅ → M7 ✅ → M8 ✅ → M4 ✅ → M5 ✅ → M6 ✅ → M9 ✅ → M10 ✅ → M11 ✅
→ M12 ✅ → M13 ✅ → 🚧 KILL-GATE 1.** **Fáze 18 je HOTOVÁ — všech třináct modulů prošlo svou branou.**
Odsud vedou koukance rukou (seznam u každého modulu v `PROJECT_STATUS.md`) a pak svatba.

Proč zrovna takhle, když se jede všechno: **ergonomie napřed, kosmetika vzadu.** Prvních pět modulů
zavírá potíže #2, #3 a #4 ze zadání a nepřidává funkce — kdyby došel čas nebo se něco zadrhlo, jsou
to ty, které na svatbě chybět nesmí. M5 (miniatury) je nejrizikovější kus celého plánu a jde až po
M3, protože M3 dodává vypínač, kterým se dá zachránit, kdyby scroll benchmark spadl. Fullscreeny
jsou poslední schválně: jsou nejvíc „na koukání" a nejmíň blokují střih.

**Když modul neprojde svou bránou, odkládá se za svatbu on sám, ne celá fáze.** Pořadí je sestavené
tak, aby se dalo useknout kdekoli za M8 a to, co je hotové, dávalo použitelnou aplikaci.
