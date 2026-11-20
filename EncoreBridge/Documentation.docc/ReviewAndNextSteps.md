# Ocena architektury i dalsze kroki

Oddziel wykonany podział odpowiedzialności od tematów wymagających dalszej analizy.

## Overview

Dla obecnej wielkości aplikacji jeden moduł z katalogami funkcji i integracji jest
rozsądnym rozwiązaniem. Osobne pakiety i rozbudowana architektura warstwowa zwiększyłyby
koszt nawigacji bez potwierdzonej potrzeby. Katalog `Services` ma ograniczony sens
wewnątrz funkcji monitorowania; przy rozroście warto rozważyć podział według źródeł.

## Wykonany refaktor

- Systemowy panel SwiftUI i menu „Opcje” zastępują ręczne okna, menu i gesty delegata.
- Cykl życia usług jest oddzielony od czasu życia widoków.
- Neutralna migawka monitorowania oddziela funkcję od kontraktu M6.
- Diagnostyka i eksport logów mają własny model i katalog.
- Publiczny kontrakt HTTP i kod urządzenia M6 zachowują dotychczasowe działanie.

## SOLID jako kryterium oceny

| Zasada | Ocena bieżącego zakresu |
| --- | --- |
| SRP | Rozdzielono cykl życia, składanie zależności, prezentację, diagnostykę i mapowanie |
| OCP | Nowy odbiorca może mieć własny mapper bez zmiany monitorowania; nowy typ źródła nadal wymaga świadomej zmiany agregacji |
| LSP | Brak własnej hierarchii podtypów wymagającej przebudowy; nie tworzymy jej na potrzeby zasady |
| ISP | Krótki callback migawki i callback statusu nie wymuszają szerokiego interfejsu na odbiorcy |
| DIP | Serwer otrzymuje dostawcę danych; kompozycja zna konkretne implementacje; monitor nie zna HTTP |

Nie jest to deklaracja, że cały projekt jest „zgodny z SOLID”. Zasady służą
wskazywaniu konkretnych kosztów zmian, a nie nadawaniu certyfikatu architekturze.

## Udokumentowany zakres przeglądu

| Obszar | Dokumentacja |
| --- | --- |
| Cykl życia, sceny, panel i diagnostyka | <doc:Architecture> oraz komentarze do symboli |
| Agregacja, przekazanie migawki i granica kontraktu M6 | <doc:Architecture> oraz komentarze do symboli |
| Apple Events, lokalne pliki, format i panel jakości Music | <doc:AppleMusicMonitoring> oraz komentarze do symboli |
| Proces `log stream`, potoki i restart nasłuchu | <doc:MusicLogStreaming> oraz komentarze do symboli |

## Kolejne części wspólnego przeglądu

1. `RoonLogFileReader`, parser i stan. Prześledzić rotację, częściowe linie,
   świeżość i ponowne wejście po `await`. Wykorzystać dotychczasowy opis Roon
   w `docs/roon-log-monitoring.md`.
2. Widoki i modele wartości. Ocenić stabilność identyfikatorów, prezentację
   równoczesnych źródeł, dostępność i zachowanie przy niepełnych metadanych.
3. Szczegóły listenera HTTP. Przejrzeć limity żądań, timeout, anulowanie
   i odporność na restart usługi. Kontrakt odbiorcy opisuje `docs/network-api.md`.
4. Powiadomienia o odtwarzaniu w Muzyce. Sprawdzić zdarzenie
   `com.apple.Music.playerInfo` odbierane przez `DistributedNotificationCenter`
   podczas ręcznej i automatycznej zmiany utworu, pauzy, wznowienia oraz
   zamknięcia Muzyki. Porównać pola `userInfo` z wynikiem `currentPlayback()`
   dla streamingu, pobranego utworu i lokalnego pliku. Osobno sprawdzić start
   monitora, gdy utwór już gra.

   Jeśli test potwierdzi użyteczność zdarzeń, wyzwalać nimi odświeżanie
   i ograniczyć odpytywanie co 500 ms na podstawie pomiaru liczby zapytań
   i opóźnienia aktualizacji. Zachować odczyt przez AppleScript przy starcie,
   do uzupełniania brakujących pól i okresowej synchronizacji na wypadek
   pominiętego zdarzenia. Przed zmianą sprawdzić, czy monitor nadal poprawnie
   wiąże raporty o formacie z bieżącym utworem oraz odczytuje format z pliku,
   gdy Muzyka udostępnia jego ścieżkę.

Decyzje o ewentualnej zmianie automatycznego otwierania panelu jakości Music
oraz o przeniesieniu synchronicznych odczytów z głównego aktora są otwarte.
Obecne działanie tych ścieżek opisuje <doc:AppleMusicMonitoring>.

Te punkty są planem przeglądu, a nie zatwierdzonym z góry przepisaniem usług.
O kolejnych refaktorach powinny decydować odtworzone problemy i testy.

Przy zmianie zachowania aktualizujemy odpowiedni komentarz `///` i artykuł DocC
w tym samym PR. Komentarz opisuje kontrakt symbolu, a artykuł łączy go z resztą
aplikacji i wyjaśnia decyzje. Po przeglądzie obszaru dopisujemy go do tej mapy.
