import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import time

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('telemetry', ROOT / 'telemetry.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def shd_state(**fields):
    selected = fields.get('title', 'LAN') if fields.get('service') == 'inputs' else 'LAN'
    result = dict(status='play', selected_input=selected)
    result.update(fields)
    return result


def input_list(active=None):
    return dict(navigation=dict(lists=[dict(items=[dict(service='inputs',
        title=name, active=name == active) for name in ('TOSLINK', 'SPDIF', 'AES-EBU', 'USB')])]))


class InputTests(unittest.TestCase):
    def test_external_selection_and_all_inactive_lan(self):
        for name in ('TOSLINK', 'USB', 'SPDIF', 'AES-EBU'):
            self.assertEqual(module.selected_input(input_list(name)), name)
        self.assertEqual(module.selected_input(input_list()), 'LAN')

    def test_incomplete_or_ambiguous_list_is_not_treated_as_lan(self):
        incomplete = input_list()
        incomplete['navigation']['lists'][0]['items'].pop()
        ambiguous = input_list('USB')
        ambiguous['navigation']['lists'][0]['items'][0]['active'] = True
        missing_flag = input_list()
        del missing_flag['navigation']['lists'][0]['items'][0]['active']
        for payload in (None, {}, dict(navigation=dict(lists=[])), incomplete, ambiguous, missing_flag):
            with self.subTest(payload=payload):
                with self.assertRaises(ValueError):
                    module.selected_input(payload)

    def test_socket_session_reuses_connection_and_ignores_unrelated_events(self):
        import json
        reader = module.InputReader()
        event = '42' + json.dumps(['pushInputSources', input_list()], separators=(',', ':'))
        with patch.object(reader, 'request', side_effect=[
                '0{"sid":"test","pingInterval":25000}', 'ok', 'ok',
                '3:3', event, 'ok', event, 'ok']) as request:
            self.assertEqual(reader.read(), 'LAN')
            self.assertEqual(reader.read(), 'LAN')
            reader.close()
        calls = request.call_args_list
        self.assertEqual(sum('sid=' not in call.args[0] for call in calls), 1)
        self.assertEqual([call.args[1] for call in calls if len(call.args) > 1],
                         ['2', '42["getInputSources"]', '42["getInputSources"]', '1'])
        self.assertIsNone(reader.url)

    def test_failed_input_read_clears_old_usb_cache(self):
        original = module._state, module._received
        try:
            module._state = shd_state(service='inputs', title='USB')
            with patch.object(module, 'InputReader') as factory:
                factory.return_value.read.side_effect = IOError('SHD offline')
                with patch.object(module.time, 'sleep', side_effect=StopIteration):
                    with self.assertRaises(StopIteration):
                        module.poll()
                factory.return_value.close.assert_called_once()
            self.assertIsNone(module._state)
        finally:
            module._state, module._received = original


class MetadataTests(unittest.TestCase):
    def test_usb_does_not_inherit_old_network_file_format(self):
        self.assertEqual(module.source_metadata(shd_state(service='inputs', title='USB',
            codec='flac', samplerate='192 kHz', bitdepth='24')), dict(name='Mac'))

    def test_optical_name(self):
        self.assertEqual(module.source_metadata(shd_state(service='inputs', title='TOSLINK')), dict(name='AppleTV'))

    def test_idle_lan_has_neutral_label(self):
        self.assertEqual(module.source_metadata(shd_state(service='inputs', title='LAN')), dict(name='LAN'))
        self.assertIsNone(module.source_metadata(None))

    def test_file_metadata_and_units(self):
        for rate in ['44.1 kHz', '44,1 kHz', '44100', 44100]:
            self.assertEqual(module.source_metadata(shd_state(service='mpd', trackType='flac',
                samplerate=rate, bitdepth='16 bit')), dict(name='Volumio', codec='FLAC', bits=16, fs_hz=44100))

    def test_roon_does_not_fall_back_to_shd_stream_resolution(self):
        self.assertEqual(module.source_metadata(shd_state(service='roonbridge', bitdepth=24,
            samplerate='96 kHz')), dict(name='Roon'))

    def test_missing_or_invalid_fields_are_omitted(self):
        self.assertEqual(module.source_metadata(shd_state(service='mpd', codec='',
            trackType='tidal', samplerate='', bitdepth=None)), dict(name='Volumio'))
        self.assertEqual(module.source_metadata(shd_state(service='mpd', samplerate='--',
            bitdepth='n/a')), dict(name='Volumio'))

    def test_shd_output_uses_fixed_spec_not_guessed_input_bits(self):
        signal = dict(input='COAX1', power=True, digital=True, locked=True, pcm=True,
                      fs_hz=96000, word_length_bits=None)
        result = module.enrich(signal, shd_state(service='inputs', title='USB'))
        self.assertEqual(result['shd_source'], dict(name='Mac'))
        self.assertEqual(result['shd_out'], dict(codec='PCM', fs_hz=96000, bits=24,
            bits_source='shd_studio_output_specification'))
        signal['fs_hz'] = 44100
        self.assertNotIn('bits', module.enrich(signal, None)['shd_out'])

    def test_no_shd_labels_on_other_input_or_standby(self):
        for name in ['A1', 'A2', 'OPT1', 'COAX2', 'CPU']:
            signal = dict(input=name, power=True, fs_hz=96000, locked=True, pcm=True)
            self.assertEqual(module.enrich(signal, shd_state(service='mpd')), signal)
        signal = dict(input='COAX1', power=False)
        self.assertEqual(module.enrich(signal, shd_state(service='mpd')), signal)

    def test_no_output_format_without_receiver_lock(self):
        result = module.enrich(dict(input='COAX1', power=True, locked=False, pcm=True),
                               shd_state(service='inputs', title='USB'))
        self.assertNotIn('shd_out', result)


class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.bridge = dict(schema_version=1, monitoring=True, ttl_ms=3000,
            generated_at=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), sources={
                'apple_music': dict(playing=True, artist='Mac artist', title='Mac track',
                    codec='ALAC', bits=24, fs_hz=96000),
                'roon': dict(playing=True, artist='Roon artist', title='Roon track',
                    codec='FLAC', bits=16, fs_hz=44100)})

    def source(self, title):
        return module.source_metadata(shd_state(service='raat' if title == 'LAN' else 'inputs', title=title,
            codec='PCM', bitdepth=32, samplerate='192 kHz'), self.bridge)

    def test_simultaneous_players_follow_selected_shd_input(self):
        for selected, key, name in [('USB', 'apple_music', 'Mac'), ('LAN', 'roon', 'Roon')]:
            expected = dict(self.bridge['sources'][key], name=name)
            expected.pop('playing')
            self.assertEqual(self.source(selected), expected)
        self.assertEqual(self.source('TOSLINK'), dict(name='AppleTV'))
        self.assertEqual(self.source('OPTICAL'), dict(name='AppleTV'))

    def test_usb_to_idle_lan_ignores_stale_usb_player_state(self):
        state = shd_state(service='inputs', title='USB', codec='PCM', bitdepth=32)
        self.assertEqual(module.source_metadata(state, self.bridge)['title'], 'Mac track')
        state['selected_input'] = module.selected_input(input_list())
        self.assertEqual(module.source_metadata(state, self.bridge), dict(name='LAN'))

    def test_button_cycle_and_network_player_changes_clear_previous_metadata(self):
        signal = dict(input='COAX1', power=True, locked=True, pcm=True, fs_hz=96000)
        sequence = [
            (shd_state(service='inputs', title='USB'), 'Mac', 'Mac track'),
            (shd_state(service='inputs', title='USB', selected_input='LAN'), 'LAN', None),
            (shd_state(service='raat', title='Roon track'), 'Roon', 'Roon track'),
            (shd_state(service='raat', status='pause', title='Roon track'), 'LAN', None),
            (shd_state(service='mpd', title='Volumio track', codec='FLAC'), 'Volumio', 'Volumio track'),
            (shd_state(service='mpd', status='stop', title='Volumio track'), 'LAN', None),
            (shd_state(service='mpd', title='Old track', selected_input='TOSLINK'), 'AppleTV', None)]
        for state, name, title in sequence:
            signal = module.enrich(signal, state, self.bridge)
            self.assertEqual(signal['shd_source']['name'], name)
            self.assertEqual(signal['shd_source'].get('title'), title)
            if name in ('LAN', 'AppleTV'):
                self.assertEqual(signal['shd_source'], dict(name=name))
            self.assertEqual(signal['shd_out']['fs_hz'], 96000)

    def test_lan_pause_or_stop_hides_old_roon_and_volumio_tags(self):
        for service in ('raat', 'mpd'):
            for status in ('pause', 'stop', None):
                state = shd_state(service=service, status=status, title='Old track',
                    codec='FLAC', bitdepth=24, samplerate='96 kHz')
                self.assertEqual(module.source_metadata(state, self.bridge), dict(name='LAN'))

    def test_lan_volumio_metadata_wins_over_unrelated_bridge_playback(self):
        state = shd_state(service='mpd', artist='Volumio artist', title='Volumio track',
            codec='flac', bitdepth='16 bit', samplerate='44.1 kHz')
        self.assertEqual(module.source_metadata(state, self.bridge), dict(name='Volumio',
            artist='Volumio artist', title='Volumio track', codec='FLAC', bits=16, fs_hz=44100))
        state['selected_input'] = 'USB'
        self.assertEqual(module.source_metadata(state, self.bridge)['title'], 'Mac track')
        state['selected_input'] = 'TOSLINK'
        self.assertEqual(module.source_metadata(state, self.bridge), dict(name='AppleTV'))

    def test_live_volumio_airplay_emulation_reports_metadata_without_guessing_codec(self):
        self.bridge['sources']['roon']['playing'] = False
        state = shd_state(service='airplay_emulation', status='play',
            artist='John Beltran', title='Austin', album='Sunrise and the Life We Live',
            trackType='airplay', codec='', bitdepth='16 bit', samplerate='44.1 kHz')
        self.assertEqual(module.source_metadata(state, self.bridge), dict(name='Airplay',
            artist='John Beltran', title='Austin', bits=16, fs_hz=44100))
        for status in ('pause', 'stop'):
            state['status'] = status
            self.assertEqual(module.source_metadata(state, self.bridge), dict(name='LAN'))

    def test_unknown_hardware_input_never_reuses_old_player_state(self):
        self.assertIsNone(module.source_metadata(dict(service='inputs', title='USB', status='play'), self.bridge))

    def test_raat_service_uses_bridge_file_metadata(self):
        for service in ('roon', 'roonbridge', 'raat', 'roonready'):
            actual = module.source_metadata(shd_state(service=service, codec='PCM', bitdepth=32), self.bridge)
            self.assertEqual(actual['title'], 'Roon track')
            self.assertEqual(actual['bits'], 16)

    def test_switches_never_retain_previous_source(self):
        signal = dict(input='COAX1', power=True, locked=True, pcm=True, fs_hz=96000)
        for selected in ('USB', 'LAN', 'TOSLINK', 'USB'):
            signal = module.enrich(signal, shd_state(service='raat' if selected == 'LAN' else 'inputs', title=selected), self.bridge)
            self.assertEqual(signal['shd_source'], self.source(selected))
        for signal in (dict(signal, input='A1'), dict(signal, power=False)):
            actual = module.enrich(signal, shd_state(service='inputs', title='USB'), self.bridge)
            self.assertNotIn('shd_source', actual)
            self.assertNotIn('shd_out', actual)

    def test_paused_selected_player_never_uses_other_player(self):
        self.bridge['sources']['apple_music']['playing'] = False
        self.assertEqual(self.source('USB'), dict(name='Mac'))
        self.assertEqual(self.source('LAN')['title'], 'Roon track')
        self.bridge['sources']['roon']['playing'] = False
        self.assertEqual(self.source('LAN'), dict(name='LAN'))

    def test_no_inferred_bits_or_fallback_to_shd(self):
        del self.bridge['sources']['apple_music']['bits']
        self.assertNotIn('bits', self.source('USB'))
        self.assertEqual(self.source('USB')['fs_hz'], 96000)
        self.bridge['sources']['apple_music'] = dict(playing=True)
        self.assertEqual(self.source('USB'), dict(name='Mac'))

    def test_invalid_fields_are_omitted(self):
        self.bridge['sources']['apple_music'] = dict(playing=True, artist=[], title='  ',
            codec='unknown', bits=True, fs_hz='96000')
        self.assertEqual(self.source('USB'), dict(name='Mac'))

    def test_stale_disabled_or_unsupported_bridge_clears_metadata(self):
        for field, value in [('monitoring', False), ('schema_version', 2),
                ('schema_version', True), ('ttl_ms', True), ('ttl_ms', 0),
                ('ttl_ms', 60000), ('sources', []), ('generated_at', 'invalid'),
                ('generated_at', '2020-01-01T00:00:00Z')]:
            with self.subTest(field=field, value=value):
                payload = dict(self.bridge, **{field: value})
                self.assertEqual(module.source_metadata(shd_state(service='inputs', title='USB'), payload),
                                 dict(name='Mac'))

    def test_cache_expires_after_three_seconds_or_failed_poll(self):
        self.assertIs(module.cached_bridge(self.bridge, 100, now=101), self.bridge)
        self.assertIsNone(module.cached_bridge(self.bridge, 100, now=103))
        self.assertIsNone(module.cached_bridge(None, 100, now=101))
        with patch.object(module.time, 'time', return_value=time.time() + 4):
            self.assertIsNone(module.cached_bridge(self.bridge, 100, now=101))

    def test_mac_unavailable_does_not_block_shd_polling(self):
        # Different workers and no HTTP in enrichment: a missing Mac still
        # permits immediate input selection and physical output measurements.
        result = module.enrich(dict(input='COAX1', power=True, locked=True,
            pcm=True, fs_hz=96000, volume_db=-18), shd_state(service='inputs', title='TOSLINK'), None)
        self.assertEqual(result['shd_source'], dict(name='AppleTV'))
        self.assertEqual(result['shd_out']['fs_hz'], 96000)
        self.assertEqual(result['volume_db'], -18)

    def test_failed_bridge_poll_clears_cache_without_changing_shd_state(self):
        original = (module._bridge, module._bridge_received, module._state)
        try:
            module._bridge = self.bridge
            shd = shd_state(service='inputs', title='TOSLINK')
            module._state = shd
            with patch.object(module, 'read_json', side_effect=IOError('Mac offline')):
                with patch.object(module.time, 'sleep', side_effect=StopIteration):
                    with self.assertRaises(StopIteration):
                        module.poll_bridge()
            self.assertIsNone(module._bridge)
            self.assertIs(module._state, shd)
        finally:
            module._bridge, module._bridge_received, module._state = original


if __name__ == '__main__':
    unittest.main()
