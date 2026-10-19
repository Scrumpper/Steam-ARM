#!/usr/bin/env python3
"""Local stand-in for GitHub's release API and asset downloads. Usage: mockgh.py DIR. Writes DIR/port; answers
GET /repos/Scrumpper/Steam-ARM/releases/latest from DIR/release.json and GET /dl/<tag>/<name> from DIR/assets/<name>.
DIR/mode (re-read per request): ok, 403, 429, 404, 500, badjson, dl404 (asset 404), truncate (asset cut at half).
Every request path is appended to DIR/requests."""
import http.server, os, sys

D = sys.argv[1]


def mode():
    try:
        return open(os.path.join(D, "mode")).read().strip() or "ok"
    except OSError:
        return "ok"


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body=b"", cut=False):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body[: len(body) // 2] if cut else body)
        if cut:
            self.wfile.flush()
            self.connection.close()

    def do_GET(self):
        with open(os.path.join(D, "requests"), "a") as f:
            f.write(self.path + "\n")
        m = mode()
        if self.path == "/repos/Scrumpper/Steam-ARM/releases/latest":
            if m in ("403", "429", "404", "500"):
                return self.send(int(m), b'{"message": "refused"}')
            if m == "badjson":
                return self.send(200, b"not json")
            try:
                return self.send(200, open(os.path.join(D, "release.json"), "rb").read())
            except OSError:
                return self.send(404)
        if self.path.startswith("/dl/"):
            if m == "dl404":
                return self.send(404)
            p = os.path.join(D, "assets", os.path.basename(self.path))
            if not os.path.isfile(p):
                return self.send(404)
            return self.send(200, open(p, "rb").read(), cut=(m == "truncate" and p.endswith(".zip")))
        self.send(404)


s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(os.path.join(D, "port.tmp"), "w").write(str(s.server_address[1]))
os.rename(os.path.join(D, "port.tmp"), os.path.join(D, "port"))
s.serve_forever()
