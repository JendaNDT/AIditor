# Projekt AIditor – Project Status
*Naposled aktualizováno: 30. 07. 2026 (FÁZE 18 HOTOVÁ — všech 13 modulů; přejmenováno na AIditor; dál koukance rukou a KILL-GATE 1)*

## 🎯 Co to je
Nativní macOS videoeditor pro svatební a rodinné filmy — plynulý speed ramping a 100 % lokální český přepis titulků. **Čistě editor, FREE a zatím jen pro autora** (svatební asistent škrtnut, licencování i distribuce odloženy — vše 28. 07. 2026 na pokyn autora).
Stack: Swift, SwiftUI (panely) + AppKit (timeline), AVFoundation, AudioEngine (vlastní DSP), WhisperKit.

## ✏️ PŘEJMENOVÁNÍ: Krása → AIditor (30. 07. 2026, na pokyn autora)

Aplikace se jmenuje **AIditor**. Přejmenování prošlo napříč repozitářem: složka a Xcode
projekt (`AIditor/AIditor.xcodeproj`, cíl i schéma `AIditor`, produkt `AIditor.app`),
Swift identifikátory (`AIditorApp`, `AIditorUI`, `AIditorToolbar`, `aiditorHex`,
`TimelineGeometry.aiditor`), názvy pracovních adresářů kontrol a souborů měření
(`AIditorExportCheck`, `AIditorBenchmark.txt` …), texty v UI, všechna dokumentace,
specifikace, tracker i design handoff (`design_handoff_aiditor_ui/`). Celkem 146 souborů.

⚠️ **Trvalé identifikátory ZŮSTALY schválně nezměněné** — bundle ID
`cz.projektkrasa.Krasa`, klíče `UserDefaults` `cz.projektkrasa.*` a přípona projektových
souborů `.projektkrasa`. Kontejner sandboxu je klíčovaný bundle ID; jeho změna by
znamenala nový kontejner, tedy **znovustažení modelu WhisperKitu (~1,5 GB)** a ztrátu
proxy, miniatur, autosave a bookmarků na složky. Podrobné zdůvodnění v `CLAUDE.md`.
Odkaz na `Projekt_Krasa_navrh_implementace.docx` (dokument mimo repozitář) taky zůstal.

**Ověřeno:** `xcodebuild` BUILD SUCCEEDED, **570 testů / 0 selhání** (TimelineModel 463,
SpeedRampEngine 53, AudioEngine 54), `swift build` MediaProbe prošel, `--shell-check`
sedí na zadání v okně i na celé obrazovce. Bundle appky nese `CFBundleName = AIditor`
a `CFBundleIdentifier = cz.projektkrasa.Krasa` — přesně jak má.

## 📍 STAV (30. 07. 2026)

**⭐ VŠECHNY NAPLÁNOVANÉ FÁZE HOTOVÉ: 0–9 (MVP), vylepšovací 10–16, ergonomie 17 i přestavba UI 18; všechna klíčová čísla ověřená sondami.** Appka umí: import s měřením VFR → střih na ose (2000 klipů bez vypadlého tiku) → rychlostní křivky kreslené myší (žlutá zóna limitu zdroje) → proxy (seek 6 ms) → hlasitosti stop za běhu → sync klopáku (na vzorek přesně) → titulky z české řeči (WhisperKit) → **přechody na střihu (prolínačka, zatmívačky, audio crossfade)** → **grafické titulky na T1 s náhledem, inspektorem a vypálením do exportu** → **fotky s Ken Burns a freeze frame** → **barevné presety per klip s intenzitou (vlastní compositor)** → **hudba s dobami v pravítku, magnetem a dopasováním klipů na dobu** → **analýzy kvality (neostrost, hluchá místa) se značkami na klipech** → **zvukové fade úchyty** → **multi-výběr, schránka, JKL a osa sledující hlavu** → projekt s autosave a obnovou po pádu → export HEVC 4K/30 s kolísáním 0,0 % a normalizací na −1 dBTP → export SRT.
A od 30. 07. 2026 v tom všem **nové UI podle design handoffu**: ikonový rail místo vývojářského sidebaru, knihovna médií s přetažením na osu, miniatury a křivky na klipech, přehled celé osy, panel se záložkami, list exportu, panel přepisu řeči, prázdný start a fullscreen náhled.

Sedm balíčků/modulů: `SpeedRampEngine` (53 testů), `TimelineModel` (463, 29 invariantů), `AudioEngine` (54), `ProbeKit`+`MediaProbe`, `Flatten`, `Ramp`; aplikace `AIditor`. **Celkem 570 automatických testů, 0 selhání** (přeměřeno 30. 07. 2026 `swift test` ve všech třech balíčcích). Závislost: WhisperKit v1.0.0. Formát projektového souboru **verze 2** (nový druh stopy `.title`; soubory v1 se dál načtou) — **fáze 17 ani 18 formát nezměnily.**

**Kontroly z příkazové řádky** (každá tiskne změřená čísla, ne „OK"): měření `--benchmark`, `--fullscreen`, `--timeline-bench`, `--shell-gpu`, `--transition-gpu`, `--color-gpu`; dodávka `--export-check`, `--mix-check`, `--normalize-check`, `--srt-check`, `--roundtrip-project`, `--autosave-check`; funkce `--transition-check`, `--title-check`, `--photo-check`, `--freeze-check`, `--color-check`, `--music-check`, `--sharp-check`, `--empty-check`, `--fade-check`, `--sync-check`, `--transcribe-check`, `--jkl-check`, `--select-check`, `--range-check`; UI fáze 18 `--shell-check`, `--status-check`, `--layers-check`, `--layout-check`, `--thumb-check`, `--overview-check`, `--panel-check`, `--library-check`, `--export-ui-check`, `--transcript-ui-check`, `--empty-start-check`, `--fullscreen-ui-check`.

**Vylepšovací fáze 10–16 hotové** (plán sestavený 28. 07. výběrem z `Projekt_Krasa_navrh_implementace.docx`): ✅ přechody → ✅ texty/T1 → ✅ fotky+Ken Burns → ✅ barevné presety → ✅ hudební synchronizace (vlajková) → ✅ analýzy kvality → ✅ vymazlení. **A od 30. 07. 2026 i celá fáze 18 — přestavba UI podle design handoffu, všech třináct modulů.** Zbývá jen to, co se dělá RUKOU: projít seznam koukanců a pak KILL-GATE 1 — sestříhat touhle appkou reálnou svatbu (materiál ~konec srpna 2026).

**➡️ PŘÍŠTÍ KROK: KOUKANCE RUKOU.** Fáze 18 je hotová celá — třináct modulů, každý za svou branou. Odsud už žádný naplánovaný kód není: **sejde se seznam koukanců** (u každého modulu je dole kurzívou) a projde se rukou na reálném materiálu. Teprve pak 🚧 **KILL-GATE 1 — sestříhat touhle appkou skutečnou svatbu** (materiál ~konec srpna 2026).

**Pořadí odsud:** fáze 18 ✅ (M1–M13, všechny brány prošly) → koukance rukou → 🚧 **KILL-GATE 1 (svatba)**.

⚠️ **Pravidlo „do kill-gate se nepřidávají funkce" bylo pro fázi 18 na pokyn autora ZRUŠENO (29. 07. 2026) — a fáze doběhla celá (30. 07. 2026).** Přestavba UI podle `design_handoff_aiditor_ui/` šla před svatbu včetně knihovny médií, přehledu osy a fullscreen režimů. **Cena zůstává na stole: třináct sessions čerstvého kódu, který nikdo neodzkoušel na skutečné zakázce.** Drží ho jen regresní sada (`--timeline-bench`, `--benchmark`, `--export-check`, `--transition-check`, `--select-check`, `--range-check`), která byla podmínkou odevzdání každého modulu — žádný se neodložil, všechny brány prošly. Co ta sada z principu neuvidí, je ergonomie: **na to jsou koukance rukou a pak svatba.**

⚠️ **Číslo „18" nese v projektu jen JEDNU věc: přestavbu UI.** Třetí vlna plánu měla původně jako fázi 18 druhou obrazovou stopu (V2); po zařazení UI dostala V2 číslo 19 a zbytek vlny se posunul (`IMPLEMENTACNI_PLAN.md`, sekce „Třetí vlna"). Důvod je prostý: „fáze 18" je od 29. 07. 2026 vypálená ve 45 zdrojových souborech, kdežto nepostavená fáze se přečíslovat dá.

## ✅ FÁZE 18 — přestavba UI podle design handoffu (HOTOVÁ 30. 07. 2026)

Plán, rozhodnutí a roadmapa všech 13 modulů: **`FAZE_18_UI.md`**. Zdroj zadání:
`design_handoff_aiditor_ui/` (šest obrazovek, hi-fi, rozměry v bodech na dodržení).

**Dvě rozhodnutí autora z 29. 07. 2026:** ① jede se **všech 13 modulů před svatbou**;
② **světlý režim padá** — okno je natvrdo tmavé.

🛠 **Oprava M3 — lišta osy neviděla změny (30. 07. 2026).** Past vnořeného
`ObservableObject` POTŘETÍ (po `selectedTitle` v F11 a `selectedSpeech` v M11).

  - **Co bylo špatně:** `TimelineLayerBar` pozorovala jen `AppModel`, ale čte a mění stav
    `TimelineControlleru` (vrstvy, přichytávání, citlivost, zoom, výřez). Controller je
    vnořený `ObservableObject`, takže jeho `objectWillChange` k liště nedošel — **pilulky
    měnily vzhled až při nejbližším překreslení z jiného důvodu** (typicky změna `status`).
    Kreslení NA OSE správně bylo: AppKit se na controller odebírá sám.
  - **⚠️ Prosté `@ObservedObject var timeline` v liště je druhá past, ne řešení.** Na témže
    objektu tepe `playhead` (30×/s během přehrávání) a `interaction` (každý pohyb myší při
    tažení). Lišta by se překreslovala celé přehrávání i celé tažení klipu.
  - **Řešení: `TimelineBarState`** — malý `ObservableObject` s CÍLENÝMI odběry
    (`$layers`, `$snappingEnabled`, `$qualitySensitivity`, `$interaction.geometry.pointsPerFrame`,
    body výřezu), všude `removeDuplicates()`. Vlastní objekt, ne `@Published` pole na
    `AppModelu`: tam by tažení posuvníku zoomu 60×/s překreslovalo CELOU skořápku.
    Zápis jde dál napřímo do `model.timeline` — **psát se smí, pozorovat ne**.
  - **Vedlejší úklid staré pasti z M6:** popisek výřezu potřebuje `Project.duration` (O(klipů),
    dvě alokace), a počítal se v KAŽDÉM průchodu `body`, dvakrát. Teď se počítá jen při změně
    bodů nebo projektu (projekt přes `debounce` 250 ms) a `body` čte hotový text.
  - **Ověřeno `--layers-check`, nová část C (12 kontrol):** 60 posunů hlavy nepřekreslilo lištu
    **ani jednou**, zatímco controller se přitom ohlásil **59×** — obě poloviny problému
    změřené jedním číslem. Každý ovladač (vrstva, přichytávání, citlivost, zoom) se v zrcadle
    projeví a stojí **právě jedno** překreslení; výřez se objeví i zmizí a **out bod na konci
    filmu se za výřez nevydává**. Snímek okna (`Snapshots/lista-osy.png`) ukazuje lištu
    v nastaveném stavu — čísla vidí mechanismus, vzhled jen obrázek.
  - **Regrese:** `--timeline-bench` **0 vypadlých tiků** (medián práce 1,89 ms),
    `--range-check` ✅, `--shell-check` ✅, `--empty-start-check` ✅.

✅ **Modul 13 — fullscreen náhled se třemi stavy (30. 07. 2026). FÁZE 18 HOTOVÁ.**

  - **Náhled přes celou obrazovku, tři stavy:** **čistý** (jen obraz a titulky, vpravo nahoře
    ztlumená kapsle `timecode · ⎋ zpět do editoru`), **ovládání** (horní pruh 112 se jménem
    projektu, klipem POD HLAVOU a čipy Proxy / preset / LUFS; dolní pruh 168 s timecodem
    22 mono, scrub lištou s výřezem a dobami, transportem s kruhem 52 a čipem shuttle,
    `Titulky ✓` / `Osa ⇧T`) a **osa** (mini osa 76 s pásem miniatur, zvukem, dobami, výřezem
    a hlavou; nad kurzorem plovoucí náhled snímku 192×108 s timecodem).
    Zapíná ⇧⌘F nebo tlačítko v pilulce transportu, ⎋ vrací. Řečový titulek se ve stavu
    „ovládání" **zvedá**, aby nesedl na scrub lištu.
  - **⚠️ Riziko modulu ošetřené vzorcem, ne novou cestou: je to TÁŽ hierarchie, jen bez chrome.**
    `previewFullscreen` odebírá skořápku stejně jako `chromeHidden` z M1, takže `PlayerView`
    zůstává na témže místě stromu. Druhé okno by znamenalo druhý `AVPlayerView` — a stěhování
    přehrávače mezi okny je přesně ta cesta, na které projekt jednou strávil den honěním
    „černého náhledu".
  - **Ověřeno `--fullscreen-ui-check`, 29 kontrol:** přepnutí ZA BĚŽÍCÍHO přehrávání nezměnilo
    `rate` (1,0 → 1,0) a hlava jela dál (97 → 124), po návratu **zůstala na svém** (124);
    osa je v náhledu **z okna pryč** (odebírá se, nekryje), přehrávač zůstal; overlay po
    2 s nečinnosti zmizí, pohyb myši ho vrátí, myš u spodní hrany vytáhne mini osu a ta
    **připnutá přes ⇧T nemizí** (kdežto vytažená myší ano); mini osa mapuje 0 / 50 / 100 %
    na snímky 0 / 90 / 180.
  - **⚠️ Sledovací oblast myši se ověřuje ČÍSLY, ne vírou.** `NSTrackingArea` je jediná cesta,
    jak se dozvědět o pohybu bez klikání, a sledovač má `hitTest` na `nil`, aby nebral kliknutí
    tlačítkům overlaye. Kontrola se ptá: **jedna oblast, volby obsahují `mouseMoved`
    i `activeInKeyWindow`, hit test vrací `nil`.** Bez toho by overlay tiše zůstal viset navždy.
  - **⚠️ Snímek okna chytil zalomený timecode — posedmé v řadě to našel obrázek.** Návrh dává
    timecodu 132 bodů, jenže to je šířka z HTML prototypu: SF Mono 22 potřebuje na
    `00:00:04:04` ~150 a zbytek si zalomí na druhý řádek. Čísla o tom nevědí nic.
  - **⚠️ NÁLEZ V MĚŘENÍ, tentokrát v cizí kontrole: `--thumb-check` padal na věci, která
    nebyla v kódu.** Druhý průchod hlásil „vygenerováno 7 dlaždic" místo nuly a vypadalo to na
    chybu v mezipaměti. Ověřeno stashnutím celého modulu 13: **táž neshoda i bez něj** — od M9
    si dlaždice žádá i knihovna médií (hrana 104) a do globálních statistik store se míchají
    její požadavky. Kontrola teď na dobu měření přepne rail na `Řeč` (knihovna se vymění za
    Zdroje řeči) a hlásí **6 vygenerovaných / 6 z disku**. `--thumb-check` se od M6 nepouštěl,
    takže to leželo tři moduly.
  - **Regrese:** `--fullscreen` (pojmenovaná brána modulu) **59,6 fps v ustáleném stavu, 0 dlouhých
    mezer, scrubování medián 47,3 ms**; `--shell-check` ✅, `--empty-start-check` ✅,
    `--layers-check` ✅, `--select-check` ✅, `--range-check` ✅, `--thumb-check` ✅ (po opravě
    izolace), `--transition-check` číslo po čísle jako ve fázi 10 (0,7 / 12,9 / 13,1),
    `--export-check` 6087 snímků = 202,900 s osy, `--timeline-bench` 0 vypadlých tiků
    (medián 1,91 ms).
  - **Co se NEDĚLÁ:** přepínač „přehrávat jen výřez" z návrhu — je to změna v přehrávací cestě
    (hlava by musela na hraně výřezu zastavit), a ta se do modulu o UI nevejde; scrub lišta
    výřez ukazuje, ale přehrávání ho neomezuje. `⌃⌘F` (fullscreen CELÉ aplikace) zůstává
    systémový: skořápka ho umí od M1 a `--shell-check` ho měří.
  - **Přiznané meze:** snímek okna z `cacheDisplay` **video nezachytí** (obraz je na něm černý —
    kreslí ho `AVPlayerView` mimo naši vrstvu), takže tři snímky stavů ukazují overlay, ne film;
    plovoucí náhled snímku se na snímku neobjeví, protože kontrola nemá myš.
  - *Koukanec rukou (v seznamu): ⇧⌘F na reálném projektu, mizení overlaye a jeho návrat myší,
    ⇧T a plovoucí náhled nad mini osou, scrub tažením a klik do doby, ⎋ zpět.*

