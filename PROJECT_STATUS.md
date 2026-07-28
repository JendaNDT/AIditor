# Projekt Krása (AIditor) – Project Status
*Naposled aktualizováno: 28. 07. 2026*

## 🎯 Co to je
Nativní macOS videoeditor pro svatební a rodinné filmy — plynulý speed ramping a 100 % lokální český přepis titulků. **Čistě editor: svatební asistent škrtnut 28. 07. 2026 na pokyn autora** (AI analýza scén a obličejů zůstává podmíněná za v1.0).
Stack (plán): Swift, SwiftUI (panely) + AppKit (timeline), AVFoundation, Metal, Vision, WhisperKit.
**Stav: Spike 0, fáze 1 i stavba fáze 2 hotové (čeká koukanec), FÁZE 3 HOTOVÁ — přehrávač hraje rychlostní křivky a editor je kreslí myší, potvrzeno rukou.** Aplikace `Krasa` se spouští, importuje klipy, měří jim časování a přehrává 4K. Pod ní šest ověřených modulů (`SpeedRampEngine`, `TimelineModel`, `ProbeKit`, `MediaProbe`, `Flatten`, `Ramp`). **Fáze 2 má NAPSANÝCH všech deset kroků (232 testů modelu): osa, pravítko, hlavičky, rozvržení s recyklací, klipy, playhead + seek, tažení s undo, zoom na kurzoru, roll/slip + menu + zkratky + kurzory, vlnové průběhy. v0.5 „MVP NULA“ JE KOMPLETNÍ: import → střih s rampami → proxy → projekt s autosave → export HEVC 4K/30 CFR + dotaz při zavírání neuloženého projektu (dialog čeká na koukanec rukou). Před námi KILL-GATE 1 (koukance autor odkládá, až bude appka celá — stavíme dál). FÁZE 7 (audio) ROZJETÁ: modul 1 `LoudnessMeter` hotový.**

## ✅ SPIKE 0 UZAVŘEN (26. 07. 2026)

> **Dá se v AVFoundation udělat plynulá rychlostní křivka tak, aby zvuk seděl, nelupal a export nespadl?**
> **Ano.** Synchron 0,00 ms, žádné lupance ani při 545 segmentech, 17 exportů bez pádu, kódování 4–7× rychleji než reálný čas.

Hlavní technické riziko projektu je zavřené. **Rozsah MVP je reálný, staví se dál.** Detaily a vyplněná kritéria v `SPIKE_0.md`.

**Poslední otevřené kritérium je zavřené.** Plynulost náhledu 4K/60 se ve spiku změřit nedala (přehrávač neexistoval) — fáze 1 ji zodpověděla a **27. 07. 2026 byla přeměřena po opravě metodiky: náhled běží přesně na stropu 60Hz displeje, bez sekání.**

## ⏭️ Příští krok

✅ **Blokátor vyřešen: „černý náhled" nebyl vada přehrávače, video překrývala vadná kreslicí vrstva časové osy (27. 07. 2026 pozdě večer).** Rozhodovací experiment ze včerejšího zápisu proběhl a vyšel OBRÁCENĚ, než napovídal hlavní podezřelý: pipeline benchmarku (b) obraz nespustila — spouštěčem bylo skrytí chrome (a), protože s ním z hierarchie odchází osa. Bisekce po vrstvách a nakonec diff stromu vrstev černého a funkčního běhu ukázaly příčinu: **`TimelinePane` měl override `draw(_:)` a jeho kreslicí `ContentLayer` dostala na macOS 26 rámec přes celé okno** (0,-454 640×718 při vlastních 640×220) — tmavá výplň rohu osy se kreslila přes video. Detaily a poučení v sekci rizik.

Oprava: roh mezi pravítkem a hlavičkami kreslí samostatné `CornerView` bez `draw` (barva přímo na vrstvě), `TimelinePane` už žádný override `draw(_:)` nemá. **Ověřeno sérií screenshotů běžící aplikace: obraz jede v plném layoutu se sidebarem, osou i transportem.** Diagnostické přepínače `--no-timeline` a `--player-only` i všechny sondy z vyšetřování jsou smazané; z vedlejších nálezů viz rizika (vadný záznam o `--player-only`, zbytečná výměna `AVPlayerLayer` → `AVPlayerView`).

✅ **Krok 4 — `TimelineLayout` + `LayerDiff` v `TimelineModelu`, s testy (28. 07. 2026).** Čistá funkce z (projekt, geometrie, scroll, výběr) na `[Placement]` a množinový diff „připojit / vrátit do fondu / přepsat rámec". **+19 testů, celkem 182, 0 selhání**; ve view se nezměnilo nic, přesně podle plánu. Klíčové záruky vymáhané testy: `toMount ∪ toUpdate` = přesně viditelné klipy v pořadí placements; `toRecycle` = co viselo a už nemá (deterministicky seřazené — množina pořadí nemá, výstup ho mít musí); nic není ve dvou seznamech; duplicitní ID se nepřipojí dvakrát. `toUpdate` dostává rámec VŽDY — diff zná jen ID, ne staré rámce, a zápis rámce s vypnutými akcemi je levnější než účetnictví, které by ho ušetřilo. Property test s náhodnými projekty a okny (50 kol, seedovaný generátor).

✅ **Krok 5 — klipy jako recyklované `CALayer` (28. 07. 2026).** `ClipLayer` (výplň podle druhu stopy, obrys, `CATextLayer` se jménem — ŽÁDNÉ `draw`, viz past s `ContentLayer` v rizicích), fond vrstev a ta „desetiřádková smyčka" `placements` → `diff` v `TimelineDocumentView.refreshClips()`, volaná při scrollu, layoutu a reloadu. K tomu import: `TimelineController.loadScannedClips` staví projekt z naskenovaných klipů — obraz na V1, zvuk svázaně (`makeLinkedClips`) na A1, délka assetu z počtu vzorků a naměřené frekvence. Ověřeno okem na screenshotu běžící aplikace: klipy na V1 (modré) i A1 (zelené) se jmény.

  ⚠️ **Nová past do sbírky: SwiftUI `updateNSView` se přeskočí, když se hodnoty representable nezměnily** — a reference na controller se nemění nikdy. Osa proto po importu zůstala prázdná: projekt se naplnil (debug log: V1=5, A1=5), ale `reload()` nikdo nezavolal. Oprava: `TimelinePane` odebírá `controller.objectWillChange` přes Combine (s `receive(on:)`, protože notifikace chodí PŘED změnou). Je to bratranec pasti „SwiftUI nesleduje vnořené ObservableObjecty" z fáze 1.

  ✅ **Koukanec plynulosti scrollu potvrzen rukou (28. 07. 2026)** — scroll přes celou osu bez zadrhnutí.

