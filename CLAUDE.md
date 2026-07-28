# Projekt Krása — kontext pro Claude Code

Nativní macOS videoeditor pro svatební a rodinné filmy. Swift, SwiftUI (panely) + AppKit (timeline), AVFoundation, Metal, Vision, WhisperKit.

**Komunikuj česky a tykej.** Autor projektu neprogramuje — staví appku s AI asistentem. Vysvětluj, co děláš, ale bez balastu.

## Zdroje pravdy

| Soubor | Na co |
|---|---|
| `Projekt_Krasa_Specifikace_Aplikace_v2.html` | **rozsah** — co má appka umět |
| `IMPLEMENTACNI_PLAN.md` | **pořadí a technologie** — v jakém pořadí to stavět |
| `PROJECT_STATUS.md` | **stav** — co je hotové, co je příští krok |
| `SPIKE_0.md` | **uzavřený Spike 0** — naměřené výsledky a co z nich plyne |

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
- **⚠️ Vždy nastav `videoInput.mediaTimeScale = frameDuration.timescale`.** Bez instrukce si `AVAssetWriter` zvolí timescale 600 a zapisované časy do ní kvantizuje. U celočíselných frekvencí to projde (1500/90000 = 10/600), u **29,97 / 59,94 / 23,976 i naší naměřené 30,01 fps** ne — 2999/90000 je v šestistovkách 19,993 ticku a výstup vyleze jako `CFR≈` s 5% rozptylem místo `CFR`. **Na zvukovém vstupu se `mediaTimeScale` nastavovat NESMÍ, vyhodí výjimku.** Platí pro zplošťovač, pro proxy generátor (fáze 4) i pro export (fáze 5) — všude, kde se zapisuje video.
- **Zvuk v proxy a zploštěných souborech zapisuj jako LPCM, ne AAC.** AAC by přidal vlastní priming delay, a tím rozbil přesně to, kvůli čemu se ty soubory dělají. LPCM žádný nemá.
- **`scaleTimeRange` umí jen konstantní rychlost.** Plynulá křivka = segmentace na mikro-úseky. Hotové v `SpeedRampEngine.segments(outputFrameRate:framesPerSegment:)`.
- **Segmentuj podle meze skoku rychlosti, ne podle počtu snímků.** `SpeedRamp.segmentation(outputFrameRate:maxSpeedStep:)`, **výchozí mez 0,015** (1,5 procentního bodu). Engine si počet úseků dopočítá sám z maximální strmosti křivky.
  Pevný `framesPerSegment` je špatná veličina: skok rychlosti závisí na délce klipu, takže `8` dá na 45s klipu 0,96 % a na 11s klipu 3,79 %. Mez skoku je naopak vlastnost výsledku, ne vstupu:

  | klip | `framesPerSegment = 8` | `maxSpeedStep = 1,5 %` |
  |---|---|---|
  | 11,4 s | 69 úseků, skok **3,79 %** | 182 úseků po 3 snímcích, **1,42 %** |
  | 44,9 s | 270 úseků, skok 0,96 % | 180 úseků po 12 snímcích, **1,44 %** |

  Krátký klip dostane jemnější dělení, dlouhý hrubší, oba stejnou kvalitu. Varianta s `framesPerSegment` zůstala pro srovnávací měření, ale není výchozí.
  ⚠️ **Mez nemusí být vždy dosažitelná.** Při jednom snímku na úsek je podlaha `max|dv/dt| / fps` — krátký a strmý ramp na nízké fps se pod ni nedostane. `SegmentationPlan.limitedByFrameRate` to hlásí a **UI to musí umět zobrazit**, ne to spolknout.

- **Korekce výšky: `.timeDomain` jako výchozí.** `.spectral` je fázový vokodér a **rozmazává transienty** — rána sekerou je čistý transient a to rozmazání je slyšet jako plechovost. `.timeDomain` transienty zachovává.
  Na drženém hudebním tónu by to dopadlo obráceně (tam je fázový vokodér lepší), **proto zůstává volitelné** — `.spectral` i `.varispeed` (bez korekce, výška se mění s rychlostí).
  Zpomalené záběry se ve svatebních filmech typicky podkládají hudbou, takže kvalita roztaženého zvuku je v praxi méně kritická — ale kdo nechá původní zvuk, pro toho důležitá je.
