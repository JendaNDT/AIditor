# MediaProbe — naměřené vlastnosti testovacích klipů

*Vygenerováno 2026-07-26T10:15:31Z nástrojem `MediaProbe`.*

Klipy samotné jsou v `.gitignore` (jsou to gigabajty videa), takže tenhle
soubor je jediný záznam o tom, na čem se měřilo. Negeneruj ho ručně —
spusť `swift run MediaProbe` a commitni výsledek.

- **Zdrojová složka:** `/Users/jenda/Desktop/Claude Projekty/AIditor/TestClips`
- **Souborů:** 5

## Jak se to měří

Apple nemá API, které řekne „tenhle soubor je VFR". Délky jednotlivých
vzorků se čtou přes `AVSampleCursor` (tabulka vzorků v kontejneru, bez
dekódování), a když stopa kurzory neumí, přes `AVAssetReader` s
`outputSettings: nil`. Porovnávají se **celá čísla v tickách timescale**,
ne sekundy — plovoucí aritmetika by vyrobila rozptyl, který v souboru není.

Každá délka se klasifikuje vůči nejčastější hodnotě (modu):

| Kategorie | Podmínka | Co s tím |
|---|---|---|
| zaokrouhlení | odchylka ≤ 1 tick | nic, je to artefakt časové základny |
| zahozený snímek | celočíselný násobek modu (±10 %) | doplnit duplikát |
| nepravidelné | cokoli jiného | přepočítat časování |

Verdikty: `CFR` všechny vzorky identické · `CFR≈` jen zaokrouhlení ·
`CFR↓n` konstantní časování s n zahozenými snímky · `CFR±` nepravidelný
jen krajní vzorek · `VFR` skutečně proměnlivé časování.

Sloupec `Edit V/A` hlásí edit list zvlášť pro obraz a pro zvuk.

`Kolísání` je odchylka **uvnitř** stopy — bez prvního a posledního vzorku
a bez zahozených snímků. Obojí by číslo nafouklo o řád a zakrylo, že
časování je jinak klidné. Nic se ale nezahazuje potichu: okraje mají
sloupec `Okraje` a vlastní řádek v detailu, zahozené snímky sloupec
`Zahozeno`. Detail navíc vždy uvádí i číslo se vším dohromady.

## Co je na klipech

Ručně udržované v `MediaProbe/CLIPS.txt` — názvy souborů jsou časová
razítka a obsah záběru z metadat vyčíst nejde.

| Soubor | Co se točilo |
|---|---|
| 20260725_202947.mp4 | 4K/60 (naměřeno 59,68 fps), 44,9 s — ⚠ DOPLŇ co je na záběru |
| 20260725_203452.mp4 | 4K/30 (naměřeno 30,01 fps), 38,6 s — ⚠ DOPLŇ co je na záběru |
| 20260725_203813.mp4 | 120fps slow-mo (naměřeno 120,00 fps), 11,3 s — vstup pro krok 4 spiku (ramp 120 → 0,25× → 30 fps). ⚠ DOPLŇ co je na záběru |
| 20260725_203901.mp4 | 4K/60 (naměřeno 60,00 fps), 31,7 s — REFERENČNÍ KLIP NA SYNCHRON. Detekce transientů ho označila jako klip s tlesknutím: vrchol 0,33 s od začátku a 1,02 s od konce, ostatní klipy mají nejhlasitější místo uprostřed. ⚠ POTVRĎ uchem |
| 20260725_204045.mp4 | 4K/60 (naměřeno 60,00 fps), 31,6 s — ⚠ DOPLŇ co je na záběru |

## Souhrn

