# Architektura i mapa katalogów

Prześledź odpowiedzialności od uruchomienia aplikacji do odpowiedzi HTTP.

## Overview

Jest to mała aplikacja w jednym module. Podział katalogów opisuje odpowiedzialności;
nie wymusza granic modułów na poziomie kompilatora. Nie dodajemy warstw i protokołów,
dopóki nie rozwiązują konkretnego problemu.

| Katalog | Odpowiedzialność | Przykład powodu zmiany |
| --- | --- | --- |
| `App` | Sceny, cykl życia i składanie zależności | Inny sposób uruchamiania usług |
| `App/MenuBar` | Panel i polecenia łączące funkcje aplikacji | Nowe polecenie w Opcjach |
| `Features/AudioMonitoring/Models` | Wartości opisujące odtwarzanie | Nowa informacja o źródle |
| `Features/AudioMonitoring/State` | Stan i koordynacja odczytów | Inne reguły aktualizacji stanu |
| `Features/AudioMonitoring/Services` | Odczyt źródeł i parsowanie | Zmiana formatu logu Roon |
| `Features/AudioMonitoring/Views` | Prezentacja odtwarzających źródeł | Układ metadanych |
| `Features/Diagnostics` | Zbieranie i prezentacja diagnostyki | Inny eksport logów |
| `Integrations/EncoreAPI` | Kontrakt M6, mapowanie i serwer HTTP | Zmiana pól JSON lub endpointów |
| `Documentation.docc` | Dokumentacja kompilowana z kodem | Zmiana decyzji architektonicznej |

Katalog `m6` poza targetem aplikacji zawiera integrację urządzenia. Katalog `script`
jest przeznaczony na lokalne narzędzia robocze i jest ignorowany przez Git.
Szczegóły kontraktu oraz wcześniejsze dowody wdrożenia są w `docs/network-api.md`.

## Cykl życia

``EncoreBridgeApp`` deklaruje sceny `MenuBarExtra` w stylu `.window` i pojedyncze okno logów.
SwiftUI odpowiada za systemową prezentację panelu i menu przycisku „Opcje”.
Nie ma ręcznego pozycjonowania menu ani osobnego menu prawego przycisku.
Okno logów ma wyłączone automatyczne otwieranie i odtwarzanie poprzedniej sesji;
otwiera je polecenie `openWindow(id: "diagnostics")`.

``EncoreBridgeAppDelegate`` jest adapterem zdarzeń aplikacji: uruchamia i zatrzymuje
``ApplicationRuntime``. Ustawienie `LSUIElement = YES` w projekcie zapewnia działanie
bez ikony Docka. Nadal jest to
cykl życia SwiftUI: `@NSApplicationDelegateAdaptor` tworzy delegata w jego obrębie.

Apple zaleca obsługę cyklu życia przez SwiftUI, kiedy to możliwe. Tutaj pozostawiamy
krótkie haki delegata, ponieważ usługi mają działać także bez otwartych okien.
Nie wiążemy ich czasu życia z `.task` panelu ani aktywnością okna logów.

## Przepływ danych

1. `MusicLogMonitor` i `RoonLogMonitor` aktualizują własny stan.
2. ``PlaybackMonitor`` udostępnia źródła dla UI oraz neutralną ``PlaybackMonitoringSnapshot``.
3. HTTP wywołuje przekazane domknięcie na głównym aktorze.
4. ``EncoreSnapshotMapper`` zamienia migawkę na ``BridgePlaybackSnapshot``.
5. Serwer koduje odpowiedź i odsyła ją klientowi, który wysłał żądanie.

Odczyt źródła Apple Music opisują <doc:AppleMusicMonitoring> i <doc:MusicLogStreaming>.

Mapowanie należy do integracji: nazwy `apple_music`, `Mac`, pola JSON, jednostki
oraz progi świeżości 3/20 sekund wynikają z kontraktu odbiorcy. Monitoring przechowuje
obserwacje bez znajomości tego kontraktu. Mapa nie zastępuje reguł samego źródła,
np. wygaszania stanu Roon po utracie raportów PLAYING.

## Panel i diagnostyka

``MenuBarRootView`` składa sekcje odtwarzania i ``MenuBarOptionsView``.
Przełącznik Start/Stop steruje monitorami źródeł. Listener HTTP należy do
``ApplicationRuntime`` i może nadal zwracać stan zatrzymanego monitorowania.

``DiagnosticsModel`` zbiera powiadomienia źródeł i serwera przez cały czas
działania aplikacji. Zachowuje do 50 ostatnich wpisów, a ``LogSummaryView``
pokazuje do 10 od najnowszego. Copy Logs kopiuje lokalny raport uwzględniający także
stan źródeł i ścieżki. ``BridgePlaybackSnapshot`` publikuje wyłącznie pola kontraktu
sieciowego i pomija szczegóły odtwarzania nieaktywnego źródła.

## SRP i DIP w praktyce

SRP, *Single Responsibility Principle*, oznacza jedną spójną odpowiedzialność,
czyli jeden rodzaj przyczyny zmiany. Liczba metod nie jest jego miarą.
Delegat nie powinien zmieniać się jednocześnie wskutek zmiany JSON, wyglądu panelu
oraz sposobu zbierania logów. Te przyczyny zostały rozdzielone.

DIP, *Dependency Inversion Principle*, dotyczy kierunku zależności polityki i szczegółów.
Miejsce składania aplikacji musi znać konkretne klasy, żeby utworzyć działający graf.
Samo `BridgeHTTPServer(...)` w takim miejscu nie narusza DIP.
Serwer otrzymuje funkcję dostarczającą DTO, zamiast tworzyć i kontrolować `PlaybackMonitor`.
Monitoring nie zależy od serwera. Nie wprowadzamy protokołu wyłącznie po to, żeby
ukryć konstruktor jedynej implementacji.

## Źródła Apple

- [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
- [NSApplicationDelegateAdaptor](https://developer.apple.com/documentation/swiftui/nsapplicationdelegateadaptor)
- [OpenWindowAction](https://developer.apple.com/documentation/swiftui/openwindowaction)
