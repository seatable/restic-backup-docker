#!/usr/bin/env python3
"""Minimal healthchecks.io mock for the tests.

Usage: healthcheck-mock.py <port> <logfile>
Every request is appended to the logfile as "<path> | <last line of the body>".
"""
import http.server
import sys

PORT = int(sys.argv[1])
LOGFILE = sys.argv[2]


class Handler(http.server.BaseHTTPRequestHandler):
    def _handle(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode(errors="replace").strip()
        last_line = body.splitlines()[-1] if body else ""
        with open(LOGFILE, "a") as f:
            f.write(f"{self.path} | {last_line}\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    do_GET = _handle
    do_POST = _handle

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
