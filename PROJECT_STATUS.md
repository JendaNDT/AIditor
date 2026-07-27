# Projekt Krása (AIditor) – Project Status
*Naposled aktualizováno: 27. 07. 2026*

## 🎯 Co to je
Nativní macOS videoeditor pro svatební a rodinné filmy — plynulý speed ramping, 100 % lokální AI (obličeje, scény, český přepis) a integrovaný svatební asistent.
Stack (plán): Swift, SwiftUI (panely) + AppKit (timeline), AVFoundation, Metal, Vision, WhisperKit.
**Stav: Spike 0 i fáze 1 hotové, hlavní technické riziko zavřené.** Aplikace `Krasa` se spouští, importuje klipy, měří jim časování a přehrává 4K. Pod ní šest ověřených modulů (`SpeedRampEngine`, `TimelineModel`, `ProbeKit`, `MediaProbe`, `Flatten`, `Ramp`). **Fáze 2 je rozdělaná: logika časové osy hotová a otestovaná (163 testů), z deseti kroků view stojí tři — osa se stopami, pravítko a hlavičky. Klipy na ní zatím nejsou.**

## ✅ SPIKE 0 UZAVŘEN (26. 07. 2026)

> **Dá se v AVFoundation udělat plynulá rychlostní křivka tak, aby zvuk seděl, nelupal a export nespadl?**
> **Ano.** Synchron 0,00 ms, žádné lupance ani při 545 segmentech, 17 exportů bez pádu, kódování 4–7× rychleji než reálný čas.

Hlavní technické riziko projektu je zavřené. **Rozsah MVP je reálný, staví se dál.** Detaily a vyplněná kritéria v `SPIKE_0.md`.

**Poslední otevřené kritérium je zavřené.** Plynulost náhledu 4K/60 se ve spiku změřit nedala (přehrávač neexistoval) — fáze 1 ji zodpověděla a **27. 07. 2026 byla přeměřena po opravě metodiky: náhled běží přesně na stropu 60Hz displeje, bez sekání.**

## ⏭️ Příští krok

✅ **Blokátor vyřešen: „černý náhled" nebyl vada přehrávače, video překrývala vadná kreslicí vrstva časové osy (27. 07. 2026 pozdě večer).** Rozhodovací experiment ze včerejšího zápisu proběhl a vyšel OBRÁCENĚ, než napovídal hlavní podezřelý: pipeline benchmarku (b) obraz nespustila — spouštěčem bylo skrytí chrome (a), protože s ním z hierarchie odchází osa. Bisekce po vrstvách a nakonec diff stromu vrstev černého a funkčního běhu ukázaly příčinu: **`TimelinePane` měl override `draw(_:)` a jeho kreslicí `ContentLayer` dostala na macOS 26 rámec přes celé okno** (0,-454 640×718 při vlastních 640×220) — tmavá výplň rohu osy se kreslila přes video. Detaily a poučení v sekci rizik.

Oprava: roh mezi pravítkem a hlavičkami kreslí samostatné `CornerView` bez `draw` (barva přímo na vrstvě), `TimelinePane` už žádný override `draw(_:)` nemá. **Ověřeno sérií screenshotů běžící aplikace: obraz jede v plném layoutu se sidebarem, osou i transportem.** Diagnostické přepínače `--no-timeline` a `--player-only` i všechny sondy z vyšetřování jsou smazané; z vedlejších nálezů viz rizika (vadný záznam o `--player-only`, zbytečná výměna `AVPlayerLayer` → `AVPlayerView`).

Teď **krok 4 stavby: `TimelineLayout` + `LayerDiff` v `TimelineModelu`, s testy.** Rozhodnutí, které vrstvy připojit z fondu, které vrátit a kterým jen přepsat rámec. Hotovo bude, až projde `swift test` — ve view se přitom nezmění nic. Je to jediný krok stavby, který má testy, a schválně ten, ve kterém se dá nejvíc ztratit.

👀 **Kroky 2 a 3 chtějí koukanec.** Krok 2 potvrzený (27. 07. 2026, 21:08). U kroku 3 se očima ověřuje, že při vodorovném scrollu jede timecode s obsahem a jména stop stojí, a při svislém naopak.

