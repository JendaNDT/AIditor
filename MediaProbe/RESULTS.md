# MediaProbe — naměřené vlastnosti testovacích klipů

*Vygenerováno 2026-07-28T16:56:45Z nástrojem `MediaProbe`.*

Klipy samotné jsou v `.gitignore` (jsou to gigabajty videa), takže tenhle
soubor je jediný záznam o tom, na čem se měřilo. Negeneruj ho ručně —
spusť `swift run MediaProbe` a commitni výsledek.

- **Zdrojová složka:** `/Users/jenda/Library/Containers/cz.projektkrasa.Krasa/Data/tmp/KrasaExportCheck`
- **Souborů:** 1

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
| export_check.mp4 | ⚠ nevyplněno |

## Souhrn

| Soubor | Obraz | Kodek | fps nom. | fps měř. | Edit V/A | Délka | Zvuk | Kolísání | Okraje | Zahozeno | Verdikt |
|---|---|---|---|---|---|---|---|---|---|---|---|
| export_check.mp4 | 3840×2160 | HEVC | 30,00 | 30,00 | 1:1/⚠ | 2:37,967 | AAC 2ch 48,0k | 0,0 % | ok | — | CFR |

## Závěr

```
Souborů celkem: 1
Skutečně proměnlivé časování (VFR): 0 z 1
Zahozených snímků celkem: 0
Netriviální edit list na obraze: 0
Netriviální edit list na zvuku: 1 — export_check.mp4
Přeškálování rychlosti edit listem: 0 — žádný klip nenese slow-mo zapsané jako edit list nad vysokorychlostní stopou.

Posun zvuku podle edit listu (1 z 1 klipů):
  · export_check.mp4: prvních 44,0 ms zdroje se zahazuje
Tohle je priming AAC kodéru. Kdo edit list ignoruje a čte syrové vzorky,
dostane zvuk posunutý o tenhle offset — a bude ho hledat jinde.
```

## Detail

### export_check.mp4

```
▸ export_check.mp4  (MP4 · 949,3 MB)
  Obsah      ⚠ nevyplněno — doplň do MediaProbe/CLIPS.txt
  Obraz      3840×2160 nativně, transform ↻0° → zobrazeno 3840×2160 (na šířku)
             kodek HEVC (hvc1), datový tok 50,1 Mbit/s
  Deklarace  nominální fps 30,000, minFrameDuration 3000/90000 (33,333 ms)
             timescale stopy 90000, timeRange 2:37,967
  Edit list  1 segment, mapování 1:1 bez posunu — nic nepřeškálovává
  Vzorky     4739 přečteno přes AVSampleCursor, 1 různá délka/délky
             histogram: 3000 t = 33,333 ms ×4739
             min 3000 t (33,333 ms), max 3000 t (33,333 ms), modus 3000 t (33,333 ms)
             směrodatná odchylka 0,0000 ticku = 0,0000 ms
             měřená fps z modu 30,0000
  Rozbor     4739× přesně na modu · 0× zaokrouhlení (±1 tick) · 0× násobek modu · 0× nepravidelné
  Kolísání   0 t = 0,000 ms = 0,00 %
             uvnitř stopy, z 4737 vzorků — bez okrajů a bez zahozených snímků
             se vším dohromady by vyšlo 0 t = 0,00 %
  Okraje     první vzorek [0] přesně na modu
             poslední vzorek [4738] přesně na modu
  Verdikt    CFR — všechny vzorky mají identickou délku.
  Zvuk       AAC (aac ), 2 kanál(ů), 48000 Hz
  Edit list z ⚠ 1 segment(ů), mapování NENÍ triviální:
             [0] source 0:00,044 + 2:37,899  →  target 0:00,000 + 2:37,899  rate 1,0000×
  Délka      2:37,967 (asset)
```