| Soubor | Obraz | Kodek | fps nom. | fps měř. | Edit V/A | Délka | Zvuk | Kolísání | Okraje | Zahozeno | Verdikt |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 20260725_202947.mp4 | 3840×2160 | HEVC | 59,66 | 59,68 | 1:1/⚠ | 0:44,952 | AAC 2ch 48,0k | 0,1 % | ok | 1 v 1× | CFR↓1 |
| 20260725_203452.mp4 | 3840×2160 | HEVC | 29,99 | 30,01 | 1:1/⚠ | 0:38,646 | AAC 2ch 48,0k | 0,0 % | 1,79× 1. | — | CFR± |
| 20260725_203813.mp4 | 3840×2160 | HEVC | 119,37 | 120,00 | 1:1/⚠ | 0:11,360 | AAC 2ch 48,0k | 1,1 % | 1,14× 1. 1,01× posl. | — | VFR |
| 20260725_203901.mp4 | 3840×2160 | HEVC | 59,79 | 60,00 | 1:1/⚠ | 0:31,725 | AAC 2ch 48,0k | 1,9 % | 1,37× 1. | 6 v 4× | VFR |
| 20260725_204045.mp4 | 3840×2160 | HEVC | 59,93 | 60,00 | 1:1/⚠ | 0:31,585 | AAC 2ch 48,0k | 0,1 % | 1,94× 1. | 2 v 2× | CFR↓2 |

## Závěr

```
Souborů celkem: 5
Skutečně proměnlivé časování (VFR): 2 z 5 — 20260725_203813.mp4, 20260725_203901.mp4
Konstantní se zahozenými snímky: 2 — 20260725_202947.mp4, 20260725_204045.mp4
  Tyhle stačí doplnit duplikáty, časování se přepočítávat nemusí.
Zahozených snímků celkem: 9
Netriviální edit list na obraze: 0
Netriviální edit list na zvuku: 5 — 20260725_202947.mp4, 20260725_203452.mp4, 20260725_203813.mp4, 20260725_203901.mp4, 20260725_204045.mp4
Přeškálování rychlosti edit listem: 0 — žádný klip nenese slow-mo zapsané jako edit list nad vysokorychlostní stopou.

Posun zvuku podle edit listu (5 z 5 klipů):
  · 20260725_202947.mp4: prvních 44,0 ms zdroje se zahazuje, zvuk začíná až v 11,1 ms stopy
  · 20260725_203452.mp4: prvních 44,0 ms zdroje se zahazuje
  · 20260725_203813.mp4: prvních 44,0 ms zdroje se zahazuje
  · 20260725_203901.mp4: prvních 44,0 ms zdroje se zahazuje
  · 20260725_204045.mp4: prvních 44,0 ms zdroje se zahazuje
Tohle je priming AAC kodéru. Kdo edit list ignoruje a čte syrové vzorky,
dostane zvuk posunutý o tenhle offset — a bude ho hledat jinde.
```

## Detail

### 20260725_202947.mp4

```
▸ 20260725_202947.mp4  (MP4 · 644,6 MB)
  Obsah      4K/60 (naměřeno 59,68 fps), 44,9 s — ⚠ DOPLŇ co je na záběru
  Obraz      3840×2160 nativně, transform ↻0° → zobrazeno 3840×2160 (na šířku)
             kodek HEVC (hvc1), datový tok 120,0 Mbit/s
  Deklarace  nominální fps 59,664, minFrameDuration 1507/90000 (16,744 ms)
             timescale stopy 90000, timeRange 0:44,952
  Edit list  1 segment, mapování 1:1 bez posunu — nic nepřeškálovává
  Vzorky     2682 přečteno přes AVSampleCursor, 3 různá délka/délky
             histogram: 1508 t = 16,756 ms ×2402, 1507 t = 16,744 ms ×279, 3016 t = 33,511 ms ×1
             min 1507 t (16,744 ms), max 3016 t (33,511 ms), modus 1508 t (16,756 ms)
             směrodatná odchylka 29,1169 ticku = 0,3235 ms
             měřená fps z modu 59,6817
  Rozbor     2402× přesně na modu · 279× zaokrouhlení (±1 tick) · 1× násobek modu · 0× nepravidelné
  Zahozeno   1 snímek/snímků ve 1 místě/místech — vzorek je celočíselným násobkem délky snímku.
             Opraví se doplněním duplikátů, ne přepočtem časování.
  Kolísání   1 t = 0,011 ms = 0,07 %
             uvnitř stopy, z 2679 vzorků — bez okrajů a bez zahozených snímků
             se vším dohromady by vyšlo 1508 t = 100,00 %
  Okraje     první vzorek [0] přesně na modu
             poslední vzorek [2681] přesně na modu
  Verdikt    CFR se zahozenými snímky — časování je jinak konstantní, ale v 1 místě/místech je vzorek celočíselným násobkem délky snímku. Chybí 1 snímek/snímků. Tohle se řeší doplněním duplikátů, ne přepočtem časování.
  Zvuk       AAC (aac ), 2 kanál(ů), 48000 Hz
  Edit list z ⚠ 2 segment(ů), mapování NENÍ triviální:
             [0] prázdný segment (edit bez média) target 0:00,000 + 0:00,011
             [1] source 0:00,044 + 0:44,883  →  target 0:00,011 + 0:44,883  rate 1,0000×
  Délka      0:44,952 (asset)
```

