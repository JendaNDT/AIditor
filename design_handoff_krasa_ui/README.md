# Handoff: UI Projektu Krása (macOS videoeditor)

## O čem to je

Přerovnání hlavního okna nativního macOS editoru **Krása** (Swift, SwiftUI panely + AppKit timeline) do
profesionálního NLE layoutu, plus obrazovky pro prázdný start, export, přepis řeči a dva fullscreen režimy.
Aplikace je funkčně hotová (fáze 0–17), UI bylo vývojářské. Cílem návrhu je opravit šest konkrétních potíží:

1. sidebar mísil dokument, nastavení, dodávku i vývojářská měření,
2. inspektor měl 132 px na křivku rychlosti i barvy,
3. transport byl řada stejně velkých tlačítek bez hierarchie,
4. stav běžících analýz (ostrost, hluchost, proxy, model přepisu) nebyl vidět,
5. osa nesla všechny informace naráz bez možnosti je vypnout,
6. chyběla knihovna médií / prohlížeč záběrů.

## O souborech v balíčku

Soubory v `designs/` jsou **designové referenční prototypy napsané v HTML** — ukazují zamýšlený vzhled,
rozměry a chování. **Nejsou to produkční zdrojáky k překopírování.** Úkolem je tyto obrazovky
**znovu postavit v existujícím prostředí aplikace Krása**: SwiftUI pro panely, AppKit (`NSView` + `CALayer`)
pro časovou osu, `AVFoundation` pro přehrávání — tedy podle vzorců, které v repozitáři už jsou
(`ContentView.swift`, `TimelinePane.swift`, `TimelineDocumentView.swift`, `TrackHeadersView.swift`,
`TimelineRulerView.swift`, `RampEditorView.swift`, `PlayerView.swift`).

HTML otevřeš přímo v prohlížeči (soubory `.dc.html` + `support.js` ve stejné složce).
Některé obrazovky mají stavy přepínatelné přes `data-props` na `<script data-dc-script>` na konci souboru
(např. `stav`: `nastaveni | prubeh | hotovo`); změň `default` a soubor znovu otevři.

## Fidelita

**Hi-fi.** Barvy, rozměry v bodech, typografie a texty jsou konečné a mají se dodržet na bod.
Paleta a geometrie osy jsou převzaté z existujícího kódu (`TimelinePalette`, `TimelineRulerView.height`,
`TrackHeadersView.width`), takže nová obrazovka na starý kód sedí. Kde návrh mění rozměr proti dnešnímu
stavu (výšky stop, šířka hlaviček), je to v tabulkách níž výslovně uvedené.

---

## Designové tokeny

### Barvy — chrome (nové, tmavý režim jediná varianta)

| Token | Hex | Použití |
|---|---|---|
| `surfaceWindow` | `#0e0f11` | pozadí okna |
| `surfaceChrome` | `#17181b` | lišty: toolbar, lišta osy, pravítko, stavový řádek |
| `surfaceRail` | `#131417` | ikonový rail, hlavičky stop, knihovna |
| `surfacePanel` | `#16181c` | připnutý panel (rampa / barva / zvuk / přepis) |
| `surfaceRow` | `#1b1d21` | řádek hlavičky stopy, karta knihovny |
| `surfaceControl` | `#1e2024` | tlačítko, pole, rozbalovátko |
| `surfaceControlActive` | `#23262b` / `#2c3037` | vybraný přepínač, aktivní ikona railu |
| `surfaceViewer` | `#08090a` | plocha okolo náhledu |
| `border` | `#24262b` | předěly lišt a panelů |
| `borderStrong` | `#2f3238` | obrys ovládacích prvků |
| `borderActive` | `#3a3f47` | obrys vybraného prvku |
| `textPrimary` | `#e9eaec` | hlavní text |
| `textSecondary` | `#9aa0a8` | popisky, hodnoty |
| `textTertiary` | `#6b7280` | meta, nápovědy |
| `textDisabled` | `#5c6067` | nedostupné |

### Barvy — signální a osa (převzaté z `TimelinePalette`, tmavá větev)

