"""A tiny HTTP/1.0 server for tests/test_http.mojo: /echo returns the request as JSON, /big 300,000 bytes."""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


class Echo(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, data):
        self.send_response(status)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/big":
            return self.reply(200, b"x" * 300_000)
        self.reply(404, b'{"error": "not found"}')

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        self.reply(200, json.dumps({"method": "POST", "session": self.headers.get("X-Session"), "body": body}).encode())


HTTPServer(("127.0.0.1", int(sys.argv[1])), Echo).serve_forever()
