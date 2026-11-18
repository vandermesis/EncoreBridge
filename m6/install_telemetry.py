#!/usr/bin/env python3
"""Run on M6 as root: install_telemetry.py <base64 payload> <expected old SHA256>.

Changes only the read-only telemetry service. Never restarts Jive, LMS or audio.
"""
import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request


def read_signal(port):
    with urllib.request.urlopen('http://127.0.0.1:%d/signal' % port, timeout=3) as response:
        return json.loads(response.read().decode('utf-8'))


def protected_processes():
    result = {}
    for name in os.listdir('/proc'):
        if name.isdigit():
            try:
                with open('/proc/%s/cmdline' % name, 'rb') as stream:
                    args = stream.read().replace(b'\0', b' ').decode('utf-8', 'replace')
                if args.startswith('./jive ') or 'slimserver.pl' in args or args.startswith('jive_alsa '):
                    result[name] = args
            except IOError:
                pass
    return result


def restart():
    return subprocess.check_output(['supervisorctl', '-c', '/etc/supervisord.conf',
                                    'restart', 'encoretelemetry']).decode('utf-8')


def main():
    target = '/usr/encore/telemetry/telemetry.py'
    payload = base64.b64decode(sys.argv[1])
    compile(payload, target, 'exec')
    with open(target, 'rb') as stream:
        old = stream.read()
    if hashlib.sha256(old).hexdigest() != sys.argv[2]:
        raise RuntimeError('Live file changed since inspection; installation stopped')
    before = read_signal(6543)
    protected = protected_processes()
    stamp = time.strftime('%Y%m%dT%H%M%SZ', time.gmtime())
    backup = target + '.backup-' + stamp
    shutil.copy2(target, backup)
    info = os.stat(target)
    temporary = target + '.new-' + stamp
    with open(temporary, 'xb') as stream:
        stream.write(payload)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(temporary, info.st_mode & 0o7777)
    os.chown(temporary, info.st_uid, info.st_gid)
    os.rename(temporary, target)
    try:
        status = restart()
        time.sleep(3)
        enriched = read_signal(6545)
        after = read_signal(6543)
        if protected_processes() != protected:
            raise RuntimeError('Unexpected Jive/LMS/audio process change')
    except Exception:
        shutil.copy2(backup, target)
        os.chown(target, info.st_uid, info.st_gid)
        restart()
        raise
    fields = ('input', 'power', 'volume_db', 'locked', 'pcm', 'fs_hz')
    print(json.dumps(dict(backup=backup, sha256=hashlib.sha256(payload).hexdigest(),
        supervisor=status, protected_processes_unchanged=True,
        before={key: before.get(key) for key in fields},
        after={key: after.get(key) for key in fields}, signal=enriched), indent=2))


if __name__ == '__main__':
    main()
