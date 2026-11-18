# Roon Server w EncoreBridge

## Ustalenia i plan

Punkt wyjścia: ostatnie wpisy wątku `codex://threads/01a12bba-5780-7601-a051-4a7d23a8e694`
oraz zapis próby `encore-roon-log-proof-20261116`. Odczyt dotyczy źródła utworu,
nie parametrów PCM po dekodowaniu, wyjścia SHD ani DSP.

1. Czytać lokalny `~/Library/RoonServer/Logs/RoonServer_log.txt` i uwzględnić rotację.
2. Powiązać zdarzenia strefy `SHD ROON`: `Playing`, `StartStream`, podsumowanie `PLAYING`.
3. Odrzucać parametry `LOADING`, `PAUSED`, `STOPPED` i innych stref; promować `Queueing`
   do bieżącego pliku tylko po potwierdzonym przejściu `OnToNext`.
4. Przekazać kompletny odczyt do dotychczasowego panelu, bez łączenia pól z Apple Music.
5. Sprawdzić parser, zmiany utworów, niepełne dane, rotację i działający odczyt na Macu.

## Działanie

- Każde odtwarzające źródło ma własną sekcję podpisaną `Apple Music` albo `Roon`.
  Podczas równoczesnego odtwarzania obie sekcje są widoczne. Nie ma priorytetów źródeł.
  Apple Music udostępnia stan odtwarzacza; sekcja Roon wymaga świeżego `PLAYING`
  z ostatnich 20 sekund i znika po wpisie pauzy lub zatrzymania.
- Tytuł i wykonawca pochodzą z tego samego podsumowania `PLAYING`. Identyfikator
  uwzględnia strefę i wpis `Playing`, jeśli jest dostępny. Nazwa pliku ani `Queueing`
  nie są źródłem tytułu.
- Kodek i głębia formatu bezstratnego pochodzą z lewej strony opisu źródła, przed `=>`.
- Skrótu `44` nie zamieniamy samodzielnie na 44,1 kHz. Dokładna częstotliwość musi
  zgadzać się z powiązanym `StartStream`. Obsługiwane są `StreamFormat` i `StreamParams`.
  Niezgodne lub brakujące dane są pomijane.
- Dla MP3/AAC/OGG/Opus nie pokazujemy głębi PCM dekodera jako głębi oryginalnego pliku.
- Po zmianie utworu i rotacji odtwarzany jest kontekst zdarzeń, bez przenoszenia parametrów
  z poprzedniego utworu. Czytnik zachowuje niepełne linie do kolejnego odczytu.
- Przy odtwarzaniu bez przerw `OnToNext` potwierdza wejście zbuforowanego nagrania.
  Istniejący ciągły strumień może dostarczyć dokładną częstotliwość wyłącznie wtedy,
  gdy zgadza się z nowym opisem źródła.
- Start/Stop Monitoring obejmuje oba źródła. Show Logs nadal pokazuje 10 ostatnich
  wpisów, a Copy Logs zawiera źródło, strefę, ścieżkę, błędy oraz diagnostykę Apple Music.

## Granice tego etapu

Czytnik działa na Macu z lokalnym Roon Server i strefą SHD ROON. Logi są nieudokumentowanym
formatem diagnostycznym i ich zmiana może wymagać aktualizacji parsera. Rozdzielenie
tytułu i wykonawcy korzysta z separatora używanego w podsumowaniu Roon (` - `);
niestandardowe nazwy zawierające ten separator mogą być niejednoznaczne.

Integracja nie zmienia odtwarzania, głośności ani konfiguracji Roon. Publiczne API Roon,
serwer HTTP oraz przesyłanie danych do wzmacniacza pozostają osobnymi etapami.

Dokumentacja lokalizacji logów: https://help.roonlabs.com/portal/en/kb/articles/logs

## Weryfikacja 16 listopada 2026

Po usunięciu priorytetów źródeł pełny zestaw zakończył się wynikiem 43 testów
zaliczonych i jednego pominiętego opcjonalnego testu odtwarzania Apple Music.
Test równoczesnego odtwarzania sprawdza niezależne tytuły i parametry obu źródeł
oraz pauzę każdego z nich. Zweryfikowano także podgląd panelu z dwiema sekcjami.
Aktualny wynik:
`/var/folders/k_/8qr7jhp17h5frjkbd3fvpxx40000gn/T/ActionArtifacts/default/RunAllTests/Test-EncoreBridge-2026.11.16_13-59-17-+0100.xcresult`.

- Pełny zestaw: 42 testy zaliczone, 1 pominięty (`testLiveMusicFormats` wymaga
  osobnego włączenia odtwarzania Apple Music). Wynik:
  `/var/folders/k_/8qr7jhp17h5frjkbd3fvpxx40000gn/T/ActionArtifacts/default/RunAllTests/Test-EncoreBridge-2026.11.16_13-47-13-+0100.xcresult`.
- Osobno zaliczony nowy test `testRoonPanelMatchesLiveSourceFileWhenAvailable`:
  działający panel, skopiowana diagnostyka oraz plik ALAC miały zgodne metadane
  i parametry. Wynik:
  `/var/folders/k_/8qr7jhp17h5frjkbd3fvpxx40000gn/T/ActionArtifacts/default/RunSomeTests/Test-EncoreBridge-2026.11.16_13-50-08-+0100.xcresult`.
- Odczyt rzeczywistych logów przez kod czytnika porównano niezależnie z AVFoundation
  i `ffprobe`: Sigur Rós — `[Njósnavélin] (The Spy Song, or The Nothing Song)`:
  ALAC, 16 bit, 44100 Hz. Zapis: `/private/tmp/EncoreBridge-roon-live-verification.json`.
- Wszystkie sprawdzenia Roon były odczytem; nie zmieniano odtwarzania ani ustawień serwera.
