# EncoreBridge

Aplikacja paska menu macOS pokazująca metadane i format źródła Apple Music oraz Roon.
M6 Encore pobiera dane z lokalnego serwera HTTP; zamknięcie panelu nie zatrzymuje usług.

Kliknij ikonę fali, aby otworzyć panel. Przycisk **Opcje** zawiera Show Logs, Copy Logs,
Start/Stop Monitoring i Close. Okno logów otwiera się wyłącznie na żądanie.

## Kod i dokumentacja

- `EncoreBridge/App` — sceny, cykl życia, składanie usług i polecenia panelu.
- `EncoreBridge/Features/AudioMonitoring` — odczyty, stan i prezentacja źródeł.
- `EncoreBridge/Features/Diagnostics` — agregacja i prezentacja logów.
- `EncoreBridge/Integrations/EncoreAPI` — mapper, DTO i serwer HTTP dla M6.
- [Architektura](EncoreBridge/Documentation.docc/Architecture.md), [współbieżność](EncoreBridge/Documentation.docc/Concurrency.md), [dalszy przegląd](EncoreBridge/Documentation.docc/ReviewAndNextSteps.md).
- [Odczyt Apple Music](EncoreBridge/Documentation.docc/AppleMusicMonitoring.md) i [nasłuch logów Music](EncoreBridge/Documentation.docc/MusicLogStreaming.md).
- [Weryfikacja refaktoru](docs/refactor-verification-20261118.md).
- [Kontrakt sieciowy](docs/network-api.md), [odczyt Roon](docs/roon-log-monitoring.md).

## Uruchomienie i testy

Otwórz `EncoreBridge.xcodeproj`, wybierz schemat `EncoreBridge` i docelowy Mac.
Obecny projekt wymaga SDK macOS 27. Dostęp Apple Events do Music oraz uprawnienie
Accessibility do odczytu panelu jakości zależą od uprawnień nadanych aplikacji na Macu.
Roon jest odczytywany z lokalnego `~/Library/RoonServer/Logs/RoonServer_log.txt` dla strefy `SHD ROON`.

```sh
xcodebuild -project EncoreBridge.xcodeproj -scheme EncoreBridge \
  -destination 'platform=macOS,arch=arm64' test
```

Test `testLiveMusicFormats` jest opcjonalny i może sterować odtwarzaniem Music.
Włączaj go świadomie przez `TEST_RUNNER_ENCOREBRIDGE_LIVE_MUSIC=1`.

## Dokumentacja DocC

W Xcode wybierz **Product → Build Documentation**. Komentarze `///` przy symbolach
łączą się z artykułami katalogu `Documentation.docc`. Dla targetu aplikacji DocC
uwzględnia symbole wewnętrzne — nie trzeba zmieniać ich na `public`.

```sh
xcodebuild -project EncoreBridge.xcodeproj -scheme EncoreBridge \
  -destination 'platform=macOS,arch=arm64' docbuild
```