| Token | Hex | Zdroj v kódu |
|---|---|---|
| `accent` (výběr, výřez, aktivní záložka) | `#ffc947` | `clipSelectedStroke` (1.00, 0.79, 0.28) |
| `playhead` | `#ff453b` | `playhead` (1.00, 0.27, 0.23) |
| `clipVideoFill` | `#3a578c` | `clipVideoFill` (0.23, 0.34, 0.55) |
| `clipAudioFill` | `#29684d` | `clipAudioFill` (0.16, 0.41, 0.30) |
| `titleClipFill` | `#8c5233` | `titleClipFill` (0.55, 0.32, 0.20) |
| `transitionFill` | `rgba(148,112,219,.60)` | `transitionFill` |
| `transitionStroke` | `#c7a8ff` | `transitionStroke` |
| `speechStrip` | `rgba(41,105,77,.65)` | `speechStripFill` |
| `beat` | `#ff9f0a` | `beat` = `systemOrange` |
| `qualitySoft` | `rgba(255,159,10,.9)` | `qualitySoft` |
| `qualityBad` | `#ff453b` | `qualityBad` = `systemRed` |
| `qualityEmpty` | `#8e8e93` | `qualityEmpty` = `systemGray` |
| `fadeFill` | `rgba(0,0,0,.35)` | `fadeFill` |
| `clipStroke` | `rgba(0,0,0,.50)` | `clipStroke` |
| `clipText` | `#f0f0f0` | `clipText` |
| `rampCurve` | `#8cb8ff` | `RampEditorPalette.curve` |
| `rampNode` | `#ebebeb` | `RampEditorPalette.node` |
| `rampZone` / `rampZoneEdge` | `rgba(255,201,71,.16)` / `rgba(255,201,71,.90)` | `RampEditorPalette.zone/zoneEdge` |
| `ok` | `#3ecf8e` | nové — hotový stav, hlasitost |
| `warn` | `#ff9f0a` | nové — běžící analýza, přiznaná mez |

### Typografie

Systémové písmo (`-apple-system` / SwiftUI `.system`). Monospace jen na čísla:
`ui-monospace, SFMono-Regular, Menlo` ↔ `NSFont.monospacedDigitSystemFont`.

| Role | Velikost / řez |
|---|---|
| název projektu | 13 / semibold, `letter-spacing:-.01em` |
| meta pod názvem | 9 / regular, `textTertiary` |
| tlačítko, pole, řádek panelu | 11–12 / regular |
| nadpis sekce v panelu | 10 / uppercase, `letter-spacing:.06–.08em`, `textTertiary` |
| jméno klipu na ose | 11 / medium, `clipText` |
| text titulkového klipu (T1) | 10 / medium |
| timecode v pravítku | 10 / monospaced digit |
| timecode v transportu (okno) | 13 mono; ve fullscreenu 22 mono |
| velké číslo (procenta exportu) | 20–22 / semibold |
| grafický titulek v náhledu | serif (Georgia ↔ `.system(design:.serif)`), **0,105 × výška obrazu**, semibold, stín `rgba(0,0,0,.65)` — podle `TitleOverlay.font(for:)` |
| řečový titulek v náhledu | 0,037 × výška obrazu, semibold, deska `rgba(0,0,0,.55)`, radius 5–8 |

### Rozměry, rádiusy, mezery

- Rádiusy: tlačítko/pole **7–8**, karta a panelová sekce **8–9**, plovoucí panel **12–14**, klip na ose **5**, čip **5–6**, pilulka transportu **22**.
- Mezery: v panelu **10**, mezi sekcemi **10–16**, uvnitř řádku **5–9**, padding panelu **10–12**, padding listu **16–20**.
- Výška ovládacích prvků: tlačítko v toolbaru **28**, tlačítko v panelu **28**, řádek presetu **26**, mini slider track **3** s úchytem **11–13**.
- Stín plovoucích vrstev: `0 22px 48px rgba(0,0,0,.62)` (panel), `0 30px 70px rgba(0,0,0,.65)` (list exportu), `0 12px 28px rgba(0,0,0,.50)` (pilulka).

---

## Obrazovka 1 — Hlavní okno (hlavní směr)

