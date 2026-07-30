# AIditor

Nativní macOS videoeditor pro svatební a rodinné filmy. Dvě věci, kvůli kterým vznikl:
**plynulé rychlostní křivky** (speed ramping bez schodů) a **český přepis řeči na titulky,
který běží celý na tvém stroji** — nic se nikam neposílá.

Swift · SwiftUI (panely) + AppKit (časová osa) · AVFoundation · WhisperKit

> **Stav:** hotové všechny naplánované fáze, 570 automatických testů prochází.
> Appka ale zatím **nesestříhala skutečnou zakázku** — to je příští krok (svatba, materiál
> ~konec srpna 2026). Ber to jako osobní projekt, ne jako produkt.

---

## Co umí

- **Import s měřením skutečného časování.** VFR je u telefonních klipů výchozí stav, ne
  výjimka — appka si u každého souboru časování změří, místo aby věřila metadatům.
- **Střih na časové ose** v AppKitu — 2000 klipů bez jediného vypadlého snímku při scrollu.
  Trim, roll, slip, ripple, multi-výběr, schránka, JKL, magnet na hrany a doby hudby.
- **Rychlostní křivky kreslené myší.** Segmentace podle meze skoku rychlosti (výchozí 1,5 %),
  ne podle pevného počtu snímků — krátký klip dostane jemnější dělení, dlouhý hrubší.
  Posuvník má **žlutou zónu** pod hranicí, kde už zdroj nemá dost snímků a obraz by trhal.
- **Proxy** ProRes 422 Proxy v polovičním rozlišení — kvůli scrubování (seek 6 ms proti
  41–95 ms u originálního HEVC), ne kvůli přehrávání.
- **Titulky z české řeči** přes WhisperKit, lokálně. Editace v panelu přepisu, export SRT
  i vypálení do obrazu.
- **Přechody na střihu**, grafické titulky, fotky s Ken Burns a freeze frame, barevné
  presety per klip, hudba s dobami v pravítku, analýzy kvality (neostrost, hluchá místa),
  zvukové fade úchyty.
- **Zvuk podle normy.** Hlasitost podle ITU-R BS.1770-4, true peak se stropem −1 dBTP,
  cross-korelační synchronizace klopáku s rekordérem.
- **Export HEVC 4K/30** přes `AVAssetWriter` s kolísáním snímkové frekvence 0,0 %.

## Sestavení

Potřebuješ **macOS 14.0+** a Xcode (vyvíjeno na Swiftu 6.3.3, SDK MacOSX26.5).

```bash
xcodebuild -project AIditor/AIditor.xcodeproj -scheme AIditor -configuration Debug build
```

Při prvním spuštění přepisu se stáhne model WhisperKitu (~1,5 GB) do kontejneru aplikace.
Je to jediné, kvůli čemu appka sahá na síť.

## Moduly

Logika je schválně v čistých Swift balíčcích bez AVFoundation a bez UI — jde je přeložit
a otestovat samostatně, i na Linuxu.

| Balíček | Co dělá | Testů |
|---|---|---:|
| [`TimelineModel/`](TimelineModel/) | model a geometrie časové osy, 29 invariantů ve `validate()` | 463 |
| [`AudioEngine/`](AudioEngine/) | hlasitost BS.1770-4, true peak, sync nahrávek, detekce dob | 54 |
| [`SpeedRampEngine/`](SpeedRampEngine/) | matematika rychlostní křivky a segmentace | 53 |
| [`MediaProbe/`](MediaProbe/) | sondy nad médii (`ProbeKit`), zplošťovač VFR→CFR, měření rampů | — |
| [`AIditor/`](AIditor/) | aplikace samotná (SwiftUI + AppKit) | — |

```bash
cd TimelineModel && swift test      # totéž v AudioEngine a SpeedRampEngine
```

## Měření místo „OK"

Appka umí přes příkazovou řádku pustit sadu kontrol, které **tisknou naměřená čísla**, ne
hlášku „prošlo". Používají se jako brána před odevzdáním každého modulu:

```bash
AIditor.app/Contents/MacOS/AIditor --shell-check
```

Dál mimo jiné `--timeline-bench` (práce na tik a vypadlé tiky), `--export-check`,
`--color-check`, `--jkl-check`, `--thumb-check`, `--fullscreen-ui-check`.

## Dokumentace

Projekt je vedený jako stavební deník, ne jako produktová dokumentace:

- [`PROJECT_STATUS.md`](PROJECT_STATUS.md) — kde to stojí a co je příští krok
- [`IMPLEMENTACNI_PLAN.md`](IMPLEMENTACNI_PLAN.md) — pořadí fází a technologie
- [`CLAUDE.md`](CLAUDE.md) — technická rozhodnutí a naměřené pasti, na kterých projekt stojí
- [`SPIKE_0.md`](SPIKE_0.md) — uzavřený úvodní spike a jeho výsledky
- [`FAZE_18_UI.md`](FAZE_18_UI.md), [`FAZE_2_TIMELINE.md`](FAZE_2_TIMELINE.md) — návrhy dvou největších fází

Produktová specifikace v repozitáři **není** — obsahuje obchodní část a zůstává lokálně.

## Licence

MIT, viz [`LICENSE`](LICENSE).
