# M6 Encore — lokalny moduł ekranu

`telemetry.py` wybiera metadane zgodnie z fizycznym wejściem SHD. Kontrakt i reguły
LAN/Roon/Volumio opisano w [dokumentacji API](../docs/network-api.md).

## Czytelność ekranu — 16 listopada 2026

`update_typography.py` zmienia wyłącznie skórę Now Playing:

- Dwa wiersze metadanych: **31 px bold** zamiast 22 px; tytuł wejścia nadal 40 px.
- Tekst metadanych, głośności i tytułu wejścia: biały `#FFFFFF`.
- Wiersze danych: `x=30`, szerokość 560 px, wysokość 49 px, `y=211` i `y=261`.
  Głośność: **38 px bold**, `y=151`, wysokość 58 px; sama wartość, np. `-20 dB`.
  Kolejność: głośność, źródło, `Input` (wcześniej `SHD Out`). AirPlay w Volumio
  ma etykietę `Airplay`.
- Weryfikacja rzeczywistym fontem `NotoSansCJKsc-Bold.otf` i SDL_ttf na M6:
  1260 kombinacji kodeka, bitów i standardowych częstotliwości;
  maksymalna szerokość 545 px, wysokość fontu 46 px. Przy 32 px najdłuższy wariant
  wymagał 565 px, dlatego końcowy rozmiar to 31 px.
- Skrypt sprawdza Lua fabrycznym `luac -p`, zapisuje kopię poprzedniej skóry
  i używa fabrycznej komendy `encore reload 0 0`. Nie kończy procesu Jive.

Podgląd zmian na urządzeniu: `python3 update_typography.py`.
Zastosowanie: `python3 update_typography.py --apply` (na M6 jako root).

[Ekran przed zmianą](../docs/evidence/m6-typography-before-20261116.png) ·
[Ekran po zmianie](../docs/evidence/m6-typography-after-20261116.png)