✅ **Modul 12 — prázdný start (30. 07. 2026).**

  - **Okno bez materiálu je TÝŽ rám, jen jiný obsah:** místo přehrávače **zóna přetažení**
    (rámeček `1,5 px dashed`, tři dlaždice, „Přetáhni sem záběry, fotky nebo hudbu",
    `Vybrat soubory…` / `Vybrat složku…`, řádek formátů), místo knihovny **Poslední projekty**
    (jméno, datum, počet záběrů, délka; offline řádek oranžově „disk není připojený";
    patička s velikostí proxy cache a stavem modelu přepisu), toolbar `Otevřít projekt… ⌘O`
    + `Nový projekt ⌘N`, rail ztlumený na 0,35, lišta osy na 0,4 a **návod v prázdných
    pruzích stop** („Sem přijdou záběry a fotky…", „Hudba na A2 · Soubor → Přidat hudbu…").
  - **Obnova zálohy je PRUH, ne dialog.** Modální okno při startu nutilo rozhodnout dřív, než
    bylo vidět o čem, a „Zahodit" je nevratné. Pruh jde ignorovat; `Zahodit` navíc dohoní to,
    co by se bylo stalo bez zálohy (sken zapamatovaných složek). Pruh říká i **počet klipů
    v záloze** — údaj, který dialog nikdy neřekl.
  - **⚠️ Riziko modulu (sandbox) vyřešené, ne obejité: přetažené URL NENÍ security-scoped.**
    Drop dává přístup jen na dobu operace a `startAccessingSecurityScopedResource()` na něm
    vrací `false`; trvalý přístup dá jedině bookmark vyrobený HNED a rovnou rozbalený zpátky
    (`MediaImporter.adopt(dropped:)`). Kdo by kopíroval vzorec z `NSOpenPanel`
    (`compactMap { beginAccess($0) }`), zahodí každý přetažený soubor. Zapsané v CLAUDE.md.
  - **⚠️ Cíl přetažení je AppKit `NSView` a obsah zóny visí UVNITŘ něj.** AppKit hledá cíl hit
    testem odspodu nahoru, takže SwiftUI obsah položený NAD terčem by drop nad textem
    a tlačítky tiše zabil. Kontrola se proto ptá `hitTest` na střed zóny a hlásí, co dostala:
    **`NSHostingView<DropZoneContent>`**, tedy potomek terče. Vedlejší přínos: kontrola jde
    skutečnou cestou protokolu (`registerForDraggedTypes` → pasteboard s `NSURL` →
    `draggingEntered` → `performDragOperation`), kterou u SwiftUI `.onDrop` nasimulovat nejde.
  - **Ověřeno `--empty-start-check`, 31 kontrol:** drop souboru i **složky** (složka dá
    **5 assetů == `videoFiles(in:)`**, a jsou to tytéž soubory, ne jen stejný počet, tedy
    „totéž co Otevřít složku"); cizí soubor projekt nezmění a appka řekne proč; po dropu má
    asset **bookmark**; obnova z pruhu dá **tytéž 2 klipy a týž počet porušení invariantů
    (0)** jako záloha přečtená napřímo, a zůstává neuložená; uložený projekt se objeví
    v seznamu se správným počtem záběrů, po smazání souboru se **sám** označí za offline
    a otevřít nejde.
  - **⚠️ Kontrola si odkládá zálohu i evidenci projektů a vrací je.** Běží v témže kontejneru
    jako appka — bez toho by uživateli přepsala zálohu neuložené práce a nechala mu v seznamu
    mrtvý dočasný projekt.
  - **⚠️ Snímek okna chytil dvě věci, pošesté v řadě:** ① **prázdný `ScrollView` se smrskl na
    nulovou šířku** a hláška „Zatím žádný uložený projekt." se vysázela PO PÍSMENKÁCH pod
    sebe (`maxWidth: .infinity` patří na OBSAH, ne jen na scroll view) — zapsané v CLAUDE.md;
    ② pruh obnovy na prvním snímku vůbec nebyl, protože si ho kontrola vlastním pořadím
    smazala (uložení testovacího projektu maže zálohu) — snímek se teď dělá, dokud nabídka platí.
  - **Přidané cesty do modelu:** `newProject()` (prázdná osa — do teď se z rozdělané práce
    nedalo vyjít jinak než importem), `openRecent`, `importDropped` (rozdělí video / fotky /
    hudbu podle přípony a pošle je TÝMIŽ cestami jako menu; **video první**, protože zakládá
    nový projekt, kdežto fotky a hudba se přidávají), `addPhotos(urls:)` oddělené od panelu.
    `confirmLosingUnsavedWork` se pod CLI neptá — modální dialog by kontrolu zasekl.
  - **⚠️ Prázdný start se NIKDY neukazuje při měření** (`showsEmptyStart` má v podmínce
    `!chromeHidden`) a zóna přehrávač **překrývá, neodebírá**: `PlayerView` musí zůstat na
    témže místě stromu, jinak by po importu vznikl nový `PlayerHostView`.
  - **Regrese:** `--shell-check` 16 hodnot ✅, `--select-check` 15 ✅, `--range-check` 9 ✅,
    `--library-check` ✅, `--export-ui-check` ✅, `--panel-check` ✅, `--layers-check` ✅,
    `--layout-check` ✅, `--overview-check` ✅, `--export-check` 6087 snímků = 202,900 s osy,
    `--transition-check` číslo po čísle jako ve fázi 10 (0,7 / 12,9 / 13,1),
    `--timeline-bench` třikrát: 1 / 0 / 0 vypadlých tiků, medián práce 1,88–1,96 ms
    (M11 měl 1,96 — beze změny; load average 1,6).
  - **Přiznané meze:** miniatura v Posledních projektech je neutrální dlaždice (skutečný snímek
    by znamenal otevřít každý projekt a rozbalit bookmark jeho prvního assetu, a offline projekt
    by ho stejně neměl); soubory se dají přetáhnout jen na PRÁZDNÉ okno — s materiálem na ose
    se přidává tlačítkem ＋ v knihovně; ikona railu `Nastavení` se **neztlumuje**, přestože ji
    tak návrh kreslí, protože na projektu nezávisí a je to jediná cesta ke správě proxy a modelu.
  - *Koukanec rukou (v seznamu): přetažení složky i jednotlivých souborů na prázdné okno, pruh
    obnovy po vynuceném ukončení, klik do Posledních projektů, ⇧⌘N a ⌘N.*

✅ **Modul 11 — panel přepisu řeči a Zdroje řeči (30. 07. 2026).**

  - **Panel se dvěma stavy:** PRŮBĚH (procenta z reálné pozice v nahrávce, tři fáze, **úseky
    přitékají průběžně** a poslední je vybledlý, „přepis běží ve stroji") a EDITACE (hledání,
    „jen pod hlavou", seznam úseků, vybraný jako karta s editovatelným polem, `Rozdělit v kurzoru` /
    `Smazat úsek`, poznámka „platí pro všechny klipy ze zdroje"). V horním pásu **Zdroje řeči**
    místo knihovny, když je rail na Řeč. Na ose **zvýrazněný rozsah** vybraného úseku na VŠECH
    klipech zdroje.
  - **Riziko modulu (průběžné doručování) vyřešené API, ne obcházením:** WhisperKit má
    `segmentDiscoveryCallback`. ⚠️ **Dvě pasti vyčtené ze zdrojáků balíčku:** parametr
    `segmentCallback:` se při VAD chunkingu **nepoužije** (batchovaná cesta bere instanční
    vlastnost), a v té cestě se posouvá jen pole `seek`, **ne `start`/`end`** — časy v callbacku jsou
    relativní ke kusu nahrávky. Proto je průběžný seznam **NÁHLED** a uložené úseky přijdou
    z návratové hodnoty; procenta se počítají ze `seek`, který absolutní je. Zapsané v CLAUDE.md.
  - **Ověřeno naostro** (`--transcribe-check` na reálném klipu): **11 úseků průběžně, 11 ve
    výsledku**. Kontrola to hlídá ZVLÁŠŤ od výsledku — kdyby callback přestal chodit, výsledek
    dorazí stejně a nikdo si toho nevšimne.
  - **Model:** `splitTranscriptSegment(atCharacter:)` a `speechCueRanges` — **+4 testy, celkem 463.**
    Čas řezu se dělí **poměrem znaků**; je to přiznaná heuristika, protože naše cesta WhisperKitu
    vrací časy na úsek, ne na slovo.
  - **Ověřeno `--transcript-ui-check`, 21 kontrol:** oprava textu se projeví na OBOU klipech zdroje
    i v `.srt` a je to JEDEN undo krok; rozdělení dá „před" 4,00–4,43 s a „tímto shromážděním"
    4,43–6,00 s se zachovaným součtem délek; prázdný text úsek maže a `.srt` o něm neví; zvýraznění
    se kreslí na 30–90 a 630–690, tedy dvakrát.
  - **⚠️ Snímek panelu chytil past projektu a její horší polovinu.** Panel pozoroval jen `AppModel`,
    ale `TimelineController` je **vnořený** `ObservableObject` — vybraný úsek se nepřekreslil na
    kartu. Horší bylo, co se za tím skrývalo: pole s textem zůstalo **prázdné**, a protože prázdný
    text úsek MAŽE, ⏎ by ho zahodilo. Text se teď plní z jednoho místa a `commit` má pojistku.
    **Kontrola to chytit nemohla** — sama nastavovala výběr přímo, tedy tou cestou, která byla
    rozbitá; obsah pole se dá ověřit jen okem.
  - **Regrese:** `--transcribe-check` naostro, `--select-check` 15 ✅, `--range-check` 9 ✅,
    `--library-check` 26 ✅, `--export-ui-check` ✅, `--shell-check` ✅, `--timeline-bench` 1,96 ms.
  - *Koukanec rukou (v seznamu): přepis naostro s otevřeným panelem, oprava textu a ⏎, rozdělení
    v kurzoru, klik do pásku řeči na ose a hned ⏎.*

✅ **Modul 10 — list exportu (30. 07. 2026). Začátek etapy D.**

  - **List 660 bodů** nad ztmaveným oknem, tři stavy: **nastavení** (rozsah Celý projekt / Jen výřez
    s počty snímků, obraz s čipem `CFR`, hlasitost Bez / Web −14 / Vysílání −23, titulky vypálit +
    `.srt`, cesta, varovný blok o duplikaci) → **průběh** (procenta, snímky, rychlost, tři fáze,
    „můžeš dál stříhat") → **hotovo** (miniatura HOTOVÉHO filmu z `ThumbnailStore` a kontrolní řádky
    včetně přiznaného stropu −1 dBTP). Toolbar otevírá list místo save panelu.
  - **⚠️ List nezakládá druhou exportní cestu:** volá tutéž `export(to:)`, kterou používají všechny
    CLI kontroly, a volby listu se do ní propisují. Jinak by se „co dostane uživatel" a „co měří
    `--export-check`" rozešlo a nikdo by si toho nevšiml.
  - **Varovný blok počítá z MATERIÁLU** (pojmenované riziko modulu): model dostal
    `duplicatedFrameShare(of:)` — průměr z `max(0, 1 − v(t)/limit)`, tedy pravidlo projektu.
    **+3 testy, celkem 459.** Ověřeno obousměrně: 30fps zdroj s rampou 0,25× → **37,5 %**,
    120fps zdroj tentýž ramp utáhne → **varování zmizí**.
  - **Ověřeno `--export-ui-check`, 20 kontrol:** celý projekt slíbeno 90 = zapsáno 90; výřez slíbeno
    30 = zapsáno 30 = **30 v souboru**; stav „hotovo" kreslí z výsledku; volby (vypnuté vypalování,
    `.srt`) se propsaly. MediaProbe na exportu z `--export-check`: **VFR 0 z 1, zahozených 0**,
    tedy čip `CFR` v listu nelže.
  - **⚠️ NÁLEZ V MĚŘENÍ: počítat snímky v souboru přes buffery PŘECEŇUJE.**
    `AVAssetReaderTrackOutput` vydá i buffery **bez dat** — 94 bufferů / 90 vzorků a 34 / 30, pokaždé
    čtyři navíc. První verze kontroly hlásila 34 proti 30 a vypadalo to na chybu v exportu, přestože
    délka souboru (1,000 s / 3,000 s) vycházela přesně. Počítat se musí `CMSampleBufferGetNumSamples`.
    Zapsané v CLAUDE.md.
  - **⚠️ Kontroly si teď dělají snímek okna SAMY** (`NSView.cacheDisplay(in:to:)` do PNG v kontejneru,
    `ExportUIChecks.writeWindowSnapshot`). `screencapture` fotil **Finder**, který nad oknem nechaly
    předchozí kontroly, a `NSApp.activate(ignoringOtherApps:)` ho nepřebil.
  - **⚠️ Snímek listu chytil tři věci (popáté v řadě):** ① vybraná mohla být **zakázaná** karta „Jen
    výřez" — zavedena efektivní volba, a čísla přitom vycházela, protože `exportRange` je bez in/out
    celý projekt; ② `ScrollView` si bral celou výšku a třetina listu zůstala prázdná; ③ hláška
    o hlasitosti měla tečku a ASCII pomlčku místo české čárky a minusu („−35.4" → „−35,4").
  - **Přiznaná mez:** odhad času se ukazuje až PO prvním exportu, z naměřené rychlosti. Vymyšlené
    „~1 min" v kontrolním listu je horší než přiznané „ukáže se po prvním exportu".
  - **Regrese:** `--export-check` 4739 snímků, `--transition-check` číslo po čísle jako ve fázi 10
    (79/0; 0,7/12,9/13,1), `--range-check` 9 ✅.
  - *Koukanec rukou (v seznamu): tři stavy listu na reálném projektu, varovný blok na 30fps klipu
    s rampou, „Zobrazit klip na ose", export výřezu z listu.*

✅ **Modul 9 — knihovna médií a přetažení na osu (30. 07. 2026). ETAPA C HOTOVÁ.**

  - **Pás 330 bodů vpravo v horním pásu:** hlavička („Knihovna · 5 · chronologicky" + ＋), filtry
    Vše / Video / Fotky / Hudba s počty, mřížka dvou sloupců s kartami, patička s tlačítkem
    „Uspořádat na V1 chronologicky" a stavem proxy. **Zavírá potíž #6 ze zadání** — dosud šel
    materiál vidět jen jako klipy na ose, kdo chtěl vědět, co má, koukal do Finderu.
  - **Karta 94 bodů** (náhled 62 + popis 32, pevná výška — past pojmenovaná v zadání): náhled
    z `ThumbnailStore` s hranou **104** (vlastní kapsa mezipaměti, takže si knihovna a osa navzájem
    nezahazují dlaždice), poster je DRUHÁ dlaždice (≈ 3,5 s — první snímek souboru bývá rozjezd
    kamery), badge délky, `120p` a `VFR`, ryska měkké ostrosti, datum ze souboru **oranžově**.
    Dvojklik ukáže materiál na ose. Ryska kvality se kreslí jen u materiálu NA OSE: klasifikace
    ostrosti je v modelu vázaná na klip a druhá tabulka prahů by se rozešla (poučení z F13).
  - **Pravidlo 6 odškrtnuté před psaním kódu:** `registerForDraggedTypes`, override metod
    `NSDraggingDestination` i SwiftUI `.onDrag { NSItemProvider(object: NSString) }` existují
    a přeloží se na macOS 14 (typecheck proti SDK). ⚠️ `namesOfPromisedFilesDropped` chce
    `override` — je na `NSObject`, ne jen v protokolu.
  - **Přetažení:** `AssetID` na pasteboardu, náhled vložení přes TYTÉŽ duchy jako tažení klipu,
    video se zvukem jako **svázaná dvojice** (jako při importu), fotka a hudba na své druhy stop.
    **O odmítnutí rozhoduje zkušební běh operace na kopii projektu**, ne vlastní tabulka pravidel
    (vzorec z F14). Vložení je **jeden undo krok** i u dvojice; odmítnutý drop nezmění nic.
  - **Ověřeno `--library-check`, 23 kontrol** — a jde SKUTEČNOU cestou protokolu (vlastní
    pasteboard, `draggingEntered` → `draggingUpdated` → `performDragOperation`), ne zkratkou do
    vnitřní funkce: filtry 7 / 5 / 1 / 1 bez překryvu; drop na V1 přistál na snímku **120**, tedy
    přesně tam, kde byl náhled; dvojice má společný `LinkID` a **⌘Z ji vzal jedním krokem**; hudba
    na V1, video na A2 i obsazené místo se odmítly s **červeným** náhledem a bez jakékoli změny
    projektu; fotka na V1 prošla.
  - **⚠️ Kontrola odhalila skutečnou chybu v kódu dropu:** podmínka „projekt po vložení musí být
    BEZ porušených invariantů" udělala z jedné cizí vady (asset bez naměřené frekvence) **zámek na
    celé vkládání**, bez vysvětlení proč. Porovnává se teď POČET porušení před a po. Neplatný asset
    si vyrobila sama kontrola — chyba, kterou tím našla, byla naše.
  - **⚠️ Screenshot chytil tři věci, počtvrté v řadě:** ① **badge se nekreslily vůbec** —
    `Image.resizable().aspectRatio(.fill)` nahlásí větší velikost, než jakou dostal, takže se `ZStack`
    rozvrhl podle obrázku a `clipped()` odřízl i popisky; přesunuté do `overlay` za rámcem;
    ② naměřená frekvence („59,68 fps") vytlačovala z karty čas natočení — v kartě je `60p`, přesné
    číslo v tooltipu, o nekonstantním časování mluví badge `VFR`; ③ slow-mo klip ukazoval `VFR`
    místo `120p`, přestože důležitější je to druhé — teď obojí.
  - **Regrese:** `--shell-check` dostal novou hlídanou hodnotu **obraz zprava 347** (knihovna 330 +
    předěl + odsazení) a prošel v okně i na celé obrazovce. Plocha obrazu zůstala **1208×680**,
    protože náhled je omezený VÝŠKOU horního pásu, ne šířkou — knihovna mu tedy nic neubrala.
    `--timeline-bench` 0 vypadlých tiků (medián 1,86 ms), `--overview-check`, `--select-check` (15)
    a `--range-check` (9) beze změny.
  - *Koukanec rukou (v seznamu): přetažení karty na V1, A2 a na obsazené místo, filtry, dvojklik na
    kartu, patička s proxy.*

✅ **Modul 6 — přehled celé osy (30. 07. 2026). ETAPA B HOTOVÁ.**

  - **`TimelineOverviewView`:** pás 46 bodů pod stopami — popisek „přehled", pás 26 bodů se slitými
    bloky klipů (obraz 9 nahoře, zvuk 8 pod ním), červená hlava, rámeček viditelného výřezu, celková
    délka mono vpravo. **Vlastní mapování celé osy na svou šířku**, ne `TimelineGeometry` (ta je
    o zoomu). Klik = skok hlavou, tažení rámečku = scroll osy.
  - **Bloky se slévají:** hodinová osa s 2320 klipy má **dva bloky** místo 2320 vrstev — sousedící
    klipy s mezerou pod bod jsou jeden blok. Přehled má říct „tady je materiál a tady díra".
    Přestavba jen při změně otisku (délka, počet klipů, šířka): **tři změny zoomu nepřestavěly nic.**
  - **Souboj s auto-scrollem (riziko modulu) ošetřený a změřený:** během tažení rámečku se osa za
    hlavou netahá (hlava skočila do poloviny hodinové osy, scroll se nepohnul), po puštění platí
    pravidlo ručního scrollu, a **klik do přehledu je výslovná navigace, která odstavení ruší**.
  - **Ověřeno `--overview-check`, 16 kontrol:** klik na 0 / 25 / 75 / 100 % hodinové osy položí hlavu
    přesně na 0 / 26 970 / 80 910 / 107 880 (odchylka nula); tažení rámečku na 50 % a 20 % dá výřez
    začínající přesně na 53 940 a 21 576 snímku; aktualizace výřezu stojí **0,001–0,002 ms**.
    ⚠️ **Plánovaná tolerance „1 snímek" je z konstrukce nedosažitelná** a kontrola to říká nahlas:
    jeden bod pásu je na hodinové ose **218 snímků**, takže kritérium je „do jednoho bodu".
  - **⚠️ NÁLEZ, který platí obecně: `Project.duration` je O(klipů) a alokuje přitom dvě pole**
    (`flatMap` + `map` v `Queries.swift`) — na 2000 klipech ~1,5 ms. První verze modulu ji čtla při
    každém zápisu rámečku, tedy za každý tik scrollu, a medián práce na tik vyskočil **z 0,95 na
    2,45 ms** (A/B proti HEAD, rozptyl 0,02). Uložením se to vrátilo na 0,96. **Táž past byla
    i v pravítku** — `drawExportRange` volal `duration` dvakrát za kreslení, jen aby zjistil, že
    výřez není nastavený; kreslení pravítka spadlo z **0,88 na 0,08 ms**. Zapsané v CLAUDE.md.
  - **⚠️ A ta obrácená závislost potřetí, tentokrát izolovaná na JEDINÝ ŘÁDEK.** Po opravě pravítka
    `--timeline-bench` hlásí medián **1,95 ms** místo 0,97 — s MENŠÍ prací. A/B na tom řádku
    (třikrát každá varianta, rozptyl 0,02) to opakuje pokaždé. Vysvětlení jako u anomálie `beats`:
    ten údaj měří dobu `scroll(to:)` na hlavním vlákně, a **když vlákno mezi tiky nemá co dělat,
    platí se za probuzení** (rampa frekvence, studená cache). Součet práce na snímek se nezměnil
    (~2 ms z 16,67), vypadlé tiky 0–1. **Kdo bude příště srovnávat s 0,95 ms, ať ví, že to číslo
    bylo dražší, ne lepší.**
  - **Přiznaný důsledek podle předpovědi M4:** 46 bodů pásu znamená, že se stopy (344) do okna
    z návrhu nevejdou a svisle se scrolluje. Vlastnost návrhu.
  - **⚠️ Vedlejší nález o ⇧Z:** podlaha zoomu (`minPointsPerFrame` 0,02) dovolí do výřezu 562 bodů
    nejvýš ~27 700 snímků, tedy **~15 minut** — hodinovou osu fit do okna nedostane a rámeček výřezu
    správně zůstává. Snižovat podlahu není v zájmu hit testingu; navigaci na dlouhé ose přebírá
    právě přehled.
  - **Regrese:** `--select-check` 15 ✅, `--range-check` 9 ✅ (i pruh výřezu v pravítku, kterého se
    oprava dotkla), `--shell-check` 16 hodnot, `--thumb-check` beze změny.
  - *Koukanec rukou (v seznamu): tažení rámečku po dlouhé ose, klik do přehledu při přehrávání,
    chování po ručním odscrollování.*

✅ **Modul 5 — miniatury na klipech, křivka rampy a popisky (30. 07. 2026). BRÁNA R1 DRŽÍ.**

  - **`ThumbnailStore`** vzorcem `WaveformStore`: dlaždice kotvené ve **zdrojovém** čase (klíč
    `soubor|úroveň|index|hrana|scale`), disková cache otiskem, generování **z proxy** (bez ní
    z originálu), dávkově přes `AVAssetImageGenerator.images(for:)` a **jedním sériovým pracovníkem**.
    Pravidlo 6 odškrtnuté před psaním kódu: to API v SDK **existuje** a přeloží se i s targetem
    macOS 14 bez gatování (ověřeno typecheckem, ne odhadem).
  - **Na klipu:** pás miniatur v dolních 96 bodech, křivka rychlosti přes něj (pás 40, 1,5 px,
    uzly 3 px, stlačená škála 0,125–2× — na 40 bodech by plná škála editoru narvala zpomalení do
    dolní třetiny) a dva popisky: **vpravo nahoře rampa** (`1× → 0,25× → 1×`), u fotky Ken Burns
    (`nájezd 1,3×`), **vlevo dole preset** (`Teplý film 62 %`). Hudební klip má v názvu tempo.
  - **⚠️ Dlaždice kotvené ve zdroji jsou vědomá odchylka od litery návrhu.** Návrh dělí pás na 2–4
    rovnoměrné dlaždice přes šířku klipu — po každém trimu by se změnil čas VŠECH dlaždic a celá sada
    by se zahodila, šedesátkrát za sekundu při tažení úchytu. Kotvení ve zdroji drží miniatury na
    místě a dlaždice se na hranách klipu zařezávají (tak to dělá Premiere i FCP). Hustota je z
    návrhu: 1 dlaždice na 96 bodů → na jeho čtyřech ukázkových šířkách přesně **2/2/3/1**.
  - **⚠️ Brána R1 drží, ale ne sama od sebe: rozhodl ODKLAD GENEROVÁNÍ, dokud se osa hýbe.**
    Kreslení pásu stojí **+0,10 až +0,13 ms** na tik (rozpočet 16,67) — zanedbatelné. Problém bylo
    generování: se studenou cache vygeneroval scroll 199 snímků za jízdy a **vypadly 2 tiky**,
    přestože práce na hlavním vlákně byla 0,34 ms — dekodéry na pozadí soutěží o výpočetní čas.
    S odkladem se za jízdy negeneruje **nic** (0 vypadlých tiků) a pás se doplní po zastavení
    (4,6 s na plný výřez ze 4K HEVC originálů). Cesta bez odkladu se dá **vynutit** (`deferralEnabled`),
    aby tiše nehnila — vzorec `forcesSteppingFallback` z `--jkl-check`. Ústupy, které plán pro tenhle
    případ chystal (hrubší dlaždice, výchozí vypnutí), se nepoužily.
  - **Ověřeno `--thumb-check`, 22 kontrol:** studená cache 53 ms na dlaždici proti **0,6 ms z disku**
    a obrázky se shodují; dlaždice je **týž snímek** jako z generátoru volaného napřímo (rozdíl jasu
    0,5 proti 4,0 u snímku o 20 s dál) — kontrola si výřez i podvzorek dělá **vlastní**, jinak by
    ověřila jen to, že se tentýž kód chová dvakrát stejně; **trimnutý klip** ukazuje trimnuté místo
    (index 12 = 9,6 s u klipu od 10 s, a obsahem sedí na 9,6 s, ne na nulu); fotka má **jednu**
    dlaždici na celý pás (jas 127 u přechodu 0→255); s vypnutou vrstvou nezůstane ani dlaždice
    a **nezadá se ani jeden požadavek na generování**.
  - **⚠️ Dvě věci chytil až screenshot** (třetí modul v řadě): ① dlaždice byla **čtverec**, ale slot
    je široký `hrana × zoom/úroveň`, takže se obraz dotahoval 1,25× a pás byl rozmazaný → poměr 1,5
    a verze diskové cache na `v2` (jinak by se tahaly staré čtverce); ② světle modrá křivka se na
    světlém záběru **ztrácela** → přechodové ztmavení pod pásem křivky (plná plocha dělala vodorovný
    šev, tři zastávky ne).
  - **⚠️ Dvě obecně platná zdražení, která se našla měřením:** `NSColor.cgColor` u dynamické barvy
    vyhodnocuje poskytovatele (early-out cesty si barvy brát nesmí — stálo to ~0,3 ms na tik)
    a `CALayer.isHidden` i předávání `ClipDrawInfo` hodnotou nejsou zdarma (stínové příznaky
    a zúžená volání ubraly dalších ~0,12 ms). Zapsané v CLAUDE.md.
  - **✅ ZAVŘENÝ DLUH Z M3 — anomálie příznaku `beats` je vysvětlená.** Práce dob žije v **kreslení
    pravítka** (`beatMarks()` prochází všechny zvukové klipy): s dobami zapnutými 1,46 ms, vypnutými
    0,88 ms. Scrollovací tik ale měří `scroll(to:)` + `reflectScrolledClipView`, tedy `refreshClips`
    (na příznaku nezávislý: 0,42 vs 0,43 ms) a nastavení `needsDisplay` — **pravítko se kreslí až
    v dalším průchodu smyčkou, vně měřeného okna**. Modul 3 tedy měřil tu část tiku, ve které o dobách
    nic není; přepínač ubírá práci tam, kde ji dělá. Obrácený pohyb toho malého čísla je vlastnost
    mikroměření sub-milisekundového okna, ne cena vrstvy.
  - **⚠️ A tím se OTEVÍRÁ ZPÁTKY závěr z M4: „0 vypadlých tiků" není na tomhle stroji
    deterministické.** V jednom sezení, na téže zátěži: kód **M4 dal 2 a 2** výpadky (medián práce
    0,80 ms), kód **M5 dal 0, 0, 0, 1, 0, 2, 2** (medián 0,95–1,00 ms) — modul, který práci PŘIDAL,
    vypadl méně často než baseline. Load average 1,6–2,2 přes sezení. **Důvěryhodná je práce na tik**
    (rozptyl 0,02 ms) **a ABBA v jednom sezení** (osm běhů, 0 vypadlých tiků ve všech).
    M4 měl pravdu v příčině (zátěž stroje), ale závěr „kritérium platí" byl na jedno měření příliš
    silný. Kritérium fáze 2 se má odsud posuzovat ABBA a prací na tik.
  - **Regrese:** `--shell-check` všech 16 hodnot, `--select-check` i `--range-check` celé,
    `--layers-check` beze změny (jen text o anomálii odkazuje na vysvětlení).
  - **Co se NEDĚLÁ:** popisek `sync −0,42 s` z návrhu — model posun z klopáku nikde nedrží
    (synchronizace klip přesune a číslo zahodí), takže by to byl vymyšlený údaj.
  - **Přiznaná mez:** mapování bodů na zdrojový čas je i na klipu s rampou lineární, jen škálované
    skutečnou spotřebou — pás pokrývá přesně použitý úsek materiálu, ale rozestupy uvnitř zpomalení
    křivce neodpovídají. Co se s časem doopravdy děje, říká křivka nakreslená přes pás.
  - *Koukanec rukou (v seznamu): pás miniatur na reálném materiálu při různém zoomu, křivka rampy na
    klipu, popisky, přepínač Miniatury na dlouhé ose, fotka v pásu.*

✅ **Modul 4 — výšky stop a hlavičky 104 (30. 07. 2026). Začátek etapy B.**

  - **Model dostal `topInset`** — výchozí **nula**, aby se nepohnulo nic, co na geometrii stojí;
    výchozí výšky zůstaly 64/44/28 s mezerou 2 (stojí na nich testy balíčku) a aplikace si své
    rozvržení předává konstruktorem přes `TimelineGeometry.aiditor`. **+3 testy, celkem 456.**
  - **Hlavičky 104 px** (dřív 96): jméno semibold **nahoře** (se stopou vysokou 136 bodů by V1 na
    středu plavalo v prázdnu), pod ním meta `obraz · 5 klipů` / `řeč` / `hudba` / `titulky`, u zvuku
    navíc **hlasitost v dB**. Řádek je karta se zaoblením jen vpravo.
  - **Uklizen dluh z M1:** `viewDidChangeEffectiveAppearance` je odstraněné ze všech tří view osy —
    okno je natvrdo tmavé, takže se nikdy nespustilo.
  - **Ověřeno `--layout-check`:** stopy na **3 / 142 / 223 / 304**, součet **344**, výšky 136/78/40,
    mezera 3, odsazení 3, hlavičky 104 — všech 11 hodnot sedí. Hit testing na bod: `y=138,9` ještě V1,
    `y=140` mezera, a hlavně **`y=0` a `y=2,9` NENÍ stopa**, takže klik nad prvním klipem ho netrefí
    (to je celý smysl `topInset`u).
  - **⚠️ Změřeno, co plán čekal: při minimálním okně se stopy NEVEJDOU** — výřez 286 proti dokumentu
    344, T1 je pod ohybem. Kontrola proto netvrdí, že se to vejde, ale že se na to **dá dostat**.
    Při okně z návrhu (1470×900) je pro stopy ~350 bodů, takže 344 projde — ale **až přijde přehled
    celé osy z M6 (46 bodů), přestane se vejít i tam**. Vlastnost návrhu, ne chyba.
  - **Regrese:** `--timeline-bench` **0 vypadlých tiků**, medián **0,80 ms** — stopy dvakrát vyšší
    (136 proti 64) **nestály nic měřitelného**. ~~Tím se zavírá otevřená položka z M8~~ —
    ⚠️ **tenhle závěr modul 5 opravil:** týž kód M4 dal v jiném sezení dvakrát 2 vypadlé tiky, takže
    „nula výpadků" byla vlastnost klidného stroje, ne kódu. Platí příčina (zátěž stroje) a platí
    medián 0,80 ms; kritérium fáze 2 se posuzuje ABBA v jednom sezení. `--select-check` 15 ✅ a `--range-check` 9 ✅
    prošly celé, přestože se hit testing posunul o odsazení.
  - **⚠️ `--shell-check` na M4 spadl, a bylo to správně** — hlídal hlavičky na 96 s komentářem „návrh
    je nemění". M4 je záměrně rozšířil; očekávání se opravilo. To, že se kontrola ozvala, je přesně
    to, k čemu je.
  - **Přiznaný mezistav:** obrazový klip je 136 bodů vysoký a nese jen jméno, takže vypadá **prázdněji
    než dřív** — vyplní ho pás miniatur v M5. Viditelnost a zámek stopy z návrhu se **nedělají**:
    model pro ně nemá stav a dvě tlačítka, která v1 nikdy nic neudělají, jsou horší než jejich absence.

✅ **Modul 8 — záložky Barva, Zvuk a Info (29. 07. 2026). ETAPA C HOTOVÁ.**

  - **Barva:** náhled před/po **ze skutečného snímku klipu** a vzorky pěti presetů renderované
    **týmž `ColorPresetFilter`em jako export** — namíchaný čtvereček by se s presetem rozešel
    a nikdo by nepoznal, které z těch dvou lže. Zdrojový snímek se drží dekódovaný, takže posuvník
    síly je jen render CoreImage, ne čtení souboru.
  - **Zvuk:** fade posuvníky **ve snímcích i v sekundách** — dosud šly fade nastavit JEN tažením
    úchytu na klipu (F16) a přesnou délku nebylo kde napsat. Délky se čtou přes
    `effectiveAudioFades` (trim smí klip zkrátit pod součet fade a model to schválně nezařezává).
    Dál mute a hlasitost stopy s poznámkou, že posuvník **jen ztišuje**, a hlasitost dodávky
    z posledního exportu.
  - **Info:** zdroj, naměřené časování a verdikt VFR, mez čistého zpomalení, čas natočení
    **s přiznaným zdrojem** (datum souboru oranžově), proxy s poznámkou, že export jde z originálů.
  - **Ověřeno `--panel-check`, část D:** preset na **5 klipech = jeden krok ⌘Z** (regrese F17/M2);
    fade se rozdá třem různě dlouhým klipům se zaříznutím per klip — **90 → 30/30, 40 → 10/30,
    16 → 0/16**.
  - **Screenshot chytil dvě věci, které měření nevidělo:** mez čistého zpomalení se vypisovala jako
    „0,502667×" (`%g` je pro UI špatný formát) a koukanec nešlo nasměrovat na konkrétní záložku —
    `--shell-demo barva` teď na ní zaparkuje.
  - **⚠️ `--timeline-bench` na tomhle stroji NEPROŠEL (2–5 vypadlých tiků) — ale není to M8.**
    Práce na tik je 0,59 ms proti rozpočtu 16,67, takže hlavní vlákno zaneprázdněné nebylo. A/B na
    tomtéž stavu stroje: **bez M8 3/4/2, s M8 3/3/2**, týž medián. Load average 1,9–2,1 po desítkách
    buildů v session. **Kritérium fáze 2 se musí přeměřit na klidném stroji** — do té doby ho
    neprohlašuju za splněné ani za rozbité. **OTEVŘENÁ POLOŽKA.**
  - **Přiznané chování k rozhodnutí:** šestnáctisnímkový klip dostal při žádaných 30+30 fade **0/16**
    (celý klip je dojezd, nájezd zmizel) — vychází to z `setAudioFadesOnSelection` z F17.
  - *Koukanec rukou (v seznamu): náhled před/po na reálném záběru, fade posuvníky, Info na klipu
    z telefonu hosta.*

✅ **Modul 7 — připnutý panel 452 se záložkami (29. 07. 2026).**

  - **Potíž #2 zadání zavřená:** křivka rychlosti má box **150 px** v panelu širokém 452, ne 132 bodů
    výšky dělených s panelem barev. Hlavička nese jméno klipu a metu („zdroj 60 fps · 00:03:00"),
    tělo scrolluje, `⌘4` panel skryje a osa se rozšíří **z 666 na 1119 bodů** (právě o 453).
  - **Záložky zatím dvě — Rychlost a Barva.** Zvuk a Info doplní M8 a do té doby se NEUKAZUJÍ:
    prázdná záložka je horší než chybějící.
  - **Záložka Rychlost:** presety `Bez rampy / 0,5× / 0,25× / 0,125×`, editor křivky, čip segmentace
    (`90 úseků`, `mez skoku nedosažitelná`), spotřeba zdroje, korekce výšky, dopasování na hudbu.
  - **Korekce výšky je NOVÁ volba a je zapojená naostro** (náhled i export).
    ⚠️ **Je to nastavení PROJEKTU, ne klipu, a jinak to nejde:** `audioTimePitchAlgorithm` je
    vlastnost `AVPlayerItem`u a výstupu čtečky, jemnější zrno API nedovoluje. Přiznaná mez v1: drží
    se v `UserDefaults`, ne v projektovém souboru.
  - **⚠️ Tolerance 2 % u presetů — rozhodnutí, ne opomenutí.** Naměřeno 59,68 fps → mez 0,5027, takže
    preset „0,5×" by byl trvale nedostupný kvůli propadu 0,54 %. Na 60fps materiálu (většinovém) by
    z presetů byla ozdoba. **Žlutá zóna v editoru zůstává přesná.**
  - **Tabulka důvodů „proč dopasování nejde" je teď jedna** (`TimelineError.beatFitReason`) pro
    kontextové menu i panel.
  - **Ověřeno `--panel-check`** syntetickými událostmi na skutečném editoru: preset 0,5× dal
    nejnižší rychlost 0,500× a spotřeba **33,700 s se vejde do zdroje 44,938 s**; box **150×428**;
    dvojklik přidal uzel (3 → 4), tažení změnilo křivku (0,51 → 0,21), **⌘Z vrátil celé**, Escape
    rozjeté tažení zrušil; `⌘4` vrátí ose 453 bodů.
  - **⚠️ Dvě chyby byly v MĚŘENÍ, ne v kódu, a obě by „prošly":** ① tažení se porovnávalo přes
    `min()` rychlostí, ale přidaný uzel leží v nejnižším bodě křivky — po posunutí nahoru zůstalo
    minimum stejné; ② táhlo se ze STŘEDU plochy, kde uzel není. Editor proto dostal měřicí okno
    `nodePoints` a pozice se **čte, nehádá**.
  - **Screenshot chytil, co měření nemohlo:** preset zároveň aktivní i pod mezí byl vykreslený jako
    vybraný a současně zašedlý. Aktivní preset se teď nevypíná — šedivět stav, který právě platí,
    vypadá jako chyba kreslení.
  - **Regrese:** `--export-check` **4739 snímků** (sáhlo se do exportu kvůli korekci výšky),
    `--timeline-bench` 0 vypadlých tiků, `--shell-check` i `--status-check` beze změny.
  - **Přiznaná nesrovnalost k rozhodnutí:** kontextové menu „Zpomalit 0,25×" (`toggleClassicRamp`)
    mez čistého zpomalení nekontroluje, panel ji ctí. Chová se tak od F14, ale teď je to vedle sebe
    vidět. Sjednocení je věc rozhodnutí, ne úklidu.
  - *Koukanec rukou (v seznamu): kreslení křivky myší v panelu, presety, ⌘4, korekce výšky na
    zpomaleném záběru se zvukem.*

✅ **Modul 3 — lišta osy (29. 07. 2026).**

  - **Pás 32 px** nad osou: přepínače `Miniatury` / `Vlny` / `Doby` / `Značky kvality`, posuvník
    `Citlivost` s hodnotou, `Přichytávání`, výřez s `I`/`O`, zoom a `Fit ⇧Z`.
  - **Vypnutá vrstva se NEPOČÍTÁ, ne jen neukazuje** — early-out v `rebuildClipInfo`,
    `applyWaveform` a `drawBeatMarks`. Kdyby se jen skryla, přepínač by nic neušetřil.
  - **Citlivost 0–1** (`UserDefaults`, přežívá restart, ne projekt) přepočítává jen KLASIFIKACI
    hotových vzorků přes `qualityMarks(samples:sensitivity:)` — **analýzu nespouští**, takže je to
    okamžité. Fáze 15 to měla v modelu, UI k tomu chybělo.
  - **Přichytávání dostalo globální přepínač** vedle shiftu: dosud existovala jen shiftová cesta,
    takže kdo chtěl hodinu stříhat bez magnetu, musel hodinu držet shift.
  - **`⇧Z` (Fit) visí na `keyDown` osy**, ne na SwiftUI zkratce — „Z" je při psaní titulku pořád jen
    písmeno (vzorec JKL z F17). Zoom umí spočítat jen `TimelinePane`: šířku výřezu zná scroll view.
  - **Miniatury: přepínač existuje, vrstva ne** (přijde v M5). Je vypnutý a nese důvod v tooltipu —
    je to **pojistka pro M5**, a ta nemá vznikat ve chvíli, kdy je zle.
  - **Ověřeno `--layers-check`:** vypnutá vrstva nenechá **ani jednu** dlaždici vlny a **ani jeden**
    proužek kvality (měřeno na skutečných nasazených vrstvách, ne na příznaku); citlivost
    0,2/0,5/0,8 → **0/289/289** značek monotónně a **vzorky zůstaly nedotčené**.
  - **⚠️ Měření ceny odhalilo anomálii — izolovanou, ale nevysvětlenou.** Deterministicky (rozptyl
    uvnitř konfigurace 0,00–0,01 ms): všechny vrstvy zapnuté **0,29 ms**, jen vlny vypnuté **0,26**,
    jen značky vypnuté **0,28**, vlny+značky vypnuté **0,25** — tedy přesně podle záměru. Ale
    **jen doby vypnuté 0,70 ms** a všechny vypnuté 0,60 ms. Anomálie sedí na jediném příznaku
    `beats`, přestože `drawBeatMarks` se s ním vypnutým vrací dřív, než zavolá `beatMarks()`, a
    měřený projekt žádné doby nemá. Prakticky bez dopadu (rozpočet 16,67 ms/tik, `--timeline-bench`
    dál 0 vypadlých tiků), **ale v M5 to musí být vysvětlené** — tam se přepínač stane pojistkou.
    ⚠️ Kritérium plánu „scroll je měřitelně levnější" je tím splněné **jen zčásti**.
  - **Regrese:** `--timeline-bench` 0 vypadlých tiků, `--shell-check` i `--status-check` beze změny.
  - ⚠️ **Lišta se dodatečně opravovala** — pozorovala jen `AppModel` a změny controlleru k ní
    nedošly (viz „Oprava M3" nahoře, 30. 07. 2026).
  - *Koukanec rukou (v seznamu): přepínače vrstev, posuvník citlivosti na reálně rozmazaném záběru,
    ⇧Z, zoom posuvník, I/O tlačítka.*

✅ **Modul 2 — stav běžících analýz (29. 07. 2026).**

  - **`AnalysisProgress` + `AnalysisChip`:** analýzy kvality z fáze 15 běžely od svého vzniku
    **úplně bez UI** — `startSharpnessAnalysis()` se rozjelo po importu a uživatel se o něm dozvěděl
    tak, že se na klipech samy objevily proužky. Teď je v toolbaru čip „Analyzuju hluchá místa · 3/5"
    (kreslí se JEN když něco běží) a ve stavovém řádku tři tečky: kvalita, proxy, model přepisu.
  - **Postup nežije ve storech, ale u smyčky.** `SharpnessStore` i `EmptinessStore` jsou actory nad
    jedním souborem — „3/5" je stav smyčky v `AppModelu`, ne stavu úložiště.
  - **⚠️ `defer { analysis.finish() }`,** ne volání na konci těla: po pádu nebo zrušení úlohy by čip
    zůstal viset a tvrdil, že se pracuje.
  - **Ověřeno `--status-check`:** obě dimenze **5/5**, **10 startů = 10 dokončení**, po doběhnutí
    nic nevisí (`running`, `chipText`, jméno souboru — vše uklizené). Screenshot ukazuje čip
    i oranžovou tečku ve stavovém řádku.
  - **⚠️ Kontrola viditelnosti čipu musela přestat být vzorkovací.** První verze vzorkovala po 20 ms
    a hlásila chybu podle toho, jestli byla disková cache studená (s teplou byl krok smyčky kratší
    než perioda vzorkování). Kritérium je teď **vlastnost stavu** — čip je vidět právě tehdy, když
    něco běží — a vzorkované pozorování zůstalo jako informační řádek. Ověřeno s oběma stavy cache.
  - **Regrese:** `--timeline-bench` 0 vypadlých tiků, `--shell-check` beze změny.
  - *Koukanec rukou (v seznamu): čip při importu většího množství klipů, tečky ve stavovém řádku.*

✅ **Modul 1 — nový rám okna (29. 07. 2026).**

  - **`UI/Shell/`:** `AppShell` (toolbar 46 → rail 60 + obsah → stavový řádek 26), `AIditorToolbar`,
    `IconRail` (6 sekcí, SF Symbols), `ViewerPane` (čipy na obraze, měřidlo hlasitosti, pilulka
    transportu s kruhem 44 a čipem rychlosti), `ShellStatusBar`, `DesignTokens`, `LegacySettingsPanel`.
    `ContentView.swift` zhubl z 4483 na 4247 řádků; `HSplitView { sidebar | player }` je pryč.
  - **Fullscreen CELÉ APLIKACE je hotový už v M1.** Skořápka je parametrická (`ShellMode`), okno
    a celá obrazovka sdílejí jedno rozvržení a liší se třemi čísly (toolbar 46/48, odsazení zleva
    78/16, horní pás 372/426) — osa, hlavičky ani panel si rozměry nemění, takže se po přepnutí nic
    nekreslí dvakrát. M13 tím zbývá jen fullscreen **náhledu**.
  - **Ověřeno `--shell-check`** ze skutečných view v hierarchii, ne z konstant: v OKNĚ osa
    **61 / 453 / 453 / 27** (zleva / shora / zprava / zdola), obraz **77 / 63**; na CELÉ OBRAZOVCE
    **61 / 509 / 453 / 27** a obraz **77 / 65** — všech 16 hodnot sedí na tabulku návrhu.
    Plocha obrazu **1208×680 → 1400×788** (fullscreen se opravdu projevil, ne jen příznakem).
  - **⚠️ Tři chyby, a každou chytilo něco jiného.** ① `NSHostingView` je **flipped** — první verze
    kontroly měla odsazení shora a zdola prohozená a obě čísla vypadala „nějak rozumně";
    ② bezpečná zóna titulkového pruhu srážela obsah o **32 bodů** (osa v okně 485 místo 453, ve
    fullscreenu správně) — chytilo měření; ③ ani po `.ignoresSafeArea()` nebyla horní třetina
    toolbaru vidět (jméno projektu a horní půlky tlačítek) — **to chytil až screenshot**, protože
    kontrola měří vůči `contentView`, který sahá k horní hraně okna. Vyřešeno
    `.windowStyle(.hiddenTitleBar)`.
  - **Tmavý režim natvrdo:** okno dostává `.darkAqua`, z `TimelinePalette` a `RampEditorPalette`
    zmizelo **22 světlých hodnot**. Inertní `viewDidChangeEffectiveAppearance` zůstalo — odstraní
    ho M4, který do těch souborů sahá kvůli výškám stop.
  - **Riziko R2 (overlaye leží NA obraze, takže náhled musí být trvale skládaný) změřeno
    `--shell-gpu`, dvě jízdy po čtyřech fázích:** ze **sedmi ustálených měření se stav s overlaji
    a bez nich neliší ani o setinu** (59,67 vs 59,67 fps, 0 dlouhých mezer). Jedna vybočená hodnota
    (34,31 fps, 371 mezer) padla v první měřené fázi první jízdy a **nezopakovala se** — tentýž stav
    dal v pozici 4 téže jízdy 59,67 a nulu.
    ⚠️ **První vysvětlení („může za to rozjezdová pozice 1") druhá jízda VYVRÁTILA** — v obráceném
    pořadí byla pozice 1 v pořádku. Byl to jednorázový výkyv; pozice 1 se z průměru vyřazuje
    z opatrnosti, ne prokazatelně, a vypisuje se.
    ⚠️ **Vlastní otázka R2 tím zodpovězená NENÍ.** Doručené snímky jsou zastropované 60Hz displejem,
    takže ukážou až trhání — kolik GPU stojí skládání, se jimi změřit nedá. Na to je `powermetrics`
    (potřebuje `sudo`, proto to nespustí kód). Kontrola tiskne značky `FÁZE n/4 START/KONEC`, aby šel
    log rozříznout. **Otevřená položka pro autora.** Ústupová cesta (mizení overlajů po ~2 s
    nečinnosti) zůstává připravená — `overlaysSuppressed` je zapojené.
  - **Regrese:** `--timeline-bench` **0 vypadlých tiků** na 2000 klipech (kritérium fáze 2 drží),
    `--select-check` i `--range-check` prošly celé.
  - *Koukanec rukou (v seznamu): puntíky v toolbaru, rail, pilulka transportu, ⌘4, ⌃⌘F tam a zpět.*

## ✅ FÁZE 17 — ergonomie střihu (HOTOVÁ 29. 07. 2026)

**Hotovo když** (kritérium plánu): *přehrání dvacetiminutové osy nevyžaduje sáhnout na scroll* ✅ (auto-scroll, modul 1) · *preset na deset klipů je jedno kliknutí* ✅ (hromadné operace, modul 2) · *klipy ze dvou kamer se poskládají v pořadí, ve kterém se natočily* ✅ (chronologie, modul 3).

✅ **Modul 3 — chronologie a export rozsahu (29. 07. 2026): FÁZE 17 JE TÍM HOTOVÁ.** Model **+11 testů (celkem 453)**.

  - **Čas natočení (`CreationDateReader`):** `AVAsset.load(.creationDate)` → `load(.dateValue)`; u fotky **EXIF `DateTimeOriginal`** přes ImageIO (po AirDropu je datum souboru čas doručení, zatímco EXIF je pořád okamžik stisknutí spouště); teprve pak datum souboru — a to se **PŘIZNÁ**: `Asset.creationDateSource` je `metadata` / `fileSystem` a sidebar ho ukazuje oranžově s poznámkou „(datum souboru)". ⚠️ Synchronní `asset.creationDate` je od macOS 13 deprecated, proto asynchronní cesta. Volitelná pole, starší projekty se čtou dál, verze formátu se nezvedá.
  - **Řazení:** sidebar jede chronologicky místo podle jména (u jedné kamery je název časové razítko, u telefonu hosta ne), kontextové menu prázdného místa na stopě nabídne **„Uspořádat chronologicky"** — vypnuté s vysvětlením, když žádný klip stopy čas nemá. Operace řadí stabilně, **zavírá mezery**, drží začátek stopy (místo vpředu na titulek se nezahodí) a **svázaná dvojčata posouvá o totéž**; klipy bez data jdou dozadu v dosavadním pořadí a jejich počet se hlásí ve stavu. Atomická: co by rozbilo osu, se neprovede.
  - **Export výřezu:** `I` a `O` staví in/out na hlavě, `⌥I`/`⌥O` je ruší, `⌥X` zruší celý výřez; pravítko kreslí světlý pruh se zarážkami **jen když je výřez opravdu výřez** (jinak by „nic nevybráno" a „vybráno vše" vypadalo stejně a uživatel by nevěděl, jestli mu export ukrojí konec). Status po exportu výřez přizná. Model: `exportRange(inPoint:outPoint:)` — chybějící nebo obrácené body znamenají **CELÝ projekt**, export nikdy nesmí tiše vyrobit prázdný soubor.
  - **`CFRRenderer` dostal volitelný `timeRange`:** `reader.timeRange` + `writer.startSession(atSourceTime: range.start)` + mřížka slotů resampleru posunutá o začátek rozsahu. Zapisovač časy odečte sám, takže výsledný soubor začíná nulou. Bez rozsahu je cesta bajt po bajtu ta dosavadní.
  - **Ověřeno `--range-check`:** pět reálných klipů má čas natočení **v metadatech (5/5)**, řazení sedí; přeházená osa se seřadila podle času, mezery se zavřely (0/60/120), **zvuk zůstal u svého obrazu** a osa je bez porušených invariantů; export výřezu dal **60 snímků proti 180 celé osy**.
  - **⚠️ Kontrolu obsahu jsem musel zesílit.** První verze porovnávala tři místa téhož záběru a jas se lišil jen o **0,95** — prošla by, i kdyby renderer rozsah ignoroval. Přepsaná jede na černé/šedé/bílé fotce: výřez **87**, začátek osy **16**, rozdíl **71 jasu**, a navíc se kontroluje, že se do výřezu nedostal obsah za out bodem.
  - **Regrese:** `--export-check` 4739 snímků v pořádku, `--transition-check` po zásahu do rendereru dává **číslo po čísle** totéž co ve fázi 10 (79/0; 0,7/12,9/13,1).
  - *Koukanec rukou (v seznamu): I/O a export výřezu, „Uspořádat chronologicky" na materiálu ze dvou zařízení, čas natočení v sidebaru.*

✅ **Modul 2 — výběr a schránka (29. 07. 2026).** Model **+23 testů (celkem 442)**, všechny prošly napoprvé.

  - **Multi-výběr:** ⌘-klik přepíná jeden klip, shift-klik bere rozsah od kotvy (`clipRange(from:to:)` — jen na TÉŽE stopě; co je „mezi" klipem na V1 a klipem na A2?), tažení v prázdné ploše je rámeček (`TimelineRect` + `geometry.clips(in:)` — PROTÍNÁ, ne „obsahuje celé": u dlouhého klipu by se jinak musel rámeček táhnout přes půl osy), ⌘A vezme všechny klipy. Titulky rámeček nebere — jejich výběr je výhradní.
  - **⚠️ Kolize modifikátorů, kterou musel modul vyřešit:** ⌘ i shift už na ose význam MĚLY — ⌘ v těle klipu je slip, shift při tažení vypíná přichytávání. Řešení: o výběru se rozhoduje až při PUŠTĚNÍ. Nepohnulo se = byl to klik a platí výběr; pohnulo = platí tažení. Kontrola to měří zvlášť („⌘-klik bez pohybu NEudělal slip").
  - **Schránka ⌘C/⌘X/⌘V** vkládá na hlavu. **Svázané dvojice se kopírují CELÉ** (i když uživatel vybral jen obraz — stejně jako se celé mažou) a vložení razí každé skupině **ČERSTVÝ `LinkID`**: se stejným by vazbu sdílely tři klipy a `validate()` hlásí `brokenLink` — táž past, kterou už jednou chytil split svázaného páru (fáze 2). Osamocená půlka vazbu ztrácí (vazba na jeden klip není vazba). Vkládá se na PŮVODNÍ stopu (hudba z A2 nesmí přistát na A1 pod řečí), jinak na první stopu téhož druhu.
  - **Vložení je ATOMICKÉ:** co se nevejde celé, nevloží se vůbec, a řekne se to („Na hlavě není místo — vlož jinam nebo udělej díru."). Rozstrkat klipy po volných místech by rozbilo jejich vzájemnou polohu, a s ní sync obrazu se zvukem — přesně to, kvůli čemu se offsety uchovávají. Nový hook `onStatus` vede hlášky z osy do stavového řádku; tiché nic nutí uživatele mačkat ⌘V třikrát.
  - **⚠️ `Clip.copied(linkID:timelineStart:)` je JEDINÉ místo, kde se klip klonuje** (i `duplicate` je na něj převedený). Dřív si kopii stavěla tři místa vlastním konstruktorem a fáze 13 jimi ztratila barevný preset. Test porovnává pole **reflexí** (`Mirror`), ne vypsaným seznamem — takže chytí i pole, které někdo přidá za rok.
  - **Hromadné operace — vlastní odměna modulu:** preset i jeho posuvník síly jedou na celý výběr, fade tažením úchytu se rozdá všem vybraným zvukovým klipům (délky se každému zařežou zvlášť — krátký klip dostane, co unese), kontextové menu nabídne „Zpomalit 0,25× (N klipů)". **Rampa se každému klipu počítá z JEHO spotřeby** — uzly jsou kotvené ve zdrojovém čase konkrétního záběru, kopírovat je z cizího klipu nejde. Klipy, kde operace nesedí, se přeskočí a řekne se kolik.
  - **Ověřeno `--select-check`:** ⌘-klik přidá i odebere, shift rozsah 4 klipy, rámeček 3 protnuté (a zvuk pod ním ne), ⌘A 7; kopie svázaného obrazu vezme i zvuk, vložená dvojice má čerstvou vazbu a projekt je **bez porušených invariantů**; vložení na obsazené místo nezmění NIC; **preset na 5 klipů = jeden undo krok** (⌘Z vrátí všech 5 naráz), zpomalení na 5 taky. V běžícím okně syntetickými událostmi: tažení myší vybere rámečkem 3 klipy, ⌘-klik přidá čtvrtý a neudělá slip, ⌘C/⌘V z klávesnice vloží klip na hlavu.
  - **Přiznané meze v1:** tažení víc vybraných klipů naráz se NEDĚLÁ (táhne se ten pod kurzorem — `TimelineInteraction` je automat na jeden klip) a **přechody se nekopírují** (přechod patří střihu dvojice sousedů; vložené sousedící klipy mají čistý střih). Ani jedno není v zadání modulu; kdyby to na svatbě chybělo, je to položka do backlogu.
  - *Koukanec rukou (v seznamu): rámeček přes deset klipů, ⌘-klik, shift-klik, ⌘C/⌘V na hlavu, preset na celý výběr a ⌘Z.*

✅ **Modul 1 — osa sleduje hlavu + JKL (29. 07. 2026).**

  - **Auto-scroll STRÁNKUJE, ne centruje.** `TimelineGeometry.scrollToKeep(playhead:scrollX:viewportWidth:maxScrollX:)` (+7 testů, celkem 419) — čistá funkce bez UI: dokud je hlava ve výřezu, vrací `nil` a osa STOJÍ; když vyjede, skočí o stránku tak, aby dosedla do levé třetiny (jízda vpřed) nebo pravé (jízda zpět — jinak by se při přehrávání pozpátku skákalo po snímcích). Rezerva 16 bodů u hrany (hlava má šířku a mezi tiky urazí kus cesty), ořez na rozsah scrollu, a když z ořezu vyjde tatáž pozice, vrací `nil` místo scrollu o nic.
  - **Kdy se NEsleduje:** scrubování (`isUserScrubbing`), jakékoli tažení (klip, titulek, fade, přechod — `documentView.hasActiveDrag`) a **live scroll** (`NSScrollViewWillStartLiveScrollNotification`, macOS 10.9+; `boundsDidChange` uživatelský scroll od programového nerozliší). Kdo si odscrolluje pryč od hlavy, toho osa nechá být, dokud hlava sama nevjede zpět do výřezu — klik do pravítka je vždycky uvnitř výřezu, takže „vrať se k hlavě" nepotřebuje žádnou další cestu.
  - **JKL:** žebřík −8…8 v `PlaybackControlleru`, L doprava, J doleva, K na pauzu (konvence NLE — ze 4× vpřed jede J na 2×, ne rovnou pozpátku). Klávesy visí na `keyDown` osy, NE na SwiftUI `keyboardShortcut`: písmeno bez modifikátoru by střílelo i při psaní titulku. KVO na `player.rate` srovná stav, když přehrávač sám zastaví (konec osy).
  - **⚠️ Změřeno (`--jkl-check`), a je to překvapení proti plánu:** na naší kompozici ze 4K HEVC **`canPlayReverse` i `canPlayFastReverse` hlásí `true`** — zpětné přehrávání funguje bez fallbacku. Vpřed 1/2/4× jede na **97–98 %** slíbené rychlosti, pozpátku −1/−2× jen na **84 %** (trhá, přesně jak plán čekal). Krokovací fallback je tedy postavený, ale nikdy se nespustí — proto ho kontrola **vynucuje** (`forcesSteppingFallback`) a měří: −1/−2× vynuceně krokováním na **93/97 %** času (obraz trhá víc, zvuk nehraje; přiznané oranžovým „(krokováním)" v transportu).
  - **⚠️ Past, kterou fallback musel obejít:** krok si vede VLASTNÍ kurzor. `player.currentTime()` odpovídá poslednímu DOKONČENÉMU seeku, a protože se seeky slučují (QA1820), krokování o `currentTime` by se zaseklo na místě. Uživatelský seek kurzor srovná — jinak by si s časovačem přetahovaly hlavu.
  - **Ověřeno `--jkl-check` i integračně:** simulace 601 tiků hlavy → **3 skoky osy, hlava mimo okno 0×**; odzoomovaná osa (celá se vejde do okna) **0 skoků**. V běžícím okně scroll **0 → 1047 b za 12 s přehrávání**, hlava ve výřezu po celou dobu (115 vzorků). Řetězec kláves: syntetické L, L, J, K poslané do osy dají **2× → 1× → pauza**, tedy keyDown → hook controlleru → přehrávač drží.
  - *Koukanec rukou (v seznamu): auto-scroll při přehrávání dlouhé osy, JKL na klávesnici, ruční odscrollování během přehrávání (osa má nechat být), indikátor rychlosti v transportu. `--jkl-demo` postaví osu a rozjede ji na 2×.*

## ✅ FÁZE 16 — vymazlení a technické dluhy (HOTOVÁ 29. 07. 2026)

✅ **Modul 3 — správa modelu Whisperu a drobnosti z koukanců (29. 07. 2026): FÁZE 16 A CELÝ PLÁNOVANÝ VÝVOJ JSOU TÍM HOTOVÉ.**

  - **Správa modelu přepisu** v sidebaru (ukazuje se, JEN když je model stažený — dokud uživatel titulky z řeči nepoužil, není co spravovat): velikost a umístění, **Smazat model** (ptá se — 1,5 GB po síti se nemaže na překlep; zahodí i model načtený v paměti, jinak by appka přepisovala z něčeho, co na disku není) a **Přemístit model…** (soubory se PŘESUNOU, ne stáhnou znovu; nová cesta jde do WhisperKitu přes `downloadBase` — ověřeno ve `WhisperKitConfig`, security-scoped bookmark vzorcem `ProxyStore`, při selhání přesunu se zůstane u staré složky místo tvrzení, že je přesunuto).
  - **Drobnost z koukanců F10 ①: trim se teď o přechod OPŘE.** `transitionArms(clipID:)` vrací ramena, která musí zůstat uvnitř klipu, a náhled tažení je zařezává. Vybrána byla zarážka, ne zčervenání: „ruka se opře o zeď a klip se doveze přesně tam, kam smí" je poctivější než červený duch, který nic neudělá. **Testy vymáhají skutečný kontrakt** — náhled se porovnává s hledanou hranou, kde `trimStart`/`trimEnd` opravdu začne odmítat, ne s jiným vypočteným číslem. Trim, který střih ZRUŠÍ (odtažení od souseda), zarážka neomezuje — tam přechod legálně umírá s ním (pravidlo ① fáze 10).
  - **Drobnost z koukanců F10 ②: přechod jde vybrat klikem do těla** — žlutý rámeček (týž jazyk výběru jako klipy a titulky), Delete ho smaže, klik do prázdna výběr ruší, výběry se navzájem vylučují.
  - **Ověřeno screenshotem (`--transition-demo`)**: žlutý rámeček na lichoběžníku prolínačky a v sidebaru „Model přepisu: výchozí složka aplikace · 1,62 GB". Regrese: `--transition-check` po zásahu do trim mezí dává **číslo po čísle** totéž co ve fázi 10 (79/0; 0,7/12,9/13,1).
  - *Koukanec rukou (v seznamu): tažení trimu se opře o přechod, výběr přechodu klikem a Delete, smazání a přemístění modelu.*

✅ **Modul 2 — true peak strop normalizace (29. 07. 2026).**

  - **`TruePeakMeter` v `AudioEngine` (+6 testů, celkem 54):** 4× převzorkování polyfázovým okénkovaným sincem (Hann, 12 taps na fázi, prototyp 48 — princip ITU-R BS.1770-4 Annex 2; koeficienty se POČÍTAJÍ, neopisují — týž přístup jako K-váhování, každá fáze normalizovaná na jednotkový součet). Streamovaně, per kanál, s kruhovým oknem. **Kotvy v testech:** sinus fs/4 s fází π/4 — vzorky 0,707, true peak 1,0 (+3 dB, klasický mezivzorkový případ); 997 Hz beze změny; ticho −120; true peak ≥ špička vzorků na šumu; streamování po nepravidelných kusech = jednorázové měření; stereo najde špičku v kterémkoli kanále.
  - **Zapojení:** `LoudnessScanner.Result.truePeakLinear` místo špičky vzorků (tentýž průchod, metr se jen přidal vedle `LoudnessMeter`), strop normalizace v exportu je teď poctivě **−1 dBTP** a status to říká.
  - **⚠️ Změřený dopad na reálném materiálu (`--normalize-check`):** strop klesl z +5,9 dB na **+4,7 dB** — mezivzorkové špičky testovacích klipů jsou o **1,2 dB výš** než špičky vzorků, takže dřívější „−1 dB" export ve skutečnosti přetékal (přesně chyba, kterou plán touhle položkou řešil). Broadcast profil na tomhle materiálu už na cíl −23 LUFS nedosáhne a poctivě to hlásí — správné chování, ne regrese.

✅ **Modul 1 — zvukové fade úchyty (29. 07. 2026).**

  - **Model (+9 testů, celkem 408; invariant 29):** `Clip.audioFades` (nájezd/dojezd ve snímcích, volitelné pole — formát beze změny verze), `setAudioFades` (jen zvuková stopa; nezáporné; součet ≤ délka — chyba nese `maxTotal` pro zarážku; prázdné fade se ukládají jako `nil`). **Fade jsou HRANOVÉ:** split dá nájezd levé polovině a dojezd pravé, overwrite hlavě/ocásku totéž — řez uprostřed žádný fade nevyrábí. Trim smí klip zkrátit pod součet fade — invariant hlídá jen zápornost a stopu, délky poctivě zařezává `effectiveAudioFades` (jediné místo, odkud je čte kompozice) — model kvůli tomu nepřepisuje šest trim operací.
  - **Kompozice:** fade = tytéž volume rampy v mixu jako crossfade (`BuiltTimeline.audioFades` → `audioMix(project:)`, přežívají živou změnu hlasitosti stopy). **Hrana pokrytá crossfadem fade NEDOSTANE** — přechod tam už rampuje a `AVAudioMix` nesmí dostat dvě rampy přes sebe.
  - **UI:** klíny (CAShapeLayer, tmavý trojúhelník nad křivkou nástupu) s úchyty (bílá kolečka na vrcholu) na zvukových klipech; tažení = náhled v klínu + JEDEN zápis při puštění (vzorec přechodů), Escape ruší, ⌘Z vrací. Úchyt bere horních 10 bodů klipu — trim zůstává na zbytku výšky hrany.
  - **Ověřeno `--fade-check` kvantitativně:** dvojí export (fade 1 s + 1 s vs. bez) — RMS hran **0,27/0,38** úrovně bez fade (přesně lineární rampa přes měřené okno), **střed 1,00** nedotčený. **Screenshot (`--fade-demo`):** klín nájezdu přes vlnu zvukového klipu s úchytem na vrcholu.
  - *Koukanec rukou (v seznamu): tažení úchytů, fade slyšet při přehrávání, kombinace s crossfadem.*

## ✅ FÁZE 15 — analýzy kvality záběrů (HOTOVÁ 29. 07. 2026)

✅ **Modul 2 — ticho a prázdno (29. 07. 2026): FÁZE 15 JE TÍM HOTOVÁ.**

  - **Model (+7 testů, celkem 399):** `EmptinessSample` (hlasitost dBFS + jas + entropie + pohyb; pohyb se v klasifikaci v1 NEPOUŽÍVÁ — kapsa se hýbe, dekorace stojí, hluchost neurčuje ani jedním směrem — ale měří se a ukládá do cache pro budoucí ladění), `LumaStats` (jas/entropie/střední rozdíl — čisté funkce s testy na kotvách: jednolitá plocha 0 bitů, půl na půl 1 bit, rovnoměrné hodnoty 8 bitů) a `emptinessMarks`: hluché místo = **TICHO a zároveň prázdný obraz** (tma NEBO nízká entropie), minimum 5 s (plán: 3–10; hluché místo je nuda, ne mezera mezi větami). **Klíčové pravidlo plánu drží test i CLI: tichá dekorace s bohatým obrazem NENÍ chyba** — a tma s hlukem (večírek) taky ne.
  - **`EmptinessStore`:** obraz týmž sekvenčním průchodem s decimací na 1/s (sdílený `LumaSampler` se `SharpnessStore`), zvuk mono 8 kHz přes `MonoAudioReader` (edit listy ctí) → RMS v oknech 1 s → dBFS; **soubor bez zvukové stopy je z definice ticho (−120)** — fotky a němé záběry rozhoduje obraz. Cache otiskem s verzí výpočtu.
  - **UI:** šedé proužky při SPODNÍ hraně klipu (ostrost nahoře, hluchost dole — jiná dimenze, jiná hrana i barva), klik = seek na začátek úseku. Obojí přes společný `layoutStrips`.
  - **Ověřeno `--empty-check`:** černý čtverec přes still movie (ticho + tma: −120 dBFS, jas 18, entropie 0,99 b) → hluchý ✓; šumová „dekorace" (jas 58, entropie 4,14 b) → NENÍ hluchá ✓; reálný klip se sekerou (průměr −38 dBFS, 45/45 vzorků) → **0 hluchých míst** ✓. **Screenshot (`--empty-demo`):** oranžový proužek ostrosti nahoře a šedý hluchosti dole na témže klipu, každý na svém místě.
  - *Koukanec rukou (v seznamu F15): hluchá místa na reálném materiálu (kapsy, čekání), klik do šedého proužku.*

✅ **Modul 1 — detekce neostrosti (29. 07. 2026).** Návrhová vrstva: značky, klik = seek, ŽÁDNÉ automatické zásahy (rozhodnutí plánu).

  - **Model (`Quality.swift`, +8 testů, celkem 392):** `SharpnessMetric.laplacianVariance` (čistý Swift, testy šachovnice vs. rozostřená šachovnice — rozostření sráží skóre řádově); klasifikace RELATIVNĚ k mediánu skóre assetu (absolutní prahy nefungují, kamery se liší o řády; medián přes CELÝ asset → trim klasifikaci nemění) s nastavitelnou citlivostí 0–1 (prahy 0,3–0,7 mediánu, tvrdý = polovina měkkého — konzervativně, žádná chytristika); `qualityMarks(samples:)` promítá běhy na klipy (vzorec `beatMarks`), jednosnímkový zákmit (< 0,5 s) se zahazuje, tma (medián 0) poctivě nehlásí nic. Vzorky patří assetu ve zdrojovém čase, ale do projektového souboru se NEUKLÁDAJÍ — drží je disková cache.
  - **`SharpnessStore` (actor):** sekvenční čtení `AVAssetReaderTrackOutput` (hardwarový dekodér, žádné seekování) s decimací na 3 vzorky/s a blokovým PODVZORKEM luma na ~192 sloupců (~4×4 pixely na blok — plný průměr 4K bloků stál přes 6 minut na 45s klip, podvzorek 3,9 s = 11× rychleji než reálný čas; průměrování zároveň ředí šum senzoru, který by metrika na plném rozlišení měřila jako „ostrost"). Cache otiskem `v2|cesta|velikost|mtime` — **verze výpočtu je součást otisku**, po změně metriky se staré soubory přestanou trefovat. Spouští se na pozadí po importu/otevření, pod CLI měřeními ne.
  - **⚠️ Past do sbírky: škálovací kompozice kadenci NEprořeďuje.** `frameDuration` pod frekvencí zdroje výstup `AVAssetReaderVideoCompositionOutput` nezredukoval (60fps klip dál dával 60 vzorků/s — změřeno prvním během `--sharp-check`) a přepsané `renderSize` u kompozice z `withPropertiesOf` vracelo u still movie prázdný obraz. Decimace po dekódování je dokumentovaně nezáludná; pro proxy/flatten kompozice funguje, protože tam kadence ≈ frekvence zdroje.
  - **UI:** oranžové (měkký záběr) a červené (rozmazaný) proužky při horní hraně klipu, recyklované; zelená se NEkreslí — značka je jen tam, kde stojí za to se podívat. **Klik do proužku = seek na začátek problému.** Přepočet značek patří do reloadu, scroll jen mapuje souřadnice; bez vzorků okamžitý early-out (scroll benchmark fáze 2 nedotčený).
  - **Ověřeno `--sharp-check` kvantitativně:** ostrá vs. Gaussem rozmazaná šachovnice PŘES STILL MOVIE mezisoubory (touž cestou jako video) — poměr skóre **93×**; reálný klip **135/135 vzorků** (3/s přesně), analýza 45 s klipu za 3,9 s, druhé čtení z diskové cache 0,001 s se shodným výsledkem. **Ověřeno screenshotem (`--sharp-demo`):** oranžový proužek na klipu přesně v místě syntetického propadu ostrosti.
  - *Koukanec rukou (v seznamu): značky na reálně rozmazaném záběru, klik do proužku, citlivost zatím bez UI (výchozí 0,5 — posuvník případně ve F16).*

## ✅ FÁZE 14 — hudební synchronizace (HOTOVÁ 29. 07. 2026, VLAJKOVÁ)

✅ **Modul 3 — dopasování na dobu (29. 07. 2026): FÁZE 14 JE TÍM HOTOVÁ.** Čistý model (**+9 testů, celkem 384, 0 selhání — napoprvé**), UI je tenké menu nad otestovanými operacemi.

  - **„Zarovnat konec na dobu hudby" (`fitClipEndToBeat`):** KONSTANTNÍ změna rychlosti — hraje se týž zdrojový úsek, spotřeba se zachovává (rychlosti křivky × f, délka ÷ f; bez křivky vznikne jeden uzel — jediný uzel = konstantní rychlost, vlastnost `SpeedMath`). Meze podle plánu: rychlost 90–115 % **a vždy nad limitem čistého zpomalení** — kandidátka doba, která by limit porušila, se přeskočí (test: 30fps zdroj na 30fps ose si místo bližšího zpomalení na 105 vybere zrychlení na 90). Obsazené doby (soused; dotyk je legální) se přeskakují; souosé svázané dvojče jde s klipem (délka i rychlost), nesouosé dostane jen rychlost. Žádná doba v dosahu → `noBeatInReach(nearest:)` — chyba NESE nejbližší dobu a UI z ní dělá radu.
  - **„Zpomalení na dobu / rampa na úder" (`rampClipToBeat`):** preset 1× → easeInOut (15 snímků) → slow, kde zpomalení DOSEDNE přesně na dobu nejblíž hlavě. Kotvy **analyticky, žádná iterace**: před rampou jede klip 1× (zdrojová kotva = čas na ose) a easeInOut spotřebuje rozpětí = délka × (1+slow)/2 — táž symetrie jako referenční hodnota Spiku 0 (ramp 1→0,25→1 přes 5 s = 3,125 s). Test drží klíčovou záruku: `frameOffset` zdrojové kotvy konce rampy == snímek doby. Výchozí slow = max(0,25; limit zdroje); zdroj bez rezervy (30 fps na 30fps ose) → `noCleanSlowdown` — **automatika limit nepřekračuje**, ruční editor křivky se žlutou zónou ano (persona Alena).
  - **Kontextové menu (jen obrazový klip, ne fotka):** o zapnutí položky rozhoduje **zkušební běh operace na kopii projektu** — menu nelže: vypnutá položka nese v tooltipu důvod přeložený z chyby modelu („nejbližší doba je na 0:00:03:15 — trimni klip…", „zdroj nemá dost snímků na čisté zpomalení", „na střihu leží přechod"). Akce jde přes controller s jedním undo krokem.
  - *Koukanec rukou (v seznamu F14): obě položky menu na reálné hudbě a klipu.*

✅ **Modul 2 — hudební mapa na ose a magnet na doby (29. 07. 2026).**

  - **`TimelineModel` má novou závislost `AudioEngine`** (oba čistý Swift, přeložitelnost na Linuxu drží) — `Asset.beatGrid: BeatGrid?` je kotvená ve ZDROJOVÉM čase souboru jako přepis: trim/přesun klipu s dobami nehnou, drží se na hudbě. Volitelné pole, verze formátu se nezvedá. `setBeatGrid` validuje (jen asset se zvukem, konečné tempo); **`beatMarks()`** promítá doby přes klipy zvukových stop inverzí `sourceOffset` (vzorec `subtitleCues` — funguje i pod rampou), deduplikuje a řadí. **+10 testů, celkem 375, 0 selhání.**
  - **Magnet:** nový druh kandidáta `SnapCandidate.Kind.beat` — SLABŠÍ než hrana klipu (hrany se zarovnávají přesně, doby jsou magnet, ne zákon; plán: síla mezi hranou a mřížkou snímků). `snapCandidates` bere `beats:` od volajícího (geometrie projekt nezná); zapojené v `TimelineInteraction.begin` (tažení klipů) i v tažení titulků.
  - **Import: menu Soubor → „Přidat hudbu…"** — klip celé skladby na A2 za poslední klip stopy, pak na pozadí `MonoAudioReader` (mono 24 kHz — krok obálky ~10,7 ms jako na 48 kHz, ale FFT poloviční) → `BeatDetector.analyze` → mřížka k assetu (`setBeatGrid` na controlleru, jeden undo krok). Status hlásí BPM a jistotu; **nízká jistota (< 30 %) se PŘIZNÁVÁ**, nenalezené tempo taky („u ambientní hudby je to v pořádku").
  - **Pravítko:** jantarové rysky dob při spodní hraně (`TimelinePalette.beat` — nová barva, s ničím se neplete), „raz" taktu vyšší a plný. Počítá se při kreslení — bez hudby je `beatMarks()` okamžitý early-out, scroll benchmark fáze 2 nedotčený.
  - **Ověřeno CLI `--music-check` kvantitativně:** klikový WAV 120 BPM toutéž cestou jako hudba uživatele → mřížka **120,02 BPM, jistota 90 %, fáze 0,502 s**; 24 značek na ose s **největší odchylkou 1 snímek od ideální mřížky 15 snímků BEZ kumulativního driftu** (přesně to má regrese v detektoru zabíjet; jednotlivá rozteč smí o snímek uhnout — 120,02 ≠ 120,00 a kontrola to nepředstírá); raz každé 4 doby; magnet přitáhl snímek vedle doby s druhem `.beat`. **Ověřeno screenshotem (`--music-demo`):** klik 110 BPM → status „110,0 BPM (jistota 93 %)", jantarové doby v pravítku sedí na transientech vlny klipu na A2.
  - *Koukanec rukou (v seznamu): Přidat hudbu… na reálné skladbě, doby v pravítku, magnet při tažení.*

✅ **Modul 1 — `BeatGrid` + `BeatDetector` v `AudioEngine` (29. 07. 2026).** Čistý Swift bez závislostí (vlastní FFT z fáze 7), **+16 testů, celkem 48 v balíčku, 0 selhání**; vše prošlo napoprvé.

  - **`BeatGrid`** (Codable — poputuje k assetu do projektového souboru): tempo, `firstBeatTime` = FÁZE mřížky (ne nutně první slyšitelný úder — předtaktí existuje), doby na takt (výchozí 4), `downbeatOffset`, jistota. Dotazy `beats(from:to:)` / `nearestBeat(to:)`; **ruční korekce podle plánu**: `doubleTempo`/`halveTempo` (oktávová chyba detekce je legální dvojznačnost), `alignBeat(to:)` (posun fáze), `markDownbeat(at:)` (která doba je „raz" — automatická detekce taktů se NEDĚLÁ, je nespolehlivá i pro velké systémy; výchozí takt od první doby).
  - **`BeatDetector.analyze`:** onset obálka (Hann rámce ~21 ms, poloviční krok, vlastní FFT; detekční funkce = půlvlnný spektrální tok + nárůst energie, každý normalizovaný — energie je kvadratická a tok by přehlušila) → tempo autokorelací obálky v mezích 60–180 BPM s mírnou log-normální preferencí ~120 BPM (autokorelace má stejná maxima na násobcích periody — váha vybírá hudebně pravděpodobnou oktávu, remízu, ne vítěze) a parabolickou interpolací vrcholu → fáze = posun s největším průměrem obálky → **zpřesnění lineární regresí časů onsetů proti indexům dob** (jen onsety do 15 % periody od předpovědi, dvě kola; bez ní by autokorelační rozlišení ~11 ms nechalo mřížku na konci tříminutové skladby ujíždět o desítky ms). Šum bez pulzace vrací `nil` (práh normalizované autokorelace 0,15), krátký signál taky.
  - **Testy na klikových stopách se známým tempem:** 120 / 97,4 (neceločíselné) / 110 s fází 0,37 s / 128 se šumem / 70 (pomalé — preference nesmí přebít autokorelaci) — **tempo v toleranci ±0,1 BPM** (se šumem ±0,3), fáze ±15 ms modulo perioda; šum → `nil`; onsety sedí na klicích (20/20, ±25 ms); mřížka: rozsahy, hranice, nejbližší doba, korekce, Codable roundtrip.
  - Vstupní kontrakt jako `WaveformSync`: mono `[Float]` + vzorkovací frekvence, převzorkování je věc volajícího.

## ✅ FÁZE 13 — barevné presety (HOTOVÁ 29. 07. 2026)

✅ **Modul 3 — UI presetů (29. 07. 2026): FÁZE 13 JE TÍM HOTOVÁ.**

  - **`ColorGradePanel` v pásu inspektoru:** picker (Bez úpravy / Jemný svatební / Teplý film / Čistá pleť / Černobílá) + posuvník Síla 0–100 %. Výběr presetu = jeden undo krok; posuvník skládá undo kolem tažení (vzorec hlasitosti a zoomu, `colorGradeDragBegan/Changed/Ended` na controlleru). Přepnutí presetu drží nastavenou sílu; „Bez úpravy" preset maže.
  - **Umístění:** u vybraného VIDEO klipu vedle editoru rychlostní křivky (HStack, panel 260 b), u fotky vedle inspektoru Ken Burns — preset patří obrazu, u zvukového klipu se panel neukazuje (`selectedVideoClip()` kontroluje druh STOPY). Náhled se při změně přestaví sám (`rebuildTimelineComposition` — týž mechanismus jako Ken Burns).
  - **Ověřeno screenshotem běžící aplikace (`--color-demo`):** tři klipy, prostřední s ČB presetem a vybraný — náhled pod hlavou je ČERNOBÍLÝ, v inspektoru panel s pickerem „Černobílá" a sílou 100 %, na ose žlutý rámeček výběru. UI → model → kompozice → přehrávač funguje živě.
  - *Koukanec rukou (v seznamu): preset v náhledu při přehrávání, síla plynule, kombinace s prolínačkou a Ken Burns.*

✅ **Modul 2 — presety hrají v kompozici, náhledu i exportu (29. 07. 2026).**

  - **Jedno místo sémantiky, dvojí emise.** `CompositionBuilder.computeSpans` počítá úseky obrazové kompozice (hranice = okraje VŠECH vkladů + oblasti přechodů; každá vrstva úseku má jednu dvojici krajních hodnot transformace a průhlednosti + případný preset). Z týchž úseků se **bez presetů** emitují standardní instrukce (vestavěný kompozitor — dosavadní cesta) a **s presety** vlastní `ColorCompositionInstruction` + `customVideoCompositorClass = ColorVideoCompositor` — geometrie obou cest se nemůže rozjet. Regrese ověřena: `--transition-check` i `--photo-check` po přestavbě dávají ČÍSLO PO ČÍSLE stejné výsledky jako ve fázích 10/12 (79/0, 0,7/12,9/13,1; 244/0, 0→254).
  - **⚠️ Odchylka od zápisu rozhodnutí z modulu 1, zdůvodněná:** instrukce NEjsou podtřída `AVMutableVideoCompositionInstruction` čtená gettery — player item si video kompozici KOPÍRUJE a kopie podtřídy by šla přes NSCopying rodiče, který o přidaných polích neví. Vlastní objekt `AVVideoCompositionInstructionProtocol` se drží referencí (dokumentovaný vzorec pro vlastní compository). Data instrukcí dodává `computeSpans`, gettery nejsou potřeba.
  - **`ColorVideoCompositor`** (CoreImage): pozadí → vrstvy odzadu dopředu (preset → transformace → alfa → source-over). Presety v `ColorPresetFilter` — jediné místo, kde se z volby modelu stávají CIFiltry (`CIPhotoEffectFade`+`CIColorControls`, `CIPhotoEffectTransfer`, `CIColorControls`, `CIPhotoEffectMono`); intenzita = `CIDissolveTransition` originál→filtrovaný.
  - **⚠️ Dvě pasti CoreImage, obě chycené kvantitativní kontrolou (první běhy `--color-check` selhaly, oprava měřením potvrzená):**
    1. **Symetrie barevného prostoru.** Pracovní prostor CI i cíl renderu MUSÍ být prostor odvozený z atributů zdrojového bufferu (`CVImageBufferCreateColorSpaceFromAttachments`) — s výchozím (lineárním) pracovním prostorem a natvrdo daným 709 se středy tónů posouvaly o ~15 jasu a směsi vycházely lineárně, zatímco vestavěný kompozitor míchá KÓDOVANÉ hodnoty (F10 to změřila). Po opravě je round trip nefiltrovaného snímku identita (odchylka 0,10 jasu).
    2. **`CIColorMatrix` počítá na NEpremultiplikovaných hodnotách.** Škálovat průhlednost přes RGB i alfu = po zpětné premultiplikaci násobit barvu DVAKRÁT — směs prolínačky vyšla o² (poměr 0,26 místo 0,5). Správně se škáluje JEN alfa; pak poměr 0,49.
  - **Ověřeno `--color-check` kvantitativně** (dvojí export: video + tři červené fotky, ČB naplno / ČB 50 % / prolínačka barevná↔ČB): pas-through video **0,10** jasu, fotka 0,01 (compositor nemění, co barvit nemá); ČB saturace **243 → 0**; intenzita 50 % → poměr saturace **0,49**; směs na střihu prolínačky **0,49**. Sonda exportu: 3840×2160 HEVC, **240×3000 ticků, kolísání 0,0 %, CFR** — mřížka drží i přes vlastní compositor.
  - **⚠️ GPU skok ZMĚŘEN (`--color-gpu on|off`, vzorec F10 — `ioreg` 1 Hz, markerový soubor):** bez presetů medián **0 %** (přímá cesta, baseline drží), s presety **medián 24 %, rozsah 8–36 %** při 4K/30 přehrávání. Je to ~dvojnásobek skoku přechodů (F10: ~12 %) — CoreImage dělá YUV→RGB→filtr→YUV na každém snímku. Přehrávání plynulé; poklesy v řadě jsou restarty 6s smyčky.
  - Preset s intenzitou 0 nebo vadný se v kompozici ignoruje (klip hraje natvrdo, vadu hlásí `validate()` — vzorec vadné rampy) a drahá cesta se nezapíná.
  - *Koukanec rukou (v seznamu): preset na klipu v náhledu, plynulost přehrávání s presety.*

✅ **Modul 1 — model: `ColorGrade` na klipu + ROZHODNUTÍ o technice renderování (29. 07. 2026).** Čistý Swift, **+14 testů, celkem 365, 0 selhání**; aplikace se s novým modelem překládá beze změn.

  - **`ColorGrade`** = `ColorPreset` (jemný svatební `softWedding`, teplý film `warmFilm`, čistá pleť `cleanSkin`, ČB `blackAndWhite` — syrové hodnoty jsou smlouva formátu, hlídá je test) + intenzita 0–1 (UI ukáže 0–100 %; **nula je legální** — obraz beze změny, ale volba presetu zůstává). Model nese JEN volbu; které CIFiltry s jakými parametry preset znamená, ví až kompoziční vrstva — vzhled jde ladit bez zásahu do formátu souboru.
  - **Preset patří KLIPU** (plán F13: „per klip, intenzita"), jen na obrazové stopě — fotka ano (je to obrazový klip), zvukový klip ne (`colorGradeNeedsVideoTrack`). Zapisuje se přes `setColorGrade`, invarianty 27–28 (preset mimo obrazovou stopu, intenzita mimo 0–1). Volitelné pole na `Clip`, staré soubory se čtou dál, verze formátu zůstává 2 (vzorec `kenBurns`).
  - **Dědění: split, duplicate i ocásek po overwrite preset drží** — test na split hned první běh odhalil, že `splitSingle` staví pravou polovinu výslovným konstruktorem a nové pole by ztratil; stejná díra byla v `duplicate` a v ocásku `overwrite`. Všechna tři místa opravená a zamčená testy. (Ken Burns tudy prošel správně už ve F12 — pole se předávalo.)
  - **⚠️ ROZHODNUTÍ (kritérium plánu — shoda náhled/export a výkon): vlastní `AVVideoCompositing`, NE `applyingCIFiltersWithHandler`.** Podklady z dokumentace (pravidlo 6):
    - `init(asset:applyingCIFiltersWithHandler:)` volá handler „once for each frame … from the asset's **first enabled video track**" — jenže naše kompozice má od F10 VÍC drah (A/B rozklad prolínaček). Klipy na dráze B by filtr nedostaly a přechody by nehrály vůbec: inicializátor si staví VLASTNÍ instrukce, takže naše opacity/transform rampy a aspect-fit zahodí. Navíc si sám nastavuje `frameDuration` z `nominalFrameRate` — o kterém máme ZMĚŘENO, že lže (119,369 vs. 120,000) — a od iOS 18 je deprecated. <https://developer.apple.com/documentation/avfoundation/avmutablevideocomposition/init(asset:applyingcifilterswithhandler:)>
    - Vlastní compositor (macOS 10.9+) je dokumentovaná cesta: AVFoundation mu předává **instrukce kompozice** a per snímek `AVAsynchronousVideoCompositionRequest` se snímky **všech** stop instrukce — víc drah není problém. <https://developer.apple.com/documentation/avfoundation/avvideocompositing>
    - Stávající `makeVideoComposition` může zůstat: standardní instrukce jdou ve vlastním compositoru ČÍST dokumentovanými gettery (`getOpacityRamp` macOS 10.7+, `getTransformRamp` totéž) — compositor převezme touž sémantiku a přidá CIFilter per klip. <https://developer.apple.com/documentation/avfoundation/avvideocompositionlayerinstruction/getopacityramp(for:startopacity:endopacity:timerange:)>
    - Shoda náhled/export je konstrukcí (tentýž `videoComposition` objekt dostává player item i `CFRRenderer` — vzorec F10), kvantitativně ji ověří `--color-check` v modulu 2. Poznámka z CLAUDE.md „vlastní `AVVideoCompositing` speed ramping neřeší" platí dál a nekoliduje — compositor je na PIXELY, přesně tohle.
  - **Dvoucestná filozofie zůstává:** bez presetu/přechodu/Ken Burns se video kompozice vůbec nestaví a platí GPU baseline z fáze 1; s presetem se čeká skok třídy F10 (medián ~12 %) — změří ho `--color-gpu` sonda v modulu 2.
  - *Koukanec rukou: zatím není na co — preset je v modelu, hrát začne modul 2.*

## ✅ FÁZE 12 — fotky a Ken Burns (HOTOVÁ 29. 07. 2026)

✅ **Modul 1 — model: fotka jako asset, klip s volnou délkou, Ken Burns (29. 07. 2026).** Čistý Swift, **+15 testů, celkem 351, 0 selhání**; aplikace i balíčky se překládají beze změn.

  - **`Asset.isStill`** (vyrábět přes `Asset.still(url:bookmark:)` — nastavuje `hasAudio: false`, aby fotka nešla na zvukovou stopu). `duration` a `measuredFrameRate` jsou u fotky nula a validace je nevymáhá; starší soubory pole nemají a čtou se jako `false` (custom dekodér, vzorec `Track.transitions`), verze formátu se nezvedá.
  - **Klip fotky zdroj NEspotřebovává** — chování titulku na obrazové stopě. Větve jsou VÝHRADNĚ ve čtyřech schválených místech zdrojové matematiky (`sourceConsumption` → nula, `sourceOffset` → stojí, `remainingSourceFrames`/`availableSourceFramesBefore` → `Int.max/2`) a v `makeClip` (výchozích 5 s) — trim, split, přesun, přechody i interakce z nich meze dostávají zadarmo. Test: natažení fotky na minutu projde, split drží `sourceStart` 0, prolínačka vedle fotky má „nekonečný" přesah a nepřeteče.
  - **`KenBurns`** = počáteční a koncový výřez v normalizovaných souřadnicích (`NormalizedRect` — vlastní typ, ne `CGRect`, model se překládá bez CoreGraphics). `setKenBurns` vymáhá: jen na fotce (`kenBurnsNeedsStill`), výřezy v obraze a ≥ 5 % (`invalidKenBurns` — menší výřez je rozmazaná kaše). Split/duplicate/overwrite Ken Burns dědí (je vztažený k délce klipu). Kompozice z něj udělá lineární `TransformRamp` — modul 3.
  - **Rychlostní křivka na fotce ZAKÁZANÁ** (`rampOnStillClip` + invariant 24) — fotka stojí z definice; freeze frame se dělá fotkou, ne nulovou rychlostí (invertibilita `SpeedRampEngine` nedotčená, přesně podle plánu).
  - Invarianty 24–26 (rampa na fotce, Ken Burns na videu, vadný výřez); fotkový asset nesmí předstírat zvuk ani zapírat obraz (rozšířený invariant `invalidAsset`).

✅ **Modul 2 — fotka v kompozici, náhledu a exportu (29. 07. 2026).**

  - **`StillMovieStore` (actor):** fotka nemá video stopu a do `AVComposition` se vkládat nedá — vyrobí se z ní JEDNOU film o JEDNOM ProRes snímku v rozměru plátna, s **vpáleným aspect-fitem** (černé pruhy) a EXIF orientací narovnanou při čtení (`CGImageSourceCreateThumbnailAtIndex` s `kCGImageSourceCreateThumbnailWithTransform` — jinak fotky na výšku leží na boku; velké fotky se rovnou podvzorkují mezí plátna). Cache `Application Support/StillMovies/<sha256(cesta|velikost|mtime|plátno)>.mov` — otisk jako vlny a proxy; zápis vedle a přejmenování po úspěchu. Vpálený aspect-fit je schválně: mezisoubor se chová jako každé jiné video, bez přechodů nevzniká video kompozice a **GPU baseline z fáze 1 platí i s fotkami**.
  - **`CompositionBuilder`:** klip fotky = vložený jeden snímek mezisouboru roztažený `scaleTimeRange` přes délku klipu — zero-order hold pak v přehrávači i exportu drží tentýž obraz, což je u fotky přesně to, co má dělat. Nečitelná fotka = mezera, ne pád (vzorec offline assetů). Kdyby kvůli přechodům vznikla video kompozice, geometrie fotky je plátno + identita.
  - **Import: menu Soubor → „Přidat fotky…"** (HEIC/JPEG/PNG, security-scoped bookmark hned) — fotky se PŘIDÁVAJÍ na konec V1 do rozdělané práce, nepřepisují osu jako import klipů. Jeden undo krok. Na ose se fotka kreslí jako obrazový klip (je to `Clip` na V1 — kreslení zadarmo).
  - **Ověřeno CLI `--photo-check` kvantitativně:** syntetický bílý čtverec 1000×1000 → osa video (0–60) + fotka (60–150) → export 150 snímků. Snímek fotky: **střed 244 jasu, pruhy 0** (aspect-fit čtverce do 16:9 přesně); fotka drží do posledního snímku (zero-order hold); snímek videa nedotčený. Vytažený snímek okem: bílý čtverec uprostřed, černé pruhy po stranách.
  - *Koukanec rukou (odloženo autorem, v seznamu): Přidat fotky…, fotka v náhledu při přehrávání a scrubování, natažení délky fotky tažením okraje.*

✅ **Modul 3 — Ken Burns v kompozici, inspektor fotky a freeze frame (29. 07. 2026): FÁZE 12 JE TÍM HOTOVÁ.**

  - **Ken Burns v `CompositionBuilderu`:** výřezy (normalizované vůči PLÁTNU — mezisoubor fotky má rozměr plátna, sémantika upřesněná v modelu) → `setTransformRamp` s lineární interpolací. Krajní hodnoty úseků instrukcí se interpolují PO SLOŽKÁCH — přesně tak rampu interpoluje kompozice sama, takže úseky navazují beze švů (kombinace KB + přechod na témže klipu funguje). Klip s KB vynucuje video kompozici — GPU skok stejné třídy jako u přechodů (změřeno F10, medián ~12 %), bez KB a přechodů zůstává přímá cesta.
  - **Inspektor fotky** (pás pod přehrávačem místo editoru křivky — rampa na fotce je zakázaná): pohyb Bez pohybu / Nájezd / Odjezd + zoom 1,1–2,0× (posuvník = jeden undo krok, vzorec hlasitosti). Výřezy drží poměr plátna a sedí ve středu; volné obdélníky model umí, UI je nabídne, až bude důvod.
  - **Freeze frame:** kontextové menu klipu → „Zmrazit snímek (fotka na konec osy)" — snímek pod hlavou se vytáhne z ORIGINÁLU (`AVAssetImageGenerator`, zero tolerance, `preferredTransform`) jako PNG do kontejneru (`FreezeFrames/`, bez bookmarku — kontejner sandbox pustí) a položí jako fotka na konec V1. Fotka, ne nulová rychlost — zákaz z plánu platí. Na fotce jsou rampa/sync/přepis v menu VYPNUTÉ s vysvětlením (přiznané meze).
  - **Ověřeno CLI:** `--photo-check` rozšířen o klip s nájezdem — pruhy na začátku **0**, na konci **254** (nájezd do bílého čtverce je vytlačil z obrazu), snímek uprostřed pohybu okem sedí (čtverec větší, pruhy tenčí). `--freeze-check`: fotka vznikne na konci osy a od zdrojového snímku pod hlavou se liší o **1,29** jasu (dekodér+PNG, prakticky shoda).
  - *Koukanec rukou (v seznamu): inspektor fotky mění pohyb v náhledu, zmrazit snímek z menu.*

## ✅ FÁZE 11 — texty, titulky a stopa T1 (HOTOVÁ 29. 07. 2026)

✅ **Modul 1 — model: druh stopy `.title`, titulkový klip, T1 (28. 07. 2026).** Čistý Swift v `TimelineModelu`, **+25 testů, celkem 326, 0 selhání**; aplikace se s novým modelem překládá beze změn.

  - **`TitleClip` NENÍ `Clip`** — nemá asset, zdrojový čas, rampu ani vazbu; nacpat ho do `Clip` by znamenalo volitelné `assetID` a věčné řešení `nil` všude. Vlastní typ s úložištěm `Track.titles` — týž vzorec jako `Transition`. Nese text, šablonu (`plain`/`names`/`dateAndPlace`/`chapter`/`thanks` — vzhled si přeloží až vykreslení), zarovnání a pozici+délku ve snímcích osy. Chování na ose sdílí s klipy: dotyk není překryv, stopa seřazená.
  - **T1 je v `Project.empty()` ZÁMĚRNĚ poslední** — aplikace si na šesti místech domýšlí `tracks[0]` = V1 a `tracks[1]` = A1 (ContentView, CLI ověření). Pořadí v poli je datové; kde T1 leží na obrazovce, rozhodne UI modul. Test tuhle smlouvu hlídá.
  - **Operace:** `makeTitle` (model razí ID i výchozí délku 4 s), `addTitle`, `removeTitle`, `moveTitle` (i mezi titulkovými stopami), `trimTitleStart/End` (bez zdrojových mezí — titulek žádný zdroj nemá), `setTitleText/Template/Alignment` (pro budoucí inspektor), `ensureTitleTrack` (projekty z doby před fází 11 si T1 doplní tudy, ne dekodérem). Překryv vrací `titleWouldOverlap(nearestLegal:)` — vzorec `wouldOverlap`, UI na něm zarazí tažení.
  - **Invarianty 18–23:** titulek jen na titulkové stopě (obrácený směr — asset klip na T1 — hlásí stávající č. 8), seřazenost, překryvy, kladná délka, nezáporný začátek, jedinečnost ID. Asset klip na T1 odmítá i `checkPlacement` (ternár `video/audio` nahrazen switchem).
  - **Formát souboru v2.** Nový PŘÍPAD enumu `TrackKind.title` není volitelné pole — starší aplikace by na něm spadla dekódovací chybou místo srozumitelného „soubor je z novější verze", a výchozí projekt teď T1 obsahuje vždy. Soubory verze 1 se dál načtou (test na doslovném JSON z doby před fází 11); pole `Track.titles` se u nich čte jako prázdné (vzorec `transitions`).
  - **Drobnosti kolem:** `project.duration` počítá i titulky (závěrečné poděkování za posledním záběrem film prodlužuje — přes černou); geometrie zná výšku titulkové stopy (28 b); hrany titulků jsou kandidáti přichytávání.
  - *Koukanec rukou: zatím není na co — stopa je v modelu, kreslit ji začne modul 2.*

✅ **Modul 2 — titulky v náhledu a pruh T1 na ose (28. 07. 2026).** Rozložení „logika do modelu": **+4 testy (celkem 330)** na `titleCues()` (seřazené promítnutí pro overlay, nese šablonu i zarovnání), `titlePlacements` (viditelnostní filtr, souřadnice dokumentu, nese text — titulků jsou jednotky, slovník netřeba) a `subtitleStripPlacements` (pásky řeči v pruhu PRVNÍ titulkové stopy; hotové cues dodává volající — přepočet patří do reloadu, ne do scrollu; bez T1 prázdné).

  - **`TitleOverlay` v náhledu:** týž vzorec jako `SubtitleOverlay` (cues přepočítané jen při změně projektu s debounce 150 ms, na tik hlavy jen filtr, kreslí se JEN když má co říct — GPU baseline chráněná, při měřeních schovaný). Šablona tady dostává konkrétní podobu: jména velkým patkovým písmem přes střed, kapitola/poděkování/datum menší pod sebou, prostý text v dolní třetině NAD řečovými titulky. Velikosti jsou zlomky výšky náhledu; **stín místo podkladové desky** — deska je poznávací znak řečového titulku, grafika leží na obraze.
  - **Pruh T1 v `TimelineDocumentView`:** `TitleLayer` (CALayer + CATextLayer, žádné `draw` — past `ContentLayer` platí), terakotová výplň (nová v paletě: neplete se s modrou/zelenou/fialovou/žlutou), recyklace ručně jako u přechodů, text přepisovaný jen při změně. **Pásky titulků z řeči**: tenké zelené proužky při spodní hraně pruhu (zvuková zelená s průhledností — řeč žije ve zvuku a pásek je projekce, ne uchopitelný objekt), pod titulkovými klipy, recyklované indexem (nemají identitu). Cues v mezipaměti obnovované v `rebuildClipInfo`.
  - **Ověřeno screenshoty běžící aplikace (`--title-demo`):** jména patkovým písmem uprostřed náhledu SOUČASNĚ s řečovým titulkem na desce dole; na ose tři terakotové titulky na T1 a zelený pásek řeči viditelný v mezeře mezi nimi. Demo staví osu s titulky a syntetickým přepisem, postaví hlavu do jmen a drží okno ~25 s v popředí.
  - Interakce s titulky na ose zatím ŽÁDNÁ (tažení, menu, výběr) — modul 3; overlay i pruh jsou čistě kreslení.

✅ **Modul 3 — interakce titulků a inspektor (28. 07. 2026).** Logika v modelu (**+6 testů, celkem 336**), view jen předává souřadnice a kreslí duchy:

  - **Model:** `titleHitTest` (tělo/okraje, úchopy v BODECH — zásadní pravidlo geometrie), náhledy tažení `titleMovePreview` (přichytává začátek i konec, bližší vyhrává; neplatný cíl HLÁSÍ, nezařezává) a `titleTrimStart/EndPreview` (zaražené o sousedy, nulu a minimální délku 1 snímek), `maxNewTitleDuration` (mezera pro nový titulek — menu z ní bere výchozí délku i vypnutí položky), `snapCandidates` umí vyloučit tažený titulek.
  - **Splátka fáze 8 — editace titulků z řeči:** `speechCueRef(at:)` vrací úsek přepisu POD snímkem osy i s adresou (asset + index) — `subtitleCues` provenienci zahazuje, inspektor ji potřebuje; `setTranscriptText` edituje text úseku, **prázdný text úsek maže** (oprava artefaktu i odstranění jednou cestou). Jde přes `setTranscript`, takže platí jeho validace.
  - **Interakce na ose:** klik vybírá titulek (žlutý rámeček), tažení těla = přesun, okrajů = trim — duch + JEDEN zápis při puštění (vzorec `move`/přechodů), Escape ruší, Shift vypíná přichytávání, Delete maže vybraný titulek, kurzory na okrajích. Klik na pásek řeči vybírá úsek přepisu. **Výběry se navzájem vylučují** (`selectClips`/`selectTitle`/`selectSpeech` na controlleru) — inspektor ukazuje právě jednu věc.
  - **Kontextové menu pruhu T1:** na volném místě „Přidat titulek: Jména / Datum a místo / Kapitola / Poděkování / Prostý text" (výchozí délka 4 s zaražená o mezeru; obsazené místo = vypnutá položka s vysvětlením), na titulku „Smazat titulek". Nový titulek se rovnou vybere — inspektor se otevře a uživatel hned píše.
  - **Inspektor v pásu pod přehrávačem** (`InspectorStrip` přepíná: editor křivky ↔ inspektor titulku ↔ inspektor řeči — vlastní malé view kvůli pasti s vnořeným `ObservableObject`). Titulek: text ŽIVĚ (v náhledu se mění při psaní; undo krok se skládá kolem fokusu — vzorec posuvníku hlasitosti), šablona a zarovnání jako pickery, Smazat. Řeč: koncept zapisovaný při odchodu z pole/Enterem — živě to nejde, prázdno je při psaní legální mezistav, ale prázdný text maže úsek.
  - **Ověřeno screenshotem** (`--title-demo` teď první titulek rovnou vybírá): žlutý rámeček na „Anna a Petr" na T1 a inspektor s textem, šablonou „Jména", zarovnáním a Smazat. Tažení/menu/editace jsou kryté testy modelu + vzorci z přechodů; ruční koukanec v seznamu níže.

✅ **Modul 4 — titulky vypálené do exportu (29. 07. 2026): FÁZE 11 JE TÍM HOTOVÁ.**

  - **⚠️ Odchylka od plánu, rozhodnutá a zapsaná (i v CLAUDE.md): `AVVideoCompositionCoreAnimationTool` se NEPOUŽÍVÁ.** Je dokumentovaný pro `AVAssetExportSession` — kterou projekt schválně nepoužívá, protože ignoruje `frameDuration` (celý důvod existence `CFRRendereru`). Chování animation toolu na cestě `AVAssetReader`+`AVAssetWriter` dokumentace nepopisuje a stavět export na nedokumentovaném chování je chyba z pravidla 6. Plán tuhle kolizi neviděl.
  - **Místo toho `frameDecorator` v `CFRRendereru`:** volitelná úprava snímku před zápisem — dostane pixel buffer a index výstupního slotu (slot, ne PTS: podržený snímek může v každém slotu potřebovat jinou dekoraci). Bez dekorátoru se nezměnilo nic; ProRes/proxy cesty se ho nedotknou.
  - **`TitleExportRenderer` (appka):** z `titleCues()` předrenderuje overlay (CoreText/AppKit do CGImage, jednou na běh se stejnou množinou aktivních titulků — titulky jsou statické) a CoreImage ho složí nad NV12 buffer do nového bufferu z poolu (barevné atributy se přenášejí, výstup v ITU-R 709). **Typografie zrcadlí `TitleOverlay`** (zlomky výšky plátna, patková jména přes střed, prostý text dole, stín místo desky) — obě místa se musí měnit spolu, zapsáno u obou.
  - **Ověřeno CLI `--title-check` kvantitativně:** dvojí export téže osy (titulek „Anna a Petr" přes snímky 30–90 vs. bez). Uvnitř titulku odchylka **16,5** a střední pás obrazu **+22 jasu** (bílý text) — titulek v souboru je; mimo titulek odchylka **0,14** — snímky bez titulku projdou nedotčené (zbytek je šum HEVC kodéru). Vytažený snímek z exportu okem odpovídá náhledu (velká patková jména se stínem uprostřed).
  - Řečové titulky se NEvypalují — dodávají se jako SRT (spec s vypalováním nepočítá, rozhodnutí fáze 8 platí).

## ✅ FÁZE 10 — přechody (HOTOVÁ 28. 07. 2026)

✅ **Modul 1 — model `Transition` v `TimelineModelu` (28. 07. 2026).** Čistý Swift, **+30 testů, celkem 284, 0 selhání**; aplikace se s novým modelem překládá beze změn.

  - **Přechod patří STŘIHU, ne klipu:** `Transition` žije na stopě a drží dvojici (levý, pravý klip); platí, jen dokud ty dva na ose skutečně sousedí. Druhy: prolínačka, zatmívačka do černé/bílé (obraz), crossfade (zvuk) — druh se kontroluje proti druhu stopy. Na jednom střihu nejvýš jeden; přepsání zachovává ID (výběr v UI se nemá rozpadnout kvůli změně délky).
  - **Oblast:** celková délka D snímků, před střihem ⌊D/2⌋, za ním zbytek (liché délky přidávají snímek ZA střih — pevně, ne podle nálady). Prolínačka a crossfade **spotřebovávají zdroj za hranou střihu na obou stranách** (meze přes hotové `remainingSourceFrames`/`availableSourceFramesBefore`); zatmívačka žádný přesah nepotřebuje — levý dojede do barvy ve svých snímcích, pravý se z ní vynoří ve svých.
  - **`maxTransitionDuration`** — model spočítá největší legální délku střihu (vejití do dvojice, zdrojové přesahy, oblasti sousedních přechodů) a `setTransition` ji vymáhá; při překročení ji vrací v chybě `transitionTooLong(maxDuration:)` — **z té UI v modulu 3 udělá zarážku tažení** (vzorec `wouldOverlap.nearestLegal`). Property test: na maximu projde vždy, nad ním nikdy (40 kol, seedovaně).
  - **Dvě pravidla pro editace, vymáhaná operacemi:** ① střih zanikl (smazání, přesun, mezera po trimu, ripple, overwrite, closeGap) → **přechod umírá s ním** (undo ho vrátí, snapshoty nesou celý projekt); ② střih žije, ale operace by přechod rozbila (trim pod rameno oblasti, slip pod zdrojový přesah, roll mimo meze, split vedený oblastí) → **operace se odmítne** s `blockedByTransition` — žádné tiché zkracování. Jediné místo vyhodnocení pravidel je `transitionDefects()`; `validate()` z něj překládá 6 nových invariantů (12–17), operace přes `reconcileTransitions`.
  - **Split/join přechody přepojují:** levá polovina dědí ID originálu (levý střih drží sám), přechod na pravém střihu se přepojí na pravou polovinu; join maže přechod zaniklého vnitřního střihu a vnější přepojí na slepenec.
  - **Rampovaný střih zakázán OBĚMA směry** (v1 dle plánu): přechod na rampu nejde přidat (`transitionOnRampedCut`) a rampa na klip s přechodem taky ne (`blockedByTransition`) — UI řekne „napřed smaž přechod".
  - **Starší projektové soubory se dál načtou:** pole `Track.transitions` se čte jako prázdné, verze formátu se nezvedá (týž vzorec jako `Asset.transcript`); test dekóduje stopu z JSON bez toho pole.

✅ **Modul 2 — přechody hrají v kompozici i exportu (28. 07. 2026).** Rozložení práce podle pravidla „logika do modelu":

  - **`TrackCompositionPlan` v `TimelineModelu` (+8 testů, celkem 292):** čistá logika A/B rozkladu stopy — prolínačka/crossfade posílá sousedy na dvě dráhy kompozice s rameny přes hranu střihu (levému se prodlouží konec, pravému PŘEDSADÍ začátek s posunutým zdrojem), zatmívačka zůstává na jedné dráze bez ramen. Vydává vklady (`Placement`: dráha, rozsah, zdrojový výřez) a předpisy oblastí (`Overlay`). Vadné přechody (ručně rozbitý projekt) plán ignoruje — klip hraje natvrdo, vadu hlásí `validate()`, stejný vzorec jako vadná rampa.
  - **`CompositionBuilder` plán jen převádí na AVFoundation:** dráhy = stopy kompozice, instrukce `AVMutableVideoComposition` s `setOpacityRamp` (prolínačka: odcházející navrchu stmívá 1→0 nad nastupujícím — lineární směs; zatmívačka: pokles do barvy pozadí instrukce a zpět, černá/bílá), zvukový crossfade = `setVolumeRamp` dvojice v `audioMix(project:)`, takže přežívá i živou změnu hlasitosti stopy (po odchodové rampě se hlasitost VRACÍ — na téže dráze leží další klipy). **Video kompozice vzniká JEN když na obraze opravdu leží přechod** (vzorec `SubtitleOverlay`) — bez něj je přehrávací cesta bajt po bajtu ta z fází 3–5 a GPU baseline platí dál.
  - **Aspect-fit transformace klipů:** s video kompozicí přestává obraz škálovat `AVPlayerLayer` — instrukce MUSÍ nést napřímení (`preferredTransform`), zmenšení a vycentrování na plátno, jinak by klip (a hlavně poloviční proxy) ležel v rohu 1:1.
  - **Export toutéž kompozicí:** `CFRRenderer` dostal volitelný `videoComposition` — čte přes všechny obrazové stopy, co vidíš v náhledu, to dostaneš v souboru. Bez přechodů se nic nemění (ověřeno `--export-check`: 4739 snímků, shodné s fází 9 do posledního čísla).
  - **Ověřeno CLI `--transition-check` kvantitativně:** zatmívačka — jas okolí 79/80, na střihu **0**; prolínačka — snímek na střihu (opacity 0,5) porovnán PO PIXELECH s průměrem obou zdrojových snímků: odchylka od směsi **0,7**, od čistých stran 12,9/13,1 — je to skutečná směs, ne tvrdý střih (průměrný jas by tvrdému střihu prošel, tenhle test ne). Sonda výstupu: 3840×2160 HEVC, 30,00 fps měřených, **kolísání 0,0 %, CFR**, délka přesně 6,000 s — ramena přechodů délku osy nemění.
  - **⚠️ GPU skok ZMĚŘEN — očekávaný, plánovaný, nastal (28. 07. 2026).** Režim `--transition-gpu on|off` přehrává touž osu ~20 s v popředí, vedle vzorkuje skript `ioreg` „Device Utilization %" (1 Hz). Výsledky: klid 0–3 %, přehrávání 4K/30 BEZ kompozice 0–10 % (medián ~2 % — potvrzuje baseline fáze 1 „holé video GPU skoro nepotřebuje"), S kompozicí **8–16 %, medián ~12 %**. ⚠️ Metrika je jiná než ve fázi 1 (`powermetrics` chce sudo/heslo, které CLI běh nemá) — srovnávat spolu jdou jen tahle dvě čísla měřená STEJNĚ, ne proti 0,25 %/9,90 % z fáze 1. Nuly uvnitř „on" běhu jsou okamžiky restartu 6s smyčky, ne výpadek.
  - Dvě pasti do sbírky: **① stdout CLI běhu se do roury bufferuje až do konce procesu** (i pod `script` pty na macOS) — synchronizace vnějšího měření jde přes markerový soubor v kontejneru, ne přes print; **② konec itemu poznávej ze `timeControlStatus == .paused`**, ne z času hlavy — periodický pozorovatel nemusí poslední snímek tiknout a smyčka čekající na `currentTime ≥ konec` se nikdy nedočká.
  - *Koukanec rukou zatím neproběhl (odloženo autorem): prolínačka/zatmívačka v náhledu okem, plynulost přehrávání přes přechod.*

✅ **Modul 3 — UI přechodů (28. 07. 2026): FÁZE 10 JE TÍM HOTOVÁ.** Rozložení opět „logika do modelu":

  - **`TransitionGeometry` v `TimelineModelu` (+9 testů, celkem 301):** `transitionPlacements` (kde leží lichoběžník, viditelnostní filtr), `transitionHitTest` (tělo/okraje, úchopy v BODECH podle zásadního pravidla geometrie), `cutHit` (nejbližší střih do tolerance 2× úchopu — cíl kontextového menu) a `transitionDraggedDuration` — tažení okraje drží délku SYMETRICKY kolem střihu (2× vzdálenost), zaraženou o `maxTransitionDuration` a zdola o 2 snímky.
  - **Kreslení:** `TransitionLayer` (`CAShapeLayer`, žádné `draw` — past `ContentLayer` platí) nad klipy: horní hrana přes celou oblast, spodní se sbíhá ke střihu. Fialová — jediná na ose, neplete se s modrou/zelenou/žlutou/červenou. Recyklace ručně (přechodů jsou jednotky, diff aparát netřeba), obnovuje se uvnitř `refreshClips`.
  - **Interakce:** lichoběžník má přednost před klipy (události, kurzory, menu) — jinak by se pod ním naslepo trimovalo. Tažení okraje = duch + JEDEN zápis při puštění (vzorec `move`: mezistav při tažení by 60×/s přestavoval kompozici), Escape ruší, ⌘Z vrací. Tělo zatím nic nedělá — akce jsou v menu.
  - **Kontextové menu:** pravý klik poblíž střihu → „Prolínačka / Zatmívačka do černé / do bílé na střihu" (zvuková stopa: „Prolnutí zvuku"), výchozí délka 1 s zaražená o mez; na lichoběžníku nebo u obsazeného střihu „Odebrat přechod". **Nedosažitelný druh zůstává v menu VYPNUTÝ s vysvětlením v tooltipu** (chybí přesahy / není místo) — přiznané meze, ne zmizelá položka.
  - **Ověřeno screenshotem běžící aplikace** (`--transition-gpu on`): oba lichoběžníky sedí na střizích 2,0 s a 4,0 s, sbíhají se ke střihu, čitelné přes okraje klipů.
  - Vědomé drobnosti do vymazlení (F16): trim/roll zaražený přechodem (`blockedByTransition`) dnes tažení tiše nepustí — duch nezčervená, jen se nic nestane; přechod nejde vybrat klikem do těla (menu stačí).

  *Koukanec rukou celé fáze (odloženo autorem, v seznamu před kill-gate): menu na střihu přidá přechod, lichoběžník jde roztáhnout se zarážkou, Odebrat funguje, prolínačka v náhledu měkce prolne, zatmívačka projde barvou, zvukový crossfade je slyšet, export zní i vypadá stejně jako náhled.*

## ✅ SPIKE 0 UZAVŘEN (26. 07. 2026)

> **Dá se v AVFoundation udělat plynulá rychlostní křivka tak, aby zvuk seděl, nelupal a export nespadl?**
> **Ano.** Synchron 0,00 ms, žádné lupance ani při 545 segmentech, 17 exportů bez pádu, kódování 4–7× rychleji než reálný čas.

Hlavní technické riziko projektu je zavřené. **Rozsah MVP je reálný, staví se dál.** Detaily a vyplněná kritéria v `SPIKE_0.md`.

**Poslední otevřené kritérium je zavřené.** Plynulost náhledu 4K/60 se ve spiku změřit nedala (přehrávač neexistoval) — fáze 1 ji zodpověděla a **27. 07. 2026 byla přeměřena po opravě metodiky: náhled běží přesně na stropu 60Hz displeje, bez sekání.**

## ⏭️ Příští krok: KOUKANCE RUKOU, pak KILL-GATE 1

**Změna kurzu 28. 07. 2026:** svatební materiál bude až ~koncem srpna, kill-gate 1 se přesunul NA KONEC vývoje. Vylepšovací fáze 10–16 (plán v `IMPLEMENTACNI_PLAN.md`, sestavený výběrem z dokumentu `Projekt_Krasa_navrh_implementace.docx` + odložených drobností) jsou **hotové všechny**:

1. ✅ **F10 — přechody** (HOTOVÁ 28. 07.; GPU skok změřen — medián ~12 % s kompozicí)
2. ✅ **F11 — texty a titulky + stopa T1** (HOTOVÁ 29. 07.; obě splátky fáze 8 splacené, export přes `frameDecorator` místo CoreAnimationTool — viz oprava v plánu)
3. ✅ **F12 — fotky a Ken Burns** (HOTOVÁ 29. 07.; fotka přes „still movie" mezisoubor, freeze frame jako fotka)
4. ✅ **F13 — barevné presety** (HOTOVÁ 29. 07.; vlastní `ColorVideoCompositor` ověřený `--color-check`, GPU skok ~24 %, UI v inspektoru)
5. ✅ **F14 — hudební synchronizace** (HOTOVÁ 29. 07.; detekce ±0,1 BPM, doby v pravítku, magnet `.beat`, dopasování s přiznanými mezemi — VLAJKOVÁ)
6. ✅ **F15 — analýzy kvality** (HOTOVÁ 29. 07.; neostrost 93×, hluchá místa s pravidlem „dekorace není chyba", značky s klik=seek — jen návrhy, nikdy automatický střih)
7. ✅ **F16 — vymazlení** (HOTOVÁ 29. 07.; zvukové fade úchyty, strop −1 dBTP, správa Whisper modelu, dvě drobnosti z koukanců F10)

**⭐ Tím skončil plán fází 0–16.** Na něj navazuje **třetí vlna (fáze 17–21, sestavená 29. 07. 2026)** — detail v `IMPLEMENTACNI_PLAN.md`:

8. **F17 — ergonomie střihu** (osa sleduje hlavu, JKL, schránka, multi-výběr a hromadné operace, chronologie, export rozsahu) **← PŘED kill-gate, jediná výjimka**
9. **F18 — druhá obrazová stopa V2** (vrstvení kompozice už hotové z F10; chybí model, UI a vynucení video kompozice při překryvu)
10. **F19 — ducking hudby pod řečí** + úklid mixu na jednu obálku na stopu
11. **F20 — multikamera (sync dvou kamer), markery, třídění podle značek kvality**
12. **F21 — stabilizace obrazu** — zařazena 29. 07. na přání autora; **začíná spikem s právem přestat** (gumový obraz je reálné riziko), aplikace ve vlastním compositoru, ořez viditelný

Mezi F17 a F18 stojí koukance rukou (seznam níže) a kill-gate.

**Seznam koukanců (odškrtávat po projití):**

- [ ] **Přechody (F10):** pravý klik poblíž střihu → prolínačka/zatmívačka (na zvukové stopě prolnutí zvuku); lichoběžník na ose jde roztáhnout tažením okraje se zarážkou; „Odebrat přechod" funguje; nedosažitelná prolínačka je v menu vypnutá s vysvětlením; prolínačka v náhledu měkce prolne, zatmívačka projde černou/bílou, crossfade je slyšet; export vypadá i zní jako náhled.
- [ ] **Fotky a Ken Burns (F12):** Soubor → Přidat fotky… položí fotky na konec V1 (5 s); fotka hraje v náhledu při přehrávání i scrubování (aspect-fit s pruhy); délka fotky jde natáhnout tažením okraje bez omezení; inspektor fotky (výběr klipu fotky) přepíná Bez pohybu / Nájezd / Odjezd a zoom mění pohyb v náhledu; pravý klik na video klip → Zmrazit snímek udělá fotku na konci osy shodnou se snímkem pod hlavou; na fotce jsou rampa/sync/přepis vypnuté s vysvětlením; export vypadá jako náhled (fotka, pohyb i pruhy).
- [ ] **Texty a T1 (F11):** pravý klik na volné místo T1 → Přidat titulek (obsazené místo vypnuté s vysvětlením); nový titulek se vybere a v inspektoru jde hned psát — text se mění v náhledu při psaní; šablony mění vzhled (jména velká patková přes střed), zarovnání funguje; tažení těla přesouvá se zarážkou o sousedy, okraje trimují, Shift vypíná přichytávání, Escape ruší, Delete maže, ⌘Z vrací; klik na zelený pásek řeči → inspektor přepisu, úprava textu se propíše do titulku v náhledu, prázdný text úsek smaže; titulek za posledním klipem prodlouží film (přes černou); exportovaný film má titulky na stejných místech a se stejným vzhledem jako náhled.
- [ ] **Barevné presety (F13, po modulu 3):** preset na klipu se projeví v náhledu při přehrávání i scrubování; intenzita mění sílu plynule; přehrávání s presety na 4K ose je plynulé; export vypadá jako náhled; preset + prolínačka + Ken Burns dohromady fungují.
- [ ] **Hudba a doby (F14, po modulu 3):** Soubor → Přidat hudbu… položí skladbu na A2 a status řekne BPM s jistotou; jantarové doby v pravítku sedí na hudbě („raz" vyšší); tažení klipu se přichytává na doby (slaběji než na hrany, Shift vypíná); u ambientní hudby se tempo poctivě nenajde; dopasování klipu na dobu (modul 3) funguje a respektuje žlutou zónu.
- [ ] **Analýzy kvality (F15):** po importu se na rozmazaných úsecích klipů objeví oranžové/červené proužky nahoře a na hluchých místech (ticho + tma/prázdno ≥ 5 s) šedé dole (chvíli to trvá — analýza jede na pozadí); klik do proužku skočí hlavou na začátek problému; ostrý/živý klip proužky nemá; tichý záběr na dekoraci se NEhlásí.
- [ ] **Vymazlení (F16, drobnosti):** trim okraje klipu se opře o přechod (dál nepustí, ale duch nezmizí); klik do lichoběžníku přechod vybere (žlutý rámeček) a Delete ho smaže; v sidebaru je velikost modelu přepisu, „Smazat model" se ptá a „Přemístit model…" ho přesune bez nového stahování.
- [ ] **Zvukové fade (F16):** na zvukovém klipu jsou v horních rozích úchyty (bílá kolečka); tažením vznikne klín nájezdu/dojezdu, Escape ruší, ⌘Z vrací; fade je slyšet při přehrávání i v exportu; na hraně s prolnutím zvuku fade nefunguje (přechod má přednost).
- [ ] **Dotaz při zavírání (F5):** změna v projektu → ⌘Q ukáže Uložit/Neukládat/Zrušit (Escape ruší); týž dotaz po výběru souboru při ⌘O a importu; „Uložit" u neuloženého projektu přes „Uložit jako" — zrušení panelu ruší i zavírání.
- [ ] **Hlasitost stop (F7):** posuvník v hlavičce A1/A2 mění hlasitost ZA BĚHU přehrávání bez zastavení; M ztlumí a vrátí; ⌘Z vrací tažení jedním krokem; hodnoty přežijí uložení a otevření projektu.
- [ ] **Normalizace exportu (F7):** volba profilu u tlačítka exportu; po exportu status hlásí „Hlasitost X → cíl (gain ±Y dB)", případně poctivé omezení špičkami.
- [ ] **Sync klopáku (F7):** pravý klik na klip → Synchronizovat externí zvuk… → výběr nahrávky → zvuk na A2 sedí s obrazem; u nesouvisející nahrávky dialog s nízkou jistotou (nepoloží mlčky).
- [ ] **Titulky (F8):** pravý klik → Vytvořit titulky z řeči (poprvé stahuje model ~1,5 GB — chce síť a trpělivost); titulek se ukazuje při přehrávání i scrubbování; Soubor → Exportovat titulky (.srt) a soubor jde otevřít.
- [ ] **Offline scénář (F5, formálně neověřený):** přejmenovat složku s klipy, otevřít projekt — klipy zůstávají, assety offline, po vrácení složky se chytí.
- [ ] Drobnosti z F4: „Smazat proxy" a start s odpojeným externím diskem.

Pak: 🚧 **KILL-GATE 1 — sestříhat touhle appkou celou reálnou svatbu** (materiál ~konec srpna 2026). Při něm se přirozeně ověří i kritérium F4 (plynulost střihu na 200GB reálném materiálu) a přepis na reálné řeči. *(Dřívější seznam „vymazlovacích drobností" je teď rozpuštěný ve fázích 11 a 16 nového plánu.)*

## ⏭️ Původní zápis příštího kroku (historie)

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

## ✅ FÁZE 9 — uzavřená v rozsahu osobní aplikace (28. 07. 2026)

**Rozhodnutí autora: Developer účet se neplatí, appka je zatím jen pro něj.** Tím z fáze 9 odpadá podpis, notarizace i Sparkle (bez šíření nemají smysl) — celá distribuce je odložená a zapsaná v plánu jako návod pro případ, že by se někdy šířila. Licencování bylo vynecháno už dřív týž den (appka bude free). Z fáze zůstala a udělala se jen migrace na `Configuration` (modul 1 níže). **Tím je postavené všechno, co ořezaný plán pro osobní v1.0 předepisuje — před námi je už jen KILL-GATE 1 a koukance.**

✅ **Modul 1 — migrace škálovací kompozice na `AVVideoComposition.Configuration` (28. 07. 2026).** Přesně podle plánu fáze 9: dvojí implementace za jedním rozhraním (`ScalingVideoComposition.make` v ProbeKitu) — na macOS 26+ nové API přes `Configuration` (má `frameDuration` i `renderSize`; **API ověřeno proti swiftinterface SDK 26.5**, ne odhadem), na macOS 14–25 dosavadní `AVMutableVideoComposition`. Stará větev NESMÍ zmizet, dokud je deployment target 14.

  - Jediné místo použití byla škálovací kompozice v `CFRRendereru` (proxy + export); `CompositionBuilder` video kompozici nepoužívá vůbec, takže migrace je menší, než plán čekal.
  - **Ověřeno exportem přes novou větev** (na tomhle stroji běží ona) a sondou MediaProbe: 3840×2160 HEVC, měřených **30,0000 fps, kolísání 0,0 %, všech 4739 vzorků přesně 3000 ticků** — shodné s ověřením staré větve do posledního čísla.
  - Deprecation warning se při targetu 14 nehlásí (deprecace platí až od macOS 26) — „odklizení warningů" z plánu se tedy týká budoucího zvednutí targetu; větvení je připravené už teď.
  - Vedlejší oprava: CLI ověření (`--mix-check`, `--normalize-check`) už trvale nepřepisují uživatelské nastavení profilu hlasitosti (uloží a vrátí).

## ✅ FÁZE 8 — titulky (HOTOVÁ 28. 07. 2026)

Rozvrh: **1)** model přepisu + promítnutí na osu + SRT (hotový, níže), **2)** WhisperKit — závislost, stažení modelu `large-v3-turbo`, přepis assetu na pozadí, **3)** zobrazení na ose/v náhledu + export SRT v UI + editace textu.

✅ **Modul 1 — model přepisu, promítnutí na osu, SRT (28. 07. 2026).** Čistý Swift v `TimelineModelu`, **+14 testů, celkem 254.**

  - **Přepis patří ASSETU a je kotvený ve ZDROJOVÉM čase** (`Asset.transcript`, `setTranscript` validuje a řadí) — totéž rozhodnutí jako u uzlů ramp: střih, trim ani přesun s titulky nehnou, drží se na slovech. Test: split klipu uprostřed titulku → dvě poloviny navazují beze spáry. Volitelné pole, verze formátu souboru se nezvedá — staré projekty se dál načtou (test).
  - **`subtitleCues()` promítá přepisy na osu** přes kliky JEN zvukových stop (svázaný pár sdílí asset — jinak by byl každý titulek dvakrát). Mapování zdroj→osa inverzí `sourceOffset` binárním půlením, takže **funguje i pod rychlostní křivkou** — titulek na zpomaleném úseku se natáhne s řečí (test: hranice sedí s vlastním mapováním střihu na snímek přesně).
  - **`SRT.serialize`** — SubRip s čárkou v časech, číslování bez děr, prázdné texty se přeskakují, LF konce. Formát času otestovaný na hodinových hodnotách.
  - Kdo přepis vyrobí, je téhle vrstvě jedno — WhisperKit je modul 2; model je hotový a otestovaný dřív, než se stáhl jediný bajt závislosti.

✅ **Modul 2 — WhisperKit: přepis řeči funguje (28. 07. 2026).** První externí závislost projektu: balíček `argmaxinc/argmax-oss-swift` **v1.0.0** (produkt `WhisperKit`; repo i tag ověřeny `git ls-remote` před přidáním, API proti zdrojákům tagu — pravidlo 6).

  - **`TranscriptionService`:** model se načítá jednou za běh aplikace; zvuk připravuje `MonoAudioReader` (mono 16 kHz — formát Whisperu, a přes `AVComposition` kvůli edit listu). Čeština natvrdo (`language: "cs"`) — detekce jazyka s hudbou v pozadí umí uletět; VAD chunking dělí dlouhé nahrávky podle pauz v řeči, ne slepě po 30 s.
  - **Vstup do UI:** kontextové menu klipu → „Vytvořit titulky z řeči". Přepisuje se ZDROJOVÝ soubor a výsledek se ukládá k assetu (`setTranscript` s undo) — na osu ho promítá modul 1 přes všechny klipy téhož zdroje.
  - **Model:** ~1,5 GB v `Documents/huggingface` uvnitř kontejneru aplikace; stahuje se při prvním použití (nový entitlement `network.client` — jediné síťové použití v aplikaci, přepis běží lokálně). Správa místa (smazání/přemístění modelu) může přijít s fází 9.
  - ⚠️ **Past v názvosloví modelů:** OpenAI „large-v3-turbo" se v repozitáři `whisperkit-coreml` jmenuje **`openai_whisper-large-v3-v20240930`** (podle data vydání). Přípona `_turbo` tam značí komprimované varianty WhisperKitu — jiná věc. S "large-v3-turbo" stažení spadne na `modelsUnavailable`; zapsáno i v kódu.
  - **Ověřeno CLI `--transcribe-check`** na české větě syntetizované hlasem Zuzana (10,4 s): tři úseky se správnými časy a přesným textem („svadbě" místo „svatbě" je artefakt syntetického hlasu, ne přepisu). Ověření na reálné řeči přirozeně přijde s Kill-gate 1.
  - *Koukanec rukou zatím neproběhl (odloženo autorem): menu na klipu, průběh ve statusu, přepis reálného klipu.*

✅ **Modul 3 — titulky v náhledu a export SRT (28. 07. 2026): FÁZE 8 JE TÍM HOTOVÁ.**

  - **`SubtitleOverlay`:** titulek pod hlavou osy, přes spodek náhledu. Vlastní malé view (vzorec `TransportBar` — hlava tiká 30×/s a překreslovat se smí jen proužek). Promítnuté titulky se přepočítávají jen při změně projektu (debounce 150 ms), na tik hlavy se jen hledá v hotovém poli; překrývající se titulky z více stop se skládají pod sebe. **Kreslí se JEN když má co říct** — prázdný overlay by přepnul WindowServer do skládání a zkazil GPU baseline z fáze 1; při měřeních je schovaný, benchmarky měří totéž co dřív.
  - **Export SRT:** menu Soubor → „Exportovat titulky (.srt)…" — `subtitleCues()` z osy → `SRT.serialize` → soubor vedle filmu. Bez titulků poradí, co udělat dřív.
  - **Ověřeno CLI `--srt-check`:** syntetický přepis na asset → promítnutí přes klipy osy → korektní SRT výstup (2 titulky, časy sedí s pozicí klipu).
  - **Vědomě odloženo (ne zapomenuto):** editace textu titulků (zatím = pustit přepis znovu; přijde s inspektorem), titulkový pruh T1 na ose ze spec 4.1 (overlay v náhledu je funkční jádro; pruh je kreslení navíc) a vypalování titulků do videa (spec s ním nepočítá, SRT je standard dodávky).
  - *Koukanec rukou zatím neproběhl (odloženo autorem): titulek se ukazuje při přehrávání i scrubbování, export SRT jde otevřít v přehrávači.*

## ✅ FÁZE 7 — audio engine (HOTOVÁ 28. 07. 2026)

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

✅ **Modul 4 — cross-korelační synchronizace, výpočetní jádro (28. 07. 2026).** `WaveformSync` v balíčku `AudioEngine` (čistý Swift, spec 7.2). **+12 testů, celkem 32 v balíčku.**

  - **Dvoustupňově:** hrubě na RMS obálkách (200 binů/s — robustní vůči rozdílným mikrofonům a gainu, hodinová nahrávka je pak pár set tisíc binů), jemně přímou korelací syrových vzorků v okolí hrubého odhadu (±1 bin, výřez ze středu překryvu) — výsledek na vzorky, hluboko pod snímek obrazu.
  - **Vlastní FFT (radix-2)** — žádný Accelerate, balíček zůstává přeložitelný na Linuxu. Ukotveno dvojím nezávislým výpočtem: FFT proti naivnímu DFT (1e-9) a FFT korelace proti přímému součtu přes všechny posuny.
  - **Míra jistoty (normalizovaná korelace obálek):** nesouvisející nahrávky < 0,2, souvisící > 0,6 i při silném šumu — pojistka proti tichému položení cizího zvuku na špatné místo, test to vymáhá. Samé ticho a příliš krátké vstupy vrací `nil`.
  - **Sémantika posunu = pozice začátku kandidáta na ose reference** (kladná: rekordér spuštěn později; záporná: dřív a přečnívá) — oba směry drží testy s konstruovanými posuny mimo mřížku obálky.
  - ⚠️ Testovací signály musí mít amplitudovou STRUKTURU (bursty) — čistý bílý šum má plochou obálku a obálková korelace na něm nemá co chytit. Řeč i hudba strukturu mají, je to vlastnost metody, ne vada.
  - **Ověřeno na reálném zvuku:** z testovacího klipu (44,9 s, rány sekerou) vyrobený „klopák" — posun 5,4321 s, gain 0,3×, přidaný šum HLASITĚJŠÍ než signál (SNR ≈ −3 dB). Sync našel **5,4321 s přesně** (chyba < 0,1 ms), jistota 0,86, výpočet 0,17 s.

✅ **Modul 5 — sync v UI (28. 07. 2026): FÁZE 7 JE TÍM HOTOVÁ.** Kontextové menu klipu → „Synchronizovat externí zvuk…" → panel na výběr nahrávky (WAV, M4A…) → korelace → položení na A2. Rozhodnutí:

  - **Referencí je celý ZDROJOVÝ soubor klipu**, ne jeho výřez na ose — trim na výsledek nemá vliv a korelace má nejvíc materiálu. Umístění: začátek klipu + (posun − zdrojový začátek). Jen pro klipy bez rampy (menu položku vypne) — lineárně položený zvuk by se s křivkou rozjel.
  - **Kvantizace na snímky s kompenzací ve zdroji:** klip smí začít jen na celém snímku; zbytek posunu se schová do `sourceStart`, takže sync drží přesnost vzorků, ne snímků. Nahrávka přečnívající před nulu osy se přistřihne.
  - **Nízká jistota (< 25 %) = dialog, ne tiché položení.** `MonoAudioReader` čte oba zvuky mono/48 kHz přes `AVComposition` — kvůli edit listu (pravidlo o 44 ms), a hlavně STEJNOU cestou, jakou zvuk čte přehrávač i export.
  - Zvukový asset jde do projektu s bookmarkem (přežije restart), `hasVideo: false`; A2 dostane vlnu z existující `WaveformStore` a export ho míchá už hotovou cestou mixu.
  - **Ověřeno CLI `--sync-check`** na WAVu vyrobeném z klipu (posun 8,0 s, gain 0,4×, šum): položeno na **+8,000 s přesně — snímek 240, sourceStart 0,0000, jistota 87 %**.
  - ⚠️ **Cenný nález z ověřování: dekodéry AAC se neshodnou na rozjezdu.** První WAV vyrobený afconvertem vyšel „o 11 ms vedle" — přeměřením obou cest se ukázalo, že afconvert a čtení přes `AVComposition` se liší přesně o 528 vzorků (11,00 ms) v tom, kolik AAC rozjezdu zahodí. Sync měřil SPRÁVNĚ (vůči tomu, jak klip slyší aplikace); chyba byla v očekávání testu. Důsledek pro appku žádný — interní cesty (sync, přehrávač, export) čtou všechny přes kompozici, takže jsou konzistentní, a reálné nahrávky z rekordérů jsou PCM WAV bez téhle dvojznačnosti. Ale je to další patrona do pravidla „zvuk čti jen přes AVComposition".
  - *Koukanec rukou zatím neproběhl (odloženo autorem): menu na klipu, výběr souboru, zvuk na A2 sedící s obrazem, dialog při nesouvisející nahrávce.*

  **K názvu fáze:** `AVAudioEngine` ani `AVAudioUnitTimePitch` z plánu nakonec potřeba nebyly — mix zvládl `AVAudioMix`, normalizace float32 gain v rendereru, korekci výšky dělá `.timeDomain` na itemu už od Spiku 0. 32-bit float pipeline je splněná měřením i gainem ve floatu (bez ořezu přes ±1). Nasadí se, až bude potřeba víc než hlasitost (EQ, odšumění) — to není v plánu v1.0.

## ✅ FÁZE 5 — projekt a export (HOTOVÁ 28. 07. 2026)

✅ **Modul 1 — projektový soubor `.projektkrasa`: uložit, otevřít, obnovit po startu.**

  - **`ProjectFile` v TimelineModelu (+4 testy, celkem 232):** verze formátu, metadata a projekt v jeho VLASTNÍ Codable podobě — celé ticky a zdrojově kotvené uzly. Kde se spec 6.2 rozchází s pozdějšími rozhodnutími (sekundy s čárkou, výstupně kotvené uzly), platí rozhodnutí. Zápis je deterministický (`sortedKeys`) — stejný projekt = stejné bajty. Verze se čte a schvaluje PŘED obsahem: soubor z novější aplikace se odmítne srozumitelně, ne dekódovací chybou.
  - **`ProjectStore` v appce:** uložit/otevřít přes panely (⌘S, ⇧⌘S, ⌘O v menu — model se kvůli tomu přestěhoval z `ContentView` do `AIditorApp`), zapamatování posledního projektu bookmarkem a obnova při startu. **Security-scoped bookmark per asset se ukládá do souboru** — bez něj by sandbox po restartu nepustil projekt k vlastním klipům. `resolveAssets` při otevření opraví přesunuté cesty, označí nedostupné assety offline (jejich klipy ZŮSTÁVAJÍ — smazat cizí práci kvůli přejmenované složce je horší chyba než díra v náhledu) a zahodí proxy, jejichž soubor zmizel.
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

✅ **Modul 2 — správa úložiště (28. 07. 2026): externí disk a mazání cache.** Volba složky přes `NSOpenPanel` se security-scoped bookmarkem (entitlements read-write + app-scope bookmarky už v projektu byly); ve zvolené složce se dělá podsložka „AIditor Proxy", ať se hashované soubory nesypou do kořene disku. Odpojený externí disk = tichý návrat k výchozí složce, klipy jedou z originálů. Mazání cache NEJDŘÍV odšije proxy z projektu — kompozice nesmí ani chvíli ukazovat na mazané soubory. Sidebar ukazuje umístění a velikost cache. Po restartu se hotové proxy najdou otiskem samy — ověřeno okem: „výchozí složka aplikace · 1,66 GB" hned po startu.

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

✅ **Krok 1 — `TimelineModel` napojený na `AIditor.xcodeproj`** (commit `3f5f9cb`). Lokální balíček stejným vzorcem jako `ProbeKit` a `SpeedRampEngine`. Přibyl `TimelineController` — vlastník stavu podle `FAZE_2_VIEW.md` 2.1, kde má **geometrie jediné úložiště** (`interaction.geometry`) a controller ji vystavuje jen průchodem.

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
- **`MediaProbe` — sonda na vlastnosti klipů.** Rozlišení, orientace, kodeky, fps, edit list a hlavně **skutečné délky vzorků přes `AVSampleCursor`** (fallback `AVAssetReader`). Rozlišuje zaokrouhlení / zahozený snímek / proměnlivé časování. Naměřené hodnoty v `MediaProbe/RESULTS.md`. První kód, který sáhl na AVFoundation. **Od 28. 07. 2026 má pojistku:** bez `--results` zapisuje `RESULTS.md` jen při měření složky `TestClips` — běh na jiné složce (jako exportní check ve fázi 5) už kanonický záznam tiše nepřepíše, výsledek zůstane v konzoli.
- **`Flatten` — zploštění VFR na pevnou snímkovou mřížku.** Krok 3 spiku. Cílová frekvence z měřeného modu, čtení přes `AVComposition` (edit list), zero-order hold převzorkování, ProRes 422 Proxy v plném rozlišení, zvuk LPCM. **Ověřeno na třech klipech: všechny `CFR` s kolísáním 0,00 %, synchron tlesknutí 0,00 ms, kódování 257–426 fps.**
- **`Ramp` — plynulá rychlostní křivka segmentací.** Krok 4 spiku, jádro produktu. `scaleTimeRange` pozpátku, časy kumulativně v celých tickách, segmentace podle meze skoku rychlosti (výchozí 1,5 %), korekce výšky `.timeDomain`. **Ověřeno na třech klipech: `CFR` 30 fps, kolísání 0,00 %, délky sedí do jednoho snímku, žádné lupance ani při 545 segmentech.**
- **Aplikace `AIditor` — fáze 1 hotová, měření přeměřeno 27. 07. 2026.** Xcode projekt (deployment target 14.0, sandbox, bundle `cz.projektkrasa.Krasa`), `MediaImporter` se security-scoped bookmarky, `VFRDetector` nad `ProbeKit`, `PlaybackController` se seekem podle QA1820 a `PlaybackBenchmark`.

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
- **Interaktivní tracker** — odškrtávací postup s progress barem (`aiditor-tracker.html`)
- Rešerše tří rizikových oblastí: Whisper na macOS, face clustering, timeline UI a compositor
- Vyřešeno pozicování, distribuce, datový model `.projektkrasa` *(cena 1 490 Kč zrušena — 28. 07. 2026 rozhodnuto, že appka bude zatím free)*

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
- **F7** Audio engine, 32-bit float, LUFS *(3 týdny)* — ✅ **HOTOVO 28. 07. 2026, pět modulů za jeden den: `LoudnessMeter` (BS.1770-4, ověřeno proti pyloudnorm), per-track hlasitost/mute (`--mix-check`), LUFS normalizace exportu se stropem špiček (`--normalize-check`), jádro cross-korelačního syncu a sync v UI (`--sync-check`: položení na vzorek přesně). Koukance rukou odložené autorem — seznam u modulů.**
- **F8** Titulky přes WhisperKit *(2 týdny)* — ✅ **HOTOVO 28. 07. 2026: model přepisu kotvený ve zdroji (+14 testů), WhisperKit přepis ověřený na české větě, overlay v náhledu a export SRT. Odloženo: editace textu, pruh T1 na ose.**
- **F9** ~~Distribuce, notarizace, Sparkle~~ — ✅ **uzavřená 28. 07. 2026 v rozsahu osobní appky: hotová jen migrace na `Configuration` (ověřeno exportem, 0,0 % kolísání); podpis, notarizace, Sparkle i licencování ODLOŽENY — appka je free a jen pro autora**
- 🚧 ~~KILL-GATE 2~~ — odložen s distribucí (není komu prodávat/rozdávat)

### Vylepšovací fáze do svatby (nové, 28. 07. 2026 — detaily v plánu)
- **F10** Přechody (prolínačka, zatmívačka, audio crossfade)
- **F11** Texty a titulky + stopa T1 (+ editace titulků z přepisu)
- **F12** Fotky a Ken Burns (+ freeze frame jako fotka)
- **F13** Barevné presety (Core Image, intenzita per klip)
- **F14** Hudební synchronizace (beat-grid, magnet, dopasování tempa) — VLAJKOVÁ
- **F15** Analýzy kvality (neostrost, ticho — jen návrhová vrstva)
- **F16** Vymazlení (zvukové fade, dBTP, správa Whisper modelu)
- 🚧 **KILL-GATE 1 na konci** (svatba, materiál ~konec srpna 2026)

### Podmíněné po kill-gate
- **F17** Stabilizace obrazu — nejtěžší z výběru, možná ji vyřeší gimbal
- **F18** Detekce momentů bez biometrie (polibek, potlesk, tanec)
- **F19** Rozpoznávání obličejů *(8–12 týdnů)* — tři gaty: právní, licenční, poptávkový
- **F20+** Backlog: reframe 9:16, masky, PiP, multicam UI, HDR, slovenština, LUTs, ducking

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
- `Projekt_AIditor_Specifikace_Aplikace_v2.html` / `.pdf` – specifikace, zdroj pravdy pro **rozsah**
- `IMPLEMENTACNI_PLAN.md` – zdroj pravdy pro **pořadí a technologie**
- `SPIKE_0.md` – **uzavřený Spike 0 s naměřenými výsledky.** Vyplněná kritéria úspěchu, vyhodnocený rozhodovací bod, metodické poznámky k testování lupanců
- `FAZE_2_TIMELINE.md` – **návrh `TimelineModelu`.** Typy, invarianty, operace, undo a zdůvodnění rozhodnutí; kód podle něj je hotový
- `FAZE_2_VIEW.md` – **návrh `TimelineView`.** Vlastnictví stavu, vrstvení `CALayer`, recyklace, cesta události, vlnové průběhy, výkonový rozpočet, deset kroků stavby a tabulka ověřených API; kód podle něj **zatím nezačatý**
- `CLAUDE.md` – kontext a technická rozhodnutí pro Claude Code
- `PROJECT_STATUS.md` – tenhle soubor
- `aiditor-tracker.html` – interaktivní tracker postupu *(udržuje autor ručně)*

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
- `AIditor/AIditor/Timeline/` – **timeline v appce**
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
