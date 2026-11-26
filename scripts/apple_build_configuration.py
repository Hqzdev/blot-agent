#!/usr/bin/env python3
"""Generate Apple build configuration for personal development or public beta."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import sys
import tempfile
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]


def read_environment(path, overrides=None):
    result = {}
    if path.is_file():
        if path.stat().st_size > 262144:
            raise ValueError('BLOT_ENV_FILE exceeds 256 KiB')
        for raw in path.read_text(encoding='utf-8-sig').splitlines():
            line = raw.strip().removeprefix('export ').strip()
            if not line or line.startswith('#'):
                continue
            key, separator, value = line.partition('=')
            if not separator or not re.fullmatch(r'[A-Z][A-Z0-9_]*', key.strip()):
                raise ValueError('Invalid BLOT_ENV_FILE syntax')
            if key.strip() in result:
                raise ValueError('Duplicate BLOT_ENV_FILE key: ' + key.strip())
            value = value.strip()
            if value.startswith(('"', "'")):
                if len(value) < 2 or value[-1] != value[0]:
                    raise ValueError('Invalid BLOT_ENV_FILE quoting')
                value = value[1:-1]
            result[key.strip()] = value
    result.update(os.environ if overrides is None else overrides)
    return result


def required(env, name):
    value = env.get(name, '').strip()
    if not value or '\n' in value or '\r' in value:
        raise ValueError('Missing or invalid ' + name)
    return value


def endpoint(env, name, default=None, origin=False):
    value = required(env, name) if default is None else env.get(name, default)
    url = urlsplit(value)
    loopback = url.scheme == 'http' and url.hostname == '127.0.0.1'
    if not (url.scheme == 'https' or (origin and loopback)) or not url.hostname or url.username or url.password or url.query or url.fragment:
        raise ValueError('Invalid ' + name)
    if origin and url.path not in ('', '/'):
        raise ValueError('Invalid ' + name)
    return value


def positive(env, name, default):
    try:
        value = int(env.get(name, default))
    except ValueError:
        raise ValueError('Invalid ' + name) from None
    if not 0 < value <= 10_000_000:
        raise ValueError('Invalid ' + name)
    return value


def configuration(env, build, *, direct_provider=False):
    profile = env.get('BLOT_DISTRIBUTION', 'personal-dev')
    personal = build == 'Debug' and profile == 'personal-dev'
    public = build == 'Release' and profile == 'public-beta'
    if not (personal or public) or (direct_provider and not personal):
        raise ValueError('Embedded GigaChat credentials are allowed only in personal Debug builds')
    result = {
        'Profile': profile,
        'GigaChat': {
            'Model': required(env, 'BLOT_GIGACHAT_MODEL'),
            'APIURL': endpoint(env, 'BLOT_GIGACHAT_API_URL', 'https://gigachat.devices.sberbank.ru/api/v1'),
            'OAuthURL': endpoint(env, 'BLOT_GIGACHAT_OAUTH_URL', 'https://ngw.devices.sberbank.ru:9443/api/v2/oauth'),
            'Scope': env.get('BLOT_GIGACHAT_SCOPE', 'GIGACHAT_API_PERS'),
            'OutputTokens': positive(env, 'BLOT_GIGACHAT_OUTPUT_TOKENS', 2048),
            'ContextTokens': positive(env, 'BLOT_GIGACHAT_CONTEXT_TOKENS', 32768),
            'RunTokenBudget': positive(env, 'BLOT_RUN_TOKEN_BUDGET', 16000),
        },
    }
    if direct_provider:
        key = required(env, 'BLOT_GIGACHAT_AUTH_KEY')
        import base64
        try:
            if b':' not in base64.b64decode(key, validate=True):
                raise ValueError()
        except (ValueError, base64.binascii.Error):
            raise ValueError('Invalid BLOT_GIGACHAT_AUTH_KEY') from None
        result['GigaChat']['AuthorizationKey'] = key
    result['AuthURL'] = endpoint(env, 'BLOT_AUTH_URL')
    if env.get('BLOT_ACCOUNT_SERVICE_URL'):
        result['AccountServiceURL'] = endpoint(env, 'BLOT_ACCOUNT_SERVICE_URL', origin=True)
    elif result.get('AuthURL'):
        auth = urlsplit(result['AuthURL'])
        result['AccountServiceURL'] = auth.scheme + '://' + auth.netloc
    if public and urlsplit(result['AccountServiceURL']).scheme != 'https':
        raise ValueError('Public beta requires an HTTPS account service')
    clients = {}
    for platform, suffix in [('macOS', 'MACOS'), ('iOS', 'IOS')]:
        value = env.get('BLOT_GOOGLE_' + suffix + '_CLIENT_ID', '')
        if value:
            if not re.fullmatch(r'[0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com', value):
                raise ValueError('Invalid BLOT_GOOGLE_' + suffix + '_CLIENT_ID')
            clients[platform] = value
    if len(clients) == 1:
        raise ValueError('Configure both BLOT_GOOGLE_MACOS_CLIENT_ID and BLOT_GOOGLE_IOS_CLIENT_ID')
    if clients and len(set(clients.values())) != 2:
        raise ValueError('Google native client IDs must be distinct')
    result['GoogleClientIDs'] = clients
    messaging = {}
    for provider, variable in [('slack', 'BLOT_SLACK_CLIENT_ID'), ('teams', 'BLOT_TEAMS_CLIENT_ID')]:
        value = env.get(variable, '')
        if value:
            pattern = r'[0-9]+\.[0-9]+' if provider == 'slack' else r'[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
            if not re.fullmatch(pattern, value):
                raise ValueError('Invalid ' + variable)
            messaging[provider] = value
    result['MessagingClientIDs'] = messaging
    ca = env.get('BLOT_GIGACHAT_CA_FILE') or str(ROOT / 'apps/shared/Resources/GigaChatRootCA.crt')
    if ca:
        source = Path(ca)
        if not source.is_absolute() or not source.is_file() or source.stat().st_size > 65536:
            raise ValueError('Invalid BLOT_GIGACHAT_CA_FILE')
        data = source.read_bytes()
        certificates = re.findall(rb'-----BEGIN CERTIFICATE-----[A-Za-z0-9+/=\r\n\t ]+-----END CERTIFICATE-----', data)
        if not 1 <= len(certificates) <= 4 or b'PRIVATE KEY' in data:
            raise ValueError('Invalid BLOT_GIGACHAT_CA_FILE')
        result['ProviderCA'] = b'\n'.join(certificates)
    result['Revision'] = hashlib.sha256(plistlib.dumps(result, sort_keys=True)).hexdigest()
    return result


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
        temporary = Path(file.name)
        try:
            os.chmod(temporary, 0o600)
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    os.replace(temporary, path)


def provider_transport_security(configuration):
    # ATS otherwise rejects this private CA before URLSession's trust delegate runs.
    # Only these exact hosts use manual CA validation; HTTPS, TLS 1.2 and PFS remain required by the client.
    hosts = {urlsplit(configuration['GigaChat'][name]).hostname for name in ['APIURL', 'OAuthURL']}
    return {'NSExceptionDomains': {
        host: {'NSExceptionAllowsInsecureHTTPLoads': True, 'NSExceptionMinimumTLSVersion': 'TLSv1.2'}
        for host in sorted(hosts)
    }}


def google_oauth_configuration(env, clients, platform_name=None):
    bundles = {'iOS': 'yaroslavstrelkov.blot-agent.ios', 'macOS': 'yaroslavstrelkov.blot-agent'}
    entries = {platform: {'ClientID': value, 'BundleID': bundles[platform],
                         'RedirectURI': 'http://127.0.0.1/oauthredirect' if platform == 'macOS'
                         else '.'.join(reversed(value.split('.'))) + ':/oauthredirect'}
               for platform, value in clients.items()}
    secret = env.get('BLOT_GOOGLE_MACOS_CLIENT_SECRET', '')
    filename = env.get('BLOT_GOOGLE_MACOS_CLIENT_JSON', '')
    if filename:
        path = Path(filename).expanduser()
        if not path.is_absolute():
            path = ROOT / path
        if path.stat().st_size > 65536:
            raise ValueError('BLOT_GOOGLE_MACOS_CLIENT_JSON exceeds 64 KiB')
        try:
            installed = json.loads(path.read_text())['installed']
            if installed['client_id'] != clients.get('macOS'):
                raise ValueError('BLOT_GOOGLE_MACOS_CLIENT_JSON client ID does not match the Mac client')
            secret = installed['client_secret']
        except (KeyError, TypeError, json.JSONDecodeError):
            raise ValueError('BLOT_GOOGLE_MACOS_CLIENT_JSON must be the Google Desktop client configuration') from None
    if secret:
        if not isinstance(secret, str) or len(secret.encode()) > 4096 or any(c in secret for c in '\r\n\0'):
            raise ValueError('Invalid BLOT_GOOGLE_MACOS_CLIENT_SECRET')
        if 'macOS' not in entries:
            raise ValueError('Desktop Google credentials require a Mac client ID')
        if platform_name not in ('iphoneos', 'iphonesimulator'):
            entries['macOS']['ClientSecret'] = secret
    return {'Enabled': bool(clients), 'Clients': entries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--direct-provider', action='store_true', help='Include the direct model credential for standalone integration checks')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--info-plist', type=Path)
    parser.add_argument('--configuration', default=os.environ.get('CONFIGURATION', 'Debug'))
    args = parser.parse_args()
    try:
        source = Path(os.environ.get('BLOT_ENV_FILE', ROOT / '.env'))
        if not source.is_absolute():
            source = ROOT / source
        env = read_environment(source)
        result = configuration(env, args.configuration, direct_provider=args.direct_provider and not args.info_plist)
        if args.output:
            atomic_write(args.output, plistlib.dumps(result, sort_keys=True))
        if args.info_plist:
            info = plistlib.loads(args.info_plist.read_bytes())
            info['NSAppTransportSecurity'] = provider_transport_security(result)
            types = [v for v in info.get('CFBundleURLTypes', []) if v.get('CFBundleURLName') not in ['dev.blot.account', 'dev.blot.google-oauth']]
            types.append({'CFBundleURLName': 'dev.blot.account', 'CFBundleURLSchemes': ['blot-agent-macos', 'blot-agent-ios']})
            clients = result['GoogleClientIDs']
            if clients:
                types.append({'CFBundleURLName': 'dev.blot.google-oauth', 'CFBundleURLSchemes': ['.'.join(reversed(clients['iOS'].split('.')))]})
            info['CFBundleURLTypes'] = types
            info['BlotMessagingClientIDs'] = result['MessagingClientIDs']
            atomic_write(args.info_plist, plistlib.dumps(info, sort_keys=False))
            if args.output:
                oauth = google_oauth_configuration(env if result['Profile'] == 'personal-dev' else {}, clients,
                                                   os.environ.get('PLATFORM_NAME'))
                atomic_write(args.output.parent / 'GoogleOAuth.plist', plistlib.dumps(oauth, sort_keys=False))
        print("Apple " + result['Profile'] + " configuration validated; Google OAuth "
              + ('configured' if result['GoogleClientIDs'] else 'not configured'))
    except (ValueError, OSError, UnicodeError):
        # Validation errors contain names only; filesystem exceptions can include secret paths.
        failure = sys.exc_info()[1]
        parser.exit(2, ('Configuration error: ' + str(failure) if isinstance(failure, ValueError) else 'Cannot read build configuration') + '\n')


if __name__ == '__main__':
    main()
