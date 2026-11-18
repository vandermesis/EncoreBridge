# Aktor, zadanie, wątek i domknięcie

Poznaj mechanizmy współbieżności na przykładach z EncoreBridge.

## Overview

Te pojęcia odpowiadają na różne pytania:

| Pojęcie | Pytanie | Przykład w aplikacji |
| --- | --- | --- |
| Wątek | Gdzie procesor wykonuje instrukcje? | Główny wątek obsługuje UI AppKit |
| Aktor | Kto chroni dostęp do zmiennego stanu? | `RoonLogFileReader` chroni czytnik i parser |
| `MainActor` | Czy stan należy do wspólnej izolacji UI? | `PlaybackMonitor` i modele obserwowane przez widoki |
| `Task` | Jaka operacja może czekać, kontynuować i zostać anulowana? | Pętla okresowego odczytu Roon |
| Domknięcie | Jaką funkcję przekazuję innemu obiektowi? | Dostawca migawki w serwerze HTTP |

## Jeden odczyt Roon, krok po kroku

1. `RoonLogMonitor.start()` tworzy zadanie z pętlą odczytu.
2. Zadanie dziedziczy izolację głównego aktora. Samo `Task { }` nie oznacza „w tle”.
3. `await reader.read(...)` przekazuje wykonanie do izolacji aktora czytnika.
4. Monitor może się zawiesić na `await`, oddając możliwość wykonania innym zadaniom.
5. Po powrocie monitor aktualizuje stan w izolacji `MainActor`; SwiftUI obserwuje te zmiany.
6. `Task.sleep` zawiesza zadanie; nie blokuje wątku jak `Thread.sleep`.
7. `stop()` anuluje zadanie. Anulowanie jest kooperacyjne: kod musi je sprawdzić
   albo użyć operacji, która reaguje na anulowanie.

Aktor nie jest osobnym wątkiem. Zadanie może w trakcie życia wykonywać się na różnych
wątkach, z zachowaniem wymaganej izolacji. Aktor umożliwia inne wejścia podczas `await`,
więc po wznowieniu nie należy zakładać, że jego stan pozostał bez zmian.

## Migawki i Sendable

``PlaybackMonitoringSnapshot`` jest strukturą z wartościami `Sendable`.
Można ją bezpiecznie przekazać pomiędzy domenami izolacji. To nie jest blokada ani
polecenie kopiowania na inny wątek. Odczyt stanu monitora nadal wymaga `MainActor`.

Typy wartości jawnie oznaczone `nonisolated` nie dziedziczą domyślnej izolacji modułu.
Nie oznacza to, że dowolna współdzielona klasa staje się bezpieczna dla wielu zadań.
``EncoreSnapshotMapper`` wykonuje krótkie, synchroniczne obliczenie na wartościach;
nie potrzebuje własnego aktora ani zadania.

Projekt korzysta z domyślnej izolacji głównego aktora. To ustawienie toolchaina,
które trzeba uwzględnić przy analizie współczesnych diagnostyk Swift Concurrency,
a nie zakładać zachowania wszystkich typów na podstawie kodu z 2023 roku.

## Kiedy closures, async/await, AsyncSequence i Combine?

Domknięcia są nadal standardowym narzędziem Swift i występują także w API SwiftUI.
W `ApplicationRuntime` domknięcie dostarczające migawkę jest krótką operacją
synchroniczną. Callback statusu informuje jednego odbiorcę o zdarzeniu. `weak`
w callbackach diagnostyki zapobiega cyklowi silnych referencji do ich właściciela.

`async/await` służy operacjom, które mogą wymagać oczekiwania. `AsyncSequence`
pasuje do sekwencji zdarzeń odbieranych asynchronicznie. Combine jest przydatne,
gdy potrzebna jest kompozycja strumieni, operatorów i subskrybentów.
Żaden z tych mechanizmów nie jest uniwersalnym zamiennikiem domknięć.

## Ograniczenia obecnego rozwiązania

Dostawca migawki HTTP pozostaje na `MainActor`, więc przeciążenie głównego aktora
może opóźnić odpowiedź. Praca synchroniczna AppleScript i analiza lokalnych plików
wymagają osobnego pomiaru przed ewentualnym przeniesieniem z izolacji UI.
Nie należy dodawać `Task.detached` w ciemno: wymaga ono świadomego ustalenia
własności stanu, `Sendable` i anulowania.