✅ **Krok 6 — playhead + seek do přehrávače: HOTOVÝ, potvrzeno rukou (28. 07. 2026).** Červená `playheadLayer` přes celou výšku dokumentu (kreslí se, ověřeno screenshotem — stojí na nule). Klik/tažení v pravítku → `setPlayheadFromUser` → `AppModel.seekPlayer`: najde obrazový klip pod hlavou, případně vymění asset v přehrávači a seekne na `sourceOffset` (převod počítá model). Zpětný směr: při přehrávání jede hlava za `currentTime`; smyčce brání `isUserScrubbing` (hlavu táhne uživatel) a podmínka `isPlaying`, přesně podle `FAZE_2_VIEW.md` sekce 5. Hlava v mezeře/za koncem: posunout se smí, seekovat není kam — přehrávač zůstává.

  Odběry v `TimelinePane` zúžené z plošného `objectWillChange` na cílené publishery (`$project`/geometrie → reload, `$selection` → refresh klipů, `$playhead` → jen přepis rámce jedné vrstvy) — hlava se při přehrávání hýbe 30×/s a plošná reakce by třicetkrát za sekundu přestavovala pruhy a překreslovala pravítko.

  ✅ **„Hotovo když" kroku 6 potvrzeno rukou (28. 07. 2026):** klik do pravítka skáče monitorem, tažení scrubuje, mezerník přehrává s hlavou v synchronu, klik za posledním klipem posune jen hlavu.

✅ **Krok 7 — tažení klipů: HOTOVÝ, potvrzeno rukou (28. 07. 2026).** Cesta události přesně podle `FAZE_2_VIEW.md` sekce 4: `mouseDown` = `hitTest` + `interaction.begin` (a výběr klipu), `mouseDragged` = `preview` **jen do overlay vrstvy** (duch s poloprůhlednou výplní, při neplatném cíli červeně, vodicí čára na kandidátovi přichycení), `mouseUp` = `commit` do modelu. Do modelu se během tažení nezapisuje — to hlídá otestovaná `TimelineInteraction`, view jen předává souřadnice a kreslí.

  Undo dvěma způsoby a je to schválně (zapsáno i v návrhu): u `move` neexistuje legální mezistav → jeden `record()` před zápisem; u trimu a rollu jsou mezistavy legální → `beginInteraction`/`endInteraction`, a když se nic nezmění, krok nevznikne. Escape tažení ruší (model se nesahal), ⌘Z/⇧⌘Z jde přes `keyDown` — appka nemá `NSUndoManager`, undo drží vlastní snapshot stack z modelu. Shift při tažení vypíná přichytávání. Roll/slip modifikátory jsou krok 9.

  ✅ **„Hotovo když" kroku 7 potvrzeno rukou (28. 07. 2026):** duch při tažení, červená přes souseda a nepustí, trim okrajem, přichytávání (Shift vypíná), Escape ruší, ⌘Z vrací, výběr klikem funguje.

✅ **Krok 8 — zoom: HOTOVÝ, kotvení potvrzeno rukou (28. 07. 2026).** Pinch (`magnify`) a ⌘+kolečko na dokumentu osy; bez ⌘ jde kolečko dál a scroll view normálně scrolluje. Kotvení na kurzoru: nová geometrie → **synchronně** přerozměřit dokument → scroll tak, aby snímek pod kurzorem zůstal pod kurzorem; kotva se drží ve zlomkových snímcích (celé by při pinchi posouvaly obsah). Během tažení se zoom ignoruje (`FAZE_2_VIEW.md` 2.6). Meze 0,02–120 bodů/snímek zařezává `TimelineGeometry.setZoom` — otestovaná.

  Cesta geometrie → přerozměření → překreslení **ověřena screenshotem** (dočasná sonda `setZoom(0,15)`, po ověření smazaná): čtyři klipy vedle sebe, pravítko samo zhrublo na 30s rozteč, úzký klip zkracuje jméno. ✅ **Kotvení na kurzoru i plynulost pinche potvrzeny rukou (28. 07. 2026):** klip zůstává pod prsty, ⌘+kolečko též, při rozjetém tažení zoom nic nedělá.

✅ **Krok 9 — roll/slip, menu, zkratky, kurzory: HOTOVÝ, potvrzeno rukou (28. 07. 2026).** ⌥ na okraji vynutí roll, ⌘ v těle slip (návrh sekce 4; bez souseda spadne roll na trim — hlídá interakce). Kurzory přes `NSTrackingArea` s `.cursorUpdate` (`columnResize` gatovaný na macOS 15+, fallback deprecated `resizeLeftRight` — přesně vzorec z návrhu). Kontextové menu: Rozdělit v hlavě (aktivní jen když hlava vede vnitřkem klipu) / Smazat / Smazat s dosunutím. Zkratky: Delete maže výběr, ⌘B řeže vybrané v hlavě. Mazání bere svázaná dvojčata; všechno píše undo.

  **Mezera nalezená v návrhu a opravená v modelu: split svázaného páru.** Dosavadní `split` nechal oběma polovinám `linkID` originálu — u páru V+A by po řezu sdílely jednu vazbu tři klipy a `validate()` by hlásil `brokenLink`. Teď je `split` link-aware: řeže i dvojče a poloviny přepojuje po dvojicích (levé sdílí původní vazbu, pravé čerstvou); u nesouosého dvojčete (vzniká trimem jednoho z páru) zůstává vazba polovině s překryvem. **+6 testů, celkem 188, 0 selhání.** Vedlejší zjištění: `move` je link-aware odjakživa — dvojče jde s klipem, nesouosost vyrobí jen trim.

  ✅ Koukanec kroku 9 potvrzen rukou (28. 07. 2026): roll ⌥, slip ⌘, kurzory, kontextové menu, Delete i ⌘B fungují.

