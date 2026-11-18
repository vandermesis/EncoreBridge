# EncoreBridge → Musical Fidelity M6 Encore 225

## Adres na tym Macu

`http://TauCetiCenter.local:8765/v1/now-playing`

Serwer uruchamia się razem z EncoreBridge i działa wyłącznie na lokalnym łączu.
Udostępnia HTTP/1.0 i HTTP/1.1, metody GET i HEAD. Nie wymaga uwierzytelniania.
Zakończenie aplikacji zamyka serwer. Start/Stop Monitoring zmienia stan czytników;
po zatrzymaniu odczytu endpoint nadal odpowiada, ale nie udostępnia zapisanych
wcześniej metadanych jako aktualnego odtwarzania.

Endpointy:

- `GET /v1/now-playing` — oba źródła, niezależnie od siebie.
- `GET /health` — stan dostępności interfejsu HTTP.

Adres i błędy uruchomienia są również w Show Logs / Copy Logs. Nazwa hosta może
zmienić się wraz z nazwą Maca; port to 8765.

## Kontrakt JSON, wersja 1

Przykład:

```json
{
  "schema_version": 1,
  "generated_at": "2026-11-16T13:16:09Z",
  "monitoring": true,
  "ttl_ms": 3000,
  "sources": {
    "apple_music": {
      "name": "Mac",
      "application": "Apple Music",
      "playing": true,
      "observed_at": "2026-11-16T13:16:09Z",
      "artist": "Ella Fitzgerald & Louis Armstrong",
      "title": "They Can't Take That Away from Me",
      "codec": "ALAC",
      "bits": 24,
      "fs_hz": 96000
    },
    "roon": {
      "name": "Roon",
      "application": "Roon",
      "zone": "SHD ROON",
      "playing": true,
      "observed_at": "2026-11-16T13:16:07Z",
      "artist": "James Horner / Randy Kerber",
      "title": "A Beautiful Mind, film score: Teaching Mathematics Again",
      "codec": "MP3",
      "fs_hz": 44100
    }
  }
}
```

Wszystkie liczby opisujące rozdzielczość są liczbami JSON: `bits` w bitach,
`fs_hz` w hercach. To te same klucze, których używa formatter `_formatInfo`
w dotychczasowym module Now Playing M6. `name` zachowuje etykiety `Mac` i `Roon`,
a `application` podaje pełną nazwę aplikacji.

Oba klucze `sources` są obecne także wtedy, gdy gra tylko jedno źródło.
Źródło nieaktywne ma `playing: false`, bez pól artist/title/codec/bits/fs_hz.
Nieznane wartości również są pomijane; nie są zastępowane zerem, pustym tekstem
ani rozdzielczością wyjściowego PCM. Brak `bits` dla MP3/AAC jest prawidłowy.

`observed_at` to czas ostatniego odczytu danego źródła. Apple Music musi mieć
odczyt nie starszy niż 3 sekundy, a Roon świeży raport PLAYING z ostatnich 20 sekund
(podsumowania Roon zwykle przychodzą co około 5 sekund). Nie wybieramy źródła
według pierwszeństwa. Pauza lub zatrzymanie monitorowania unieważniają metadane.

Odpowiedź nie zawiera ścieżek plików, identyfikatorów biblioteki ani surowych logów.
Nagłówki zawierają `Cache-Control: no-store`, długość w bajtach UTF-8 i
`Connection: close`. HEAD zwraca te same nagłówki co GET, bez treści.

## Odczyt na M6

```sh
curl --max-time 2 -fsS http://TauCetiCenter.local:8765/v1/now-playing
```

Przykład Python 3, dostępny na sprawdzonym Encore:

```python
import json
import urllib.request

with urllib.request.urlopen(
        'http://TauCetiCenter.local:8765/v1/now-playing', timeout=2) as response:
    payload = json.loads(response.read(65536).decode('utf-8'))

if payload.get('schema_version') != 1:
    raise ValueError('Unsupported EncoreBridge schema')

sources = payload['sources']
mac_source = sources['apple_music']
roon_source = sources['roon']
```

Zalecane odpytywanie: co 1 sekundę, jedno żądanie w toku, limit czasu 2 sekundy.
Po błędzie lub po 3 sekundach bez nowej odpowiedzi odbiorca usuwa dane z pamięci
podręcznej. `monitoring: false` lub `playing: false` ukrywa odpowiednie metadane.

## Połączenie z wcześniejszym modułem ekranu

