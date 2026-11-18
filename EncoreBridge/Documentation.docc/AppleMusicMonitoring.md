# Jak EncoreBridge monitoruje Music

Prześledź odczyt bieżącego utworu, wybór źródła informacji o formacie i odrzucanie starych danych.

## Overview

EncoreBridge monitoruje odtwarzanie w osobnej aplikacji Music. ``MusicLogMonitor``
zestawia trzy rodzaje danych: bieżący stan odtwarzacza, format lokalnego pliku lub
raport z logu oraz jakość pokazaną w interfejsie Music.

| Źródło | Co dostarcza | Od czego zależy |
| --- | --- | --- |
| Apple Events | ID utworu, tytuł, wykonawcę, album, stan odtwarzania, zgłaszaną częstotliwość i opcjonalną ścieżkę pliku | Działająca aplikacja Music i zgoda na jej automatyzację |
| AVFoundation lub manifest `.movpkg` | Parametry lokalnego pliku lub zapisanego wariantu | Ścieżka zwrócona przez Music i dostęp do pliku |
| `log stream` | Częściowe raporty o formacie źródłowym | Dostępność i format diagnostycznych wpisów Music |
| Accessibility | Jakość opisaną w dymku Music | Osobna zgoda Accessibility i zgodna struktura interfejsu Music |

## Tożsamość utworu i AppleScript

``LocalMusicTrackService/currentPlayback()`` sprawdza obecność procesu
`com.apple.Music` przed utworzeniem skryptu. Właściwość `lazy` przechowuje
`NSAppleScript`, a pierwsze wykonanie kompiluje skrypt. Kolejne wywołania odczytują
bieżący stan Music, używając tego samego skompilowanego zapytania. Warunek
`if not running` w skrypcie pozostaje drugim sprawdzeniem na wypadek zamknięcia
Music między sprawdzeniem procesu a wykonaniem zapytania.

Skrypt zapamiętuje `persistent ID` wybranego utworu i sprawdza je ponownie przed
zwróceniem wyniku. Odczyt zostaje odrzucony, jeśli ID na końcu jest inne. To chroni
przed typowym przypadkiem zmiany utworu w trakcie zapytania. Utwór może pozostać
wybrany po pauzie, więc Music zwraca stan `isPlaying` niezależnie od jego tożsamości.

AppleScript formułuje zapytanie do słownika Music. Scripting Bridge lub bezpośrednie
Apple Events mogłyby wysłać podobne zapytania z kodu Swift i wymagałyby tej samej
zgody na automatyzację. `ApplicationMusicPlayer` z MusicKit dotyczy własnego
odtwarzacza aplikacji. `SystemMusicPlayer` jest niedostępny na natywnym macOS
w SDK projektu. Dostępne w katalogu warianty jakości nie wskazują, który wariant
wybrał odtwarzacz. Now Playing w macOS 27 służy do publikowania własnej sesji
odtwarzania. [NSAppleScript](https://developer.apple.com/documentation/foundation/nsapplescript)
· [Scripting Bridge](https://developer.apple.com/documentation/scriptingbridge/sbapplication)
· [ApplicationMusicPlayer](https://developer.apple.com/documentation/musickit/applicationmusicplayer)
· [SystemMusicPlayer](https://developer.apple.com/documentation/musickit/systemmusicplayer)
· [MediaSession](https://developer.apple.com/documentation/nowplaying/mediasession)

## Składanie formatu

1. Monitor wykonuje pierwszy odczyt przy uruchomieniu, potem odpytuje Music
   z przerwami 500 ms i odświeża stan po istotnych wpisach w logu.
2. Nowe ID usuwa raporty starego utworu. Zmiana ID lub częstotliwości unieważnia
   też wynik sprawdzania panelu jakości i anuluje jego bieżące zadanie.
3. Jeśli Music podało ścieżkę, ``LocalMusicTrackService`` sprawdza lokalny plik
   przez `AVAudioFile`. Dla `.movpkg` wybiera wariant oznaczony jako pobrany
   w `boot.xml` i szuka jego wpisu w playlistach pakietu. Format ostatniego
   poprawnie rozpoznanego pliku jest ponownie używany przy tym samym URL.
4. Format lokalnego pliku ma pierwszeństwo, a kolejnym wyborem jest potwierdzony
   format z panelu Music. Sama częstotliwość zgłoszona przez Music pozwala znaleźć
   zgodne raporty z logów. Jeśli brak dokładniejszej podstawy, monitor wybiera
   najnowszy z tych raportów.
5. ``AudioFormatSnapshot/fillingMissingValues(from:)`` uzupełnia tylko brakujące
   pola zgodnymi raportami. Gdy oba raporty zawierają różne kodeki lub różne
   częstotliwości, wynik zachowuje dane z podstawowego źródła.

``AudioFormatParser`` rozpoznaje określone diagnostyczne raporty o aktywnym
formacie i etykiety jakości. Źródłowy kodek i głębia mają inne znaczenie niż
format dekodera i parametry wyjścia audio. Pola, których monitor nie potrafi
ustalić, pozostają opcjonalne.

## Odczyt panelu jakości

Dla aktywnego utworu bez ścieżki pliku monitor może zaplanować maksymalnie trzy
próby z odstępem ponad trzech sekund. Warunek sprawdza brak potwierdzonego wyniku
z panelu, dlatego próba może zostać zaplanowana także wtedy, gdy log dał już format.

``MusicQualityService/audioFormat(for:)`` sprawdza, czy drzewo Accessibility
zawiera metadane z tytułem utworu i przycisk jakości. Gdy brakuje otwartego dymka,
usługa wysyła `AXPress`, okresowo szuka etykiety i próbuje zamknąć zaobserwowany
dymek po odczycie. Wywołania Accessibility zachodzą na głównym aktorze, a przerwy
`Task.sleep` oddają mu możliwość obsługi innych zadań. Następnie monitor sprawdza
anulowanie, aktualne ID i częstotliwość przed zatwierdzeniem wyniku.

Brak zgody Accessibility wyłącza ten tor odczytu. Przy zmianie Music zachowanie
może się zmienić wraz z identyfikatorami elementów UI lub układem dymka.
Naciśnięcie przycisku jest obserwowalnym skutkiem działania usługi dla użytkownika.
[AXUIElementPerformAction](https://developer.apple.com/documentation/applicationservices/1462091-axuielementperformaction)

## Co sprawdzono

W teście na Macu ta sama instancja EncoreBridge przeszła dwa cykle uruchomienia
Music, odtwarzania i zamknięcia Music. Endpoint HTTP pokazał bieżący tytuł i usunął
go po każdym zamknięciu. Drugi cykl sprawdził ponowne użycie skryptu po restarcie
Music.

W osobnym pomiarze przy zamkniętym Music mediana starego odczytu wyniosła 1,42 ms,
a mediana sprawdzenia procesu 0,005 ms. Wyniki dotyczą pojedynczych operacji
w kontrolowanym pomiarze i uzasadniają pominięcie cyklicznej kompilacji skryptu
przy zamkniętym Music.

Zobacz <doc:MusicLogStreaming> po szczegóły odczytu logów i <doc:Concurrency> po
wyjaśnienie izolacji stanu między wywołaniami.
