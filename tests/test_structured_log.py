"""Independent JSON parsing and byte-bound checks for the native-codec log path."""
import json
import unittest
from lupa.lua52 import LuaRuntime, lua_type


def value(obj):
    if lua_type(obj) == 'table':
        return {key: value(item) for key, item in obj.items()}
    return obj


class StructuredLogTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().encode = lambda obj: json.dumps(value(obj), ensure_ascii=True, separators=(',', ':'))
        self.lua.execute("""
          fs=require('tests.support').fs()
          log=require('autobuilder.core.log').new(fs,'events.jsonl',
            {level='INFO',maxBytes=220,backups=2},function() return 100 end,{serializeJSON=encode})
        """)

    def test_records_survive_rotation_and_escaped_messages(self):
        self.lua.execute("""
          for i=1,8 do assert(log:event('delivery',{worker=12,job='task:7:'..i,
            item='minecraft:stone',count=i,message='quoted " and newline\\n'})) end
        """)
        files = value(self.lua.globals().fs.files)
        self.assertEqual(set(files), {'events.jsonl', 'events.jsonl.1', 'events.jsonl.2'})
        rows = []
        for contents in files.values():
            self.assertLessEqual(len(contents.encode()), 220)
            rows.extend(json.loads(line) for line in contents.splitlines())
        self.assertTrue(rows)
        self.assertTrue(all(row['event'] == 'delivery' and row['time'] == 100 for row in rows))
        self.assertTrue(all(row['message'] == 'quoted " and newline\n' for row in rows))

    def test_oversized_event_does_not_truncate_or_replace_previous_records(self):
        self.lua.execute("assert(log:event('assignment',{job='task:7:1',worker=12}))")
        before = value(self.lua.globals().fs.files)
        ok, reason = self.lua.eval("log:event('delivery',{message=string.rep('x',1000)})")
        self.assertFalse(ok)
        self.assertIn('maxBytes', reason)
        self.assertEqual(value(self.lua.globals().fs.files), before)
        self.lua.execute("assert(log:event('completed',{job='task:7:1'}))")
        for contents in value(self.lua.globals().fs.files).values():
            for line in contents.splitlines():
                json.loads(line)

    def test_failed_write_returns_error_without_claiming_success(self):
        self.lua.execute("fs.fault.open='events.jsonl'")
        ok, reason = self.lua.eval("log:event('delivery',{count=3})")
        self.assertFalse(ok)
        self.assertIn('disk full', reason)
        self.assertEqual(value(self.lua.globals().fs.files), {})