Dotychczasowy moduł M6 czyta lokalnie `http://127.0.0.1:6545/signal`, a dane
sprzętowe Encore pochodzą z portu 6543. Nowy endpoint Maca uzupełnia ten przepływ
o format źródła i artist/title. Nie jest zamiennikiem pomiaru `shd_out`.

Backend M6 odczytuje fizyczne wejście przez `getInputSources` / `pushInputSources`
Socket.IO (Engine.IO 3). Kompletna lista TOSLINK/SPDIF/AES-EBU/USB zawiera flagi
`active`. Gdy wszystkie są `false`, wybrane jest wewnętrzne LAN. Niekompletna lub
niejednoznaczna odpowiedź nie jest interpretowana jako LAN — etykieta zostaje
usunięta. Samo REST `getState` opisuje odtwarzacz i po przełączeniu USB → LAN może
nadal zwracać `service=inputs`, `title=USB`, `status=play`.

| Fizyczne wejście SHD | Odtwarzanie | Etykieta M6 | Dane |
| --- | --- | --- | --- |
| USB | Dowolny stan odtwarzacza SHD | Mac | EncoreBridge `sources.apple_music` |
| TOSLINK / OPTICAL | Dowolny stan odtwarzacza SHD | AppleTV | Bez metadanych z Maca |
| LAN | Brak / pauza / stop | LAN | Bez poprzednich metadanych |
| LAN | Aktywne Roon (`raat`, `roon`, `roonbridge`, `roonready`) | Roon | EncoreBridge `sources.roon` |
| LAN | Aktywna usługa Volumio (`mpd`, Qobuz, Tidal, Spotify itd.) | Volumio | `artist`, `title`, `codec`/`trackType`, `bitdepth`, `samplerate` z SHD |
| LAN | AirPlay w Volumio (`airplay_emulation`, `airplay`, `shairport`) | Airplay | Metadane z SHD; nie zgadujemy brakującego kodeka |

Na LAN stan musi mieć `status=play` i rozpoznaną usługę sieciową. Pozostałości
`service=inputs` nie uruchamiają wyświetlania Apple Music. Świeże EncoreBridge
`roon.playing=false` również przywraca etykietę LAN, nawet jeżeli stan SHD jeszcze
opisuje poprzedni utwór Roon. Aktywne Volumio pobiera metadane z SHD niezależnie
od stanu aplikacji na Macu.
Serwer zawsze udostępnia oba źródła. Głośność, synchronizacja, pomiar częstotliwości
wyjścia SHD i informacja o DSP nadal pochodzą z istniejącego modułu M6/SHD.

Wdrożony moduł [m6/telemetry.py](../m6/telemetry.py) odpytuje SHD i EncoreBridge
w niezależnych wątkach. Brak Maca nie opóźnia wykrywania wejścia SHD.
Przy błędzie odczytu wejścia ukrywa etykietę źródła; przy błędzie EncoreBridge
ukrywa jego metadane. Pauza/stop sieciowego odtwarzacza przywraca LAN.
Nie podmieniamy danych drugą aplikacją ani
parametrami dekodowanego strumienia SHD. Nieznana głębia bitowa jest pomijana.
`shd_out` nadal opisuje fizyczny sygnał wyjściowy SHD.

Lokalny endpoint M6 przekazuje także `artist` i `title` wybranego źródła.
Ekran Jive renderuje w wierszu źródła nazwę, kodek, bity i częstotliwość;
główny nagłówek pozostaje `miniDSP SHD`. Pod nim jest sama wartość głośności w dB
(38 px), następnie źródło i wiersz `Input` (po 31 px). `Input` jest nową etykietą
dotychczasowego wiersza `SHD Out`; wartości nadal opisują wejście M6 po DSP w SHD,
pochodzą z tego samego `shd_out` i nie są parametrami oryginalnego pliku.

Ostatnia instalacja 16 listopada zmieniła wyłącznie `/usr/encore/telemetry/telemetry.py`
i zrestartowała usługę `encoretelemetry`. Kopia przed poprawką rozpoznawania LAN:
`/usr/encore/telemetry/telemetry.py.backup-20261116T135949Z`.
Procesy Jive, LMS i audio oraz stan zasilania, wejście i głośność pozostały bez zmian.
Skrypt z kontrolą SHA256 i cofnięciem po błędzie:
[m6/install_telemetry.py](../m6/install_telemetry.py).

## Weryfikacja 16 listopada 2026

