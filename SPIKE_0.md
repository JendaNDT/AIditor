# Spike 0 – „Funguje speed ramp vůbec?"
*Projekt Krása · zadání prvního kroku · 25. 07. 2026*

## Otázka, na kterou spike odpovídá

> Dá se v AVFoundation udělat **plynulá** rychlostní křivka na reálném klipu z mého telefonu tak, aby zvuk seděl, nelupal a export nespadl — na MacBooku Air M3/M4?

Nic víc. Až bude odpověď, ví se, jestli má smysl stavět zbytek.

## Co spike NEDĚLÁ

Žádná timeline. Žádné panely. Žádná AI. Žádný svatební asistent. Žádné ukládání projektu. Žádný design. Žádná lokalizace.
**Je to odpadní kód.** Až odpoví na otázku, zahodí se a MVP se začne psát načisto s tím, co se ví.

Tohle je celý smysl — když se to rozbije, přijdeš o víkend, ne o čtvrt roku.

---

## Příprava (1–2 hodiny)

1. **Xcode** z App Storu (zdarma). Nový projekt → macOS → App → SwiftUI. Apple Developer Program ($99) **zatím nepotřebuješ** — ten je až na distribuci.
2. **Git hned na začátku:** `git init` a první commit ještě než napíšeš první řádek. Pak commit po každé funkční drobnosti. Když AI v dalším kroku rozbije kód, `git reset --hard` tě vrátí zpátky.
3. **Claude Code v terminálu na Macu**, ne v chatu. Musí umět spustit `xcodebuild` a přečíst si chybu, kterou vyrobil. Bez toho ho posíláš naslepo.
4. **Testovací složka `TestClips/`** — reálné klipy, ne syntetika:
   - 4K/60 z telefonu, 30–60 s
   - 4K/30 z telefonu
   - 1080p nebo 4K/120 (slow-mo)
   - jeden klip, kde někdo mluví (kvůli kontrole zvuku)
   - **u každého si zjisti, jestli je CFR nebo VFR.** `ffprobe` nebo Media Inspector. Alespoň jeden VFR tam nech schválně — je to nejčastější zdroj rozjetého zvuku.
5. **Referenční bod pro synchron:** natoč si 30s klip, kde na začátku a na konci tleskneš. Po exportu uvidíš na první pohled, jestli zvuk ujel.

---

## Postup

### Krok 1 – Otevřít a přehrát (cíl: půl hodiny)
`NSOpenPanel` → vybraný soubor → `AVPlayer` v `NSViewRepresentable` → mezerník play/pauza, šipky krok po snímku.
✅ Hotovo, když přehraješ 4K/60 klip a zkroluješ po snímcích.

### Krok 2 – Konstantní zpomalení + export
`AVMutableComposition`, jeden video track, jeden audio track, `scaleTimeRange` na celý klip na 0,5×. Export přes `AVAssetExportSession` do 1080p.
✅ Hotovo, když soubor vyleze a jde přehrát v QuickTimu.
⚠️ Tady poprvé poslouchej zvuk. Lupance na začátku/konci?

### Krok 3 – Plynulá křivka (tady se to zlomí, nebo ne)
Ramp 1,0× → 0,25× → 1,0× přes prostředek klipu.
**Pozor, tohle je jádro spiku:** `scaleTimeRange` dělá konstantní změnu rychlosti přes daný úsek — vytvoří lineární časové mapování. Plynulý Bézier se z jednoho volání udělat nedá.
Dvě cesty, vyzkoušej v tomhle pořadí:

- **A) Segmentace (jednodušší):** klip se nakrájí na desítky krátkých úseků, každý dostane vlastní `scaleTimeRange` podle křivky. Schodovitá aproximace. Rychlé na napsání, ale každá hranice segmentu je potenciální lupnutí ve zvuku.
- **B) Vlastní compositor (těžší):** `AVMutableVideoComposition` s vlastním `AVVideoCompositing`, kde si časové mapování počítáš sám. Čistší výsledek, výrazně víc práce. Sáhni po tom, jen když A) selže na kvalitě.

✅ Hotovo, když ramp vidíš i slyšíš a export doběhne.

### Krok 4 – Změřit
Zapiš si čísla. Bez nich to není spike, ale hraní.

---

## Kritéria úspěchu — vyplň po víkendu

