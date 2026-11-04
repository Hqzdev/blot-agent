import importlib.util
from pathlib import Path
import tempfile
import subprocess
import sys
import plistlib
import unittest

spec = importlib.util.spec_from_file_location('apple_config', Path(__file__).resolve().parents[1] / 'apple_build_configuration.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class AppleConfigurationTests(unittest.TestCase):
    def environment(self):
        return {'BLOT_GIGACHAT_AUTH_KEY': 'dGVzdDpvbmx5', 'BLOT_GIGACHAT_MODEL': 'GigaChat',
                'BLOT_AUTH_URL': 'https://example.com/login', 'BLOT_SMTP_PASSWORD': 'server-only-secret'}

    def test_no_server_secret_is_embedded_and_auth_origin_is_derived(self):
        value = config.configuration(self.environment(), 'Debug')
        self.assertEqual(value['AccountServiceURL'], 'https://example.com')
        self.assertNotIn('server-only-secret', repr(value))
        self.assertIn('ProviderCA', value)

    def test_release_is_rejected_without_including_secret_values(self):
        with self.assertRaisesRegex(ValueError, 'personal Debug'):
            config.configuration(self.environment(), 'Release')

    def test_missing_and_invalid_parameters_report_only_names(self):
        for name, value in [('BLOT_GIGACHAT_AUTH_KEY', 'sensitive-invalid-key'), ('BLOT_AUTH_URL', 'http://example.com/login'),
                            ('BLOT_RUN_TOKEN_BUDGET', 'sensitive-invalid-budget')]:
            env = self.environment()
            env[name] = value
            with self.assertRaises(ValueError) as error:
                config.configuration(env, 'Debug')
            self.assertNotIn(value, str(error.exception))

    def test_dotenv_is_data_and_process_values_override_file(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'env'
            source.write_text('BLOT_GIGACHAT_MODEL="$(touch never-execute)"\n')
            self.assertEqual(config.read_environment(source, {})['BLOT_GIGACHAT_MODEL'], '$(touch never-execute)')
            self.assertEqual(config.read_environment(source, {'BLOT_GIGACHAT_MODEL': 'override'})['BLOT_GIGACHAT_MODEL'], 'override')

    def test_relative_env_override_works_from_outside_repository(self):
        config.ROOT.joinpath('.build').mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=config.ROOT / '.build') as directory:
            source = Path(directory) / 'input.env'
            output = Path(directory) / 'AppleInstallation.plist'
            source.write_text('\n'.join(key + '=' + value for key, value in self.environment().items()))
            result = subprocess.run([sys.executable, str(config.ROOT / 'scripts/apple_build_configuration.py'), '--output', str(output)],
                                    cwd='/tmp', env={'BLOT_ENV_FILE': str(source.relative_to(config.ROOT))}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(plistlib.loads(output.read_bytes())['AuthURL'], 'https://example.com/login')

    def test_google_native_ids_must_both_be_configured(self):
        env = self.environment()
        env['BLOT_GOOGLE_MACOS_CLIENT_ID'] = '123-test.apps.googleusercontent.com'
        with self.assertRaisesRegex(ValueError, 'both'):
            config.configuration(env, 'Debug')

    def test_packaged_app_allows_manual_ca_validation_only_for_provider_hosts(self):
        env = self.environment()
        env['BLOT_GIGACHAT_API_URL'] = 'https://api.example.com/v1/'
        env['BLOT_GIGACHAT_OAUTH_URL'] = 'https://oauth.example.com:9443/api/v2/oauth'
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'input.env'
            info = Path(directory) / 'Info.plist'
            source.write_text('\n'.join(key + '=' + value for key, value in env.items()))
            info.write_bytes(plistlib.dumps({'CFBundleIdentifier': 'dev.blot.test'}))
            result = subprocess.run([sys.executable, str(config.ROOT / 'scripts/apple_build_configuration.py'),
                                     '--info-plist', str(info)],
                                    env={'BLOT_ENV_FILE': str(source)}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            value = plistlib.loads(info.read_bytes())
            self.assertEqual(value['CFBundleIdentifier'], 'dev.blot.test')
            ats = value['NSAppTransportSecurity']
            self.assertEqual(set(ats), {'NSExceptionDomains'})
            self.assertEqual(set(ats['NSExceptionDomains']), {'api.example.com', 'oauth.example.com'})
            for domain in ats['NSExceptionDomains'].values():
                self.assertTrue(domain['NSExceptionAllowsInsecureHTTPLoads'])
                self.assertEqual(domain['NSExceptionMinimumTLSVersion'], 'TLSv1.2')
                self.assertNotIn('NSIncludesSubdomains', domain)
                self.assertNotIn('NSExceptionRequiresForwardSecrecy', domain)


if __name__ == '__main__':
    unittest.main()