### 20260725_203452.mp4

```
▸ 20260725_203452.mp4  (MP4 · 444,7 MB)
  Obsah      4K/30 (naměřeno 30,01 fps), 38,6 s — ⚠ DOPLŇ co je na záběru
  Obraz      3840×2160 nativně, transform ↻0° → zobrazeno 3840×2160 (na šířku)
             kodek HEVC (hvc1), datový tok 96,2 Mbit/s
  Deklarace  nominální fps 29,990, minFrameDuration 2998/90000 (33,311 ms)
             timescale stopy 90000, timeRange 0:38,646
  Edit list  1 segment, mapování 1:1 bez posunu — nic nepřeškálovává
  Vzorky     1159 přečteno přes AVSampleCursor, 3 různá délka/délky
             histogram: 2999 t = 33,322 ms ×1093, 2998 t = 33,311 ms ×65, 5365 t = 59,611 ms ×1
             min 2998 t (33,311 ms), max 5365 t (59,611 ms), modus 2999 t (33,322 ms)
             směrodatná odchylka 69,4702 ticku = 0,7719 ms
             měřená fps z modu 30,0100
  Rozbor     1093× přesně na modu · 65× zaokrouhlení (±1 tick) · 0× násobek modu · 1× nepravidelné
  Kolísání   1 t = 0,011 ms = 0,03 %
             uvnitř stopy, z 1157 vzorků — bez okrajů a bez zahozených snímků
             se vším dohromady by vyšlo 2366 t = 78,89 %
  Okraje     první vzorek [0] 5365 t = 59,611 ms, 1,789× modu ⚠
             poslední vzorek [1158] přesně na modu
             Vyjmuté z kolísání výše, ne zahozené — krajní vzorek bývá
             useknutý a nafoukl by číslo o řád.
             nepravidelné vzorky na indexech: 0
  Verdikt    CFR s odchylkou na okraji — nepravidelný je pouze vzorek/vzorky na indexu 0 (první a/nebo poslední). Uvnitř stopy je frekvence konstantní. Useknutý krajní vzorek je běžný a neznamená VFR.
  Zvuk       AAC (aac ), 2 kanál(ů), 48000 Hz
  Edit list z ⚠ 1 segment(ů), mapování NENÍ triviální:
             [0] source 0:00,044 + 0:38,590  →  target 0:00,000 + 0:38,590  rate 1,0000×
  Délka      0:38,646 (asset)
```

### 20260725_203813.mp4