`designs/Krasa hlavni okno.dc.html` · okno **1470×900** (MacBook Air 13"), minimum 1180×760.
Vertikální stack: toolbar 46 → tělo (flex) → stavový řádek 26.
Tělo: rail 60 | obsah (flex).
Obsah: horní pás 372 → lišta osy 32 → osa (flex) → nic dalšího.
Osa je vodorovný stack: sloupec osy (flex) | připnutý panel 452.

### 1.1 Toolbar (výška 46, `surfaceChrome`, spodní `border`)

Zleva: puntíky okna · název projektu 13/semibold + meta 9 („uloženo 21:04 · 30 fps · 3840×2160 · proxy") ·
svislý předěl · skupina akcí `Přidat média… | Titulek | Hudba | Zmrazit snímek` (28 px, `surfaceControl`).
Zprava: **čip běžících analýz** (28 px, `rgba(255,159,10,.11)`, obrys `rgba(255,159,10,.32)`, tečka `warn` 7 px,
text „Analyzuju kvalitu · 3/5"), tlačítko `Rampa ⌘4` (`surfaceControlActive`), primární `Exportovat…`
(`accent` výplň, text `#191a1c`, semibold).

Mapování na kód: nahrazuje horní část dnešního sidebaru + `ProjectStatusRow`. Čip čte stav běhů
`SharpnessStore` / `EmptinessStore` (dnes `startSharpnessAnalysis()` běží bez jakéhokoli UI).

### 1.2 Rail (šířka 60, `surfaceRail`)

Šest položek 44×44, radius 11, ikona + popisek 8 px: **Média** (aktivní: `surfaceControlActive` + `borderActive`),
Text, Barva, Zvuk, Řeč, dole Nastavení. Rail určuje, co je v panelu vpravo a co v knihovně —
nahrazuje vývojářský sidebar. Ikony vzít ze SF Symbols (`film`, `textformat`, `paintpalette`,
`waveform`, `text.bubble`, `gearshape`); v prototypu jsou jen geometrické náhrady.

### 1.3 Horní pás (výška 372)

**Přehrávač** (flex, `surfaceViewer`, `overflow:hidden`, padding 16): obraz drží 16:9 a **škáluje se podle výšky**
(`height:100%; width:auto`) — jinak přeteče do transportu.
- vlevo nahoře tři čipy na obraze (`rgba(0,0,0,.55)`, 9 px): `Proxy 1/2`, `rampa 0,25×` (`rampCurve`), `Teplý film 62 %` (`#ffd88a`),
- vpravo svislé měřidlo: dva pruhy 6 px (`ok`), popisky `LUFS`, `−16,2`, `−1,0 TP` (`warn`),
- grafický titulek na 31 % výšky obrazu, řečový titulek 58 px nad spodní hranou obrazu,
- **pilulka transportu** dole na střed: výška 44, `rgba(18,20,24,.92)`, obrys `borderActive`; obsah:
  timecode 13 mono | předěl | `J` `◀` **kruh 44 play/pauza** (`#e9eaec`, glyf `#131417`) `▶` `L` | předěl |
  čip rychlosti `−2× krokováním` (`rgba(255,159,10,.14)` / `warn`). Čip se zobrazuje jen když
  `PlaybackController.shuttleRate != 0`; oranžový je jen v `isSteppingFallback`.

**Knihovna** (šířka 330, `surfaceRail`, levý `border`): hlavička 34 („Knihovna · 14 · chronologicky", `＋`) ·
řádek filtrů (pilulky 12 px radius: Vše/Video/Fotky/Hudba, aktivní `surfaceControlActive`) ·
**mřížka 2 sloupce, `grid-auto-rows:94px`, gap 8, `overflow-y:auto`** (karta: náhled 62 px + popis 32 px;
karty musí mít pevnou výšku, jinak je mřížka zmáčkne) · patička: `Uspořádat na V1 chronologicky` + řádek
stavu proxy (tečka `ok`, „Proxy 5/5 · 4,7 GB", odkaz „Nastavení…").
Badge na náhledu: `VFR` (`warn`, text `#1a1a1a`), `120p` (`rgba(120,180,255,.92)`), délka vpravo nahoře,
oranžová ryska = úsek s měkkou ostrostí. Datum ze souboru se přiznává oranžově (dnešní pravidlo
`creationDateSource == .fileSystem`).

### 1.4 Lišta osy (výška 32, `surfaceChrome`, horní i spodní `border`)

`Na ose:` + čtyři přepínače vrstev (`Miniatury`, `Vlny`, `Doby`, `Značky kvality`) — zapnutý
`surfaceControlActive` + `borderActive`, vypnutý `surfaceRow` + `border`; předěl; `Citlivost` + slider 80 px
(`warn`) + hodnota mono 0,65 (mapuje na citlivost 0–1 v `qualityMarks`, dnes bez UI); předěl;
`Přichytávání` + nápověda „Shift vypne"; vpravo `výřez 0:04–0:26` + tlačítka `I` `O` (`accent` text) ;
předěl; `zoom` slider 96 px + `Fit ⇧Z`.

### 1.5 Osa

Sloupec osy = pravítko 26 → stopy (flex) → přehled celé osy 46.

**Pravítko** (`TimelineRulerView`, výška 26 — beze změny):
hlavní ryska 1×8 px `#7c828b` + popisek plný timecode `00:00:04:00` (10 mono, `textSecondary`, 3 px vpravo od rysky),
půlryska 1×4 px `rgba(124,130,139,.45)`, rozteč popisků ≥ 100 px; doby `beat` u spodní hrany
(běžná 1×4 s alfou 0,5, „raz" 2×8 plný); výřez = pruh `rgba(255,201,71,.18)` + 2 px zarážky `accent`,
kreslí se jen když výřez opravdu je výřez.

**Hlavičky stop** (`TrackHeadersView`, šířka **104** místo dnešních 96; `surfaceRail`):
řádek na stopu, `surfaceRow`, radius `0 7px 7px 0`, gap 3, horní odsazení 3.
Řádky musí mít **pevnou výšku** (`flex:none; box-sizing:border-box`), jinak se rozjedou s pruhy.

| Stopa | Výška (návrh) | Dnes | Obsah hlavičky |
|---|---|---|---|
| V1 | **136** | 64 | jméno 11/semibold + „obraz · 5 klipů" 9 px + dvě mini tlačítka (viditelnost, zámek) |
| A1 | **78** | 44 | jméno + „řeč" · `M` 19×15 + slider hlasitosti + hodnota `−4,0 dB` |
| A2 | **78** | 44 | jméno + „hudba" · totéž, `−12,5 dB` |
| T1 | **40** | 28 | jméno + „titulky" |

Součet 136+78+78+40 + 3×3 gap + 3 = **344**; klipy na ose leží na `top` 3 / 142 / 223 / 304 (tj. y hlaviček).

**Klipy** (radius 5, obrys `clipStroke` 1 px, vybraný `accent` 1,5 px + `box-shadow 0 0 0 1px rgba(255,201,71,.25)`):
- obrazový klip: výplň `clipVideoFill`, dolních 96 px = **pás miniatur** (dělený na 2–4 dlaždice),
  jméno 11/medium vlevo nahoře se zaříznutím (`right:5px; nowrap; ellipsis`),
  badge vpravo nahoře nebo vlevo dole (`rgba(0,0,0,.5)`, 9 px): preset `Teplý film 62 %`, rampa `1× → 0,25× → 1×`, `nájezd 1,3×`,
  **křivka rampy** kreslená přímo na klipu (`rampCurve`, 1,5 px, výška pásu 40 px, uzly 3 px),
  **proužky kvality** 4 px u horní hrany (`qualitySoft` / `qualityBad`) a **hluchosti** u spodní (`qualityEmpty`) — radius 1,5;
- zvukový klip: výplň `clipAudioFill`, vlna = svislé rysky `rgba(255,255,255,.30–.36)` každé 3–4 px v pásu 30–40 px,
  **fade klíny** `fadeFill` (trojúhelník od horní hrany ke špičce) s úchytem 6×6 `rgba(255,255,255,.9)` na vrcholu,
  badge `sync −0,42 s`;
- titulkový klip na T1: `titleClipFill`, text 10/medium `#f5ece6`;
- pásek titulku z řeči: 4 px `speechStrip` u spodní hrany pruhu T1;
- **přechod**: lichoběžník `transitionFill` + obrys `transitionStroke` přes střih (horní hrana celá,
  spodní se sbíhá ke střihu, „noha" 4 px), popisek délky 9 px u spodní hrany.
  ⚠️ Vrstva přechodů leží **nad** klipy (v HTML `z-index:2`) — jinak ho soused překryje.
- hlava: 2 px `playhead` přes celou výšku + úchyt 14×8 nahoře; vodicí čára přichytávání 1 px `rgba(255,201,71,.45)`.

**Přehled celé osy** (nový prvek, výška 46, `surfaceRail`): popisek „přehled" 9 px + pás 26 px
(`surfaceWindow`, obrys `border`, radius 5) s bloky klipů (`clipVideoFill` 9 px, zvuk `clipAudioFill` 8 px),
červenou hlavou a **rámečkem viditelného výřezu** (`rgba(255,201,71,.08)` + obrys `rgba(255,201,71,.7)`),
vpravo celková délka mono. Řeší navigaci na dvacetiminutové stopáži (doplněk k `scrollToKeep`).

### 1.6 Připnutý panel (šířka 452, `surfacePanel`, levý `border`)

Hlavička 34: jméno klipu 11/semibold + meta („zdroj 120 fps · 0:22") + `⌘4 skryje`.
Pod ní záložky (11 px, aktivní `accent` podtržení 2 px + semibold): **Rychlost · Barva · Zvuk · Info**.
Tělo: padding 10/12, gap 10, `min-height:0; overflow-y:auto` — **rozpočet výšky je 360 px**, obsah se do něj musí vejít.

**Záložka Rychlost**
- řada presetů: `Bez rampy | 0,5× | 0,25× | 0,125×` (28 px, aktivní `#3a3320` + `accent`, nedostupný text `textDisabled`),
- editor křivky: box 150 px (`surfaceWindow`, obrys `border`, radius 8), **gutter popisků 46 px** vlevo
  (`2×`, `1×` zvýrazněné `#f0f0f0`, `0,50×`, `0,25×` v `accent`, `0,10×` v `textTertiary`),
  vodicí linky `#2a2d33` (osa 1× `borderActive`), **žlutá zóna** = `rampZone` s horní hranou `rampZoneEdge`
  + popisek „limit zdroje 0,25× — pod ním se snímky duplikují",
  křivka `rampCurve` 2 px, uzly kruh r=5 `rampNode` (vybraný obrys `accent` 2 px),
  nápověda dole 9 px: „dvojklik přidá uzel · Delete smaže · Shift vypne přichytávání",
- čip segmentace `182 úseků · skok 1,42 %` (`accent`) + „spotřeba zdroje 3,125 s",
- `Korekce výšky` rozbalovátko (Časová doména / Spektrální / Bez korekce),
- sekce `Dopasování na hudbu`: `Zpomalení na dobu` + `Zarovnat konec na dobu`
  a řádek „Nejbližší doba na 00:00:11:12 · rampa na ni dosedne". Vypnuté položky nesou důvod z chyby modelu
  (`noBeatInReach(nearest:)`, `noCleanSlowdown`).

**Záložka Barva**
- náhled **před / po**: dvě dlaždice 52 px (originál `linear-gradient(150deg,#3b4a55,#181c22)`,
  s presetem `#6a5238 → #2a1f16`, obrys `accent`), popisky 9 px,
- pět řádků presetů (26 px): vzorek 34×18 + název; vybraný `#3a3320` + `accent` + „vybráno".
  Pořadí a názvy odpovídají `ColorPreset`: **Bez úpravy, Jemný svatební, Teplý film, Čistá pleť, Černobílá**,
- `Síla` slider 0–100 % (výplň `accent`) + hodnota mono,
- čip `platí pro výběr · 3 klipy` + „jeden krok ⌘Z",
- `Kopírovat na celý výběr` / `Zrušit preset` (v tooltipu poznámka o vlastním kompozitoru a GPU mediánu 24 %).

**Záložka Zvuk**
- meta „svázaný zvuk na A1 · 2 kanály · 48 kHz",
- sekce `Fade`: Nájezd / Dojezd slidery (`ok`) s hodnotou `18 sn · 0,6 s` (snímky **i** sekundy)
  a pravidlem „Hrana pod crossfadem fade nedostane",
- sekce `Stopa A1`: `M` + hlasitost + `−4,0 dB`,
- sekce `Klopák`: soubor, `posun −0,42 s · jistota 96 %`, čip `na vzorek` (`ok`),
- čipy `−16,2 LUFS` a `−1,0 dBTP` (`warn`) + „měřeno na výběru",
- `Synchronizovat zvuk…` / `Titulky z řeči…`.

### 1.7 Stavový řádek (výška 26, `surfaceChrome`)

Tři stavové tečky s textem (`warn` Ostrost 3/5 · hluchá místa ve frontě; `ok` Proxy 5/5; `ok` Model přepisu 1,62 GB),
vpravo poslední akce („Rampa 1× → 0,25× nastavena · ⌘Z vrátí"). Sem míří dnešní `onStatus` hook z osy.

---

## Obrazovka 2 — Prázdný start

V `designs/Krasa varianty 1a-3a.dc.html` jako varianta **3a** (kolo 3 nahoře).
Stejný rám, jen jiný obsah:
- toolbar: `Otevřít projekt… ⌘O` + primární `Nový projekt ⌘N`,
- **pruh obnovy zálohy** místo modálního dialogu (`rgba(255,159,10,.10)` / obrys `rgba(255,159,10,.30)`):
  text s datem zálohy + `Obnovit zálohu` / `Zahodit`,
- rail: neaktivní sekce na `opacity:.35`,
- místo přehrávače **zóna přetažení**: rámeček `1.5px dashed #33373e`, radius 14, tři náhledové dlaždice,
  nadpis 19/semibold „Přetáhni sem záběry, fotky nebo hudbu", odstavec 12 px o měření časování a proxy,
  `Vybrat soubory…` / `Vybrat složku…`, řádek podporovaných formátů 10 px,
- místo knihovny **Poslední projekty** (název, datum, počet záběrů, délka; offline projekt oranžově „disk není připojený"),
  patička: velikost proxy cache a „Model přepisu nestažený · 1,5 GB při prvním použití",
- lišta osy ztlumená (`opacity:.4`), pruhy stop prázdné s návodem, kam co patří; hlava `rgba(255,69,59,.45)`.

## Obrazovka 3 — Export

`designs/Krasa export.dc.html` · **list 660 px** na střed (top 56) nad ztmaveným oknem
(`rgba(6,7,8,.62)` přes schéma okna na `opacity:.4`). Radius 14, `#191b1f`, obrys `borderActive`.
Tři stavy (`data-props` → `stav`): `nastaveni | prubeh | hotovo`. Scénář je jeden a čísla musí zůstat konzistentní:
celý projekt `00:04:12:07` = **7 567 snímků**, ~2,8 GB, ~1 min při ~126 fps.

- **Hlavička:** „Exportovat film" 16/semibold + „vždy z originálů, proxy se nepoužije"; vpravo délka mono a odhad.
- **nastaveni:** sekce `Rozsah` (dvě karty: Celý projekt / Jen výřez I—O s počty snímků, vybraná `accent`),
  `Obraz` (HEVC · 3840×2160 · 30 fps + čip `CFR` v `ok` a „kolísání 0,0 %"),
  `Hlasitost` (Bez normalizace / Web −14 LUFS / Vysílání −23 LUFS + poznámka o stropu −1 dBTP),
  `Titulky` (checkbox vypálit T1 s počtem; checkbox `.srt` vedle filmu se 148 úseky),
  `Uložit jako` (cesta mono + `Změnit…`),
  **varovný blok** o duplikaci snímků u 30fps klipu s rampou 0,25× (37,5 %) + odkaz „Zobrazit klip na ose",
  patička: odhad + `Zrušit` / primární `Exportovat`.
- **prubeh:** 42 % velké číslo, „3 180 z 7 567 snímků · zbývá asi 35 s", rychlost mono, progress 6 px (`accent`),
  tři fáze s kolečky (hotová `ok ✓` / běžící `accent` prstenec / čekající obrys `borderActive`),
  poznámka „Můžeš dál stříhat…", patička `Zrušit export` / `Skrýt na pozadí`.
- **hotovo:** miniatura 112×63, „Film je hotový", jméno a velikost mono, délka a rozsah;
  kontrolní řádky: časování `CFR 30,000 fps · kolísání 0,0 %` (`ok`),
  hlasitost `gain omezen špičkami na +1,4 dB` (`warn` — poctivé přiznání), titulky (`ok`);
  patička `Ukázat ve Finderu` / `Exportovat znovu…` / `Zavřít`.

## Obrazovka 4 — Přepis řeči

`designs/Krasa prepis.dc.html` · stejný rám jako hlavní okno, rail na **Řeč**, panel vpravo = přepis.
Dva stavy (`stav`): `prubeh | editace`.
- horní pás: náhled s řečovým titulkem na desce + čip „titulek z řeči · A1";
  vpravo **Zdroje řeči** (co je přepsané: „148 úseků · 12,3 min řeči"; co ne: „bez přepisu · ⌘5 spustí"),
  patička: model `large-v3 · 1,62 GB`, „Přepis běží ve stroji — nic se nikam neposílá",
- lišta osy: přepínače `Pásky řeči`, `Vlny` zapnuté; nápověda „klik do pásku vybere úsek · ⏎ potvrdí text",
- osa: v A1 zvýrazněný rozsah vybraného úseku (`rgba(255,201,71,.14)` + svislé hrany `accent`),
  na T1 pásky řeči, vybraný pásek celý `accent`,
- panel **editace**: hledání + přepínač „jen pod hlavou"; seznam úseků (čas mono 9 px + text 11 px);
  vybraný úsek je karta `surfaceControl` + obrys `accent`: rozsah `0:11 → 0:14`, nápověda
  „⏎ potvrdí · prázdné smaže", **editovatelné pole** 44 px s kurzorem, akce `Rozdělit v kurzoru` /
  `Smazat úsek` a poznámka „platí pro všechny klipy ze zdroje"; patička: čip `148 úseků`,
  „12,3 min řeči · 3 ručně upravené", `Přepsat znovu od hlavy` / `Uložit .srt…`,
- panel **prubeh**: 64 % + „2:41 ze 4:12 · zbývá asi 40 s", tři fáze (Model načten / Rozpoznávám řeč /
  Promítnutí na T1), **úseky přitékají průběžně** (poslední na `opacity:.6`),
  poznámka o lokálním běhu, patička `Zrušit přepis` / `Skrýt na pozadí`.

## Obrazovka 5 — Fullscreen celé aplikace

`designs/Krasa fullscreen aplikace.dc.html` · **1470×956** (celá obrazovka Airu 13").
Beze změny proti hlavnímu oknu, kromě:
- toolbar 48 px, padding 16, **bez puntíků** — začíná názvem projektu; vpravo za Exportem předěl a
  `Zpět do okna ⌃⌘F`,
- získaných 56 px dostane **přehrávač** (pás 372 → 426); osa, hlavičky i panel si drží stejné rozměry
  a souřadnice, takže se nic nekreslí dvakrát,
- stavový řádek dodává „· menu vyjede u horní hrany".

## Obrazovka 6 — Fullscreen náhled (jen obraz)

`designs/Krasa fullscreen nahled.dc.html` · 1470×900, obraz 16:9 = pás **827 px** na střed (pillarbox 36 / 37).
Tři stavy (`stav`): `cisty | ovladani | osa`.
- **cisty:** jen obraz a titulky; vpravo nahoře ztlumená (opacity .5) kapsle `00:00:08:22 · ⎋ zpět do editoru`.
- **ovladani** (myš se pohnula): horní gradient 112 px (`rgba(0,0,0,.72) → 0`) s názvem projektu, klipem a rampou,
  vpravo čipy `Proxy 1/2`, `Teplý film 62 %`, `−16,2 LUFS`, `⎋ zpět`;
  dolní gradient 168 px: timecode **22 mono**, scrub lišta (track 4 px `rgba(255,255,255,.18)`, přehráno `playhead`,
  výřez `rgba(255,201,71,.28)` se zarážkami `accent`, doby `beat` pod tím, úchyt 4×18 se `box-shadow 0 0 0 3px rgba(255,69,59,.2)`),
  zbývající čas mono; řada: `I 0:04` / `O 0:26` + „přehrávat jen výřez" · transport (34 px tlačítka, **kruh 52 px** play/pauza,
  čip `−2× krokováním`) · `Titulky ✓` / `Osa ⇧T`.
  **Řečový titulek se v tomhle stavu zvedá** na `bottom:212` (v čistém `bottom:108`), aby nesedl na scrub.
- **osa** (⇧T nebo myš k spodní hraně): dolní gradient 146 px s mini osou 76 px
  (`rgba(14,15,17,.82)`, obrys `rgba(255,255,255,.10)`, radius 10): pás miniatur 40 px, zvuk 12 px, doby 5 px,
  výřez a hlava; nad kurzorem **plovoucí náhled snímku** 192×108 s timecodem. Titulek v tomhle stavu ustupuje.

---

## Interakce a chování

| Prvek | Chování | Kde to už v kódu je |
|---|---|---|
| přepínače vrstev osy | zap/vyp kreslení miniatur, vln, dob, značek — bez přepočtu při scrollu | `rebuildClipInfo`, `layoutStrips` |
| citlivost analýz | 0–1, přepočet značek, ne nové vzorkování | `qualityMarks(samples:)`, dnes bez UI |
| rychlé presety zpomalení | jedno kliknutí = jeden undo krok pro celý výběr; pod limitem zdroje nedostupné s důvodem | `toggleClassicRamp`, `pureSlowdownLimit` |
| tažení uzlu křivky | náhled bez zápisu, `rampDragBegan/Changed/Ended`, Escape ruší, varování o strmosti se dopočítá po puštění | `RampEditorView` |
| slidery (síla presetu, hlasitost, fade, zoom) | undo se skládá kolem tažení (`…DragBegan/Changed/Ended`) | `ColorGradePanel`, `TrackHeadersView` |
| JKL | žebřík −8…8, `L` vpřed, `J` zpět, `K` pauza; `−2×` oranžově jen v krokovacím fallbacku | `PlaybackController.shuttle` |
| auto-scroll za hlavou | stránkuje; vypnuto při scrubování, tažení a live scrollu | `scrollToKeep(...)` |
| I / O / ⌥I / ⌥O / ⌥X | staví a ruší výřez; pravítko ho kreslí jen když je to opravdu výřez | `exportRange` |
| ⌘4 / ⌘5 | skryje/zobrazí připnutý panel (rampa / přepis); šířku dostane osa | nové |
| ⌃⌘F | fullscreen celé aplikace ↔ okno | nové |
| ⇧T ve fullscreen náhledu | mini osa u spodní hrany; myš do posledních ~60 px totéž | nové |
| ⎋ | zavře fullscreen náhled, ruší rozjeté tažení | částečně `interaction.cancel()` |
| přetažení z knihovny | drop na stopu vloží klip; fotky a hudba na své stopy | dnes jen menu `Přidat fotky…`, `Přidat hudbu…` |
| stav analýz | čip v toolbaru + stavový řádek: co běží, co je ve frontě, co je hotové | běhy existují, UI ne |

Animace držet krátké a nenápadné: overlay ve fullscreenu 150 ms `ease-out` (skrytí po ~2 s nečinnosti),
panel při ⌘4 120 ms, čipy bez animace. **Na ose se nic neanimuje** — implicitní animace `CALayer`
se vypínají `CATransaction.setDisableActions(true)` (dnešní pravidlo).

## Stav (co si UI musí pamatovat)

Nové stavy UI (nepatří do `Project`, tedy ani do projektového souboru):
`railSection` (media/text/color/audio/speech/settings), `panelVisible` + `panelTab` (speed/color/audio/info),
`timelineLayers` (thumbnails/waveforms/beats/qualityMarks – bool), `qualitySensitivity` (0–1, `UserDefaults`),
`libraryFilter` + `librarySearch`, `isFullscreen`, `fullscreenOverlay` (clean/controls/timeline),
`exportSheet` (nastaveni/prubeh/hotovo + progress), `transcriptPanel` (prubeh/editace + vybraný úsek).
Vše ostatní už existuje: `TimelineController` (project, undo, geometry, playhead, selection, waveforms,
sharpnessSamples, emptinessSamples, exportRange), `PlaybackController`, `ProjectStore`, `ProxyStore`,
`TranscriptionService`.

## Assety

Žádné bitmapy. Miniatury klipů a náhledy v knihovně jsou v prototypu **placeholdery** (tmavé gradienty) —
v aplikaci je nahradí skutečné snímky z proxy (`AVAssetImageGenerator` / dlaždice vedle vln).
Ikony railu a mini tlačítek brát ze **SF Symbols**; v HTML jsou jen geometrické náhrady.
Vlny jsou v prototypu `repeating-linear-gradient` — v aplikaci zůstávají předrenderované `CGImage` dlaždice.

## Soubory

| Soubor | Co obsahuje |
|---|---|
| `designs/Krasa hlavni okno.dc.html` | **hlavní směr** — hlavní okno 1470×900, panel s záložkami (`panelTab`), `showRampPanel` |
| `designs/Krasa fullscreen aplikace.dc.html` | totéž na celé obrazovce 1470×956 |
| `designs/Krasa fullscreen nahled.dc.html` | fullscreen náhled jen s obrazem, stavy `cisty/ovladani/osa` |
| `designs/Krasa export.dc.html` | list exportu, stavy `nastaveni/prubeh/hotovo` |
| `designs/Krasa prepis.dc.html` | přepis řeči, stavy `prubeh/editace` |
| `designs/Krasa varianty 1a-3a.dc.html` | historie rozhodování: **1a** rekonstrukce dnešního UI, **1b/1c** varianty layoutu, **2a** zvolená kombinace, **3a** prázdný start |
| `designs/support.js` | runtime prototypů (nekopírovat do aplikace) |

### Screenshoty (`screenshots/`)

| Soubor | Obrazovka |
|---|---|
| `01-hlavni-okno.png` | hlavní okno 1470×900, panel na záložce Zvuk |
| `02-fullscreen-aplikace.png` | celá aplikace na celé obrazovce 1470×956 |
| `03-fullscreen-nahled.png` | fullscreen náhled, stav `ovladani` |
| `04-export.png` | list exportu, stav `prubeh` |
| `05-prepis-reci.png` | přepis řeči, stav `editace` |
| `06-varianty-1a-3a.png` | plátno s koly 1–3 (rekonstrukce, varianty, prázdný start) |

Screenshoty zachycují **výchozí stav** každého souboru. Ostatní stavy se přepnou v `data-props`
na `<script data-dc-script>` na konci příslušného `.dc.html` (`stav`, `panelTab`, `showRampPanel`)
a soubor se znovu otevře v prohlížeči.

Pořadí implementace, které nic nerozbije: **toolbar + stavový řádek → rail + knihovna → lišta osy (vrstvy, citlivost)
→ výšky stop a miniatury na klipech → připnutý panel (Rychlost, pak Barva a Zvuk) → přehled celé osy
→ list exportu → panel přepisu → fullscreen režimy.**
