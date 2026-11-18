#!/usr/bin/env python3
"""Read-only SHD metadata bridge; no audio/control commands or direct I2C access."""
import json
import calendar
import re
import threading
import time
import urllib.request
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

SHD_URL = 'http://minidsp-shd.local/api/v1/getState'
ENCORE_URL = 'http://127.0.0.1:6543/signal'
BRIDGE_URL = 'http://TauCetiCenter.local:8765/v1/now-playing'
_lock = threading.Lock()
_state = None
_received = 0
_bridge = None
_bridge_received = 0
NETWORK_SERVICES = ('mpd', 'qobuz', 'tidal', 'tidalconnect', 'spop',
                    'spotify', 'volspotconnect2', 'webradio', 'airplay',
                    'airplay_emulation', 'shairport')
CODECS = dict((x.lower(), x) for x in ('FLAC', 'ALAC', 'WAV', 'AIFF', 'MP3',
                                     'AAC', 'OGG', 'OPUS', 'DSD', 'PCM'))
CODECS.update({'audio/flac': 'FLAC', 'audio/x-flac': 'FLAC', 'wave': 'WAV'})
ROON_SERVICES = ('roon', 'roonbridge', 'raat', 'roonready')


def selected_input(payload):
    """Input flags remain accurate when getState still describes the old player."""
    try:
        lists = payload['navigation']['lists']
        items = [item for group in lists for item in group['items']
                 if item.get('service') == 'inputs']
        names = [item['title'].strip().upper() for item in items]
        if not {'TOSLINK', 'SPDIF', 'AES-EBU', 'USB'}.issubset(set(names)):
            raise ValueError('Incomplete input list')
        if any(type(item.get('active')) is not bool for item in items):
            raise ValueError('Missing input selection flags')
        active = [name for name, item in zip(names, items) if item['active']]
        if len(active) > 1:
            raise ValueError('Ambiguous input selection')
        # SHD lists its external inputs only. All inactive means internal LAN.
        return active[0] if active else 'LAN'
    except (KeyError, TypeError, AttributeError):
        raise ValueError('Invalid input list')


class InputReader:
    """Read-only Socket.IO/Engine.IO v3 polling, using the SHD's shipped API."""
    def __init__(self):
        self.url = None
        self.ping_at = 0

    def request(self, url, packet=None):
        data = None if packet is None else (str(len(packet)) + ':' + packet).encode('utf-8')
        request = urllib.request.Request(url, data=data,
            headers={'Content-Type': 'text/plain; charset=UTF-8'})
        with urllib.request.urlopen(request, timeout=1.2) as response:
            return response.read(131072).decode('utf-8')

    def read(self):
        if self.url is None:
            base = SHD_URL.split('/api/', 1)[0] + '/socket.io/?EIO=3&transport=polling'
            opened = self.request(base)
            match = re.search(r'0(\{"sid".*?\})', opened)
            if not match:
                raise ValueError('Missing Engine.IO handshake')
            sid = json.loads(match.group(1))['sid']
            self.url = base + '&sid=' + urllib.parse.quote(sid, safe='')
            self.ping_at = time.monotonic()
        if time.monotonic() >= self.ping_at:
            self.request(self.url, '2')
            self.ping_at = time.monotonic() + 20
        self.request(self.url, '42["getInputSources"]')
        # Ignore unrelated pushState/volume events on this private connection.
        for _ in range(4):
            body = self.request(self.url)
            marker = '42["pushInputSources",'
            index = body.find(marker)
            if index >= 0:
                event, _ = json.JSONDecoder().raw_decode(body[index + 2:])
                return selected_input(event[1])
        raise ValueError('Missing pushInputSources response')

    def close(self):
        if self.url is not None:
            try:
                self.request(self.url, '1')
            except Exception:
                pass
        self.url = None


def read_json(url, timeout):
    response = urllib.request.urlopen(url, timeout=timeout)
    try:
        data = json.loads(response.read(131072).decode('utf-8'))
    finally:
        response.close()
    if not isinstance(data, dict):
        raise ValueError('Expected object')
    return data


def number(value):
    if isinstance(value, bool):
        return None
    match = re.match(r'^\s*(\d+(?:[.,]\d+)?)\s*(kHz|Hz|bit|bits)?\s*$', str(value), re.I)
    if not match:
        return None
    return float(match.group(1).replace(',', '.')), (match.group(2) or '').lower()


def bridge_lifetime(payload, now=None):
    """Accept only a fresh snapshot of the supported API; never cache past TTL."""
    if not isinstance(payload, dict) or type(payload.get('schema_version')) is not int:
        return 0
    if payload['schema_version'] != 1 or payload.get('monitoring') is not True:
        return 0
    ttl = payload.get('ttl_ms')
    if type(ttl) not in (int, float) or not 0 < ttl <= 3000:
        return 0
    if not isinstance(payload.get('sources'), dict):
        return 0
    try:
        generated = calendar.timegm(time.strptime(payload['generated_at'], '%Y-%m-%dT%H:%M:%SZ'))
    except (KeyError, TypeError, ValueError, OverflowError):
        return 0
    age = (time.time() if now is None else now) - generated
    # ISO8601 timestamps have whole seconds; tolerate subsecond rounding and
    # small clock skew, but do not revive a previously generated snapshot.
    if age < -5 or age >= ttl / 1000.0:
        return 0
    return min(ttl / 1000.0, ttl / 1000.0 - max(age, 0))