- Pełny zestaw: 54 testy zaliczone, 2 warunkowe testy odtwarzania pominięte
  (odtwarzanie Apple Music nie było przełączane przez test, a bieżące źródło Roon
  nie spełniało warunku lokalnego pliku ALAC dla porównania AVFoundation).
  Wynik: `/var/folders/k_/8qr7jhp17h5frjkbd3fvpxx40000gn/T/ActionArtifacts/default/RunAllTests/Test-EncoreBridge-2026.11.16_14-19-35-+0100.xcresult`.
- M6 (`m6encore-00024a`) wykonał rzeczywisty odczyt HTTP 200 z Maca, gdy oba źródła
  odtwarzały. Zapis: [oba źródła](evidence/m6-simultaneous-sources-20261116.json).
- Końcowy test wykonany w Pythonie na M6 potwierdził schemat i TTL, HEAD,
  HTTP/1.0, odmowę POST i odczytu logów, klientów równoległych, limit nagłówków
  8 KiB oraz zamykanie niepełnego żądania po 3 sekundach bez zatrzymywania serwera.
  Zapis: [test protokołu z M6](evidence/m6-network-api-20261116.json).
- Reprodukcja testu: `python3 script/verify_network_api.py http://TauCetiCenter.local:8765`.
  Ten sam skrypt może być wykonany na M6 przez Python 3; nie instaluje nic na urządzeniu.
- Testy backendu M6: 29 zaliczonych (`python3 -m unittest discover -s m6/tests -v`).
  Obejmują równoczesne odtwarzanie, zmianę wejścia, pauzę, brak bitów,
  awarię Maca, TTL i zachowanie parametrów fizycznego wyjścia SHD.
  Regresje obejmują również LAN przy starym `title=USB`, pauzę/stop Roon i Volumio,
  niezależne dane Volumio oraz walidację i ponowne używanie sesji Socket.IO.
  Przed instalacją nowy czytnik na M6 poprawnie odczytywał LAN przez ponad 20 sekund,
  także po wysłaniu kolejnego heartbeat w tej samej sesji.
- Po ostatnim wdrożeniu przez ponad 30 sekund potwierdzono zgodność fizycznego
  LAN z odtwarzaniem Roon i danymi M6, przy równoczesnym Apple Music.
  [Odczyty wejścia i odtwarzacza](evidence/m6-input-selection-live-20261116.json).
  Podczas tej obserwacji Roon pozostawał aktywny; idle LAN i Volumio sprawdzono
  testami regresji, bez zmiany odtwarzania przez kod aktualizacji.
  [Wynik instalacji](evidence/m6-idle-lan-deployment-20261116.json) zawiera SHA256,
  ścieżkę kopii zapasowej i niezmieniony stan sprzętowy oraz procesy Jive/LMS/audio.
- Poprawka AirPlay Volumio: rzeczywisty SHD zgłasza `service=airplay_emulation`.
  Po dodaniu tej nazwy lokalny endpoint M6 zwrócił `Volumio`, John Beltran —
  `Austin`, 16 bit / 44100 Hz. Pustego kodeka ani `trackType=airplay` nie
  zastąpiono domyślnym kodekiem. Test obejmuje również pauzę/stop → LAN.
  [Wynik wdrożenia AirPlay](evidence/m6-volumio-airplay-20261116.json).
  Kopia przed tą poprawką: `/usr/encore/telemetry/telemetry.py.backup-20261116T164339Z`.
- Po wdrożeniu Toslink zwrócił wyłącznie `AppleTV`, mimo aktywnego Apple Music.
- LAN potwierdzono na żywo przy równoczesnym Apple Music i Roon: backend wybrał
  Kate Bush z Roon oraz zaktualizował `Snowflake` na `Lake Tahoe`.
  [Zrzut ekranu Roon](evidence/m6-roon-routing-20261116.png) potwierdza
  `Roon: ALAC · 24 bit · 96 kHz`.
- USB sprawdzono na M6 przez funkcję mapującą z rzeczywistą odpowiedzią EncoreBridge:
  wybrano Elvis Presley z Apple Music, podczas gdy Roon przekazywał Kate Bush.
  W tym końcowym odczycie fizycznie wybrany był LAN; USB nie potwierdzono jeszcze
  zrzutem ekranu. [Zapis odczytu i mapowania](evidence/m6-source-routing-20261116.json).

Odczyt pól stanu odtwarzacza opiera się na [dokumentacji API Volumio](https://github.com/volumio/Volumio2/wiki/WebSockets-API-Reference).
Listę wejść i flagi aktywności sprawdzono na rzeczywistym SHD 3.912, a nie tylko
na podstawie opisu API.
