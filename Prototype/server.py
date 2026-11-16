#!/usr/bin/env python3
"""Local server for the Hike web prototype.

Serves the prototype page and forwards map tiles, routing, place search and trail
requests to the public services, caching every answer on disk so repeated runs do not
query them again.

    python3 Prototype/server.py            # then open http://localhost:8765

The prototype exists to try out and demonstrate the interface in a browser. It is not
the iOS app, and it uses BRouter for routing where the app uses openrouteservice or
Apple Maps.
"""
import hashlib
import os
import subprocess
import sys
import urllib.parse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
CACHE = os.environ.get("HIKE_PROTOTYPE_CACHE", os.path.join(ROOT, ".cache"))
USER_AGENT = "Hike-prototype/1.0"
TRAILS = "https://hiking.waymarkedtrails.org/api/v1"


def fetch(url, kind):
    """Returns the body of `url`, from the disk cache when available."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, kind + "-" + hashlib.sha1(url.encode()).hexdigest())
    if os.path.exists(path) and os.path.getsize(path) > 0:
        with open(path, "rb") as handle:
            return handle.read()
    result = subprocess.run(
        ["curl", "-sS", "--fail", "-m", "40", "-A", USER_AGENT, url],
        capture_output=True,
    )
    if result.returncode != 0 or not result.stdout:
        return None
    with open(path + ".tmp", "wb") as handle:
        handle.write(result.stdout)
    os.replace(path + ".tmp", path)
    return result.stdout


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, *args):
        pass

    def reply(self, body, content_type):
        if body is None:
            self.send_error(502, "upstream request failed")
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "max-age=86400")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed.query)
        parts = [part for part in parsed.path.split("/") if part]

        def param(name):
            return urllib.parse.quote(query.get(name, [""])[0], safe=",.-")

        if len(parts) == 4 and parts[0] == "tiles":
            z, x, y = parts[1], parts[2], parts[3].split(".")[0]
            if not (z.isdigit() and x.isdigit() and y.isdigit()):
                return self.send_error(400)
            return self.reply(fetch(f"https://tile.opentopomap.org/{z}/{x}/{y}.png", "tile"), "image/png")
        if parsed.path == "/api/route":
            points = urllib.parse.quote(query.get("pts", [""])[0], safe=",.-")
            url = f"https://brouter.de/brouter?lonlats={points}&profile=hiking-mountain&alternativeidx=0&format=geojson"
            return self.reply(fetch(url, "route"), "application/json")
        if parsed.path == "/api/geocode":
            return self.reply(fetch(f"https://photon.komoot.io/api/?q={param('q')}&limit=1", "geo"), "application/json")
        if parsed.path == "/api/trails/search":
            url = f"{TRAILS}/list/search?query={param('query')}&limit=30"
            return self.reply(fetch(url, "search"), "application/json")
        if parsed.path == "/api/trails/area":
            return self.reply(fetch(f"{TRAILS}/list/by_area?bbox={param('bbox')}&limit=40", "area"), "application/json")
        if len(parts) == 4 and parts[:3] == ["api", "trails", "detail"] and parts[3].isdigit():
            return self.reply(fetch(f"{TRAILS}/details/relation/{parts[3]}", "detail"), "application/json")
        return super().do_GET()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    print(f"Hike prototype on http://localhost:{port}")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