✅ **Krok 10 — vlnové průběhy (28. 07. 2026): NAPSANÝ a vlna ověřená screenshotem.** Přesně dvě vrstvy mezipaměti z návrhu 2.7: **špičky** (min/max na okno 256 vzorků, `AVAssetReader` nad `AVCompozicí` — kompozice ctí edit list, takže vlna není o 44 ms vedle zvuku; disková cache s otiskem cesta+velikost+mtime v Application Support/Waveforms) a **dlaždice** (`CGImage` klíčem asset + mocnina dvou zoomu + index, líně na pozadí; mezi úrovněmi se natahují, takže pinch mezipaměť nezahazuje). Žádný `CATiledLayer` — jeho úrovně detailu jsou vázané na měřítko vrstvy. Dlaždice se skládají jen pro viditelný výřez klipu a jsou assetové: trim ani slip je nezahazuje. U titěrných klipů se vlna i titulek schovávají úplně, nezmenšují (návrh, sekce 6). Špičky jdou z originálu, ale přes `Asset.url(usingProxies:)` — jediné místo rozhodující o souboru. Render černou s alfou → dlaždice nezávisí na světlém/tmavém režimu. **Ověřeno okem: obálka s transienty (rány sekerou) na zvukovém klipu A1 hned při prvním spuštění.**

  ✅ Koukanec kroku 10 potvrzen rukou (28. 07. 2026): vlna se při pinchi jen lehce rozmaže a po ustálení je ostrá, nic neseká; scroll přes osu plynulý. Výkonový test s 1000 klipy zůstává otevřený.

✅ **FÁZE 2 JE HOTOVÁ (28. 07. 2026): deset kroků, interakce potvrzené rukou a výkonový test splněný.** Režim `--timeline-bench` postaví syntetickou osu s 1000 dvojicemi obraz+zvuk (2000 klipů) a projede ji celou tam a zpět scrollem řízeným ČASEM (krokování po ticích by vypadlý tik schovalo — zpomalil by jízdu). Tiky přes `CADisplayLink` z `NSView.displayLink(target:selector:)`; vypadlý tik = zaseknuté hlavní vlákno.

**Výsledek: 0 vypadlých tiků na 1202 ticích, medián práce na tik 1,99 ms, maximum 2,55 ms** (dokument 40 129 bodů, ujeto 79 170 bodů, 60 Hz). Nebyla to formalita — **první běh měl 65 vypadlých tiků a medián 14,15 ms** a našel tři skutečné chyby, všechny opravené:
  1. **Lineární hledání pro každý viditelný klip každý tik.** `timeline.clip()`, hledání assetu a jména jsou O(všechny klipy); na 2000 klipech to dělalo ~240 000 porovnání za tik (~5 ms). → slovník `ClipDrawInfo` přestavovaný jen při změně projektu.
  2. **`CATextLayer.string` přepisovaný stejnou hodnotou.** Vrstva po každém zápisu rastruje text znova — desítky rastrů za tik. → zápis jen při změně (`ClipLayer.titleText`).
  3. **Zpětná smyčka dlaždic vln.** Každá na pozadí dokončená dlaždice bumpla `version` a spustila CELÝ `refreshClips` navíc k tomu scrollovacímu. → throttle odběru na 100 ms.

  ⚠️ K tomu past do sbírky: **zakryté okno pozastaví display link z `NSView.displayLink`** — benchmark pak visí na prvním tiku a nikdy nezačne. Proto si okno před měřením říká o popředí (`makeKeyAndOrderFront`) a čas se počítá až od prvního tiku. Stejná třída pasti jako „měření náhledu je platné, jen když bylo na co koukat".

## 🔄 FÁZE 7 — audio engine (rozjetá 28. 07. 2026)

Rozvrh fáze: **1)** `LoudnessMeter` (hotový, níže), **2)** per-track hlasitost a mute do přehrávání i exportu přes `AVAudioMix` (model už `AudioSettings` na stopě má), **3)** LUFS normalizace exportu — změřit mix kompozice offline průchodem, aplikovat gain podle profilu, volba profilu v UI, **4)** cross-korelační sync klopáku (FFT). Pozn.: `AVAudioEngine` ze jména fáze zatím potřeba nebyl — mix a normalizace jdou přes `AVAudioMix` + gain; nasadí se, až půjde o víc než hlasitost.

✅ **Modul 1 — balíček `AudioEngine`: `LoudnessMeter` podle ITU-R BS.1770-4 (28. 07. 2026).** Čistý Swift bez AVFoundation (vzor `SpeedRampEngine`), **20 testů, 0 selhání.**

  - **K-váhování s přepočtem koeficientů pro libovolnou vzorkovací frekvenci** (bilineární transformace analogového prototypu, tytéž konstanty jako referenční libebur128). Test drží přepočet proti tabulce koeficientů ze standardu pro 48 kHz s přesností 1e-10 — koeficienty nejsou opsané, ale odvozené, a tabulka je hlídá.
  - Bloky 400 ms s krokem 100 ms, absolutní gate −70 LKFS, relativní −10 LU pod průměrem přeživších. Kotvy ze standardu: full-scale sinus 997 Hz → −3,01 LKFS; dva kanály → +3,01 LU. Streamování po nepravidelných kusech dává výsledek shodný na 1e-9 s jednorázovým měřením (na tom stojí budoucí použití nad `AVAssetReaderem`).
  - **32-bit float headroom:** vzorky přes ±1 se měří, neořezávají (+6 dB nad FS čte +3,01 LKFS) — „nulové riziko přepalu" ze spec 7.1 začíná už u metru.
  - Profily `web` (−14 LUFS, výchozí) a `broadcast` (−23 LUFS, EBU R128) + výpočet normalizačního gainu; kruhový test měř→gain→přeměř končí na cíli.
  - **Nezávisle ověřeno proti `pyloudnorm`** (zavedená python implementace téhož standardu) na čtyřech signálech: sinus, „program" se segmenty úrovní −18 až −70 a tichem, stereo s různým obsahem kanálů, šum na 44,1 kHz. **Shoda do 0,05 LU** — hluboko pod tolerancí EBU ±0,5 LU. Na analytické kotvě (sinus −20 dBFS → −23,0103) sedí náš metr přesně; pyloudnorm je o 0,04 vedle.
  - Poučný detail z testů: bloky na rozhraní signál→ticho (75/50/25 % tónu) gate právem přežijí a integrovanou hlasitost o ~0,13 LU zředí — chování podle standardu, test to dokumentuje tolerancí, ne obcházením.

