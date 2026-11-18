#!/usr/bin/env python3
"""Preview the M6 Now Playing typography patch; --apply installs and reloads it.

Run on the M6 as root. Uses the factory `encore reload` command, never quits Jive.
"""
import difflib
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

TARGET = '/usr/encore/play/share/jive/applets/M6EncoreSkin/M6EncoreSkinApplet.lua'
WHITE = 'fg = { 0xff, 0xff, 0xff }'


def patch(source):
    for name, y in (('npsourceInfo', 211), ('npsignalInfo', 261), ('npvolumeInfo', 151)):
        pattern = r'(\b' + name + r' = \{)(.*?)(\n        \},)'
        match = re.search(pattern, source, re.S)
        if not match:
            raise ValueError('Missing style ' + name)
        body = match.group(2)
        body, count = re.subn(r'fg = \{[^}]+\}', WHITE, body)
        if count != 1:
            raise ValueError('Unexpected foreground style ' + name)
        if name == 'npvolumeInfo':
            body, count = re.subn(r'font = _boldfont\((?:25|36|38)\)', 'font = _boldfont(38)', body)
            if count != 1:
                raise ValueError('Unexpected volume font')
            body, count = re.subn(r'x = 30, y = \d+, w = \d+, h = \d+',
                                 'x = 30, y = 151, w = 525, h = 58', body)
            if count != 1:
                raise ValueError('Unexpected volume bounds')
        else:
            body, count = re.subn(r'font = _boldfont\((?:22|31|32)\)', 'font = _boldfont(31)', body)
            if count != 1:
                raise ValueError('Unexpected font ' + name)
            body, count = re.subn(r'x = 30, y = \d+, w = \d+, h = \d+',
                                 'x = 30, y = %d, w = 560, h = 49' % y, body)
            if count != 1:
                raise ValueError('Unexpected bounds ' + name)
        source = source[:match.start(2)] + body + source[match.end(2):]
    # Keep the input heading in the same white as its data rows.
    anchor = source.index('\n\t\tnptitle = {', source.index('s.nowplaying ='))
    end = source.index('\n\t\tnpartistalbum', anchor)
    heading = source[anchor:end]
    heading, count = re.subn(r'fg\s*= _tracklayout.fg,', WHITE + ',', heading)
    if count != 1 and WHITE not in heading:
        raise ValueError('Unexpected input heading foreground')
    source = source[:anchor] + heading + source[end:]
    # The resident NowPlaying applet retains its Lua formatter until reboot.
    # Filter only these two label styles so skin reload updates them immediately,
    # including labels recreated later, without restarting Jive or audio.
    source = re.sub(r'Label\._encoreTelemetryLabels\b', 'Label._encoreTelemetryLabelsV2', source)
    source = source.replace("value = value:gsub('^SHD Out:', 'INPUT:')",
                            "value = value:gsub('^SHD Out:', 'Input:'):gsub('^INPUT:', 'Input:')")
    if 'Label._encoreTelemetryLabelsV2' not in source:
        hook = '''
    if not Label._encoreTelemetryLabelsV2 then
        local setValue = Label.setValue
        Label.setValue = function(widget, value)
            if type(value) == 'string' then
                local style = widget:getStyle()
                if style == 'npvolumeInfo' then
                    value = value:gsub('^Volume:%s*', '')
                elseif style == 'npsignalInfo' then
                    value = value:gsub('^SHD Out:', 'Input:'):gsub('^INPUT:', 'Input:')
                end
            end
            return setValue(widget, value)
        end
        Label._encoreTelemetryLabelsV2 = true
    end
'''
        marker = 'function skin(self, s, reload, useDefaultSize)'
        if source.count(marker) != 1:
            raise ValueError('Unexpected skin entry point')
        source = source.replace(marker, marker + '\n' + hook, 1)
    return source


def reload_skin():
    with open('/sys/class/net/eth0/address') as stream:
        player = stream.read().strip()
    connection = socket.create_connection(('127.0.0.1', 9090), timeout=3)
    try:
        connection.sendall((player + ' encore reload 0 0\n').encode('ascii'))
        reply = connection.recv(4096).decode('utf-8')
    finally:
        connection.close()
    if 'encore reload' not in reply:
        raise RuntimeError('Unexpected reload response: ' + reply)
    return reply.strip()


def signal():
    with urllib.request.urlopen('http://127.0.0.1:6543/signal', timeout=3) as response:
        data = json.loads(response.read().decode('utf-8'))
    return {key: data.get(key) for key in ('input', 'power', 'volume_db', 'locked', 'fs_hz')}


def main():
    with open(TARGET, encoding='utf-8') as stream:
        before = stream.read()
    after = patch(before)
    if '--apply' not in sys.argv:
        print(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
                                         fromfile=TARGET, tofile=TARGET)))
        return
    if after == before:
        print(json.dumps(dict(status='already installed')))
        return
    stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
    temporary, backup = TARGET + '.new-' + stamp, TARGET + '.backup-' + stamp
    info = os.stat(TARGET)
    with open(temporary, 'x', encoding='utf-8') as stream:
        stream.write(after)
        stream.flush()
        os.fsync(stream.fileno())
    env = dict(os.environ)
    env['LD_LIBRARY_PATH'] = '/usr/encore/play/lib:' + env.get('LD_LIBRARY_PATH', '')
    subprocess.check_output(['/usr/encore/play/bin/luac', '-p', temporary], env=env,
                            stderr=subprocess.STDOUT)
    before_signal = signal()
    shutil.copy2(TARGET, backup)
    os.chmod(temporary, info.st_mode & 0o7777)
    os.chown(temporary, info.st_uid, info.st_gid)
    os.rename(temporary, TARGET)
    try:
        reply = reload_skin()
    except Exception:
        shutil.copy2(backup, TARGET)
        os.chown(TARGET, info.st_uid, info.st_gid)
        reload_skin()
        raise
    time.sleep(2)
    print(json.dumps(dict(backup=backup, sha256=hashlib.sha256(after.encode('utf-8')).hexdigest(),
                         reload=reply, before=before_signal, after=signal()), indent=2))


if __name__ == '__main__':
    main()
