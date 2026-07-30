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
- **Fotka hraje přes „still movie" mezisoubor (`StillMovieStore`, fáze 12).** Fotka nemá video stopu a do `AVComposition` se vkládat nedá — vyrobí se z ní JEDNOU film o jednom ProRes snímku v rozměru plátna s VPÁLENÝM aspect-fitem (a narovnanou EXIF orientací), a kompozice ho roztáhne `scaleTimeRange`. Vpálený aspect-fit je záměr: mezisoubor se chová jako běžné video, bez přechodů/Ken Burns nevzniká video kompozice a GPU baseline platí i s fotkami. Cache s otiskem cesta|velikost|mtime|plátno, vzorec proxy.
- **`AVVideoCompositionCoreAnimationTool` se nepoužívá — titulky do exportu vypaluje `frameDecorator` v `CFRRendereru` (rozhodnuto 29. 07. 2026, fáze 11).** Ten nástroj je dokumentovaný pro `AVAssetExportSession`, kterou projekt schválně nepoužívá (ignoruje `frameDuration`); jeho chování na cestě `AVAssetReader`+`AVAssetWriter` dokumentace nepopisuje — pravidlo 6. Dekorátor přimíchá předrenderovaný titulek (CoreImage, NV12) jen do snímků, kde titulek leží; ostatní projdou bajt po bajtu nedotčené (změřeno: odchylka mimo titulek 0,14). Typografii šablon drží `TitleExportRenderer.font(for:)` a `TitleOverlay.font(for:)` — měnit se musí SPOLU.
- **Barevné presety (F13) jedou přes vlastní `AVVideoCompositing` (`ColorVideoCompositor`), NE `applyingCIFiltersWithHandler` (rozhodnuto 29. 07. 2026, hotové v modulu 2).** Ten inicializátor filtruje jen „first enabled video track" — naše kompozice má od F10 víc drah (A/B rozklad prolínaček), klipy na dráze B by filtr nedostaly; staví si vlastní instrukce (zahodil by opacity/transform rampy i aspect-fit) a `frameDuration` si bere z `nominalFrameRate`, o kterém máme změřeno, že lže. Provedení: `CompositionBuilder.computeSpans` je JEDINÉ místo sémantiky obrazové kompozice — bez presetů z něj jdou standardní instrukce (vestavěný kompozitor), s presety vlastní `ColorCompositionInstruction` (objekt `AVVideoCompositionInstructionProtocol`, NE podtřída standardní instrukce — player item kompozici KOPÍRUJE a kopie podtřídy by přes NSCopying rodiče přišla o přidaná pole). Bez presetu/přechodu/KB se video kompozice dál nestaví (GPU baseline platí); s presety je skok medián ~24 % (změřeno `--color-gpu`). Vzhled presetů drží JEN `ColorPresetFilter` v `ColorCompositor.swift`.
- **⚠️ Dvě pasti CoreImage v compositoru (obě chytila kvantitativní kontrola `--color-check`):** ① pracovní prostor CI i cíl renderu musí být TENTÝŽ prostor odvozený z atributů zdrojového bufferu (`CVImageBufferCreateColorSpaceFromAttachments`) — jinak round trip posouvá středy (~15 jasu) a směsi vycházejí lineárně, zatímco vestavěný kompozitor míchá kódované hodnoty; ② `CIColorMatrix` počítá na NEpremultiplikovaných hodnotách — průhlednost se škáluje JEN přes alfu, škálování RGB+alfa násobí barvu průhledností dvakrát (směs vyšla o²).
- **Vlastní `AVVideoCompositing` speed ramping neřeší — segmentace je jediná cesta.** Compositor dostane přes `sourceFrame(byTrackID:)` snímek, který kompozice pro daný `compositionTime` **už vybrala**; požádat o jiný zdrojový čas nejde. Časování určuje `CMTimeMapping` stopy, a ten je dvojice `CMTimeRange` — afinní z definice. Compositor je na pixely (efekty, prolínačky, Metal), ne na čas.
- **Miniatury na klipech (F18/M5): dlaždice kotvené ve ZDROJOVÉM čase, generování odložené, dokud se osa hýbe.** Kotvení ve zdroji (klíč `soubor|úroveň|index|hrana|scale`, jedna dlaždice na 96 bodů) znamená, že trim a slip dlaždice nezahodí, jen posunou výřez — na hranách klipu se zařezávají, jak to dělá Premiere i FCP. Návrhové rovnoměrné dělení klipu by po každém trimu zahodilo celou sadu, šedesátkrát za sekundu při tažení úchytu.
  ⚠️ **Odklad není optimalizace, ale podmínka brány R1.** Kreslení pásu stojí 0,10–0,13 ms na tik (rozpočet 16,67), ale generování za jízdy srazilo scroll o **2 vypadlé tiky** při práci 0,34 ms na tik: dekodéry na pozadí soutěží s hlavním vláknem o výpočetní čas, a to se v práci na tik nikdy neukáže. `ThumbnailStore.deferGeneration()` volá `TimelinePane.syncChrome()`, tedy každý posun výřezu; požadavky se dál sbírají a přeteklé padají zezdola (zásobník, ne fronta — poslední požadavek je to, na co se uživatel kouká).