✅ **Modul 2 — per-track hlasitost a mute do přehrávání i exportu (28. 07. 2026).** Mix je vlastnost STOPY, ne klipu — Alena míchá „řeč (A1) proti hudbě (A2)". Rozložení práce:

  - **Model (+8 testů, celkem 240):** `setTrackVolume` (zařezává do 0–2, tedy do +6 dB), `setTrackMuted` (mute hlasitost NEPŘEPISUJE — po odmutování se vrací), `effectiveVolume` — jediné místo skládající mute+volume, a `Timeline.withDefaultAudioSettings()` — porovnání „změnilo se něco KROMĚ mixu?". Mix se veze v `Track.audio`, takže projektový soubor i undo snapshoty ho nesou zadarmo (test to hlídá).
  - **`CompositionBuilder` vrací `BuiltTimeline`** — kompozici + mapu „stopa kompozice → stopa osy". `audioMix(project:)` z ní staví `AVAudioMix` z AKTUÁLNÍCH hlasitostí; když všechny stopy hrají naplno, vrací `nil` a přehrávací cesta je bajt po bajtu ta ověřená z fází 3–5.
  - **Změna hlasitosti NEVYMĚNÍ player item.** Živý mix jde na běžící item (`applyAudioMix`) odběrem BEZ debounce — uživatel míchá poslechem a čtvrtsekundové zpoždění přestavby by z posuvníku udělalo loterii. Kompozice se přestavuje jen když se změní něco jiného než mix (porovnání přes `withDefaultAudioSettings`). Výměna itemu by navíc zastavila přehrávání.
  - **Export:** tentýž mix jde do `CFRRendereru` — s mixem se čte přes `AVAssetReaderAudioMixOutput` i u jediné stopy. Co slyšíš při střihu, to dostaneš v souboru.
  - **UI:** hlavičky zvukových stop mají tlačítko M (mute) a mini posuvník 0–200 % (jméno stopy se posunulo nahoru). Tažení posuvníku = jeden undo krok (vzorec trimu: `volumeDragBegan/Changed/Ended`); posuvník se během tažení nepřepisuje z modelu, poskakoval by pod myší.
  - **Ověřeno CLI `--mix-check`:** dvojí export téže osy, plná hlasitost proti A1 na 0,25×. Rozdíl integrované hlasitosti **11,99 LU proti očekávaným 12,04** (přeměřeno pyloudnorm přes afconvert) — mix jde exportní cestou správně. Druhý export zároveň cvičí `AVAssetReaderAudioMixOutput` s mixem, dosud reálně neprošlapaný.
  - *Koukanec rukou zatím neproběhl (odloženo autorem): posuvník při přehrávání mění hlasitost bez zastavení, M ztlumí, ⌘Z vrací, hodnoty přežijí uložení projektu.*