- **⚠️ Zpomalení potřebuje dost snímků ve zdroji: `zdrojFps × nejnižšíRychlost ≥ výstupFps`.** Jinak se snímky duplikují a zpomalený úsek trhá. Pro ramp na 0,25× při výstupu 30 fps je potřeba **zdroj 120 fps** — a to je přesně důvod, proč telefony nabízejí slow-mo režim, ne libovůle výrobce. Naměřeno na třech klipech, teorie sedí na desetinu procenta:

  | zdroj | potřeba | duplikátů |
  |---|---|---|
  | 120,0 fps | 120 | **0,0 %** |
  | 59,7 fps | 120 (chybí 2×) | 13,5 % |
  | 30,0 fps | 120 (chybí 4×) | 37,5 % |

  Podíl duplikátů = průměr z `max(0, 1 − v(t)·zdrojFps/výstupFps)` přes časovou osu. U zdroje na úrovni výstupu vyjde `1 − průměrná rychlost` = 37,5 %, protože průměrná rychlost klasického rampu je 0,625.

- **Z toho pravidla plyne LIMIT, ne jen varování: `maximální čisté zpomalení = výstupFps / zdrojFps`.** Posuvník rychlosti má mít pod tou hranicí **žlutou zónu** — uživatel to musí vidět předem, ne zjistit po exportu.

  | zdroj | při výstupu 30 fps | při výstupu 24 fps |
  |---|---|---|
  | 60 fps | 0,5× | 0,4× |
  | 120 fps | 0,25× | 0,2× |
  | 240 fps | 0,125× | 0,1× |


- **Persony to nemají stejně.** [Filip](Projekt_Krasa_Specifikace_Aplikace_v2.html) (primární) točí sám a může se zařídit — jemu limit stačí říct dopředu a on natočí 120 fps. [Alena](Projekt_Krasa_Specifikace_Aplikace_v2.html) (sekundární) skládá film z cizích videí od hostů, typicky 30 fps, a zařídit se nemůže. **Pro ni je duplikace snímků s přiznaným varováním legitimní chování, ne nedodělek** — ale přiznané být musí. Nikdy jí netvrď, že výsledek je plynulý, když není.
- **Vlastní `AVVideoCompositing` speed ramping neřeší — segmentace je jediná cesta.** Compositor dostane přes `sourceFrame(byTrackID:)` snímek, který kompozice pro daný `compositionTime` **už vybrala**; požádat o jiný zdrojový čas nejde. Časování určuje `CMTimeMapping` stopy, a ten je dvojice `CMTimeRange` — afinní z definice. Compositor je na pixely (efekty, prolínačky, Metal), ne na čas.
- **Proxy: ProRes 422 Proxy (`'apco'`) v polovičním rozlišení**, a při generování zploštit VFR na CFR.
- **⚠️ Proxy NENÍ kvůli přehrávání, ale kvůli SCRUBOVÁNÍ.** Přeměřeno 27. 07. 2026: `AVPlayer` doručuje 4K HEVC na stropu 60Hz displeje u všech testovacích klipů, a **fullscreen na tom nic nemění** — obraz 2,16× větší, čísla stejná. Plynulost obrazu proxy nepotřebuje. Rozdíl je v odezvě seeku: **6,2 ms u ProRes proti 41–52 ms u HEVC** podle klipu, u 120fps zdroje **95 ms**. ProRes je intra-only, HEVC musí dekódovat od nejbližšího klíčového snímku, a se zero tolerance (kterou v editoru mít musíme) to obejít nejde. Argumentovat proxy plynulostí přehrávání znamená řešit problém, který neexistuje.
  ⚠️ **Dřívější čísla „60,3 a 60,7 fps" byla vadná** — metoda počítala nejvýš jeden snímek na tik displeje a okna měřila o 0,8 % delší než sekundu, takže vycházela nad vlastním deklarovaným stropem. Opraveno; závěr o proxy se nezměnil, protože stojí na scrubování, které dotčené nebylo. Detaily v `PROJECT_STATUS.md`, sekce rizik.
