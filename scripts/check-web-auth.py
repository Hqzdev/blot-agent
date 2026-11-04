#!/usr/bin/env python3
"""Real Next -> Java -> TLS SMTP -> SQLite registration and native PKCE handoff. No external mail/model/Google."""
import base64
from datetime import datetime, timezone
from email import policy
from email.parser import BytesParser
import hashlib
import http.cookiejar
import json
import os
from pathlib import Path
import queue
import re
import secrets
import socket
import socketserver
import sqlite3
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '.build'


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


class MailServer(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, context):
        self.context = context
        self.messages = queue.Queue()
        super().__init__(('127.0.0.1', 0), MailHandler)


class MailHandler(socketserver.BaseRequestHandler):
    def handle(self):
        connection = self.request
        stream = connection.makefile('rb')

        def send(value):
            connection.sendall(value.encode() + b'\r\n')

        send('220 localhost ESMTP verification')
        try:
            while True:
                line = stream.readline(8192)
                if not line:
                    break
                command = line.decode('ascii', 'replace').strip()
                upper = command.upper()
                if upper.startswith('EHLO'):
                    send('250-localhost\r\n250-STARTTLS\r\n250 AUTH LOGIN PLAIN')
                elif upper == 'STARTTLS':
                    send('220 Ready for TLS')
                    stream.close()
                    connection = self.server.context.wrap_socket(connection, server_side=True)
                    stream = connection.makefile('rb')
                elif upper.startswith('AUTH LOGIN'):
                    if upper == 'AUTH LOGIN':
                        send('334 VXNlcm5hbWU6')
                        stream.readline(8192)
                    send('334 UGFzc3dvcmQ6')
                    stream.readline(8192)
                    send('235 Authenticated')
                elif upper.startswith('AUTH PLAIN'):
                    if upper == 'AUTH PLAIN':
                        send('334 ')
                        stream.readline(8192)
                    send('235 Authenticated')
                elif upper.startswith(('MAIL FROM:', 'RCPT TO:', 'RSET', 'NOOP')):
                    send('250 OK')
                elif upper == 'DATA':
                    send('354 Send message')
                    body = bytearray()
                    while True:
                        part = stream.readline(8192)
                        if not part or part == b'.\r\n':
                            break
                        body.extend(part[1:] if part.startswith(b'..') else part)
                    self.server.messages.put(bytes(body))
                    send('250 Accepted')
                elif upper == 'QUIT':
                    send('221 Bye')
                    break
                else:
                    send('500 Unsupported')
        finally:
            stream.close()
            connection.close()


