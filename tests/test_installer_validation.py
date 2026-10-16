"""Offline installer validation tests. Run: python -m unittest discover -s tests -v.

Only extracted validation functions run; installers/downloads are never executed.
PowerShell behavior tests run when powershell or pwsh is available.
"""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
COMMON = {
    'tools/runtime_profiles.py', 'tools/python_runtime.py',
    'tools/ffmpeg_runtime.py', 'main/compute_telemetry.py',
    'main/compute_backend.py', 'gui/splash_ipc.py', 'gui/tk_compat.py',
}
WINDOWS = {'tools/uv_bootstrap.ps1', 'tools/windows_python.ps1'}
MACOS = {'tools/macos_python.sh'}


def contents(name):
    return (ROOT / name).read_text(encoding='utf-8')


def shell_function(name):
    return 'installation_complete() {' + contents(name).split('installation_complete() {', 1)[1].split('\nlegacy_version()', 1)[0]


def shell_files(name):
    loop = shell_function(name).split('for file in ', 1)[1].split('; do', 1)[0]
    return set(loop.replace('\\\n', ' ').split())


def windows_files(name):
    text = contents(name)
    block = (text.split('$files=@(', 1)[1].split(');', 1)[0] if name.endswith('.bat')
             else text.split('$required = @(', 1)[1].split('\n    )', 1)[0])
    return set(re.findall(r'[\"\']([^\"\']+)[\"\']', block))


def fixture(root, files):
    for name in files:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('fixture\n')
    (root / 'VERSION').write_text('1.2.1\n')
    (root / 'pyproject.toml').write_text('[project]\nname = "amadeus"\n')


class ValidationTests(unittest.TestCase):
    def test_bootstrap_lists(self):
        for name in ('AMADEUS-Setup.sh', 'AMADEUS-Setup.command'):
            self.assertTrue(COMMON <= shell_files(name), name)
        batch = windows_files('AMADEUS-Setup.bat')
        helper = windows_files('AMADEUS-Setup.ps1')
        self.assertEqual(batch, helper)
        self.assertTrue(COMMON | WINDOWS <= helper)

    @unittest.skipUnless(shutil.which('bash'), 'bash unavailable')
    def test_shell_validation(self):
        for name, system, platform_files in (
            ('AMADEUS-Setup.sh', 'Linux', set()),
            ('AMADEUS-Setup.command', 'Darwin', MACOS | {'AMADEUS.command'}),
        ):
            function = shell_function(name)
            with tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                fixture(root, shell_files(name) | COMMON | platform_files)
                # Override uname independently of validator arguments.
                script = function + '\nuname() { echo ' + system + '; }\ninstallation_complete "$1"\n'
                def validate():
                    return subprocess.run(['bash', '-c', script, '--', str(root)], capture_output=True).returncode
                self.assertEqual(validate(), 0, name)
                self.assertFalse((root / '.venv').exists())
                for relative in sorted(COMMON | (MACOS if system == 'Darwin' else set())):
                    with self.subTest(installer=name, missing=relative):
                        path = root / relative
                        path.unlink()
                        self.assertNotEqual(validate(), 0)
                        path.write_text('')
                        self.assertNotEqual(validate(), 0)
                        path.write_text('fixture\n')
                        self.assertEqual(validate(), 0)

    @unittest.skipUnless(shutil.which('powershell') or shutil.which('pwsh'), 'PowerShell unavailable')
    def test_powershell_validation(self):
        executable = shutil.which('powershell') or shutil.which('pwsh')
        text = contents('AMADEUS-Setup.ps1')
        function = 'function Test-CompleteInstallation' + text.split('function Test-CompleteInstallation', 1)[1].split('\nfunction Test-LegacyVersion', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory) / 'app'
            fixture(root, windows_files('AMADEUS-Setup.ps1') | COMMON | WINDOWS)
            script = pathlib.Path(directory) / 'check.ps1'
            script.write_text('param([string]$Root)\n' + function + '\nif (Test-CompleteInstallation $Root) { exit 0 }; exit 1\n')
            def validate():
                return subprocess.run([executable, '-NoProfile', '-File', str(script), str(root)], capture_output=True).returncode
            self.assertEqual(validate(), 0)
            self.assertFalse((root / '.venv').exists())
            for relative in sorted(COMMON | WINDOWS):
                with self.subTest(missing=relative):
                    path = root / relative
                    path.unlink()
                    self.assertNotEqual(validate(), 0)
                    path.write_text('')
                    self.assertNotEqual(validate(), 0)
                    path.write_text('fixture\n')
                    self.assertEqual(validate(), 0)


if __name__ == '__main__':
    unittest.main()