- **⚠️ GPU rezidence náhledu nesleduje plochu obrazu, ale nutnost kompozice.** Změřeno 27. 07. 2026: tentýž klip a tatáž plocha dá 9,90 % s aplikací na pozadí a 0,25 % s aplikací vpředu. Dokud je náhled holé video a nic přes něj neleží, jde na displej jako samostatná vrstva a GPU se skoro nezapojí. **Ta skoro-nula není rezerva, je to varování:** jakmile ve fázi 3 přijde vlastní compositor nebo efekty, přepne se to na skládání přes GPU a čísla neporostou plynule — skočí.
- **Datový model nese u každého assetu dvě cesty — originál a volitelnou proxy — od fáze 2.** Generovat se nemusí až do fáze 4, ale struktura tam musí být hned; doplnit ji později znamená přepsat model i playback. Volba „pracovat s proxy" je per projekt, ne per klip. Časová základna se bere z originálu.
- **Jedna časová základna projektu.** Nikdy neodvozuj čísla snímků ze zdrojových časových značek.
- **Časová základna projektu: 30 fps.** Rozhodnuto 26. 07. 2026.
  Kandidátem bylo 24 fps, protože dává hlubší čisté zpomalení (ze 120fps zdroje 0,2× místo 0,25×) a je filmovější. **Rozhodl ale převod při NORMÁLNÍ rychlosti**, ne ve zpomalených úsecích:

  | zdroj → základna | poměr | výsledek |
  |---|---|---|
  | 60 → 30 | **2:1** | čisté, každý druhý snímek |
  | 120 → 30 | **4:1** | čisté |
  | 120 → 24 | 5:1 | čisté |
  | **60 → 24** | **2,5:1** | ⚠️ nerovnoměrné zahazování, viditelné trhání při panorámování |
  | 30 → 24 | 1,25:1 | ⚠️ totéž, ještě horší |

  **Naměřené klipy jsou většinou 60 fps.** Při 24 fps by tedy trhaly běžné záběry — a to kvůli výhodě, která se projeví jen ve zpomalených úsecích. Zpomalené záběry jsou menšina stopáže, panorámování ne.
- **Seek se zero tolerance + coalescing** podle Apple QA1820.
- **WhisperKit** (`argmaxinc/argmax-oss-swift`), model `large-v3-turbo`. Ne whisper-small — pro češtinu má 34–38 % chybovost.
- Minimální macOS 14.0 pro běh, novější API runtime gatovaná.

## Naměřeno na reálných klipech (`MediaProbe`, 25. 07. 2026)

Pět klipů ze Samsungu, 4K HEVC. Čísla a metoda v `MediaProbe/RESULTS.md`.

- **VFR je výchozí stav, ne výjimka.** Ani jeden z pěti klipů nemá čistě konstantní časování. Nepiš kód, který předpokládá pevnou délku snímku, a pak k němu dodělávej VFR větev — začni od proměnlivého časování.
- **Zvuk NIKDY nečti ze syrové tabulky vzorků.** Všech pět klipů má na zvukové stopě edit list, který zahazuje prvních **44 ms** (priming AAC kodéru). Čti přes `AVComposition` nebo respektuj `AVAssetTrack.segments` — obojí edit list ctí. Kdo ho ignoruje, dostane zvuk posunutý o 44 ms a bude tu chybu hledat v synchronizaci, ne ve čtení.
- **`nominalFrameRate` lže.** U slow-mo klipu hlásí 119,369 fps, naměřeno 120,000. Je to metadata, ne měření. **Časovou základnu projektu z něj neodvozuj** — to je jen jiná formulace už platného pravidla o jedné časové základně.
- **Slow-mo klip je opravdové 120 fps**, ne 30fps stopa se zpomalením v edit listu. Edit list obrazu je u všech pěti klipů 1:1. Ta druhá varianta ale existuje a `VFRDetector` s ní musí počítat — u klipů z iPhonu bývá běžná.
- **Hardwarový ProRes engine potvrzen měřením.** Zploštění do ProRes 422 Proxy ve 4K běželo **257–426 fps** podle klipu, tedy 4–7× rychleji než reálný čas. Softwarové kódování by takhle rychlé nebylo. Otevřená otázka z plánu (sekce 9) je zodpovězená.
- **Rozlišuj zahozený snímek od proměnlivého časování.** Vzorek, který je celočíselným násobkem délky snímku, je zahozený snímek — opraví se doplněním duplikátu. Skutečně nepravidelná délka vyžaduje přepočet časování. Je to rozdíl v ceně opravy o řád. `MediaProbe` to už rozlišuje.