✅ **Krok 1 — `TimelineModel` napojený na `Krasa.xcodeproj`** (commit `3f5f9cb`). Lokální balíček stejným vzorcem jako `ProbeKit` a `SpeedRampEngine`. Přibyl `TimelineController` — vlastník stavu podle `FAZE_2_VIEW.md` 2.1, kde má **geometrie jediné úložiště** (`interaction.geometry`) a controller ji vystavuje jen průchodem.

  Ověřeno, ne odhadnuto: `xcodebuild` bez chyb i varování, Xcode hlásí `Explicit dependency on target 'TimelineModel'`, v binárce je **5039 symbolů modulu** `TimelineModel` a 143 testů balíčku dál procházelo. *(Samotné „BUILD SUCCEEDED" nedokazuje nic — projekt se přeložil i předtím, než o balíčku věděl.)*

✅ **Krok 2 — `TimelineDocumentView` v `NSScrollView`, pruhy stop** (commit `28a5af3`). `isFlipped = true`, pruhy jako `CALayer`, `TimelinePane` s scroll view a most do SwiftUI (`TimelinePaneView` — ne `TimelineView`, to jméno už `SwiftUI` zabírá). Osa sedí pod přehrávačem.

  **Rozvržení ověřeno čísly proti `TimelineGeometry`**, na skutečných souborech aplikace, ne na kopii logiky: `V1 y=0 h=64`, `A1 y=66 h=44`, `A2 y=112 h=44`, dokument 1200 bodů proti 700 viditelným (tedy je co scrollovat). Aplikace se spustí bez pádu.

  🚩 **Při měření náhledu se osa z hierarchie odstraní, ne skryje.** Timeline je první věc v projektu, nad kterou musí WindowServer skládat — nechat ji na obrazovce znamená měřit něco jiného než čísla z fáze 1. A skrývání nulovým rámcem už jednou layout rozbilo, aniž si toho měření všimlo.

  ⚠️ **První verze prošla všemi kontrolami a přitom nebyla vidět.** Pruhy braly barvu ze `systémových sémantických` barev (`controlBackgroundColor` proti `underPageBackgroundColor`) — ty se ale v tmavém režimu liší o **0,039** ve složce bílé, takže z osy byl jeden slitý blok. Kontrola ověřovala, že vrstva barvu *má*, ne že je *k rozeznání*; test „hodnota není nil" je slabší, než vypadá. Opraveno vlastní paletou přes `NSColor(name:dynamicProvider:)`: rozdíl **0,150** u obrazové stopy a 0,080 u zvukové, v obou režimech vzhledu.

  Druhá věc, kterou čísla nechytila: osa i přehrávač jsou oba pružné `NSViewRepresentable`, takže si volné místo rozdělily napůl a osa zabírala 427 bodů. Teď má pevných 220.

✅ **Krok 3 — pravítko s timecode a hlavičky stop** (commit `8b5fba0`). Hlavičky 96 bodů vlevo, pravítko 26 bodů nahoře, obojí **mimo** `NSScrollView`: dostávají `contentView.bounds.origin` a každé si bere jen svou složku. Uvnitř scroll view by pravítko odjelo svisle a hlavičky vodorovně.

  **Timecode a volba rozteče rysek jsou v `TimelineModelu`, ne ve view.** Obojí je čistá funkce s porovnatelnou návratovou hodnotou; ve view by to nikdo neotestoval a chyba by se poznala jen tím, že si někdo všimne špatného popisku u hrany okna. **+20 testů, celkem 163, 0 selhání.** *(Je to druhé rozšíření modelu ve fázi 2 — `FAZE_2_VIEW.md` počítalo jen s `TimelineLayout`. Důvod je ale tentýž a pravidlo „co bude ve view navíc, to nikdo neotestuje" je silnější.)*

  **Bez drop-frame, a je to rozhodnutí, ne opomenutí.** Drop-frame timecode řeší rozpor mezi 29,97 snímku za sekundu a hodinami na zdi. Základna projektu je celé číslo, takže žádný rozpor nevzniká a po `00:00:29:29` následuje rovnou `00:00:30:00`. Kdyby se někdy zaváděla necelá základna, `Timecode.swift` je jedno ze dvou míst k přepsání.

  Ověřeno: vodorovný scroll hne jen pravítkem, svislý jen hlavičkami, popisky stojí na násobcích rozteče (při výchozím zoomu po sekundě, 120 bodů).

Pak zbytek **`TimelineView` v AppKitu — poslední kus fáze 2.** Co v něm doopravdy zbývá:

| část | stav |
|---|---|
| matematika osy, hit testing, přichytávání | ✅ `TimelineGeometry` |
| logika tažení, náhled, meze, výsledná operace | ✅ `TimelineInteraction` |
| střihové operace a jejich pravidla | ✅ `Project` |
| undo | ✅ `UndoStack` |
| `NSView` v `NSScrollView`, pruhy stop | ✅ krok 2 |
| pravítko a hlavičky stop přes `NSView.boundsDidChangeNotification` | ✅ krok 3 |
| timecode a rozteč rysek | ✅ `Timecode` v modelu, 20 testů |
| `TimelineLayout` + `LayerDiff` | ❌ krok 4 |
| klipy jako recyklované `CALayer` | ❌ krok 5 |
| vlnové průběhy jako `CGImage` dlaždice per zoom | ❌ |
| kurzory, kontextové menu, klávesové zkratky | ❌ |

**Do view patří jen kreslení a předávání událostí.** Co v něm bude navíc, to už nikdo neotestuje — a je to jediná část fáze 2, která se dá ověřit výhradně okem na běžící aplikaci.

**Návrh view je hotový: `FAZE_2_VIEW.md`** (27. 07. 2026). Deset kroků stavby, každý s vlastním „hotovo když", ověřená tabulka API a jedno rozšíření modelu (`TimelineLayout` + `LayerDiff` — rozhodnutí o recyklaci vrstev jako čistá testovatelná logika, ne kód ve view).

🚩 **Podmínka, ne nápad: datový model nese u každého assetu dvě cesty** — originál a volitelnou proxy — a přehrávání musí umět vybrat, kterou použije. Generovat se proxy nemusí až do fáze 4, ale struktura tam musí být hned. Doplnit ji později znamená přepsat model i playback.

### ✅ Náhled doměřen včetně fullscreenu (27. 07. 2026)

**Fullscreen nestojí nic.** Tři platné běhy na 4K/60 klipu, plocha obrazu 2,16× větší (40 % → 86 % displeje):

| | okno | celá obrazovka |
|---|---|---|
| doručeno | 59,9 fps | 59,9 fps |
| scrubování (medián) | 51,6 ms | 51,3 ms |
| GPU rezidence | 0,25 % | 0,00–0,06 % |

Měřilo se **na baterii se zapnutým úsporným režimem**, tedy za horších podmínek, než jaké budou v praxi — závěr je proto konzervativní. Otevřená položka „přeměřit náhled na celou obrazovku" je tím uzavřená.

## ✅ Hotovo
- **`SpeedRampEngine` — první modul, zkompilovaný a otestovaný.** **41 testů**, 0 selhání, Swift 6.3.3. Bézier easing, integrace rychlostní křivky, inverzní mapování pro scrubbing, segmentace pro `scaleTimeRange` zarovnaná na hranice snímků a řízená mezí skoku rychlosti, `Codable` pro `project.json`. Ověřeno proti nezávislé Python referenci na analyticky spočitatelných případech.
- **`MediaProbe` — sonda na vlastnosti klipů.** Rozlišení, orientace, kodeky, fps, edit list a hlavně **skutečné délky vzorků přes `AVSampleCursor`** (fallback `AVAssetReader`). Rozlišuje zaokrouhlení / zahozený snímek / proměnlivé časování. Naměřené hodnoty v `MediaProbe/RESULTS.md`. První kód, který sáhl na AVFoundation.
- **`Flatten` — zploštění VFR na pevnou snímkovou mřížku.** Krok 3 spiku. Cílová frekvence z měřeného modu, čtení přes `AVComposition` (edit list), zero-order hold převzorkování, ProRes 422 Proxy v plném rozlišení, zvuk LPCM. **Ověřeno na třech klipech: všechny `CFR` s kolísáním 0,00 %, synchron tlesknutí 0,00 ms, kódování 257–426 fps.**
- **`Ramp` — plynulá rychlostní křivka segmentací.** Krok 4 spiku, jádro produktu. `scaleTimeRange` pozpátku, časy kumulativně v celých tickách, segmentace podle meze skoku rychlosti (výchozí 1,5 %), korekce výšky `.timeDomain`. **Ověřeno na třech klipech: `CFR` 30 fps, kolísání 0,00 %, délky sedí do jednoho snímku, žádné lupance ani při 545 segmentech.**
- **Aplikace `Krasa` — fáze 1 hotová, měření přeměřeno 27. 07. 2026.** Xcode projekt (deployment target 14.0, sandbox, bundle `cz.projektkrasa.Krasa`), `MediaImporter` se security-scoped bookmarky, `VFRDetector` nad `ProbeKit`, `PlaybackController` se seekem podle QA1820 a `PlaybackBenchmark`.

  Naměřeno na pěti klipech, obraz v okně 1280×720 px (16,4 % displeje), MacBook Air M4, vestavěný displej 2940×1912 px / 60 Hz, napájení ze sítě:

  | klip | zdroj | strop metody | doručeno | scrub (medián) |
  |---|---|---|---|---|
  | 202947 | 59,682 fps | 59,7 | **59,7** | 49,2 ms |
  | 203452 | 30,010 fps | 30,0 | **30,0** | 41,0 ms |
  | 203813 slow-mo | 120,000 fps | 60,0 | **60,0** | 95,1 ms |
  | 203901 | 60,000 fps (VFR) | 60,0 | **59,9** | 51,6 ms |
  | 204045 | 60,000 fps | 60,0 | **60,0** | 51,9 ms |

  **Doručování je nasycené na stropu metody u všech klipů** — víc než jeden snímek na tik displeje se nezapočítá. Znamená to *spotřeba na 60Hz displeji je pokrytá*, ne *tolik zvládne dekodér*. U slow-mo klipu je strop i výsledek shodně 60,0, takže o propustnosti 120 fps se z toho nedozvíme nic.

  **GPU baseline pro fáze 2–3.** Holý náhled 4K/60 na popředí, ať v okně nebo na celé obrazovce, stojí **pod 0,3 % GPU rezidence** — video jde na displej jako samostatná vrstva a GPU se skoro nezapojí. S aplikací na pozadí, kdy se skládat musí, to skočí na ~10 %. Až se ve fázi 3 přidá vlastní compositor nebo efekty, přepne se to natrvalo do té dražší cesty; tohle jsou hodnoty, proti kterým se to pozná. Podrobnosti v sekci rizik.

  Dřívější zápis „okno 1280×1192 px" byla plocha **vrstvy** v backing pixelech, ne okna ani obrazu. Samotný obraz měl 1280×720 px.
- **`TimelineModel` — logika, geometrie a interakce časové osy.** **163 testů, 0 selhání.** Čistý Swift bez AVFoundation a bez AppKitu, takže se přeloží a otestuje i na Linuxu — díky tomu byl ověřený dřív, než se sáhlo na UI.
  - **Datový model:** dvě časové soustavy s jedinou hranicí mezi nimi (`Frames` na ose, `SourceTime` ve zdroji), deset invariantů kontrolovaných po každé operaci, kompletní sada operací (vložení, přepis, ripple, split, join, trim, slip, roll, vazba obrazu na zvuk), dotazy na meze tažení a snapshot undo nad celým projektem.
  - **`TimelineGeometry`:** mapování čas↔pixel při zoomu, viditelný rozsah binárním půlením, rozvržení stop, hit testing s okraji klipů, přichytávání s pořadím síly kandidátů. Šířka úchopu a tolerance přichytávání jsou v **bodech**, ne ve snímcích — jinak by po odzoomování nešel chytit okraj klipu a po přiblížení by přichytávání skákalo přes půl obrazovky.
  - **`TimelineInteraction`:** stavový automat tažení. Určení druhu podle toho, co je pod myší, průběžný náhled s přichytáváním a kontrolou legálnosti, meze trimu a rollu, výsledná operace na modelu. Během tažení se do modelu nezapisuje.

  Návrh a zdůvodnění v `FAZE_2_TIMELINE.md`.
- **`ProbeKit` — sdílené měřicí a renderovací jádro.** Klasifikace délek vzorků, verdikt CFR/VFR, edit list, `CFRRenderer`. Používají ho všechny tři nástroje, takže měří a renderují stejným kódem.
- Produktová a technická specifikace v2.0 (HTML + PDF)
- **Implementační plán** — 12 fází, 3 kill-gates, modulová mapa, session protokol (`IMPLEMENTACNI_PLAN.md`)
- **Interaktivní tracker** — odškrtávací postup s progress barem (`krasa-tracker.html`)
- Rešerše tří rizikových oblastí: Whisper na macOS, face clustering, timeline UI a compositor
- Vyřešeno pozicování, cena (1 490 Kč jednorázově), distribuce, datový model `.projektkrasa`

## 🔄 Rozjeté (nedodělané)
- **Fáze 2 — timeline.** `TimelineModel` hotový, otestovaný, v gitu a **napojený na `Krasa.xcodeproj`** (krok 1 z deseti). `TimelineView` navržený (`FAZE_2_VIEW.md`), kreslicí kód nezačatý — stojí zatím jen `TimelineController` jako vlastník stavu.
- **Pozor:** v sekci 8.1 specifikace jsou položky MVP odškrtnuté `[x]`. Je to seznam *rozsahu*, ne stav.

## 📝 TODO
### Cesta k v0.5 „MVP nula" (~6 měsíců při 30 h/týdně)
- **F0** Spike 0 — ověření speed rampingu — ✅ **HOTOVO 26. 07. 2026**, hlavní riziko zavřené
- **F1** Kostra, import, přehrávač, VFRDetector — ✅ **HOTOVO 26. 07. 2026**
- **F2** Timeline v AppKitu — nejtěžší UI v projektu *(4–5 týdnů)* — 🔄 **model hotový (163 testů), z deseti kroků view hotové 3**
- **F3** Speed ramping ostrý *(3 týdny)*
- **F4** Proxy + zploštění VFR→CFR *(2 týdny)*
- **F5** Projekt, autosave, undo, export *(3 týdny)*
- 🚧 **KILL-GATE 1:** sestříhat touhle appkou celou reálnou svatbu

### Cesta k v1.0 (+~4 měsíce)
- **F6** Svatební asistent *(2 týdny)* — **podmínka funkčnosti hlavní funkce**, ne jen odlišení: bez pravidla „zpomalované záběry toč na 120 fps" dostane uživatel trhaný ramp
- **F7** Audio engine, 32-bit float, LUFS *(3 týdny)*
- **F8** Titulky přes WhisperKit *(2 týdny)*
- **F9** Distribuce, notarizace, Sparkle, licence *(3 týdny)* — **+ migrace na `AVVideoComposition.Configuration`** jako druhá větev pod `if #available(macOS 26.0, *)`. Ne dřív.
- 🚧 **KILL-GATE 2:** prodat deseti lidem, kteří tě neznají

### Za v1.0 — podmíněné
- **F10** AI analýza scén a kvality záběrů *(2 týdny)* — bezpečná AI, žádné právní riziko
- **F11** Rozpoznávání obličejů *(8–12 týdnů)* — tři gaty: právní, licenční, poptávkový
- **F12+** Multicam, HDR, slovenština, LUTs

### Škrtnuto
- **Optical flow dopočet mezisnímků.** Ne odloženo — škrtnuto. Je to výzkumný problém, ne funkce na dopsání.

## ⚠️ Známá rizika a korekce specifikace
*(Detaily v `IMPLEMENTACNI_PLAN.md`, sekce 1.)*

- **⚠️ Override `draw(_:)` na view uvnitř timeline pane vyrobí na macOS 26 kreslicí vrstvu přes CELÉ okno a překryje přehrávač.** Příčina „černého náhledu", rozřešeno 27. 07. 2026 diffem stromu vrstev (`layers_black` vs `layers_ok`): `TimelinePane` (640×220) dostal `ContentLayer` s rámcem (0,-454 640×718) — celé okno včetně titulkové lišty — a tmavou výplní osy zakryl `AVPlayerView`, který přitom celou dobu obsah MĚL (`FigVideoContainerLayer` 3840×2160 ve stromu seděl). Postižený byl kořen `NSViewRepresentable` i jeho nepřevrácený potomek (první verze `CornerView`); `TimelineRulerView` a `TrackHeadersView` (převrácené, nekořenové) kreslí bez potíží — přesná podmínka spouštěče známá není, tohle je změřený stav. Tři poučení:
  1. **Rozhoduje EXISTENCE overridu, ne jeho obsah.** Prázdné `draw` s okamžitým `return` černí stejně — vyzkoušeno. Bisekce přes „vypnout tělo metody" proto viníka minula a našel ho až dump vrstev.
  2. **Ploché barvy nekreslit, ale dávat vrstvě** (`wantsLayer` + `backgroundColor` + překlad přes `performAsCurrentDrawingAppearance`, vzorec `CornerView` v `TimelinePane.swift`).
  3. Až příště „zmizí" obsah okna, **dumpni strom vrstev a hledej `ContentLayer` s rámcem větším než view** — série screenshotů z bisekce stála hodinu, diff stromů pět minut.

  Vedlejší nálezy z téhož vyšetřování: dřívější záznam „`--player-only` je černý" byl **vadný** (na dnešním buildu holý přehrávač obraz ukazoval; spouštěčem byla vždy jen přítomnost osy) — nejspíš se tehdy pozoroval pauznutý přehrávač bez spuštěného přehrávání. A výměna vlastní `AVPlayerLayer` za `AVPlayerView` nebyla k opravě potřeba; `AVPlayerView` ale zůstává — dělá totéž a obsluhu vrstvy řeší za nás.

- **⚠️ Měření doručených snímků je NASYCENÁ metrika a na velikost plochy je slepá.** Zjištěno 26. 07. 2026. Tři nezávislé důvody, každý sám o sobě stačí:
  1. `pollFrame` počítá **nejvýš jeden snímek na tik display linku**, takže na 60Hz panelu je strop 60 bez ohledu na to, co stroj zvládne.
  2. `AVPlayerItemVideoOutput` doručuje v rozlišení **zdroje** nezávisle na velikosti okna — dekódovací zátěž se roztažením okna nemění, roste jen škálování.
  3. Sekundové okno se uzavíralo na prvním tiku **za** hranicí a čas se resetoval na aktuální, takže přeběh propadal. Okno trvalo v průměru 1,0083 s a počet se vydával za „fps".

  Z bodu 3 plyne, proč vyšlo **60,3 fps na displeji se stropem 60,0** — a report si nad tím číslem sám tiskl „víc se doručit nedá". Opraveno: `MeasurementWindow` nese svou skutečnou délku a fps se počítá jako počet/čas.

  Z bodů 1 a 2 plyne, že **„4K/120 na 60,7 fps" neměří dekodér** — u 120fps zdroje je nový buffer připravený na každém tiku, takže se změřil počet tiků display linku. Že 60,7 > 60,3 znamená jen to, že 60fps zdroj občas jeden tik fázově mine.

  **Nedotčené zůstává scrubování** (48,3 vs 6,2 ms): měří se přes `measuredSeek`, jinou cestou. Rozhodnutí „proxy je kvůli scrubování, ne kvůli přehrávání" tedy platí dál.
- **🚩 GPU rezidence náhledu nesleduje plochu obrazu, ale to, jestli je potřeba kompozice.** Změřeno 27. 07. 2026. Dva okenní běhy, tentýž klip a tatáž plocha, se liší **čtyřicetinásobně**: s aplikací na pozadí 9,90 %, s aplikací vpředu a nezakrytým oknem 0,25 %. Fullscreen při 2,16× větší ploše 0,00–0,06 %.

  Výklad: dokud je náhled prostě video a nic přes něj neleží, systém ho pošle na displej jako samostatnou vrstvu a GPU se nezapojí. Jakmile se musí skládat, GPU se probudí.

  **Důsledek pro fázi 3, a je to varování, ne rezerva:** ta skoro-nula platí jen pro holé video. Až přes náhled půjde vlastní compositor, efekty nebo Metal, přepne se to na skládání přes GPU a čísla **neporostou plynule — skočí**. Výchozí hodnota, proti které se to pozná, je změřená (viz sekce Hotovo). Zároveň z toho plyne, že `powermetrics --samplers gpu_power` je pro cenu *holého* náhledu skoro slepý; užitečný bude až na efektech.
- **⚠️ Měření náhledu je platné jen tehdy, když bylo na co koukat.** Zjištěno 27. 07. 2026 poté, co první fullscreen běh vrátil spokojených 60,0 fps s rozbitým layoutem: skrytí sidebaru přes `maxWidth: 0` zalomilo text do nulové šířky a natáhlo view na 4398 bodů, tedy 4,5× výšku displeje. Snímky z `AVPlayerItemVideoOutput` přitom chodí dál bez ohledu na to, jestli se něco kreslí — vada se v číslech nijak neprojevila.

  V kódu to teď hlídá `NSWindow.occlusionState`, podíl obrazu ležícího uvnitř `contentView`, ořez vrstvy na viditelnou plochu (`PlayerHostView.visibleBounds`) a podíl času, kdy byla aplikace aktivní. Když cokoli z toho klesne pod 99 %, běh se prohlásí za neplatný místo aby vrátil hezké číslo. Ověřeno v praxi — druhý pokus jeden ze čtyř běhů takhle sám odmítl.

  *(Pozor na dřívější verzi téhle poznámky: nulová GPU rezidence se v ní vykládala jako důkaz, že se obraz nekreslí. Není — viz předchozí bod.)*
- **Kadence display linku není metrika kompozice.** `CADisplayLink` je vázaný na vsync displeje — ten proběhne, i když WindowServer nestíhá skládat; ukáže se prostě starý snímek. Vypadlý tik znamená **zaseknuté hlavní vlákno naší aplikace**, ne přetížené GPU. Cenu skládání měř `powermetrics` puštěným vedle, nebo — až ve fázích 2–3, kde se stejně bude stavět — vlastní Metal cestou přes `addPresentedHandler` / `presentedTime` a `gpuStartTime` / `gpuEndTime`.
- **`ProcessInfo.thermalState` na Apple silicon lže podobně jako `nominalFrameRate`.** Zůstává `.nominal` dlouho poté, co se stroj už taktuje dolů. Jako důkaz nepřetíženosti ho neber; na bezventilátorovém Airu je 20 s chladnutí navíc řádově málo, proto se před srovnávacím měřením pouští zahazovaný zahřívací běh.

- **⚠️ `.onTapGesture` na řádku SwiftUI `Listu` na macOS nefunguje.** Odhaleno 27. 07. 2026, ale bylo to v projektu od fáze 1: klik na klip v seznamu nedělal nic. `List` stojí na macOS nad `NSTableView` a ten si myš bere na vlastní výběr, takže se gesto uvnitř řádku nespustí. **Na iOSu tentýž kód funguje** — proto se ta chyba snadno napíše.

  Skrývala se za tím, že se první klip vybíral sám: dokud v přehrávači něco bylo, nebylo poznat, že ručně vybrat nejde. Správně je `List(selection:)` a výběr držený v modelu, ne v `@State` ve view. Zvýrazněný řádek je vedlejší zisk — předtím nešlo poznat, který klip je načtený.

  **Poučení do fáze 2:** UI napsané „ze zvyku z iOSu" projde překladem i kontrolou a přesto nefunguje. Sedí to k témuž vzorci jako barvy vrstev — chyba, kterou odhalí jen ruka na myši.
- **⚠️ SwiftUI nesleduje vnořené `ObservableObject`y.** Odhaleno 27. 07. 2026, v projektu od fáze 1. `ContentView` drží `AppModel`, ale `currentTime` a `isPlaying` publikuje `AppModel.controller` — jiný objekt, jehož změny view nepřekreslí. Časomíra proto trvale ukazovala `0:00.000` a tlačítko se nepřepínalo na „Pauza", **přestože přehrávání prokazatelně běželo** (60 ohlášení za 2 s, čas 1,867 s — data byla v pořádku, jen je nikdo neposlouchal). Oprava: malé view `TransportBar` s `@ObservedObject` přímo na controlleru. Schválně malé — pozorovatel času chodí 30×/s a překreslovat celé okno by znamenalo 30×/s volat `updateNSView` na časové ose.
- **⚠️ `CALayer.render(in:)` a `cacheDisplay(in:to:)` se nedají použít k ověření, jak vrstva doopravdy leží.** Zjištěno 27. 07. 2026 při kroku 2 fáze 2. Otázka zněla, jestli podvrstvy dědí `NSView.isFlipped`. `render(in:)` vrátil, že se převrácením nic nemění — a přitom `layer.isGeometryFlipped` bylo prokazatelně `true`. Ta metoda převrácení **ignoruje**. `cacheDisplay` byl ještě horší: jednou obsah vrstvy zachytil, podruhé při stejném kódu vůbec.

  **Odpověď je ano, dědí** — AppKit `isGeometryFlipped` u převráceného layer-backed view sám nastaví a SDK k té vlastnosti říká *„geometry of the layer **and its sublayers** is flipped vertically"*. `TimelineGeometry.y(ofTrackAt:)` jde vrstvě předat rovnou.

  **Poučení nad rámec téhle otázky:** vlastní měřicí metoda může vrátit hezký a úplně obrácený výsledek. Tady to odhalil až sebekalibrující se běh, kde se totéž změřilo na známém referenčním případu. Je to stejná třída chyby jako vadné okno u měření fps ve fázi 1.
- **⚠️ Barva systémové `NSColor` uložená do `CALayer` v tmavém režimu zamrzne.** `NSColor.cgColor` se vyhodnotí pro appearance platnou v okamžiku volání, ne pro tu, ve které vrstva leží. Překládat se proto musí uvnitř `performAsCurrentDrawingAppearance` a znovu ve `viewDidChangeEffectiveAppearance()`. **Na `NSColor` předanou přímo AppKit view (`NSScrollView.backgroundColor`) to neplatí** — tu si view překládá při každém kreslení samo. Rozdíl je v tom, kdo barvu drží: vrstva si pamatuje `CGColor` (hodnotu), view drží `NSColor` (recept).
- **⚠️ `NSCursor.resizeLeftRight` je od macOS 27.0 deprecated a náhrada `NSCursor.columnResize` je až od macOS 15.0.** Ověřeno 27. 07. 2026 v dokumentaci Apple. Na deployment targetu 14.0 tedy potřebuje kurzor pro dělič klipů `if #available(macOS 15.0, *)` s fallbackem na tu deprecated verzi. **Je to přesně stejný vzorec jako `AVMutableVideoComposition` vs `AVVideoComposition.Configuration`** — a je to jediné API z celého návrhu `TimelineView`, které runtime gate potřebuje. Zbytek (`isFlipped`, `boundsDidChangeNotification`, `magnify(with:)`, `NSTrackingArea`, `CALayer.contentsScale`, `CATiledLayer`) je dostupný od macOS 10.x. Tabulka s odkazy je v `FAZE_2_VIEW.md`, sekce 10.
  *Mimochodem: první odhad názvu náhrady (`NSCursor.columnResizeCursor(in:)`) neexistoval — správně je `columnResize` a `columnResize(directions:)`. Přesně ten druh chyby, kvůli které platí pravidlo o ověřování API.*
- **⚠️ `NSViewBoundsDidChangeNotification` je starý ObjC název.** V Swiftu je to `NSView.boundsDidChangeNotification` a **posílá se jen tehdy, když je `postsBoundsChangedNotifications == true`** — na `NSScrollView.contentView` se to musí zapnout ručně. Při změně `frame` se neposílá vůbec. `IMPLEMENTACNI_PLAN.md` sekce fáze 2 nese starý název.
- **`AVMutableVideoComposition` je od macOS 26 deprecated, ale používá se dál.** Náhrada `AVVideoComposition.Configuration` je `@available(macOS 26.0, *)`, a minimum projektu je macOS 14.0 — na macOS 14–25 tedy neexistuje. Deprecated ≠ odstraněné. Warning umlčovat cíleně u volání, ne globálně. *(Dřívější text tvrdil opak — byla to chyba, opraveno 25. 07. 2026.)*
- **`scaleTimeRange` neumí plynulou křivku** — dělá lineární časové mapování. `CMTimeMapping` je dvojice `CMTimeRange`, takže křivka do něj nejde zapsat z principu. **Ramp = segmentace, jiná cesta není** (vlastní compositor do časování nevidí). ~~Hlášené artefakty ve zvuku na hranicích segmentů~~ — **změřeno 26. 07. 2026: nejsou.** Poslechem ověřeno až po 545 segmentů na dvou klipech s vysokým podílem ticha. Jemnost segmentace se proto volí podle velikosti kompozice, ne podle sluchu.
- **Whisper-small je pro češtinu nepoužitelný** (34–38 % WER) → `large-v3-turbo` (~13 %, stejná velikost jako medium, násobně rychlejší).
- **`SpeechAnalyzer` češtinu nepodporuje** — v seznamu 42 locale není `cs_CZ`. Sekce 4.3.1 specifikace se ruší.
- **Vision nemá veřejné API pro otisk obličeje.** Face grouping = vlastní Core ML model + vlastní DBSCAN + UI pro ruční opravy. Ente na tom pracovalo 21 měsíců s placeným týmem.
- **Modely pro rozpoznávání obličejů jsou z velké části komerčně zakázané.** InsightFace, ArcFace, buffalo_l: *non-commercial research only*. Jediný čistý je AuraFace-v1 (Apache 2.0), a z jeho repa se smí stáhnout **pouze `glintr100.onnx`**.
- **EU AI Act čl. 2(10) nechrání dodavatele software**, jen koncového uživatele. Termín pro Annex III po Digital Omnibus: 2. 12. 2027.
- **`AVAssetExportSession` ignoruje `frameDuration`** → export přes `AVAssetWriter`.
- **`AVAssetWriter` si bez instrukce zvolí timescale 600 a kvantizuje do ní zapisované časy.** U 29,97 / 59,94 / 23,976 i naší 30,01 fps to vyrobí rozptyl a výstup vyleze jako `CFR≈` místo `CFR`. Vždy `videoInput.mediaTimeScale = frameDuration.timescale`; na zvuku NE, vyhodí výjimku. Odhaleno až ověřením na druhém klipu — na jednom by chyba prošla.
- **Zvuk v proxy a zploštěných souborech jen jako LPCM.** AAC by přidal vlastní priming delay a rozbil to, kvůli čemu ty soubory vznikají.
- **Zpomalení potřebuje dost snímků ve zdroji: `zdrojFps × nejnižšíRychlost ≥ výstupFps`.** Ramp na 0,25× při 30 fps výstupu chce zdroj 120 fps. Naměřeno: 120 fps → 0 % duplikátů, 60 fps → 13,5 %, 30 fps → 37,5 %. **Musí to být v UI jako varování dopředu**, ne až ve výsledku. Zároveň argument pro pravidlo „zpomalované záběry toč na 120 fps" ve svatebním asistentovi.
- **VFR z telefonu.** Apple nemá API pro detekci — musíš číst délky vzorků sám. **Změřeno 25. 07. 2026 na pěti klipech ze Samsungu (`MediaProbe/RESULTS.md`): ani jeden nemá čistě konstantní časování.** VFR je výchozí stav, ne okrajový případ.
- **Zvuk má edit list, který zahazuje prvních 44 ms.** Priming AAC kodéru, u všech pěti klipů. **Zvuk se nikdy nesmí číst ze syrové tabulky vzorků** — jen přes `AVComposition` nebo s respektováním `AVAssetTrack.segments`. Jinak je posunutý o 44 ms a chyba se hledá v synchronizaci místo ve čtení.
- **`nominalFrameRate` lže.** Slow-mo klip hlásí 119,369 fps, naměřeno 120,000. Metadata, ne měření — časovou základnu projektu z něj neodvozovat.
- **Zahozený snímek ≠ proměnlivé časování.** Vzorek jako celočíselný násobek délky snímku = zahozený snímek, opraví se duplikátem. Nepravidelná délka = přepočet časování. Rozdíl v ceně opravy je řádový, `MediaProbe` to rozlišuje.
- **Nikdo nikdy nepublikoval benchmark vlastního `AVVideoCompositing` na 4K/60.** Spike 0 to nezodpověděl — vlastní compositor se nestavěl, protože se ukázalo, že do časování nevidí. Otázka zůstává otevřená pro efekty a Metal ve fázích 2–3.
- **Vykonavatelské riziko.** Web stack z předchozích projektů se sem nepřenáší.

## 🏗️ Klíčová rozhodnutí
- **Timeline v AppKitu, zbytek v SwiftUI.** SwiftUI nemá recyklaci buněk ani viditelnost do drag session. Riverside má SwiftUI chrome + samostatný timeline engine, Recut je celý AppKit.
- **Stav timeline vlastní `TimelineController`, ne view.** Projekt, undo, interakce, playhead, výběr i mezipaměť vln. **Geometrie má jediné úložiště** — `interaction.geometry`, controller ji vystavuje jen průchodem. Dvě kopie `TimelineGeometry` by se při zoomu rozešly a hit testing by počítal s jiným měřítkem než přichytávání; taková chyba nespadne, jen se klip trefuje vedle. *(`FAZE_2_VIEW.md`, 2.1)*
- **Rozhodnutí o recyklaci vrstev patří do `TimelineModelu`, ne do view.** Přibude `TimelineLayout` + `LayerDiff` — čistá funkce z (projekt, geometrie, scroll) na množiny „připojit / vrátit do fondu / přepsat rámec". Ve view zbude desetiřádková smyčka. Chyby recyklace jsou množinové, ne kreslicí, a takhle mají testy. *(`FAZE_2_VIEW.md`, 2.4)*
- **Vlnové průběhy: špičky jednou na asset, dlaždice po mocninách dvou.** Cachovat dlaždice podle aktuálního `pointsPerFrame` by zahodilo mezipaměť při každém snímku pinche. Mezi úrovněmi se dlaždice natáhne — během gesta lehce rozmazaná, po ustálení ostrá. **Špičky se čtou přes `AVComposition`**, jinak je vlna o 44 ms vedle zvuku (edit list u všech pěti měřených klipů). *(`FAZE_2_VIEW.md`, 2.7)*
- **Během tažení se nemění zoom.** Kandidáti na přichycení se počítají jednou při `begin` a jsou ve snímcích; změna `pointsPerFrame` by uprostřed tažení posunula tolerance. `magnify` i ⌘+kolečko se při `isDragging` ignorují. *(`FAZE_2_VIEW.md`, 2.6)*
- **Kompozice přes `AVMutableVideoComposition`** pro spike i MVP. `AVVideoComposition.Configuration` až jako druhá větev před vydáním (fáze 9), runtime gatovaná přes `if #available(macOS 26.0, *)`.
- **Speed ramping a `Configuration` spolu nesouvisí.** `Configuration` neobsahuje žádné časování — jen instrukce, transformace, průhlednost, ořez, barvy.
- **Jedna časová základna projektu, 30 fps.** Nikdy neodvozovat čísla snímků ze zdrojových časových značek.
  Kandidátem bylo 24 fps kvůli hlubšímu čistému zpomalení, ale **rozhodl převod při normální rychlosti**: 60 → 24 je poměr 2,5:1, tedy nerovnoměrné zahazování snímků a viditelné trhání při panorámování. 60 → 30 je 2:1 a 120 → 30 je 4:1, obojí čisté. Většina klipů je 60 fps, takže 24 by trhalo běžné záběry kvůli výhodě jen ve zpomalených úsecích.
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

### Dokumentace
- `Projekt_Krasa_Specifikace_Aplikace_v2.html` / `.pdf` – specifikace, zdroj pravdy pro **rozsah**
- `IMPLEMENTACNI_PLAN.md` – zdroj pravdy pro **pořadí a technologie**
- `SPIKE_0.md` – **uzavřený Spike 0 s naměřenými výsledky.** Vyplněná kritéria úspěchu, vyhodnocený rozhodovací bod, metodické poznámky k testování lupanců
- `FAZE_2_TIMELINE.md` – **návrh `TimelineModelu`.** Typy, invarianty, operace, undo a zdůvodnění rozhodnutí; kód podle něj je hotový
- `FAZE_2_VIEW.md` – **návrh `TimelineView`.** Vlastnictví stavu, vrstvení `CALayer`, recyklace, cesta události, vlnové průběhy, výkonový rozpočet, deset kroků stavby a tabulka ověřených API; kód podle něj **zatím nezačatý**
- `CLAUDE.md` – kontext a technická rozhodnutí pro Claude Code
- `PROJECT_STATUS.md` – tenhle soubor
- `krasa-tracker.html` – interaktivní tracker postupu *(udržuje autor ručně)*

### Kód
- `SpeedRampEngine/` – **matematika rychlostní křivky.** Čistý Swift, žádné závislosti
  - `Sources/SpeedRampEngine/SpeedRampEngine.swift` – křivka, mapování, segmentace
  - `Tests/SpeedRampEngineTests/SpeedRampEngineTests.swift` – **41 testů**
  - `README.md` – API, naměřené hodnoty, volba jemnosti segmentace
  - `ref_speedramp.py` – Python reference, proti které se to ověřovalo
- `TimelineModel/` – **logika časové osy.** Čistý Swift, žádné závislosti, přeloží se i na Linuxu
  - `Sources/TimelineModel/Time.swift` – `Frames` a `SourceTime`, hranice mezi soustavami
  - `Sources/TimelineModel/Model.swift` – `Asset`, `Clip`, `Track`, `Timeline`, `Project`, převody
  - `Sources/TimelineModel/Validation.swift` – deset invariantů
  - `Sources/TimelineModel/Operations.swift` – všechny střihové operace
  - `Sources/TimelineModel/Queries.swift` – meze tažení pro UI
  - `Sources/TimelineModel/UndoStack.swift` – snapshot undo nad celým projektem
  - `Sources/TimelineModel/Geometry.swift` – matematika view: zoom, viditelný rozsah, hit testing, přichytávání
  - `Sources/TimelineModel/Interaction.swift` – stavový automat tažení: náhled, meze, výsledná operace
  - `Sources/TimelineModel/Timecode.swift` – popisky pravítka: `HH:MM:SS:FF` a volba rozteče rysek
  - `Tests/TimelineModelTests/` – **163 testů**
  - `README.md` – API, dvě časové soustavy, co se snadno rozbije
- `Krasa/Krasa/Timeline/` – **timeline v appce**
  - `TimelineController.swift` – vlastník stavu: projekt, undo, interakce (a v ní **jediná kopie geometrie**), playhead, výběr
  - `TimelineDocumentView.swift` – plocha osy: `isFlipped`, pruhy stop, barvy přežívající přepnutí do tmavého režimu, Retina
  - `TimelinePane.swift` – rozvržení, `NSScrollView`, synchronizace pravítka a hlaviček se scrollem, most do SwiftUI
  - `TimelineRulerView.swift` – timecode a rysky, posun podle `bounds.origin.x`
  - `TrackHeadersView.swift` – jména stop, posun podle `bounds.origin.y`
- `MediaProbe/` – **balíček se třemi nástroji a sdílenou knihovnou**
  - `Sources/ProbeKit/` – sdílené jádro: klasifikace délek vzorků, verdikt CFR/VFR, edit list, `CFRRenderer`, `VideoResampler`
  - `Sources/MediaProbe/` – sonda: `swift run MediaProbe`
  - `Sources/Flatten/` – zploštění VFR→CFR, test synchronu, detekce transientů a řeči, export snímků: `swift run Flatten`
  - `Sources/Ramp/` – rychlostní křivka na reálném souboru: `swift run Ramp`
  - `RESULTS.md` – **naměřené vlastnosti klipů**; generované, needituj ručně
  - `CLIPS.txt` – **ručně psané poznámky, co se na kterém klipu točilo.** Sonda je načítá do `RESULTS.md`

### Data (mimo git)
- `TestClips/` – 5 klipů ze Samsungu, 2,1 GB, **ignorované gitem**
  - `flattened/` – zploštěné vstupy pro ramp (`*_cfr.mov`)
  - `flattened/ramped/` – výstupy rampu (`*_ramp_step15.mov`)
