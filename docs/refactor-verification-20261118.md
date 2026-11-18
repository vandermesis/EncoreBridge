# Weryfikacja refaktoru — 18 listopada 2026

Zakres: cykl życia SwiftUI, panel z przyciskiem Opcje, granica monitorowanie/API,
agregacja diagnostyki i dokumentacja DocC. To nie jest raport zakończonego audytu
wszystkich usług aplikacji; dalsze części przeglądu opisuje katalog DocC.

## Wyniki

- Debug: kompilacja zakończona poprawnie, bez ostrzeżeń kompilatora.
- Testy: 49 testów zaliczonych, zero błędów i pominięć; uwzględniając przypadki
  parametryzowane raport urządzenia obejmuje 58 wykonań.
- Zestaw zawiera wszystkie testy jednostkowe oraz `testMonitoringControls`
  i `testOptionsMenuAndPanelLifecycle`. Opcjonalnego odtwarzania Music nie uruchamiano.
- UI: start/stop, kopiowanie logów, otwieranie okna logów oraz dwa cykle panelu
  i menu Opcje. Menu ma rzeczywisty, niepusty obszar pod paskiem menu; panel
  pozostaje dostępny, a okno logów nie otwiera się samo.
- Release i DocC: poprawna kompilacja, bez ostrzeżeń. DocC nie zgłasza błędnych linków.
- Podpis lokalny sprawdzony przez `codesign --verify --deep --strict`;
  zachowano uprawnienie Apple Events. `LSUIElement` ma wartość `true`.
- Zainstalowano `/Applications/EncoreBridge.app`. Poprzednia wersja jest w
  `/private/tmp/EncoreBridge-before-runtime-refactor-20261118.app`.
- Przy zamkniętym panelu działają `/health` (status `ok`) i `/v1/now-playing`
  (`monitoring: true`, schema 1, oba klucze źródeł).
- Porównanie z kopią sprzed refaktoru: pliki serwera, odpowiedzi HTTP i DTO
  przeniesiono bez zmiany treści. Katalog `m6` nie zmienił się.

Wynik testów lokalnych: `/private/tmp/EncoreBridge-refactor-final-tests-20261118.xcresult`.
Archiwum dokumentacji: `/private/tmp/EncoreBridge-refactor-20261118/Build/Products/Release/EncoreBridge.doccarchive`.
Pliki w `/private/tmp` mogą zostać usunięte przez system.

## Nierozwiązany komunikat runtime

Raport testów zawiera dwa ostrzeżenia runtime:
`This method should not be called on the main thread as it may lead to UI unresponsiveness.`
Nie są to ostrzeżenia kompilatora i nie zostały wyciszone.

Eksport archiwum logów i symbolikacja wykazały:
`Security.framework → __SecTrustEvaluateThreadRuntimeCheck_block_invoke_2`,
następnie ramki `libdispatch` i `libsystem_pthread`.
Stos nie zawiera ramki kodu aplikacji, która pozwalałaby wskazać konkretną poprawkę.
Zapisano diagnostykę w `/private/tmp/EncoreBridge-main-thread-warning-symbols.txt`.
Nie uznajemy tego za dowód, że wszystkie komunikaty runtime zostały naprawione.
Dalsza diagnoza powinna odtworzyć wywołanie inicjujące ocenę zaufania i sprawdzić,
czy zależy od uruchomienia przez debugger/toolchain.