✅ **Modul 3 — LUFS normalizace exportu (28. 07. 2026).** Před exportem se změří budoucí mix a zvuk se dorovná na cílový profil. Volba v sidebaru u exportu: Bez normalizace / **Web −14 (výchozí, spec 7.1)** / Vysílání EBU R128 −23. Nastavení aplikace (UserDefaults), ne projektu — je to vlastnost dodávky, ne střihu.

  - **`LoudnessScanner` (appka):** přečte zvuk kompozice TÝMŽ aparátem jako export (`AVAssetReaderAudioMixOutput` s mixem, `.timeDomain`) a prožene ho `LoudnessMeterem` → integrovaná hlasitost + špička vzorků. Měří se výsledek, ne zdroj.
  - **Gain se násobí do vzorků v `CFRRendereru`** (`audioGainLinear`, float32 dekódování, `vDSP_vsmul` po segmentech blokového bufferu). Záměrně NE přes `AVAudioMix.volume` — dokumentace mu dovoluje jen 0,0–1,0 a normalizace potřebuje i zesilovat; stavět na nedokumentovaném rozsahu je přesně chyba z pravidla 6. S gainem se čte s `alwaysCopiesSampleData = true` (do sdílené paměti čtečky se zapisovat nesmí) a dekóduje ve float32, aby zesílení nemělo strop v celočíselném mezikroku.
  - **Strop proti clippingu: špička po zesílení ≤ −1 dBFS.** Bez limiteru je to jediná poctivá ochrana; když zasáhne, export to řekne ve statusu („gain omezen špičkami… na cíl nedosáhl"), nezamlčí. Vědomé zjednodušení: měří se špička vzorků, ne true peak — a AAC kodér smí strop o desetinky přestřelit (naměřeno −0,87 dBFS při stropu −1); dotažení na dBTP je případná budoucí práce, ne vada.
  - **Ověřeno CLI `--normalize-check` (A1 ztišená na 0,5× → materiál −28,9 LUFS) nezávislým přeměřením pyloudnorm:**
    - profil Web −14: gain by chtěl +14,9 dB, špičky povolily **+6,0 dB** → výstup −23,03 LUFS a poctivá hláška o omezení. Sedí: −28,9 + 6,0 = −22,9 (rozdíl 0,1 = gatování).
    - profil Vysílání −23 (`--broadcast`): gain +5,9 dB POD stropem → **výstup −23,11 LUFS, cíl dosažen**, špička −1,03 dBFS pod stropem.
  - *Koukanec rukou zatím neproběhl (odloženo autorem): volba profilu u exportu, hláška o hlasitosti po exportu.*

## 🔄 FÁZE 5 — projekt a export (rozjetá 28. 07. 2026)

✅ **Modul 1 — projektový soubor `.projektkrasa`: uložit, otevřít, obnovit po startu.**

  - **`ProjectFile` v TimelineModelu (+4 testy, celkem 232):** verze formátu, metadata a projekt v jeho VLASTNÍ Codable podobě — celé ticky a zdrojově kotvené uzly. Kde se spec 6.2 rozchází s pozdějšími rozhodnutími (sekundy s čárkou, výstupně kotvené uzly), platí rozhodnutí. Zápis je deterministický (`sortedKeys`) — stejný projekt = stejné bajty. Verze se čte a schvaluje PŘED obsahem: soubor z novější aplikace se odmítne srozumitelně, ne dekódovací chybou.
  - **`ProjectStore` v appce:** uložit/otevřít přes panely (⌘S, ⇧⌘S, ⌘O v menu — model se kvůli tomu přestěhoval z `ContentView` do `KrasaApp`), zapamatování posledního projektu bookmarkem a obnova při startu. **Security-scoped bookmark per asset se ukládá do souboru** — bez něj by sandbox po restartu nepustil projekt k vlastním klipům. `resolveAssets` při otevření opraví přesunuté cesty, označí nedostupné assety offline (jejich klipy ZŮSTÁVAJÍ — smazat cizí práci kvůli přejmenované složce je horší chyba než díra v náhledu) a zahodí proxy, jejichž soubor zmizel.
  - **Jeden soubor, ne balíček ze spec 6.1** — proxy jsou centrální cache s vlastním umístěním (fáze 4; spec 6.3 to sama doporučuje) a autosavy patří do Application Support, aby přežily přesun souboru. Zdůvodněná odchylka, ne opomenutí.
  - Import klipů = **nový neuložený projekt** (sken dál přepisuje celou osu — přírůstkový import je samostatná kapitola). Sidebar ukazuje jméno projektu a čas uložení. **`usesProxies` tím konečně přežívá restart** — dluh z fáze 4 splacen.
  - **Ověřeno:** CLI `--roundtrip-project` (uložit → načíst → porovnat: 5 assetů, 10 klipů, rampa přežila do posledního ticku) a **obnova napříč procesy** screenshotem — po restartu se projekt otevřel sám, bookmarky assetů se vyřešily, sidebar se přeměřil, osa i přehrávač naložené.

  ✅ **Koukanec potvrzen rukou (28. 07. 2026): projekt se ukládá i obnovuje.** Ukládání, střih, restart a návrat do stejného stavu fungují. *(Offline scénář s přejmenovanou složkou zůstává formálně neověřený okem — kód i testy na něj jsou.)*

✅ **Modul 2 — autosave a obnova po pádu (28. 07. 2026).** Záloha 5 s po poslední změně a při ukončení aplikace, jen když se projekt liší od **baseline** (poslední uložený/otevřený stav; u čerstvého skenu sken samotný — pouhé spuštění zálohu nevyrábí). Sloty v Application Support: otisk cesty projektu + jeden pro neuložený projekt. Obnova: při otevření projektu se nabídne záloha novější než soubor, při startu bez projektu záloha neuloženého; obnovená práce se dál hlásí jako „neuloženo" a autosave ji chrání dál. Indikátor „neuloženo" v sidebaru.

  - **Nalezená a opravená chyba:** `nil` baseline při startu označila prázdný projekt za neuložený a debounce ho za 5 s zbytečně zazálohoval — příští start by nabízel „obnovu" prázdného projektu. Bez baseline teď špinavo není; obnovený neuložený projekt dostává baseline = prázdný projekt (porovnání s `Project.empty()` nejde použít napřímo — razí náhodná ID stop).
  - **Ověřeno CLI `--autosave-check`:** čistý po skenu, špinavý po střihu, záloha se zapíše, sedí s projektem a jde zahodit.
  - ⚠️ Metodická poznámka: headless CLI běhy aplikace se občas zaseknou před vytvořením okna (`.task` pak nevystartuje) — vypadá to jako visící kód, ale je to vrtoch prostředí; opakované spuštění projde. Stálo to hodinu vyšetřování, které ale odhalilo tu skutečnou chybu s baseline.

  ✅ **Koukanec modulu 2 potvrzen rukou (28. 07. 2026): obnova po pádu funguje.**

✅ **Modul 3 — export přes `AVAssetWriter`: HEVC 4K/30 CFR z originálů (28. 07. 2026).**

  - **`CFRRenderer` zobecněn:** `OutputFormat` (ProRes+LPCM pro mezisoubory / **HEVC+AAC pro dodávku** — AAC u dodávky nevadí, soubor se už nereimportuje a priming ctí přehrávače), pevný `outputSize` (plátno projektu — video kompozice sjednotí mix rozlišení a rotací), **více zvukových stop přes `AVAssetReaderAudioMixOutput`** (A1+A2; per-track hlasitost je věc audio enginu fáze 7) a hlášení průběhu z resampleru. Ověřená časová logika — mřížka, `mediaTimeScale` na video vstupu, zero-order hold — NEDOTČENÁ.
  - **Export v appce:** vždy Z ORIGINÁLŮ (proxy je poloviční a jen na střih), kompozici staví tentýž `CompositionBuilder` jako náhled (včetně ramp), `.timeDomain` na zvuku, HEVC 50 Mbit + AAC 256k do `.mp4`, ukazatel průběhu v sidebaru, ⌘E v menu.
  - **Ověřeno CLI exportem s rampou a sondou MediaProbe:** 3840×2160 HEVC, přesně 30,00 fps, **CFR s kolísáním 0,0 %** (past s timescale 600 nezafungovala — `mediaTimeScale` je nastavená), **4739 snímků = přesně 157,967 s osy**, AAC 2ch 48 kHz, ~48 Mbit; kódování 2× rychleji než reálný čas. Pozn.: cesta mixu více stop (A2 s hudbou) zatím reálně necvičená — A2 je v testovacím projektu prázdná a kompozice ji vynechává.

  ✅ **Koukanec modulu 3 potvrzen rukou a uchem (28. 07. 2026): export funguje, video je plynulé i se zvukem.**

✅ **Modul 4 — dotaz při zahazování neuložené práce (28. 07. 2026).** Jeden dialog „Uložit / Neukládat / Zrušit" na třech místech, kde se zahazuje rozdělaná práce: ⌘Q (přes `NSApplicationDelegate.applicationShouldTerminate` — SwiftUI vlastní hák nemá, delegát je přišitý přes `@NSApplicationDelegateAdaptor`), otevření jiného projektu a import klipů (= nový projekt). Tři rozhodnutí:

  - **„Neukládat" zahazuje i autosave** — je to výslovné rozhodnutí uživatele; příští start by jinak „obnovoval" práci, kterou právě zahodil. „Uložit" u neuloženého projektu jde přes „Uložit jako" a zrušení toho panelu ruší i zavírání (hlídá se `isDirty` po návratu, ne návratová hodnota panelu).
  - **Dotaz přichází až PO výběru v panelu** (otevřít/import), ne před ním — kdyby uživatel řekl „Neukládat" a pak panel zrušil, projekt by zůstal, ale záloha už by byla pryč.
  - **CLI běhy (`--…`) se neptají** — `terminate(nil)` v headless režimu by visel na modálním dialogu. Ověřeno: `--autosave-check` po změně prošel a aplikace se ukončila i se špinavým projektem.

  **v0.5 „MVP nula" je tím KOMPLETNÍ** — před námi KILL-GATE 1: sestříhat touhle appkou celou reálnou svatbu. *(Koukanec dialogu rukou zatím neproběhl: ⌘Q se změnami, Uložit/Neukládat/Zrušit, dotaz před otevřením i importem.)*

## ✅ FÁZE 4 — proxy a výkon (HOTOVÁ až na kritérium reálného materiálu, 28. 07. 2026)

✅ **Modul 1 — `ProxyStore`: generování proxy a přepínač „stříhat z proxy".** ProRes 422 Proxy v polovičním rozlišení, VFR zploštěné na CFR, zvuk LPCM — přesně rozhodnutí z plánu, render dělá sdílený `CFRRenderer` (tentýž kód jako ověřený `Flatten`). Rozložení:

  - **`CFRRenderer` umí `outputScale`** — škáluje se při dekódování přes `AVAssetReaderVideoCompositionOutput` s `renderSize` (ne po snímcích na CPU); kompozice zároveň aplikuje `preferredTransform`, výstup se zapisuje s identitou. Cadence kompozice = cílová mřížka, zero-order hold resampleru projde 1:1.
  - **Cache** v Application Support/Proxies s otiskem `cesta|velikost|mtime` (stejný vzorec jako vlny); zápis přes `.partial` + přejmenování — nedopsaný soubor po pádu nesmí vypadat jako hotová proxy.
  - **Generuje se na pozadí po importu**, postupně (ProRes engine je jeden); klip bez proxy dál jede z originálu (`url(usingProxies:)` má fallback).
  - **Proxy se k assetům přišívají po KAŽDÉ změně projektu** — undo vrací snapshoty z doby před dokončením proxy a bez opětovného přišití by ⌘Z tiše přepnul přehrávání na originály. Smyčka nehrozí, `setProxy` při shodě nezapisuje.
  - Přepínač v sidebaru je **per projekt** (`Project.usesProxies`, rozhodnutí z fáze 2), bez undo — je to režim práce, ne střih. Kompozice se staví přes `Asset.url(usingProxies:)` — jediné místo volby souboru.
  - **Ověřeno sondou na všech 5 vygenerovaných proxy: 1920×1080, `apco`, CFR s kolísáním 0,0 %, LPCM 48 kHz, edit list 1:1** — a hlavně zachované PŘESNÉ frekvence originálů (30,01 / 59,68 / 60 / 120 fps), žádné zaokrouhlení na katalogové hodnoty. Velikosti 196–470 MB na klip: ProRes je velký, proxy je o seeku (6,2 ms proti 41–95 ms), ne o místě.

  ✅ **Koukanec potvrzen rukou (28. 07. 2026): proxy fungují a scrubování je znatelně svižnější.** Naměřených 6,2 ms proti 41–95 ms je tedy i subjektivně cítit — přesně efekt, kvůli kterému proxy jsou.

✅ **Modul 2 — správa úložiště (28. 07. 2026): externí disk a mazání cache.** Volba složky přes `NSOpenPanel` se security-scoped bookmarkem (entitlements read-write + app-scope bookmarky už v projektu byly); ve zvolené složce se dělá podsložka „Krása Proxy", ať se hashované soubory nesypou do kořene disku. Odpojený externí disk = tichý návrat k výchozí složce, klipy jedou z originálů. Mazání cache NEJDŘÍV odšije proxy z projektu — kompozice nesmí ani chvíli ukazovat na mazané soubory. Sidebar ukazuje umístění a velikost cache. Po restartu se hotové proxy najdou otiskem samy — ověřeno okem: „výchozí složka aplikace · 1,66 GB" hned po startu.

  ⚠️ Poznámka k restartu: `usesProxies` je per projekt a projekt se zatím při každém startu staví znovu ze skenu — přepínač se tedy vrací na vypnuto. Srovná se to s projektovým souborem ve fázi 5, není to vada proxy.

  ✅ **Koukanec modulu 2 potvrzen rukou (28. 07. 2026): externí disk funguje, proxy se vygenerovaly znovu do nového umístění.** Kritérium plánu „proxy jde vygenerovat na externí disk" je tím splněné. *(Neověřené drobnosti: „Smazat proxy" a start s odpojeným diskem — kód na to je, oko na tom nebylo.)*

  **Zbývá z fáze 4:** kritérium „200 GB projekt se stříhá plynule" — chce reálný svatební materiál, ne pět testovacích klipů.