- **⚠️ V kreslicí cestě osy (`refreshClips`, per klip a tik) se NESMÍ: brát `NSColor.cgColor`, číst `CALayer` vlastnosti ani předávat struktury s referenčními poli hodnotou.** `cgColor` dynamické barvy vyhodnocuje poskytovatele, gettery `CALayer` konzultují probíhající transakci a `ClipDrawInfo` nese `Asset` s URL a poli, takže každé volání je několik retain/release. Změřeno na M5: barvy v early-out cestách ~0,3 ms na tik, vlastnosti a předávání dalších ~0,12 ms — z ničeho, co by bylo vidět. Řešení: barvy až za guardem, stínové příznaky viditelnosti a rozhodnutí „volat vůbec?" v `apply`, ne uvnitř volané funkce.
- **⚠️ Nová cesta do modelu si musí meze ZKUSIT, ne popsat.** Přetažení z knihovny (F18/M9) rozhoduje o tom, jestli je drop legální, provedením operace na KOPII projektu — vlastní tabulka pravidel („na V1 patří video a fotky") by se s modelem rozešla. A pozor na opačný extrém: podmínka „výsledek musí projít `validate()` bez porušení" udělá z jedné cizí vady zámek na celé vkládání (chytil `--library-check`, když do projektu přišel asset bez naměřené frekvence) — porovnávej **počet** porušení před a po.
- **⚠️ V SwiftUI `Image.resizable().aspectRatio(contentMode: .fill)` nahlásí větší velikost, než jakou dostal.** `ZStack` se pak rozvrhne podle obrázku a následné `clipped()` odřízne i to, co v něm leželo vedle (v M9 tím zmizely VŠECHNY badge na kartách knihovny a měření to nevidělo — chytil až screenshot). Popisky a překryvy patří do `.overlay` ZA `frame`+`clipped`, ne do téhož `ZStacku`.
- **⚠️ `Project.duration` je O(klipů) a alokuje přitom dvě pole** (`flatMap` + `map` v `Queries.swift`) — na 2000 klipech **~1,5 ms**. V kreslicí ani scrollovací cestě se volat nesmí; kdo ji potřebuje často, ať si hodnotu uloží a obnovuje ji při změně projektu (`TimelineOverviewView.cachedTotalFrames`). Chytilo se to v M6 dvakrát: v přehledu osy (medián práce na tik 0,95 → 2,45 ms) a v pravítku, kde `drawExportRange` volal `hasExportRange` i `exportRange`, tedy `duration` DVAKRÁT za každé kreslení, jen aby zjistil, že výřez není nastavený (kreslení pravítka 0,88 → 0,08 ms). Totéž platí o každé jiné „nevinné" vlastnosti modelu, která iteruje klipy.
- **⚠️ Scrollovací tik měří i PROBUZENÍ vlákna, takže méně práce jinde ho umí prodloužit.** Změřeno třikrát nezávisle (anomálie `beats` v M3/M5 a A/B na jediném řádku pravítka v M6, vždy rozptyl 0,02 ms): když hlavní vlákno mezi tiky nemá co dělat, `medianWorkMs` z `--timeline-bench` STOUPNE — u pravítka z 0,97 na 1,95 ms po odebrání 0,8 ms práce. Součet práce na snímek se nemění a vypadlé tiky ne. **Nevracet optimalizace zpátky podle toho čísla** a při srovnávání sessions vždycky říct, co se z frame budgetu kde platí.
- **⚠️ „Nula vypadlých tiků" NENÍ na autorově stroji deterministické kritérium.** Naměřeno 30. 07. 2026: v jednom sezení dal tentýž kód M4 dvakrát 2 výpadky a kód M5 (který práci PŘIDAL) sedmkrát 0–2. Load average se přes sezení hýbe mezi 1,6 a 2,2 a rozhoduje o tom víc než náš kód. **Poctivě se dá posuzovat jen ABBA v jednom sezení a práce na tik** (ta je stabilní na 0,02 ms). Absolutní nula je vlastnost klidného stroje.
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
- **Zpětné přehrávání (JKL, F17): naše kompozice ho UMÍ, ale za cenu 84 % rychlosti.** Změřeno 29. 07. 2026 (`--jkl-check`) na 4K HEVC bez proxy: `canPlayReverse` i `canPlayFastReverse` hlásí `true`, vpřed 1/2/4× jede na 97–98 % slíbeného, pozpátku −1/−2× jen na **84 %**. Ptát se ale MUSÍME dál (jiný zdroj může říct `false`) — proto fallback na krokování časovačem, který se v praxi nespustí, a proto ho `--jkl-check` **vynucuje** (`forcesSteppingFallback`): nespouštěná cesta tiše shnije. ⚠️ **Od macOS 10.9 jde každý hotový item přehrát mezi 1,0 a 2,0 i když `canPlayFastForward` je `false`** — ta vlastnost od té doby značí rychlosti NAD 2,0 (hlavička `AVPlayerItem`), takže ptát se jí na 2× je chyba.
  Krokovací fallback si vede VLASTNÍ kurzor: `player.currentTime()` odpovídá poslednímu dokončenému seeku a coalescing by krok zasekl na místě. Uživatelský seek kurzor srovná (jinak by si hlavu přetahovaly).
- **WhisperKit** (`argmaxinc/argmax-oss-swift` v1.0.0, produkt `WhisperKit`) — zapojený od fáze 8. ⚠️ **Past v názvosloví modelů:** OpenAI „large-v3-turbo" se v repozitáři `whisperkit-coreml` jmenuje **`openai_whisper-large-v3-v20240930`** (podle data vydání); přípona `_turbo` tam značí komprimované varianty WhisperKitu — jinou věc. Ne whisper-small — pro češtinu má 34–38 % chybovost. Model (~1,5 GB) se stahuje při prvním použití do kontejneru (jediné síťové použití aplikace, entitlement `network.client`).
- **`AVAudioMix.volume` má dokumentovaný rozsah jen 0,0–1,0** — zesilovat přes něj se NESMÍ (nedokumentované chování). Normalizační gain se násobí přímo do vzorků (float32, `vDSP_vsmul` v `CFRRendereru`), se stropem **−1 dBTP** (true peak, od F16 — `TruePeakMeter` v AudioEngine, 4× převzorkování; špička vzorků mezivzorkové špičky neviděla a na reálném klipu lhala o 1,2 dB), který se při zásahu poctivě hlásí.
- **Dekodéry AAC se neshodnou na rozjezdu:** afconvert vs. čtení přes `AVComposition` se liší přesně o 528 vzorků (11,00 ms). Interní cesty appky (sync, přehrávač, export, měření) čtou VŠECHNY přes kompozici, takže jsou vzájemně konzistentní — další důvod pravidla „zvuk jen přes AVComposition".
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
Logika, geometrie a interakce časové osy. Čistý Swift, závislosti
`SpeedRampEngine` a od F14 `AudioEngine` (oba také čistý Swift), **žádné
AVFoundation ani AppKit** — přeloží se a otestuje i na Linuxu. **453
testů, ověřeno; 29 invariantů ve `validate()`.** Od fáze 3 umí `sourceConsumption`/`sourceOffset` rychlostní
křivku (uzly kotvené ve zdrojovém čase) a `rampPlaybackPlan` vydává
segmentaci v celých tickách pro `scaleTimeRange`. Od vylepšovacích fází
navíc:

- **Přechody (F10):** `Transition` patří STŘIHU (dvojici sousedů), žije jen
  dokud střih žije; `TrackCompositionPlan` dělá A/B rozklad drah s rameny.
  Dvě pravidla editací: střih zanikl → přechod umírá s ním; střih žije, ale
  operace by přechod rozbila → operace se odmítá (`blockedByTransition`).
- **Titulky (F11):** druh stopy `.title` (T1, ve výchozím projektu POSLEDNÍ
  — appka si domýšlí `tracks[0]` = V1), `TitleClip` s vlastním typem po
  vzoru `Transition` (text, šablona, zarovnání; žádný asset ani zdroj);
  `titleCues()`/`titlePlacements` pro overlay a pruh, `speechCueRef`/
  `setTranscriptText` pro editaci titulků z řeči. Kvůli novému případu
  enumu `TrackKind` je **formát souboru na verzi 2**.
- **Fotky (F12):** `Asset.isStill` (vyrábět přes `Asset.still(url:)`), klip
  fotky zdroj NEspotřebovává a délku nic neomezuje — větve jsou VÝHRADNĚ
  ve čtyřech schválených místech zdrojové matematiky a v `makeClip`.
  `KenBurns` = dva výřezy normalizované vůči PLÁTNU. Rampa na fotce je
  zakázaná (`rampOnStillClip`) — freeze frame se dělá fotkou.
- **Barvy (F13):** `Clip.colorGrade` (`ColorPreset` + intenzita 0–1, nula
  legální) přes `setColorGrade` — jen obrazová stopa (fotka ano, zvuk ne).
  Model nese jen VOLBU; co preset opticky znamená, ví až kompoziční vrstva.
  Split/duplicate/ocásek overwrite preset dědí — POZOR, ta tři místa staví
  `Clip` výslovným konstruktorem: nové pole klipu se tam musí předat ručně,
  jinak se potichu ztratí (testy to hlídají).
- **Hudba (F14):** `Asset.beatGrid` (typ `BeatGrid` z AudioEngine) kotvená
  ve ZDROJOVÉM čase — trim/přesun s dobami nehnou; `setBeatGrid` (jen asset
  se zvukem), `beatMarks()` promítá doby na osu inverzí `sourceOffset`
  (vzorec `subtitleCues`). Magnet: `SnapCandidate.Kind.beat` — SLABŠÍ než
  hrana klipu; `snapCandidates(beats:)` dostává doby od volajícího,
  geometrie projekt nezná. Dopasování: `fitClipEndToBeat` (konstantní
  rychlost 90–115 %, VŽDY nad limitem čistého zpomalení, spotřeba se
  zachovává, souosé dvojče jde s klipem) a `rampClipToBeat` (zpomalení
  dosedne na dobu; kotvy analyticky — easeInOut spotřebuje rozpětí ×
  (1+slow)/2). Chyby nesou RADU (`noBeatInReach(nearest:)`), UI je
  překládá do tooltipů vypnutých položek menu; o zapnutí položky
  rozhoduje zkušební běh operace na kopii projektu.
- **Kvalita (F15):** `SharpnessMetric.laplacianVariance` + `qualityMarks
  (samples:)` — klasifikace RELATIVNĚ k mediánu skóre CELÉHO assetu
  (absolutní prahy nefungují; trim klasifikaci nemění), citlivost 0–1,
  zákmity < 0,5 s a tma (medián 0) se nehlásí. Vzorky se do projektového
  souboru NEUKLÁDAJÍ — drží je `SharpnessStore` (cache otiskem
  `v2|cesta|velikost|mtime`; verze výpočtu je součást otisku). ⚠️ Past:
  `frameDuration` škálovací kompozice výstup čtečky pod frekvencí zdroje
  NEprořeďuje — vzorkuj decimací po dekódování. Hluchá místa
  (`emptinessMarks`): TICHO **a zároveň** prázdný obraz (tma NEBO nízká
  entropie), minimum 5 s — tichá dekorace s bohatým obrazem NENÍ chyba
  a soubor bez zvukové stopy je z definice ticho. Pohyb se měří a
  ukládá, ale v klasifikaci v1 se nepoužívá (kapsa se hýbe, dekorace
  stojí — hluchost neurčuje).
- **Přechody na ose (F16, drobnosti z koukanců):** `transitionArms(clipID:)`
  vrací ramena, která musí zůstat uvnitř klipu — **náhled trimu je
  zařezává, takže se tažení o přechod OPŘE** místo tichého odmítnutí při
  puštění. Trim, který střih zruší (odtažení od souseda → mezera), rameno
  neomezuje: tam přechod legálně umírá s ním. Přechod jde vybrat klikem
  do těla (`selectedTransition`) a smazat Delete.
- **Fade (F16):** `Clip.audioFades` přes `setAudioFades` — jen zvuková
  stopa. Fade jsou HRANOVÉ: split/overwrite dávají nájezd začátku
  a dojezd konci. Trim smí klip zkrátit pod součet fade — délky
  zařezává `effectiveAudioFades` (jediné místo, odkud je čte
  kompozice); invariant 29 hlídá jen zápornost a stopu. V mixu jsou to
  tytéž volume rampy jako crossfade; hrana pokrytá crossfadem fade
  NEDOSTANE (dvě rampy přes sebe mix nesmí dostat).
- **Osa sleduje hlavu (F17):** `scrollToKeep(playhead:scrollX:viewportWidth:
  maxScrollX:)` — čistá funkce, STRÁNKUJE (hlava za hranou → skok do levé
  třetiny při jízdě vpřed, do pravé při jízdě zpět), mezi skoky osa STOJÍ.
  Rezerva 16 b u hrany. Zapojení v `TimelinePane`: vypnuto při scrubování,
  tažení čehokoli a během live scrollu; kdo si odscrolluje pryč, toho osa
  nechá být, dokud hlava sama nevjede do výřezu.
- **Schránka a multi-výběr (F17):** `Clipboard` je stav SEZENÍ, ne
  dokumentu (do souboru nepatří). `clipboard(copying:)` bere svázaná
  dvojčata celá (vzorec mazání), `paste(_:at:)` razí **čerstvý `LinkID`
  pro každou skupinu** — se stejným by vazbu sdílely tři klipy a
  `validate()` hlásí `brokenLink` — a je ATOMICKÝ (co se nevejde celé,
  nevloží se vůbec; rozstrkání by rozbilo vzájemnou polohu klipů a s ní
  sync). Vkládá se na PŮVODNÍ stopu, jinak na první téhož druhu.
  ⚠️ **`Clip.copied(linkID:timelineStart:)` je JEDINÉ místo, kde se klip
  klonuje** (i `duplicate` jde přes něj) — dřív si kopii stavěla tři místa
  vlastním konstruktorem a F13 jimi ztratila barevný preset; test porovnává
  pole REFLEXÍ, takže chytí i budoucí přidané pole.
  ⚠️ V UI mají `⌘` a `shift` na ose DVA významy (klik = výběr, tažení =
  slip / vypnuté přichytávání) — rozhoduje se až při puštění podle toho,
  jestli se myš pohnula.
- **Chronologie a výřez (F17):** `Asset.creationDate` + `creationDateSource`
  (`metadata` / `fileSystem`) — datum souboru je NÁHRADA a UI ji přiznává
  (po kopírování z karty je to čas kopírování). Čte `CreationDateReader`:
  `AVAsset.load(.creationDate)` → `load(.dateValue)`, u fotek EXIF
  `DateTimeOriginal` přes ImageIO, teprve pak soubor. ⚠️ Synchronní
  `asset.creationDate` je od macOS 13 deprecated.
  `arrangeChronologically(trackID:)` řadí stabilně, zavírá mezery, drží
  začátek stopy a **posouvá svázaná dvojčata o totéž** (jinak se rozejde
  obraz se zvukem); klipy bez data jdou dozadu a jejich počet se vrací.
  Export výřezu: `exportRange(inPoint:outPoint:)` v modelu (chybějící nebo
  obrácené body = CELÝ projekt), v `CFRRendereru` volitelný `timeRange` =
  `reader.timeRange` + `startSession(atSourceTime:)` + posunutá mřížka
  slotů; zapisovač časy odečte, takže soubor začíná nulou.

```swift
var project = Project.empty()                        // V1 + A1 + A2 + T1
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
`sourceOffset(in:atFrame:)`. Rampa (fáze 3) i fotky (fáze 12) vyměnily jen
vnitřek těch funkcí; kdyby si to počítala každá operace po svém, přepisuje
se jich šest.

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
Měření hlasitosti podle ITU-R BS.1770-4 (na něm stojí EBU R128), cross-korelační synchronizace nahrávek, od fáze 14 detekce dob hudby (`BeatGrid` + `BeatDetector`) a od fáze 16 true peak (`TruePeakMeter` — 4× převzorkování polyfázovým okénkovaným sincem; koeficienty se počítají, neopisují, kotva: mezivzorková špička sinusu fs/4 s fází π/4 = +3 dB nad vzorky). Čistý Swift, žádné závislosti (vlastní FFT — Accelerate by zabil přeložitelnost na Linuxu). **54 testů; hlasitost nezávisle ověřena proti `pyloudnorm` — shoda < 0,05 LU** (tolerance EBU je ±0,5 LU); sync na reálném zvuku najde posun s chybou < 0,1 ms i při SNR −3 dB; tempo na klikových stopách ±0,1 BPM.

```swift
// mřížka dob hudebního podkladu (fáze 14)
if let grid = BeatDetector.analyze(samples: monoSamples, sampleRate: 48_000) {
    grid.bpm                       // tempo (zpřesněné regresí přes onsety)
    grid.beats(from: 0, to: 30)    // doby s příznakem „raz" (isDownbeat)
    // ruční korekce: doubleTempo/halveTempo, alignBeat(to:), markDownbeat(at:)
    // grid.confidence < ~0,3 = mřížce nevěř a přiznej to v UI
}
// šum/řeč bez pulzace vrací nil — mřížka se nevymýšlí
```

Vstup mono `[Float]` + frekvence (převzorkování je věc volajícího — kontrakt `WaveformSync`). Fáze mřížky (`firstBeatTime`) není nutně první slyšitelný úder (předtaktí); detekce taktů se nedělá automaticky, „raz" určuje uživatel přes `markDownbeat`.

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
- **Stabilizace obrazu už škrtnutá NENÍ** — 29. 07. 2026 ji autor zařadil jako fázi 21 (třetí vlna). Výhrady ale platí: „gumový obraz" z rolling shutteru globální transformací opravit nejde, proto v1 jen AFINNÍ registrace (ne homografie), korekce se aplikuje ve VLASTNÍM compositoru (per-snímková transformace přes instrukce = tisíce instrukcí na klip), ořez je viditelný a fáze začíná spikem s právem přestat.
- Rozpoznávání obličejů — až za v1.0 a jen po projití právního a licenčního gate (viz plán, podmíněná fáze 23).
- Freeze frame a zpětné přehrávání v `SpeedRampEngine` — rozbilo by invertibilitu mapování.
