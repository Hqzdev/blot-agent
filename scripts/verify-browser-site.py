#!/usr/bin/env python3
"""Disposable loopback-only website used by the real WebKit verification app."""
import http.server
import pathlib
import sys
import time

PAGE = b'''<!doctype html><html><head><meta charset="utf-8"><title>Blot browser verification</title></head>
<body><h1>Local test page</h1><label>Note<input id="note" type="text"></label>
<label>Password<input id="password" type="password" value="never-expose-this"></label>
<textarea aria-label="Verification code">private-code-never-expose</textarea>
<div contenteditable="true" aria-label="Card number">private-card-never-expose</div>
<button id="change" onclick="document.getElementById('status').textContent='clicked'">Change status</button>
<a id="next" href="/second">Next page</a><a id="popup" href="/second" target="_blank">New tab</a>
<a href="/download" download="browser-test.txt">Download file</a><p id="status">Ready</p>
<div style="height:1800px"></div><p>Bottom of page</p></body></html>'''


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.startswith('/slow'):
            time.sleep(5)
        if self.path.startswith('/download'):
            data = b'Blot browser download verified\n'
            mime = 'application/octet-stream'
        elif self.path.startswith('/second'):
            data = b'<!doctype html><title>Second page</title><h1>Second page</h1><a href="/page">Back to form</a>'
            mime = 'text/html; charset=utf-8'
        else:
            data, mime = PAGE, 'text/html; charset=utf-8'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', str(len(data)))
        if mime == 'application/octet-stream':
            self.send_header('Content-Disposition', 'attachment; filename="browser-test.txt"')
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
    server.serve_forever()
