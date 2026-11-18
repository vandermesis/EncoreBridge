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

## Kolejne części wspólnego przeglądu

1. `MusicLogMonitor` i `LocalMusicTrackService`: przejść po zależnościach AppleScript,
   AVFoundation i plików. Zmierzyć blokowanie UI, zanim wydzielimy asynchroniczny odczyt.
2. `MusicQualityService` i `AppleMusicLogService`: omówić dostępność, proces `log stream`,
   fragmenty danych i kończenie pracy. Oddzielić obserwację od ewentualnych skutków w UI Music.
3. `RoonLogFileReader`, parser i stan: prześledzić rotację, częściowe linie,
   świeżość i ponowne wejście po `await`; rozszerzać testy tylko dla wykrytych ryzyk.
4. Widoki i modele wartości: ocenić stabilność identyfikatorów, prezentację wielu źródeł,
   dostępność i zachowanie przy niepełnych metadanych.
5. HTTP: przejrzeć limit żądań, timeout, anulowanie i odporność na restart usługi.

Te punkty są planem przeglądu, a nie zatwierdzonym z góry przepisaniem usług.
O kolejnych refaktorach powinny decydować odtworzone problemy i testy.
