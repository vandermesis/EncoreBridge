# ``EncoreBridge``

Odczyt informacji o odtwarzaniu Apple Music i Roon oraz udostępnianie ich aplikacji paska menu i odbiorcy M6.

## Overview

EncoreBridge rozdziela monitorowanie źródeł, prezentację, diagnostykę i kontrakt HTTP.
M6 pobiera dane przez HTTP. Aplikacja nie wysyła ich samoczynnie do wzmacniacza.
Zamknięcie panelu nie zatrzymuje monitorowania ani serwera.

## Topics

### Poznawanie projektu

- <doc:Architecture>
- <doc:Concurrency>
- <doc:ReviewAndNextSteps>

### Cykl życia i składanie zależności

- ``ApplicationRuntime``
- ``EncoreBridgeAppDelegate``

### Stan i integracja

- ``PlaybackMonitor``
- ``PlaybackMonitoringSnapshot``
- ``EncoreSnapshotMapper``
- ``BridgePlaybackSnapshot``
- ``DiagnosticsModel``
