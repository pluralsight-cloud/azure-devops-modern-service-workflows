#!/usr/bin/env python3
"""Local MOCK NuGet v3 push endpoint for Module 4 (127.0.0.1 only, no network).

Usage: python3 mock-feed.py <push-status-code> <port>
GET  /index.json -> a minimal v3 service index that advertises a push URL.
PUT  /push       -> replies with the status code you chose (401, 403, 409, 201 ...).
It stands in for a feed to show how `dotnet nuget push` reports each HTTP class.
It is NOT Azure Artifacts or GitHub Packages: their real response wording may
differ from this mock.
"""
import http.server
import json
import sys

code, port = int(sys.argv[1]), int(sys.argv[2])


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"version": "3.0.0", "resources": [
            {"@id": f"http://127.0.0.1:{port}/push", "@type": "PackagePublish/2.0.0"}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_PUT(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(code)
        if code == 401:
            self.send_header("WWW-Authenticate", 'Basic realm="mock"')
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *args):
        pass


http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
