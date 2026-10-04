"""Desktop release/offline packaging and genuine JSON bootstrap integration."""
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('release', ROOT / 'tools/release.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)
BASE = 'https://raw.githubusercontent.com/example/autobuilder/main'


class ReleaseTests(unittest.TestCase):
    def fixture(self, target):
        import shutil
        shutil.copytree(ROOT / 'autobuilder', target / 'autobuilder',
                        ignore=shutil.ignore_patterns('data', 'logs'))
        for name in ('startup.lua', 'update.lua'):
            shutil.copy(ROOT / name, target / name)
        release.generate(target, BASE, '0.2.1')

    def test_manifest_hashes_and_deterministic_generation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            before = (root / 'manifest.json').read_bytes()
            release.generate(root, BASE, '0.2.1', check=True)
            self.assertEqual(before, (root / 'manifest.json').read_bytes())
            manifest = json.loads(before)
            for entry in manifest['files']:
                data = (root / entry['path']).read_bytes()
                self.assertEqual(entry['sha256'], hashlib.sha256(data).hexdigest())
                self.assertEqual(entry['bytes'], len(data))
                self.assertNotEqual(entry['path'], 'autobuilder/settings.lua')
            for role in release.ROLES:
                selected = {entry['path'] for entry in manifest['files'] if role in entry['roles']}
                for path in selected:
                    code = (root / path).read_text()
                    for module in re.findall(r'require\([\'"](autobuilder[^\'"]+)[\'"]\)', code):
                        dependency = module.replace('.', '/') + '.lua'
                        self.assertTrue(dependency == 'autobuilder/settings.lua' or dependency in selected,
                                        (role, path, dependency))
            (root / 'autobuilder/core/runtime.lua').write_text('return {}')
            with self.assertRaises(ValueError):
                release.generate(root, BASE, '0.2.1', check=True)

    def test_all_offline_roles_and_no_overwriting_existing_output(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'source'
            root.mkdir()
            self.fixture(root)
            for role in release.ROLES:
                output = Path(folder) / role
                release.offline(root, output, role, 17 if role != 'controller' else None)
                receipt = json.loads((output / 'autobuilder/.installation.json').read_text())
                self.assertEqual(receipt['role'], role)
                settings = (output / 'autobuilder/settings.lua').read_text()
                self.assertIn('"controller"' if role == 'controller' else '"worker"', settings)
                if role != 'controller':
                    self.assertIn('17', settings)
                capability = {'builder': 'building', 'logger': 'logging', 'courier': 'courier'}.get(role)
                if capability:
                    self.assertIn(capability + ' = true', settings)
                self.assertTrue((output / 'installer.lua').exists())
                self.assertTrue((output / 'startup.lua').exists())
                for path, meta in receipt['files'].items():
                    self.assertEqual(meta['sha256'], hashlib.sha256((output / path).read_bytes()).hexdigest())
                with self.assertRaises(FileExistsError):
                    release.offline(root, output, role, 17)

    def test_offline_rejects_invalid_configuration_and_stale_artifacts(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / 'source'
            root.mkdir()
            self.fixture(root)
            output = Path(folder) / 'out'
            for role, cid in [('unknown', 1), ('worker', None), ('worker', -1)]:
                with self.assertRaises(ValueError):
                    release.offline(root, output, role, cid)
                self.assertFalse(output.exists())
            (root / 'autobuilder/core/runtime.lua').write_text('broken')
            with self.assertRaises(ValueError):
                release.offline(root, output, 'worker', 1)
            self.assertFalse(output.exists())

    def test_standalone_bootstrap_uses_real_json_and_no_installed_modules(self):
        try:
            from lupa.lua52 import LuaRuntime
        except ImportError:
            self.skipTest('Use .venv/bin/python for Lua bootstrap integration')
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.fixture(root)
            lua = LuaRuntime(unpack_returned_tuples=True)
            lua.execute("package.path=" + json.dumps(str(ROOT / '?.lua') + ';') + '..package.path')
            def to_lua(value):
                if isinstance(value, dict):
                    return lua.table_from({key: to_lua(val) for key, val in value.items()})
                if isinstance(value, list):
                    return lua.table_from([to_lua(val) for val in value])
                return value
            def to_python(value):
                if hasattr(value, 'items'):
                    values = dict(value.items())
                    if values and set(values) == set(range(1, len(values) + 1)):
                        return [to_python(values[i]) for i in range(1, len(values) + 1)]
                    return {k: to_python(v) for k, v in values.items()}
                return value
            env = lua.execute("""
              local e={fs=require('tests.install_support').fs(),turtle={},
                print=function() end,write=function() end,read=function() return '11' end}
              setmetatable(e,{__index=_G}); e._G=e
              e.require=function() error('bootstrap used installed require') end
              return e
            """)
            env.textutils = lua.table_from({
                'serializeJSON': lambda val: json.dumps(to_python(val), sort_keys=True),
                'unserializeJSON': lambda val: to_lua(json.loads(val)),
            })
            # Local binary metadata is not a downloadable release artifact.
            (root / 'autobuilder' / '.unrelated-binary').write_bytes(b'\x80\x00')
            manifest = json.loads((root / 'manifest.json').read_text())
            paths = ['manifest.json'] + [entry['path'] for entry in manifest['files']]
            responses = lua.table_from({BASE + '/' + path: (root / path).read_text()
                                        for path in paths})
            env.http = lua.eval("""function(responses) return {get=function(url)
                local data=responses[url]; assert(data,'missing response '..url)
                return {readAll=function() return data end,close=function() end,getResponseCode=function() return 200 end}
              end} end""")(responses)
            fn = lua.eval('function(code,env) return assert(load(code,"@installer.lua","t",env)) end')(
                (root / 'installer.lua').read_text(), env)
            fn('miner', '11')
            receipt = json.loads(env.fs.files['/autobuilder/.installation.json'])
            self.assertEqual(receipt['role'], 'miner')
            original = env.fs.files['/autobuilder/settings.lua']
            fn('update')
            self.assertEqual(original, env.fs.files['/autobuilder/settings.lua'])
            self.assertFalse(env.fs.exists('/.autobuilder-install/transaction'))
            # Mimic a hard interruption after deleting /installer.lua. Prevent
            # inline rollback too, as if power were lost during recovery.
            env.fs.files['/installer.lua'] = 'return "old bootstrap"'
            env.fs.fault.move = '/installer.lua'
            env.fs.fault.copy = '/installer.lua'
            with self.assertRaises(Exception):
                fn('update')
            self.assertIsNone(env.fs.files['/installer.lua'])
            recovery_code = env.fs.files['/.autobuilder-install/transaction/recover.lua']
            self.assertIsNotNone(recovery_code)
            env.fs.fault.move = None
            env.fs.fault.copy = None
            env.http = None
            recover = lua.eval('function(code,env) return assert(load(code,"@recover.lua","t",env)) end')(
                recovery_code, env)
            recover()
            self.assertEqual(env.fs.files['/installer.lua'], 'return "old bootstrap"')
            self.assertFalse(env.fs.exists('/.autobuilder-install/transaction'))
            # The fleet entry is also standalone: discovery and installation run
            # without the installed require implementation. Profile execution is
            # a separate shell program, verified by Lua/native setup tests.
            env.fs = lua.execute("return require('tests.install_support').fs()")
            env.http = lua.eval("function(r) return {get=function(url) return {readAll=function() return assert(r[url]) end,close=function() end} end} end")(responses)
            lua.eval("""function(e)
              local request;local now=0
              e.os={getComputerID=function() return 12 end,epoch=function() return now end}
              e.peripheral={getNames=function() return {'right'} end,getType=function() return 'modem' end,call=function() return true end}
              e.rednet={isOpen=function() return true end,broadcast=function(m) request=m end,
                receive=function(_,timeout) now=now+timeout*1000;return 11,{version=1,type='fleet_offer',requestId=request.requestId,
                  controllerId=11,release='0.2.1',baseUrl='""" + BASE + """',profile={role='worker',controllerId=11}} end}
              e.shell={run=function(path,arg)
                assert(path=='/autobuilder/fleet_apply.lua' and e.fs.exists(path))
                e.appliedController=e.textutils.unserializeJSON(e.fs.files[arg]).controllerId
                return true
              end}
            end""")(env)
            fleet = lua.eval('function(code,env) return assert(load(code,"@fleet.lua","t",env)) end')(
                (root / 'fleet.lua').read_text(), env)
            fleet('install', '--no-reboot')
            self.assertEqual(env.appliedController, 11)
            self.assertEqual(json.loads(env.fs.files['/autobuilder/.installation.json'])['role'], 'worker')
            self.assertFalse(env.fs.exists('/.autobuilder-fleet-profile.json'))


if __name__ == '__main__':
    unittest.main()