| # | Co | Výsledek |
|---|-----|----------|
| 1 | Export doběhl bez pádu | ☐ |
| 2 | Zvuk je na konci klipu pořád v synchronu (test s tlesknutím) | ☐ |
| 3 | Ve zvuku nejsou lupance na hranicích segmentů | ☐ |
| 4 | Hlas není „čipmank" (`AVAudioUnitTimePitch` funguje) | ☐ |
| 5 | Náhled 4K/60 — seká se? Kolik fps? | ___ |
| 6 | Jak dlouho trval export 60s klipu? | ___ min |
| 7 | Choval se VFR klip jinak než CFR? | ___ |

---

## Rozhodovací bod (neděle večer)

- **Všechno zelené** → stavíš dál podle sekce 8.1 specifikace. Rozsah MVP je reálný.
- **Zvuk lupe nebo ujíždí** → řešitelné, ale znamená to vlastní audio pipeline přes `AVAudioEngine` místo AVFoundation zkratky. Připočti si týdny, ne dny. Uprav plán, ne ambici.
- **Náhled se seká i po vygenerování proxy** → proxy workflow povyšuješ z „nice to have" na povinnou součást MVP, případně přehodnoť rozsah.
- **Nedostal ses ani ke kroku 3** → to je taky odpověď, a ta nejdůležitější. Znamená to, že cesta vede přes užší produkt (jedna mini-appka „Speed Ramp") místo celého NLE.

Žádný z těch výsledků není neúspěch. Neúspěch by bylo zjistit to samé po půl roce psaní timeline.

---

## Hotové prompty pro Claude Code

### Prompt 0 – ověření API (**pusť ho jako první**)
```
Než začneme cokoli psát: potvrď mi, jak se v AVFoundation na macOS 14+
v roce 2026 reálně dělá plynulá (eased, ne konstantní) změna rychlosti klipu.

Konkrétně:
1. Co přesně dělá AVMutableCompositionTrack.scaleTimeRange(_:toDuration:) —
   je výsledné časové mapování lineární přes celý úsek, nebo umí křivku?
2. Pokud lineární: jaký je doporučený způsob plynulého rampu?
   Segmentace na mikro-úseky, nebo vlastní AVVideoCompositing?
3. U každé zmíněné třídy mi dej přesný název a odkaz na developer.apple.com.

Pokud si něčím nejsi jistý, řekni to explicitně místo odhadu.
Ještě nepiš žádný kód.
```

### Prompt 1 – přehrávač
```
Vytvoř jeden soubor VideoPlayerView.swift pro macOS SwiftUI app (min. macOS 14).
1. AVPlayer + AVPlayerLayer vnořený do NSViewRepresentable.
2. NSOpenPanel pro výběr souboru, včetně Security-Scoped Bookmark
   (appka poběží v sandboxu).
3. Play/pauza mezerníkem, krok po 1 snímku šipkami vlevo/vpravo.
Žádný balast, žádné další funkce. Čistý kompilovatelný Swift.
Až to napíšeš, spusť xcodebuild a oprav chyby, než mi to vrátíš.
```

### Prompt 2 – rychlostní křivka
```
Vytvoř samostatný modul SpeedRampEngine.swift. Zatím čistá matematika,
žádné AVFoundation volání.
1. struct SpeedNode(timeOffset: Double, multiplier: Double)
2. Funkce, která pro daný čas na timeline vrátí odpovídající čas ve zdrojovém
   videu — integrál rychlostní křivky, cubic Bézier interpolace mezi uzly.
3. XCTest testy: ramp 1.0 → 0.25 → 1.0 musí být spojitý, monotónní
   a na koncích sedět na očekávaný čas.
Testy musí projít, než mi kód vrátíš.
```

### Prompt 3 – složení a export
```
Použij SpeedRampEngine a postav AVMutableComposition, která na vybraný klip
aplikuje ramp 1.0 → 0.25 → 1.0 přes prostřední třetinu.
Postupuj cestou segmentace na mikro-úseky (viz odpověď z Promptu 0).
Video i audio track drž v synchronu, na audio nasaď AVAudioUnitTimePitch.
Export přes AVAssetExportSession do 1080p H.264.
Do konzole vypiš dobu exportu v sekundách.
```

---

## Jedno pravidlo na závěr

Když AI navrhne API, které nenajdeš na developer.apple.com — **nepokračuj**. Nech ji navrhnout alternativu a ověř si ji sám. Ve specifikaci v2.0 se takhle našly dvě smyšlené věci („optický tok přes Core Image", framework „Core Speech"). V dokumentu to stálo jednu opravu. V kódu by to stálo víkend.