## ✅ FÁZE 3 — speed ramping ostrý (HOTOVÁ 28. 07. 2026)

✅ **Modul 1 — `CompositionBuilder`: přehrávač hraje CELOU OSU.** `AVMutableComposition` z timeline projektu: stopa kompozice na stopu osy, výřez zdroje každého klipu počítá model (`sourceStart` + `sourceConsumption`), časy výhradně v timescale 90 000 (nikdy sekundy s plovoucí čárkou), soubor vybírá `Asset.url(usingProxies:)`. Kompozice se přestavuje při každé změně projektu (import, střih, undo) s debounce 250 ms. **Ověřeno průjezdem hranice klipů:** přehrávání běželo v čase 0:34 na kompozici, kde sólo první klip končí ve 26 s — hraje sekvence, ne soubor.

  **Vazba hlava ↔ přehrávač z kroku 6 se tím ZJEDNODUŠILA:** snímek osy je přímo čas kompozice (`CompositionBuilder.time/frame`), per-klipové mapování přes assety je smazané. Sidebar dál umí sólo poslech zdroje (`PlayerContent.solo`) kvůli kontrole klipu a benchmarkům; klik do pravítka vrací přehrávač na osu.

✅ **Modul 2 — rychlostní křivky hrají v kompozici (28. 07. 2026).** Klip s rampou se v kompozici škáluje po úsecích (`scaleTimeRange` POZPÁTKU — vzorec ověřený nástrojem `Ramp` ve Spiku 0), mez skoku rychlosti 1,5 %, `.timeDomain` korekce výšky na player itemu. Rozložení práce:

  - **Uzly rampy jsou kotvené ve ZDROJOVÉM čase** (rozhodnutí z návrhu modelu: zpomalení má po trimu zůstat „na hodu kyticí"), kdežto `SpeedRampEngine` počítá po výstupní ose. Most: engine umí `anchoredToSource(_:)` (výstupní ofsety dopočítá z průměrné rychlosti intervalů — táž kvadratura jako integrální tabulka, takže uzly leží na svých zdrojových pozicích přesně) a **okénkovou segmentaci** — klip po trimu pokrývá jen výsek křivky. **53 testů enginu.**
  - **`TimelineModel` závisí na `SpeedRampEngine`** (oba čistý Swift, dál se testují i na Linuxu). Vyměněný vnitřek `sourceConsumption`/`sourceOffset` přesně podle plánu — operace se nemusely přepisovat. Meze trimu (`remainingSourceFrames`, `availableSourceFramesBefore`) se u rampy přepočítávají rychlostí křivky. **`trimStart` a `slip` přešly na `sourceOffset`** — dosavadní vzorec `sourceStart + sourceTime(delta)` platil jen při 1×. Nová operace `setSpeedRamp` (link-aware — dvojče dostane tutéž křivku, jinak se rozejde obraz se zvukem; zrychlení za konec souboru operace odmítne), validace `invalidSpeedRamp`, `RampPlaybackPlan` — segmentace v celých tickách (kumulativní hranice, poslední úsek dotažený na spotřebu). **208 testů modelu.**
  - Křivka enginu se staví nad celou doménou zdroje assetu (před prvním uzlem a za posledním jede krajní rychlostí), takže pozice klipu na křivce je prosté `outputTime(atSource: sourceStart)` a trim/slip/split nemají zvláštní případy.
  - **Zaokrouhlení na hranici sekund→ticky: dolů s tolerancí 1e-3 ticku.** Referenční hodnota drží: klasický ramp přes 5 s spotřebuje **přesně 281 250 ticků** (3,125 s). Split rampovaného klipu uprostřed zpomalení smí kvantizací `sourceStart` ujet o jednotky ticků (1 tick × 1/rychlost, u 0,25× až 4 ticky = 44 µs) — testy to dokumentují, proti snímku (3000 ticků) je to nic.
  - **Ověřeno skriptem na reálném klipu** (dva klipy na stopě, první s rampou): délka kompozice na tick přesná (240 snímků = 720 000 ticků), 150 úseků navazuje beze zbytku, druhý klip začíná přesně na 5 s se správným zdrojem — škálování pozpátku ho neposunulo — a uprostřed zpomalení je rychlost 0,2500×.
  - **Dočasný ovladač pro koukanec:** kontextové menu klipu → „Zpomalit 0,25× (testovací rampa)" / „Zrušit zpomalení". Křivka se natáhne tak, aby klip zůstal stejně dlouhý (kotví se přes 62,5 % spotřeby). Zmizí, až modul 3 přinese editor.

  ✅ **Koukanec modulu 2 potvrzen rukou a uchem (28. 07. 2026):** plynulé zpomalení do 0,25× a zpět, klip stejně dlouhý, zvuk bez lupanců i bez „mickey-mouse" výšky, hlava v synchronu, ⌘Z/menu rampu ruší, split rampovaného klipu navazuje. Trvá: 60fps zdroj na 0,25× duplikuje ~13,5 % snímků — žlutá zóna v UI je až modul 3.

✅ **Modul 3 — `SpeedRampEditor`: HOTOVÝ, potvrzeno rukou (28. 07. 2026).** Pruh editoru mezi přehrávačem a osou; křivku ukazuje pro právě jeden vybraný klip. Rozložení práce podle pravidla „logika do modelu":

  - **`TimelineModel` (+20 testů, celkem 228):** `RampEditorScale` — svislá osa rychlosti v log₂ škále [0,125×; 8×] (0,5× a 2× stejně daleko od 1×), `rampEditorNodes`/`rampSpeedProfile` — pozice uzlů a vzorek křivky pro kreslení (vodorovná osa = výstupní snímky klipu, ta je při editaci stabilní), `addRampNode`/`removeRampNode` — uzel se pokládá NA křivku (rychlost i zdrojová kotva z aktuálního mapování; poslední smazaný uzel vrací klip na 1×), `RampNodeDrag` — tažení mapované přes základnu zachycenou při stisku (přes průběžně měněnou křivku by se chyba skládala a uzel by kurzoru ujížděl), `pureSlowdownLimit` — mez `výstupFps / zdrojFps` z NAMĚŘENÉ frekvence.
  - **Poznatek zapsaný v testech:** vložení uzlu doprostřed easeInOut přechodu mírně přerozdělí časování okolí (výsek Bézierovy křivky není Bézierova křivka téže rodiny) — rychlost a zdrojová kotva sedí přesně, výstupní pozice uzlu se smí lišit o pár snímků.
  - **`RampEditorView` (AppKit):** jen vrstvy, ŽÁDNÉ `draw(_:)` (past s celookenní `ContentLayer`). Žlutá zóna pod mezí čistého zpomalení, mřížka rychlostí, křivka jako `CAShapeLayer` path, uzly jako kolečka, varování `limitedByFrameRate` (během tažení se nepočítá — segmentace není na 60×/s — a dopočítá se po puštění myši). Dvojklik přidá uzel, tažení hýbe uzlem (svisle rychlost, vodorovně zdrojová kotva), Delete/kontextové menu maže, Escape tažení ruší. Undo vzorcem trimu: mezistavy legální, průběžné zápisy `setSpeedRamp` (link-aware — dvojče jde s sebou), `beginInteraction`/`endInteraction` = jeden krok.
  - Menu položka povýšená z „testovací rampy" na trvalý preset: „Zpomalit 0,25× (klasický ramp)" / „Zrušit rychlostní křivku" — tři uzly a tři tahy jedním klikem.
  - Ověřeno screenshotem běžící aplikace: pruh editoru sedí v layoutu, náhled hraje (žádná regrese černého obrazu), bez výběru ukazuje nápovědu.

  ✅ **Koukanec modulu 3 potvrzen rukou (28. 07. 2026):** kreslení křivky myší, náhled i zvuk podle ní, žlutá zóna podle zdroje, undo tažení jedním krokem, mazání uzlů i varování o nedosažitelné mezi — všechno sedí.

  **FÁZE 3 JE HOTOVÁ** — kritérium „nakreslíš křivku myší, náhled ji ukáže, zvuk drží" splněno a potvrzeno rukou. Výkonový test fáze 2 prošel týž den — příští krok je fáze 4 (proxy + zploštění VFR→CFR).

✅ **Kroky 2 a 3 potvrzené.** Krok 2 rukou 27. 07. 2026 (21:08); krok 3 v rámci ručního průchodu 28. 07. 2026 — checklist zahrnoval scrubování v pravítku a scroll přes celou osu, rozjetý timecode nebo ujíždějící hlavičky by nešly přehlédnout.

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
| `TimelineLayout` + `LayerDiff` | ✅ krok 4, 19 testů |
| klipy jako recyklované `CALayer` | ✅ krok 5 |
| vlnové průběhy jako `CGImage` dlaždice per zoom | ✅ krok 10 |
| kurzory, kontextové menu, klávesové zkratky | ✅ krok 9 |

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
- **`SpeedRampEngine` — první modul, zkompilovaný a otestovaný.** **53 testů**, 0 selhání, Swift 6.3.3. Bézier easing, integrace rychlostní křivky, inverzní mapování pro scrubbing, segmentace pro `scaleTimeRange` zarovnaná na hranice snímků a řízená mezí skoku rychlosti, `Codable` pro `project.json`. Ověřeno proti nezávislé Python referenci na analyticky spočitatelných případech.
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
- **`TimelineModel` — logika, geometrie a interakce časové osy.** **232 testů, 0 selhání.** Čistý Swift bez AVFoundation a bez AppKitu (jediná závislost: `SpeedRampEngine`, také čistý Swift), takže se přeloží a otestuje i na Linuxu — díky tomu byl ověřený dřív, než se sáhlo na UI.
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
- **Fáze 4 — proxy.** Hotová a potvrzená rukou; otevřené zůstává jen kritérium plynulosti na reálném 200GB materiálu (přirozeně u Kill-gate 1).
- **Fáze 5 — projekt a export.** HOTOVÁ včetně dotazu při zavírání neuloženého projektu (dialog čeká na koukanec rukou). MVP nula je kompletní — na řadě je KILL-GATE 1: sestříhat reálnou svatbu.
- **Pozor:** v sekci 8.1 specifikace jsou položky MVP odškrtnuté `[x]`. Je to seznam *rozsahu*, ne stav.

## 📝 TODO
### Cesta k v0.5 „MVP nula" (~6 měsíců při 30 h/týdně)
- **F0** Spike 0 — ověření speed rampingu — ✅ **HOTOVO 26. 07. 2026**, hlavní riziko zavřené
- **F1** Kostra, import, přehrávač, VFRDetector — ✅ **HOTOVO 26. 07. 2026**
- **F2** Timeline v AppKitu — nejtěžší UI v projektu — ✅ **HOTOVO 28. 07. 2026** (228 testů modelu, interakce rukou, výkonový test 2000 klipů bez vypadlého tiku)
- **F3** Speed ramping ostrý — ✅ **HOTOVO 28. 07. 2026** (tři moduly, potvrzeno rukou; reálný čas: dva dny místo tří týdnů)
- **F4** Proxy + zploštění VFR→CFR *(2 týdny)* — 🔄 **ProxyStore + správa úložiště hotové a potvrzené rukou (externí disk funguje); zbývá kritérium plynulosti na reálném materiálu**
- **F5** Projekt, autosave, undo, export *(3 týdny)* — ✅ **HOTOVO 28. 07. 2026 — projektový soubor, autosave s obnovou po pádu, export i dotaz při zavírání neuloženého projektu (dialog čeká na koukanec rukou)**
- 🚧 **KILL-GATE 1:** sestříhat touhle appkou celou reálnou svatbu

### Cesta k v1.0 (+~3 měsíce)
- **F7** Audio engine, 32-bit float, LUFS *(3 týdny)* — 🔄 **moduly 1–3 hotové 28. 07. 2026: `LoudnessMeter` (BS.1770-4, ověřeno proti pyloudnorm), per-track hlasitost/mute (ověřeno `--mix-check`) a LUFS normalizace exportu se stropem špiček (ověřeno `--normalize-check`: cíl −23 dosažen na 0,11 LU, strop poctivě hlášen); zbývá cross-korelační sync klopáku**
- **F8** Titulky přes WhisperKit *(2 týdny)*
- **F9** Distribuce, notarizace, Sparkle, licence *(3 týdny)* — **+ migrace na `AVVideoComposition.Configuration`** jako druhá větev pod `if #available(macOS 26.0, *)`. Ne dřív.
- 🚧 **KILL-GATE 2:** prodat deseti lidem, kteří tě neznají

### Za v1.0 — podmíněné
- **F10** AI analýza scén a kvality záběrů *(2 týdny)* — bezpečná AI, žádné právní riziko
- **F11** Rozpoznávání obličejů *(8–12 týdnů)* — tři gaty: právní, licenční, poptávkový
- **F12+** Multicam, HDR, slovenština, LUTs

### Škrtnuto
- **Svatební asistent (F6: checklist, záběrový plán, BPM plánovač).** Škrtnut 28. 07. 2026 na pokyn autora — produkt je čistě videoeditor. Pravidlo „záběry na zpomalení toč na 120 fps" tím nezaniká: říká ho žlutá zóna v editoru křivek (hotová ve fázi 3) a varování o duplikaci snímků musí zůstat v UI přiznané. Číslování fází se nemění, po F5 následuje F7.
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
- **Zpomalení potřebuje dost snímků ve zdroji: `zdrojFps × nejnižšíRychlost ≥ výstupFps`.** Ramp na 0,25× při 30 fps výstupu chce zdroj 120 fps. Naměřeno: 120 fps → 0 % duplikátů, 60 fps → 13,5 %, 30 fps → 37,5 %. **Musí to být v UI jako varování dopředu**, ne až ve výsledku — po škrtnutí svatebního asistenta (28. 07. 2026) je editor jediné místo, které to uživateli řekne: žlutá zóna v editoru křivek.
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
  - `Tests/SpeedRampEngineTests/SpeedRampEngineTests.swift` – **53 testů**
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
  - `Sources/TimelineModel/Layout.swift` – rozvržení viditelných klipů (`Placement`) a recyklační diff vrstev
  - `Tests/TimelineModelTests/` – **232 testů**
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