## Prostředí (ověřeno 25. 07. 2026)

- **Swift 6.3.3** (`swiftlang-6.3.3.1.3`), target `arm64-apple-macosx26.0`.
- **Xcode nainstalovaný**, aktivní v `/Applications/Xcode.app`. SDK `MacOSX26.5.sdk`.
- ⚠️ **Deployment target nového Xcode projektu nastav ručně na macOS 14.0.** Výchozí hodnota by byla 26.0, což je proti rozhodnutí výše a tiše by ti povolilo API, které na cílových strojích neexistuje. V SwiftPM balíčcích totéž přes `platforms: [.macOS(14)]`.
- Testovací klipy jsou v `TestClips/` — gitem ignorované, do repozitáře nepatří.

## Hotové moduly

### `SpeedRampEngine/`
Matematika rychlostní křivky. Čistý Swift, žádné závislosti. **53 testů, ověřeno.**

```swift
let ramp = try SpeedRamp.classicSlowMotion(sourceDuration: 8.0, slowSpeed: 0.25)
let plan = try ramp.segmentation(outputFrameRate: 30, maxSpeedStep: 0.015)
// plan.segments, plan.framesPerSegment, plan.limitedByFrameRate
```

Referenční hodnota: ramp 1,0 → 0,25 → 1,0 přes 5 s spotřebuje **přesně 3,125 s** zdroje. Když ti při stavbě kompozice vyjde jiné číslo, chyba je v převodu na `CMTime`, ne v matematice.

Testy pustíš přes `cd SpeedRampEngine && swift test`.

### `TimelineModel/`
Logika, geometrie a interakce časové osy. Čistý Swift, jediná závislost
`SpeedRampEngine` (také čistý Swift), **žádné AVFoundation ani AppKit** —
přeloží se a otestuje i na Linuxu. **254 testů, ověřeno.** Od fáze 3 umí
`sourceConsumption`/`sourceOffset` rychlostní křivku (uzly kotvené ve
zdrojovém čase) a `rampPlaybackPlan` vydává segmentaci v celých tickách
pro `scaleTimeRange`.

```swift
var project = Project.empty()                        // V1 + A1 + A2
project.addAsset(asset)
let clip = try project.makeClip(assetID: asset.id)   // model razí ID i délku
try project.insert(clip, onTrack: project.timeline.tracks[0].id)
try project.split(clipID: clip.id, at: Frames(120))
assert(project.validate().isEmpty)
```

**Dvě časové soustavy, hranice jen na dvou místech:**
`Frames` (celé snímky na ose, 30 fps) ↔ `SourceTime` (zlomek ve zdroji), přes
`timeline.sourceTime(_:)` a `timeline.availableFrames(from:)`. Ta druhá zaokrouhluje
**vždy dolů** — nahoru by dovolila trim o snímek za konec souboru. Převod `Frames`
na sekundy záměrně neexistuje, aby nešlo osové snímky převést frekvencí assetu.

**Spotřebu zdroje počítá jen `sourceConsumption(of:)`** a pozici ve zdroji jen
`sourceOffset(in:atFrame:)`. Fáze 3 vymění vnitřek těch dvou funkcí; kdyby si to
počítala každá operace po svém, přepisuje se jich šest.

**`CMTime` není `Codable`**, proto vlastní `SourceTime`. Ověřeno v dokumentaci.

**`TimelineGeometry`** je matematika pro `TimelineView`: mapování čas↔pixel při zoomu,
viditelný rozsah (binárním půlením, ne průchodem), rozvržení stop, hit testing s okraji
klipů, přichytávání. Do AppKit view piš jen kreslení a události — co v něm bude navíc,
to už nikdo neotestuje.

