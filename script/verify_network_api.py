#!/usr/bin/env python3
"""Read-only protocol verification; runs on a Mac or directly on M6 Encore."""
import concurrent.futures
import http.client
import json
import socket
import sys
import time
from urllib.parse import urlsplit

target = urlsplit(sys.argv[1])
host, port = target.hostname, target.port or 8765
checks = []


def request(method, path):
    connection = http.client.HTTPConnection(host, port, timeout=5)
    try:
        connection.request(method, path)
        response = connection.getresponse()
        data = response.read(65536)
        return response.status, dict(response.getheaders()), data
    finally:
        connection.close()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def read_raw(connection):
    data = b""
    while len(data) < 65536:
        try:
            chunk = connection.recv(4096)
        except ConnectionResetError:
            break
        if not chunk:
            break
        data += chunk
    return data


status, headers, body = request("GET", "/v1/now-playing")
require(status == 200, "GET failed")
require(headers.get("Cache-Control") == "no-store", "Missing no-store")
require(int(headers["Content-Length"]) == len(body), "Wrong UTF-8 byte length")
snapshot = json.loads(body.decode("utf-8"))
require(snapshot["schema_version"] == 1, "Unsupported schema")
require(snapshot["ttl_ms"] == 3000, "Wrong TTL")
require(set(snapshot["sources"]) == {"apple_music", "roon"}, "Missing source")
for item in snapshot["sources"].values():
    require(isinstance(item["playing"], bool), "Invalid playback flag")
    if not item["playing"]:
        require(not any(key in item for key in ("artist", "title", "codec", "bits", "fs_hz")),
                "Inactive source exposes stale fields")
    if "bits" in item:
        require(type(item["bits"]) is int, "Depth must be numeric")
    if "fs_hz" in item:
        require(type(item["fs_hz"]) is int, "Rate must be numeric hertz")
require("fileURL" not in body.decode("utf-8") and "/Users/" not in body.decode("utf-8"),
        "Private paths exported")
checks.append("snapshot_and_schema")

status, _, body = request("HEAD", "/v1/now-playing")
require(status == 200 and not body, "HEAD failed")
checks.append("head")
require(request("GET", "/health")[0] == 200, "Health failed")
require(request("GET", "/logs")[0] == 404, "Diagnostics must not be public")
require(request("POST", "/v1/now-playing")[0] == 405, "POST must be rejected")
checks.append("health_and_read_only_routes")

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    statuses = list(pool.map(lambda _: request("GET", "/v1/now-playing")[0], range(4)))
require(statuses == [200] * 4, "Concurrent requests failed")
checks.append("concurrent_clients")

with socket.create_connection((host, port), timeout=5) as connection:
    connection.sendall(b"GET /health HTTP/1.0\r\n")
    connection.sendall(b"\r\n")
    require(read_raw(connection).startswith(b"HTTP/1.1 200"), "HTTP/1.0 failed")
checks.append("http_1_0")

with socket.create_connection((host, port), timeout=5) as connection:
    connection.sendall(b"GET /health HTTP/1.1\r\nX-Fill: " + b"a" * 9000)
    require(read_raw(connection).startswith(b"HTTP/1.1 431"), "Header limit failed")
checks.append("bounded_headers")

with socket.create_connection((host, port), timeout=5) as connection:
    started = time.monotonic()
    connection.sendall(b"GET /health HTTP/1.1\r\n")
    require(read_raw(connection) == b"", "Incomplete request returned data")
    require(time.monotonic() - started < 5, "Incomplete client was not closed")
require(request("GET", "/health")[0] == 200, "Listener stopped after a client timeout")
checks.append("incomplete_request_timeout_and_recovery")

print(json.dumps({"verified_from": socket.gethostname(),
                  "base_url": sys.argv[1],
                  "checks": checks,
                  "snapshot": snapshot}, ensure_ascii=False, indent=2))