def bridge_metadata(payload, key, name):
    result = dict(name=name)
    if not bridge_lifetime(payload):
        return result
    source = payload['sources'].get(key)
    if not isinstance(source, dict) or source.get('playing') is not True:
        return result
    for field in ('artist', 'title'):
        value = source.get(field)
        if isinstance(value, str) and value.strip():
            result[field] = value.strip()
    codec = source.get('codec')
    if isinstance(codec, str) and codec.strip().lower() in CODECS:
        result['codec'] = CODECS[codec.strip().lower()]
    bits = source.get('bits')
    if type(bits) is int and bits in (8, 16, 20, 24, 32, 64):
        result['bits'] = bits
    rate = source.get('fs_hz')
    if type(rate) is int and 8000 <= rate <= 1536000:
        result['fs_hz'] = rate
    return result


def source_metadata(state, bridge=None):
    if not isinstance(state, dict):
        return None
    service = str(state.get('service') or '').lower()
    selected = state.get('selected_input')
    if selected == 'USB':
        return bridge_metadata(bridge, 'apple_music', 'Mac')
    if selected in ('TOSLINK', 'OPTICAL'):
        return dict(name='AppleTV')
    if selected != 'LAN':
        return None
    if state.get('status') != 'play':
        return dict(name='LAN')
    if service in ROON_SERVICES:
        if bridge_lifetime(bridge):
            roon = bridge['sources'].get('roon')
            if isinstance(roon, dict) and roon.get('playing') is False:
                return dict(name='LAN')
        return bridge_metadata(bridge, 'roon', 'Roon')
    elif service in NETWORK_SERVICES:
        name = 'Airplay' if service in ('airplay', 'airplay_emulation', 'shairport') else 'Volumio'
    else:
        return dict(name='LAN')
    result = dict(name=name)
    for field in ('artist', 'title'):
        value = state.get(field)
        if isinstance(value, str) and value.strip():
            result[field] = value.strip()
    codec = CODECS.get(str(state.get('codec') or '').strip().lower())
    if not codec:
        codec = CODECS.get(str(state.get('trackType') or '').strip().lower())
    if codec:
        result['codec'] = codec
    bits = number(state.get('bitdepth'))
    if bits and bits[0] in (8, 16, 20, 24, 32, 64):
        result['bits'] = int(bits[0])
    rate = number(state.get('samplerate'))
    if rate:
        value, unit = rate
        if unit == 'khz' or (not unit and value < 1000):
            value *= 1000
        if unit in ('', 'hz', 'khz') and 8000 <= value <= 1536000:
            result['fs_hz'] = int(round(value))
    return result


def enrich(signal, state, bridge=None):
    result = dict(signal)
    result.pop('shd_source', None)
    result.pop('shd_out', None)
    if signal.get('input') != 'COAX1' or not signal.get('power'):
        return result
    source = source_metadata(state, bridge)
    if source:
        result['shd_source'] = source
    if signal.get('locked') is True and signal.get('pcm') is True:
        output = dict(codec='PCM')
        rate = signal.get('fs_hz')
        if isinstance(rate, (int, float)) and rate > 0:
            output['fs_hz'] = rate
        if rate == 96000:
            # Fixed SHD Studio output format, per miniDSP; not inferred word length.
            output['bits'] = 24
            output['bits_source'] = 'shd_studio_output_specification'
        result['shd_out'] = output
    return result


def poll():
    global _state, _received
    reader = InputReader()
    while True:
        try:
            selected = reader.read()
            state = read_json(SHD_URL, 1.2)
            state['selected_input'] = selected
        except Exception:
            state = None
            reader.close()
        with _lock:
            _state, _received = state, time.monotonic()
        time.sleep(1)


def poll_bridge():
    global _bridge, _bridge_received
    while True:
        try:
            payload = read_json(BRIDGE_URL, 1.2)
            if not bridge_lifetime(payload):
                payload = None
        except Exception:
            payload = None
        with _lock:
            _bridge, _bridge_received = payload, time.monotonic()
        time.sleep(1)


def cached_bridge(payload, received, now=None):
    age = (time.monotonic() if now is None else now) - received
    if not bridge_lifetime(payload):
        return None
    return payload if 0 <= age < payload['ttl_ms'] / 1000.0 else None


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != '/signal':
            self.send_error(404)
            return
        try:
            signal = read_json(ENCORE_URL, 2)
        except Exception:
            signal = {}
        with _lock:
            state = _state if time.monotonic() - _received < 3 else None
            bridge = cached_bridge(_bridge, _bridge_received)
        data = json.dumps(enrich(signal, state, bridge)).encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class Server(ThreadingMixIn, HTTPServer):
    daemon_threads = True


if __name__ == '__main__':
    for target in (poll, poll_bridge):
        worker = threading.Thread(target=target)
        worker.daemon = True
        worker.start()
    Server(('127.0.0.1', 6545), Handler).serve_forever()