```
▸ 20260725_203813.mp4  (MP4 · 109,9 MB)
  Obsah      120fps slow-mo (naměřeno 120,00 fps), 11,3 s — vstup pro krok 4 spiku (ramp 120 → 0,25× → 30 fps). ⚠ DOPLŇ co je na záběru
  Obraz      3840×2160 nativně, transform ↻0° → zobrazeno 3840×2160 (na šířku)
             kodek HEVC (hvc1), datový tok 80,5 Mbit/s
  Deklarace  nominální fps 119,369, minFrameDuration 750/90000 (8,333 ms)
             timescale stopy 90000, timeRange 0:11,360
  Edit list  1 segment, mapování 1:1 bez posunu — nic nepřeškálovává
  Vzorky     1356 přečteno přes AVSampleCursor, 5 různá délka/délky
             histogram: 750 t = 8,333 ms ×636, 758 t = 8,422 ms ×481, 757 t = 8,411 ms ×197, 751 t = 8,344 ms ×41, 854 t = 9,489 ms ×1
             min 750 t (8,333 ms), max 854 t (9,489 ms), modus 750 t (8,333 ms)
             směrodatná odchylka 4,7045 ticku = 0,0523 ms
             měřená fps z modu 120,0000
  Rozbor     636× přesně na modu · 41× zaokrouhlení (±1 tick) · 0× násobek modu · 679× nepravidelné
  Kolísání   8 t = 0,089 ms = 1,07 %
             uvnitř stopy, z 1354 vzorků — bez okrajů a bez zahozených snímků
             se vším dohromady by vyšlo 104 t = 13,87 %
  Okraje     první vzorek [0] 854 t = 9,489 ms, 1,139× modu ⚠
             poslední vzorek [1355] 758 t = 8,422 ms, 1,011× modu ⚠
             Vyjmuté z kolísání výše, ne zahozené — krajní vzorek bývá
             useknutý a nafoukl by číslo o řád.
             nepravidelné vzorky na indexech: 0, 2, 4, 6, 8, 10, 12, 14, … +671
  Verdikt    VFR — 679 vzorek/vzorků má délku, kterou nevysvětlí ani zaokrouhlení, ani zahozený snímek. Časování je skutečně proměnlivé a před střihem se musí přepočítat na CFR.
  Zvuk       AAC (aac ), 2 kanál(ů), 48000 Hz
  Edit list z ⚠ 1 segment(ů), mapování NENÍ triviální:
             [0] source 0:00,044 + 0:11,262  →  target 0:00,000 + 0:11,262  rate 1,0000×
  Délka      0:11,360 (asset)
```

### 20260725_203901.mp4

```
▸ 20260725_203901.mp4  (MP4 · 455,6 MB)
  Obsah      4K/60 (naměřeno 60,00 fps), 31,7 s — REFERENČNÍ KLIP NA SYNCHRON. Detekce transientů ho označila jako klip s tlesknutím: vrchol 0,33 s od začátku a 1,02 s od konce, ostatní klipy mají nejhlasitější místo uprostřed. ⚠ POTVRĎ uchem
  Obraz      3840×2160 nativně, transform ↻0° → zobrazeno 3840×2160 (na šířku)
             kodek HEVC (hvc1), datový tok 120,0 Mbit/s
  Deklarace  nominální fps 59,794, minFrameDuration 1495/90000 (16,611 ms)
             timescale stopy 90000, timeRange 0:31,725
  Edit list  1 segment, mapování 1:1 bez posunu — nic nepřeškálovává
  Vzorky     1897 přečteno přes AVSampleCursor, 24 různá délka/délky
             histogram: 1500 t = 16,667 ms ×1563, 1501 t = 16,678 ms ×219, 1498 t = 16,644 ms ×44, 1496 t = 16,622 ms ×16, 1497 t = 16,633 ms ×12, 1504 t = 16,711 ms ×10 … a další 18
             min 1495 t (16,611 ms), max 4501 t (50,011 ms), modus 1500 t (16,667 ms)
             směrodatná odchylka 109,5509 ticku = 1,2172 ms
             měřená fps z modu 60,0000
  Rozbor     1563× přesně na modu · 223× zaokrouhlení (±1 tick) · 4× násobek modu · 107× nepravidelné
  Zahozeno   6 snímek/snímků ve 4 místě/místech — vzorek je celočíselným násobkem délky snímku.
             Opraví se doplněním duplikátů, ne přepočtem časování.
  Kolísání   29 t = 0,322 ms = 1,93 %
             uvnitř stopy, z 1891 vzorků — bez okrajů a bez zahozených snímků
             se vším dohromady by vyšlo 3001 t = 200,07 %
  Okraje     první vzorek [0] 2051 t = 22,789 ms, 1,367× modu ⚠
             poslední vzorek [1896] přesně na modu
             Vyjmuté z kolísání výše, ne zahozené — krajní vzorek bývá
             useknutý a nafoukl by číslo o řád.
             nepravidelné vzorky na indexech: 0, 557, 559, 561, 563, 565, 567, 569, … +99
  Verdikt    VFR — 107 vzorek/vzorků má délku, kterou nevysvětlí ani zaokrouhlení, ani zahozený snímek. Časování je skutečně proměnlivé a před střihem se musí přepočítat na CFR. Z toho 6 zahozený snímek/snímků.
  Zvuk       AAC (aac ), 2 kanál(ů), 48000 Hz
  Edit list z ⚠ 1 segment(ů), mapování NENÍ triviální:
             [0] source 0:00,044 + 0:31,678  →  target 0:00,000 + 0:31,678  rate 1,0000×
  Délka      0:31,725 (asset)
```