⚠️ **Šířka úchopu okraje a tolerance přichytávání jsou v BODECH, ne ve snímcích,**
a přepočítávají se zoomem. Ve snímcích by po odzoomování okraj klipu zabíral zlomek
pixelu a nešel by chytit; po přiblížení by přichytávání skákalo přes půl obrazovky.

**`TimelineInteraction`** je stavový automat tažení: `begin(hit:)` při stisku,
`preview(atX:y:)` při každém pohybu (čistá funkce, model se nesahá), `commit(atX:y:into:)`
při puštění. Druh tažení plyne z toho, co bylo pod myší; `forcing:` ho přepíše na
`roll` nebo `slip`.

⚠️ **Během tažení klipu se do modelu NEZAPISUJE.** Každý mezistav při přetahování přes
souseda by byl překryv, tedy chyba, a to šedesátkrát za sekundu. `beginInteraction` /
`endInteraction` na `UndoStacku` je jen pro trim a roll, kde jsou mezistavy legální.

Testy pustíš přes `cd TimelineModel && swift test`. Návrh a zdůvodnění v `FAZE_2_TIMELINE.md`.

### `AudioEngine/`
Měření hlasitosti podle ITU-R BS.1770-4 (na něm stojí EBU R128) a cross-korelační synchronizace nahrávek. Čistý Swift, žádné závislosti (vlastní FFT — Accelerate by zabil přeložitelnost na Linuxu). **32 testů; hlasitost nezávisle ověřena proti `pyloudnorm` — shoda < 0,05 LU** (tolerance EBU je ±0,5 LU); sync na reálném zvuku najde posun s chybou < 0,1 ms i při SNR −3 dB.

```swift
// sync klopáku: kam na osu reference patří začátek kandidáta
let match = WaveformSync.offset(reference: cameraAudio, candidate: lavAudio,
                                sampleRate: 48_000)
// match.offsetSeconds (kladné = rekordér spuštěn později), match.confidence
// (0–1; < 0,2 = nesouvisející nahrávky — NIKDY nepoložit mlčky)
```

```swift
var meter = LoudnessMeter(sampleRate: 48_000, channelCount: 2)
meter.addInterleaved(buffer)      // nebo add([[Float]]) po kanálech, streamovaně
let lufs = meter.integrated       // nil = ticho nebo míň než 400 ms
let gainDB = LoudnessNormalization.gainDecibels(
    measured: lufs!, target: LoudnessProfile.web.targetLUFS)   // web −14, broadcast −23
```

Vstup se NEOŘEZÁVÁ — 32-bit float zdroje (DJI Mic, Zoom F3) nesou hodnoty přes ±1 a metr je měří správně; ořez je věc až finálního zápisu. Koeficienty K-váhování se přepočítávají pro libovolnou vzorkovací frekvenci; tabulka ze standardu pro 48 kHz je drží testem. Testy: `cd AudioEngine && swift test`.

## Co do projektu nepatří

- **Licencování a freemium — odloženo 28. 07. 2026 na pokyn autora: aplikace bude zatím FREE.** Ceny a PRO verze ve specifikaci (1 490 Kč) neplatí. Kill-gate 2 přeformulován v plánu na „deset cizích lidí ji použije" místo „prodat".
- **Svatební asistent (checklist, záběrový plán, BPM plánovač) — škrtnut 28. 07. 2026 na pokyn autora.** Produkt je čistě videoeditor; specifikace (sekce 4.4) ho sice obsahuje, ale platí plán. Pravidlo „záběry na zpomalení toč na 120 fps" tím nezaniká — říká ho žlutá zóna v editoru křivek a duplikace snímků musí zůstat v UI přiznaná.
- Optical flow dopočet mezisnímků — škrtnuto, je to výzkumný problém.
- Rozpoznávání obličejů — až za v1.0 a jen po projití právního a licenčního gate (viz plán, fáze 11).
- Freeze frame a zpětné přehrávání v `SpeedRampEngine` — rozbilo by invertibilitu mapování.