def main():
    BUILD.mkdir(exist_ok=True)
    java_home = BUILD / 'tools/jdk-25.0.4.1+1/Contents/Home'
    jar = ROOT / 'backend/cloud/build/libs/blot-cloud.jar'
    if not jar.exists() or not (ROOT / 'landing/.next/BUILD_ID').exists():
        raise RuntimeError('Build :cloud:bootJar and run next build first')
    with tempfile.TemporaryDirectory(prefix='web-auth-', dir=BUILD) as temporary:
        directory = Path(temporary)
        cert, key, trust = (directory / name for name in ('smtp.crt', 'smtp.key', 'smtp.p12'))
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-subj', '/CN=localhost',
                        '-addext', 'subjectAltName=DNS:localhost', '-keyout', str(key), '-out', str(cert)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run([str(java_home / 'bin/keytool'), '-importcert', '-noprompt', '-alias', 'isolated-smtp', '-file', str(cert),
                        '-keystore', str(trust), '-storepass', 'isolated-test-only'], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        tls.load_cert_chain(cert, key)
        smtp = MailServer(tls)
        threading.Thread(target=smtp.serve_forever, daemon=True).start()
        cloud_port, web_port = free_port(), free_port()
        origin = f'http://127.0.0.1:{web_port}'
        cloud = f'http://127.0.0.1:{cloud_port}'
        env = {k: v for k, v in os.environ.items() if not k.startswith('BLOT_')}
        source = directory / '.env'
        source.write_text('')
        env.update(BLOT_ENV_FILE=str(source), BLOT_CLOUD_CHALLENGE_KEY=base64.b64encode(secrets.token_bytes(32)).decode(),
                   BLOT_CLOUD_DATABASE=str(directory / 'cloud.sqlite'), BLOT_CLOUD_PORT=str(cloud_port), BLOT_CLOUD_ADDRESS='127.0.0.1',
                   BLOT_SMTP_HOST='localhost', BLOT_SMTP_PORT=str(smtp.server_address[1]), BLOT_SMTP_USERNAME='verification',
                   BLOT_SMTP_PASSWORD='isolated-password', BLOT_SMTP_FROM='verification@example.invalid',
                   BLOT_CLOUD_ORIGIN=cloud, BLOT_ACCOUNT_SERVICE_URL=cloud,
                   BLOT_GOOGLE_WEB_CLIENT_ID='', BLOT_GOOGLE_WEB_CLIENT_SECRET='', BLOT_GOOGLE_WEB_REDIRECT_URI='',
                   BLOT_WEB_SESSION_SECRET=secrets.token_urlsafe(32))
        cloud_log = (BUILD / 'web-auth-server.log').open('w')
        next_log = (BUILD / 'web-auth-site.log').open('w')
        backend = subprocess.Popen([str(java_home / 'bin/java'), '--enable-native-access=ALL-UNNAMED',
                                    '-Djavax.net.ssl.trustStore=' + str(trust), '-Djavax.net.ssl.trustStorePassword=isolated-test-only',
                                    '-jar', str(jar)], cwd=directory, env=env, stdout=cloud_log, stderr=subprocess.STDOUT)
        website = subprocess.Popen(['node', 'node_modules/next/dist/bin/next', 'start', '--hostname', '127.0.0.1', '--port', str(web_port)],
                                   cwd=ROOT / 'landing', env=env, stdout=next_log, stderr=subprocess.STDOUT)
        browser = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

        def request(path, body=None, bearer=None, expected=200, origin_header=None):
            headers = {'Content-Type': 'application/json', 'Origin': origin_header or origin}
            if bearer:
                headers['Authorization'] = 'Bearer ' + bearer
            req = urllib.request.Request(origin + path, data=None if body is None else json.dumps(body).encode(), headers=headers)
            try:
                response = browser.open(req, timeout=25)
            except urllib.error.HTTPError as failure:
                response = failure
            data = response.read()
            if response.status != expected:
                code = json.loads(data).get('code') if data.startswith(b'{') else 'non-json'
                raise RuntimeError(f'{path}: expected {expected}, received {response.status}/{code}')
            return json.loads(data) if data.startswith((b'{', b'[')) else data

        def mail_code():
            message = BytesParser(policy=policy.default).parsebytes(smtp.messages.get(timeout=15))
            match = re.search(r'\b([0-9]{6})\b', message.get_content())
            if not match:
                raise RuntimeError('SMTP message lacks confirmation code')
            return match[1]

        try:
            for target, process in [(cloud + '/v1/health', backend), (origin + '/login', website)]:
                for _ in range(200):
                    if process.poll() is not None:
                        raise RuntimeError('Verification process exited; inspect .build/web-auth-*.log')
                    try:
                        with urllib.request.urlopen(target, timeout=1) as response:
                            if response.status == 200:
                                break
                    except (urllib.error.URLError, TimeoutError):
                        time.sleep(.1)
                else:
                    raise RuntimeError('Verification startup timed out')
            email, password = 'web-wire@example.org', 'test-password-long-enough'
            assert request('/api/auth/session') == {'account': None}
            assert request('/api/auth/session', {'action': 'register', 'email': email, 'password': password, 'name': 'Web verification'})['verificationRequired']
            verification_code = mail_code()
            assert request('/api/auth/session', {'action': 'verify', 'email': email, 'code': verification_code})['authenticated']
            assert request('/api/auth/session')['account']['email'] == email
            request('/api/auth/session', {'action': 'logout'}, origin_header='https://attacker.example', expected=403)
            verifier = secrets.token_urlsafe(32)
            state = secrets.token_urlsafe(32)
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
            query = urllib.parse.urlencode({'response_type': 'code', 'client_id': 'blot-ios', 'redirect_uri': 'blot-agent-ios:/oauth/account',
                                           'state': state, 'code_challenge': challenge, 'code_challenge_method': 'S256', 'intent': 'login'})
            handoff = request('/api/auth/app', {'query': query})
            callback = urllib.parse.urlsplit(handoff['callbackURL'])
            parameters = urllib.parse.parse_qs(callback.query)
            assert callback.scheme == 'blot-agent-ios' and parameters['state'] == [state]
            assert set(parameters) == {'state', 'code'}
            exchange = {'code': parameters['code'][0], 'codeVerifier': verifier, 'clientID': 'blot-ios', 'redirectURI': 'blot-agent-ios:/oauth/account'}
            request('/v1/auth/browser/token', {**exchange, 'codeVerifier': 'x' * 43}, expected=401)
            native = request('/v1/auth/browser/token', exchange)
            assert native['bootstrapAllowed'] and native['accessToken'] != native['refreshToken']
            request('/v1/auth/browser/token', exchange, expected=401)
            assert request('/v1/auth/me', bearer=native['accessToken'])['email'] == email
            pending = request('/api/auth/app', {'query': query})
            request('/api/auth/session', {'action': 'logout'})
            stale = urllib.parse.parse_qs(urllib.parse.urlsplit(pending['callbackURL']).query)['code'][0]
            request('/v1/auth/browser/token', {**exchange, 'code': stale}, expected=401)
            assert request('/v1/auth/me', bearer=native['accessToken'])['email'] == email
            request('/api/auth/session', {'action': 'recover', 'email': email})
            reset_code = mail_code()
            new_password = 'updated-password-long-enough'
            request('/api/auth/session', {'action': 'reset', 'email': email, 'code': reset_code, 'password': new_password})
            request('/v1/auth/me', bearer=native['accessToken'], expected=401)
            request('/api/auth/session', {'action': 'login', 'email': email, 'password': password}, expected=401)
            request('/api/auth/session', {'action': 'login', 'email': email, 'password': new_password})
            assert request('/api/auth/session')['account']['email'] == email
            with sqlite3.connect(directory / 'cloud.sqlite') as db:
                hashes = db.execute('SELECT access_hash,refresh_hash FROM sessions').fetchall()
                assert all(native['accessToken'] not in row and native['refreshToken'] not in row for row in hashes)
            cloud_log.flush(); next_log.flush()
            for log in [BUILD / 'web-auth-server.log', BUILD / 'web-auth-site.log']:
                contents = log.read_text()
                assert all(value not in contents for value in [password, new_password, native['accessToken'], native['refreshToken'], verifier, verification_code])
            evidence = {'checkedAt': datetime.now(timezone.utc).isoformat(), 'result': 'PASS', 'realHTTP': True, 'realSQLite': True,
                        'tlsSMTP': 'isolated local fixture', 'scenarios': ['registration and email verification', 'encrypted HttpOnly browser session',
                        'CSRF origin rejection', 'PKCE handoff and wrong-verifier/replay rejection', 'web logout invalidates pending code',
                        'native session independent of browser logout', 'password reset revokes native sessions', 'no credentials in logs'],
                        'googleExternal': False, 'physicalAppLaunch': False}
            (BUILD / 'web-auth-evidence.json').write_text(json.dumps(evidence, indent=2) + '\n')
            print('PASS: real Next -> Java -> TLS SMTP -> SQLite; registration, verification, reset, browser session and native PKCE handoff.')
        finally:
            for process in (website, backend):
                process.terminate()
            for process in (website, backend):
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait()
            smtp.shutdown(); smtp.server_close(); cloud_log.close(); next_log.close()


if __name__ == '__main__':
    main()