### 20260725_204045.mp4

```
▸ 20260725_204045.mp4  (MP4 · 453,8 MB)
  Obsah      4K/60 (naměřeno 60,00 fps), 31,6 s — ⚠ DOPLŇ co je na záběru
  Obraz      3840×2160 nativně, transform ↻0° → zobrazeno 3840×2160 (na šířku)
             kodek HEVC (hvc1), datový tok 120,1 Mbit/s
  Deklarace  nominální fps 59,934, minFrameDuration 1500/90000 (16,667 ms)
             timescale stopy 90000, timeRange 0:31,585
  Edit list  1 segment, mapování 1:1 bez posunu — nic nepřeškálovává
  Vzorky     1893 přečteno přes AVSampleCursor, 4 různá délka/délky
             histogram: 1500 t = 16,667 ms ×1657, 1501 t = 16,678 ms ×234, 2904 t = 32,267 ms ×1, 3000 t = 33,333 ms ×1
             min 1500 t (16,667 ms), max 3000 t (33,333 ms), modus 1500 t (16,667 ms)
             směrodatná odchylka 47,1941 ticku = 0,5244 ms
             měřená fps z modu 60,0000
  Rozbor     1657× přesně na modu · 234× zaokrouhlení (±1 tick) · 2× násobek modu · 0× nepravidelné
  Zahozeno   2 snímek/snímků ve 2 místě/místech — vzorek je celočíselným násobkem délky snímku.
             Opraví se doplněním duplikátů, ne přepočtem časování.
  Kolísání   1 t = 0,011 ms = 0,07 %
             uvnitř stopy, z 1890 vzorků — bez okrajů a bez zahozených snímků
             se vším dohromady by vyšlo 1500 t = 100,00 %
  Okraje     první vzorek [0] 2904 t = 32,267 ms, 1,936× modu ⚠
             poslední vzorek [1892] přesně na modu
             Vyjmuté z kolísání výše, ne zahozené — krajní vzorek bývá
             useknutý a nafoukl by číslo o řád.
  Verdikt    CFR se zahozenými snímky — časování je jinak konstantní, ale v 2 místě/místech je vzorek celočíselným násobkem délky snímku. Chybí 2 snímek/snímků. Tohle se řeší doplněním duplikátů, ne přepočtem časování.
  Zvuk       AAC (aac ), 2 kanál(ů), 48000 Hz
  Edit list z ⚠ 1 segment(ů), mapování NENÍ triviální:
             [0] source 0:00,044 + 0:31,508  →  target 0:00,000 + 0:31,508  rate 1,0000×
  Délka      0:31,585 (asset)
```
