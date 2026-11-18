# Nasłuch logów Music i cykl życia procesu

Prześledź odczytywanie dwóch potoków, dostarczenie ostatniego wpisu i szybki restart nasłuchu.

## Overview

``AppleMusicLogService`` uruchamia proces `/usr/bin/log stream` z predykatem
`process == "Music"` i wyjściem NDJSON. Analizę znaczenia raportów wykonują
``AudioFormatParser`` i ``MusicLogMonitor``. Serwis dostarcza im tekst na
`MainActor`, gdzie monitor aktualizuje stan widoczny w UI.

## Odczyt dwóch potoków

| Kanał | Rola | Co zachowuje aplikacja |
| --- | --- | --- |
| `stdout` | Wpisy logu, zwykle jedna wartość JSON na linię | `eventMessage`, zapasowe `message` lub oryginalna linia przy braku rozpoznanej treści |
| `stderr` | Komunikaty diagnostyczne subprocessu | Pierwsze 8 KiB i oznaczenie skrócenia. Reszta jest odczytywana, żeby zwolnić miejsce w potoku |

Rozmiar potoku jest ograniczony. Gdy potok się zapełni, zapis czeka na odczyt.
Gdyby serwis czekał najpierw na `stdout`, a proces próbował zapisać dużo do
`stderr`, obie strony mogłyby czekać na siebie.

Każdy `LogPipe` ma osobną kolejkę Dispatch. Pojedynczy systemowy `read` odczytuje
do 8 KiB i pozwala dostarczyć krótkie wpisy, gdy potok jest nadal otwarty.
Blokujące oczekiwanie odbywa się na kolejce I/O. `withCheckedThrowingContinuation`
zawiesza zadanie Swift i wznawia je po odebraniu danych lub błędu.
Czytnik pobiera kolejną porcję na żądanie, więc pomiędzy blokami odczytu nie narasta
kolejka buforów. Dekoder `AsyncSequence.lines` składa linię z kolejnych porcji bajtów.

## Zakończenie nasłuchu

``AppleMusicLogService/start(onMessage:onFailure:)`` rejestruje `terminationHandler`
przed uruchomieniem procesu. Handler przekazuje kod wyjścia przez `AsyncStream`
z buforem na jedną wartość. Dzięki temu kod wyjścia może poczekać, aż czytnik
zacznie na niego czekać, nawet jeśli proces zakończy się bardzo szybko.

Grupa zadań `TaskGroup` obsługuje trzy zdarzenia: koniec `stdout`, koniec
`stderr` i wyjście procesu. Zamknięcie potoku stwierdzamy po zwróceniu zera bajtów
(EOF). Proces może sam wcześniej zamknąć oba potoki i nadal działać. Serwis
podaje kod wyjścia i zebraną diagnostykę po zakończeniu procesu i odczycie
ostatnich wpisów. Gdy odczyt się nie powiedzie, serwis sygnalizuje procesowi
zakończenie pracy przed wyjściem z grupy zadań.
[Process.terminationHandler](https://developer.apple.com/documentation/foundation/process/terminationhandler)
· [AsyncStream.makeStream](https://developer.apple.com/documentation/swift/asyncstream/makestream%28of%3Abufferingpolicy%3A%29)

``AppleMusicLogService/stop()`` najpierw unieważnia aktywny proces w stanie usługi,
potem anuluje zadania i wysyła sygnał zakończenia. Anulowanie zadania Swift jest
kooperacyjne. Trwający systemowy odczyt może czekać do czasu otrzymania danych
lub zamknięcia potoku. Po wznowieniu usługa sprawdza tożsamość instancji `Process`
przed przekazaniem wpisów lub zakończenia. Opóźniony callback starego procesu
nie zmienia nowego nasłuchu.

## Co sprawdzają testy

`AppleMusicLogServiceTests` korzystają z fabryki procesu w usłudze. Uruchamiają
krótkie procesy testowe, które pozwalają kontrolować kolejność zapisu i zamknięcia
potoków. Testy sprawdzają:

- złożenie JSON zapisanego w dwóch częściach i dostarczenie go po zapisie 1 MiB
  do `stderr`, wraz z ograniczoną diagnostyką i rzeczywistym kodem wyjścia,
- dalsze działanie `MainActor` po zamknięciu `stdout`, także wtedy, gdy
  `stderr` się zamknął, a proces jeszcze czeka na sygnał z testu,
- szybkie Stop → Start, gdy stary proces nadal może zgłosić opóźniony wpis
  albo zakończenie. Nowy proces powinien w tym czasie dostarczyć własne dane.

W próbie diagnostycznej z opóźnionym zamknięciem `stderr` najdłuższy odstęp
między zadaniami na głównym aktorze wyniósł około 610 ms przed poprawką
i 14 ms po niej. To pomiar dla kontrolowanego procesu testowego na jednym Macu.
