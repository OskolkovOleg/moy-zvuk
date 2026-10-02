#!/usr/bin/env python3
"""One-shot test credential handoff on loopback. Never logs credentials."""
import getpass
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from zvuk_music import Client

TOKEN = os.environ.pop('ZVUK_TEST_TOKEN', None) or getpass.getpass('Your Zvuk token (hidden): ')
if not TOKEN.strip():
    raise SystemExit('Token is required for live integration tests')
CLIENT = Client(token=TOKEN.strip())
ALLOWED = ('177981965', '180082552')

class Handler(BaseHTTPRequestHandler):
    delivered = False
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path == '/credential' and not Handler.delivered:
            Handler.delivered = True
            data = {'token': TOKEN.strip()}
        elif self.path.removeprefix('/stream/') in ALLOWED:
            result = CLIENT.get_direct_stream_url(self.path.removeprefix('/stream/'))
            data = {'stream': result.stream}
        else:
            self.send_error(404)
            return
        payload = json.dumps(data).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

print('Test bridge ready on loopback:18746', flush=True)
HTTPServer(('127.0.0.1', 18746), Handler).serve_forever()
