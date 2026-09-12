#!/usr/bin/env python3
"""Validate native language resources without building or launching the application."""
import json
import pathlib
import plistlib
import re

root = pathlib.Path(__file__).resolve().parents[2]
count = 0
for resources in sorted((root / 'Sources').glob('**/Resources')):
    english = resources / 'en.lproj/Localizable.strings'
    if not english.exists():
        continue
    tables = []
    plural_keys = set()
    for language in ['en', 'ja', 'zh-Hans']:
        path = resources / f'{language}.lproj/Localizable.strings'
        table = {}
        for line in path.read_text().splitlines():
            match = re.fullmatch(r'("(?:\\.|[^"\\])*") = ("(?:\\.|[^"\\])*");', line)
            assert match, f'Invalid strings syntax: {path}: {line}'
            key, value = map(json.loads, match.groups())
            assert key not in table, f'Duplicate key: {path}: {key}'
            assert value, f'Empty translation: {path}: {key}'
            table[key] = value
        tables.append(table)
        plural_path = path.with_suffix('.stringsdict')
        if plural_path.exists():
            plurals = plistlib.loads(plural_path.read_bytes())
            if language == 'en':
                plural_keys = set(plurals)
            assert set(plurals) == plural_keys, f'Plural keys differ: {plural_path}'
    assert set(tables[0]) == set(tables[1]) == set(tables[2]), f'Language keys differ: {resources}'
    for key in tables[0]:
        signatures = [sorted(re.findall(r'%(?:\d+\$)?(?:\.\d+)?(?:@|ld|d|f)', table[key].replace('%%', ''))) for table in tables]
        assert signatures[0] == signatures[1] == signatures[2], f'Format arguments differ: {resources}: {key}'
    for source in resources.parent.glob('*.swift'):
        for key_literal in re.findall(r'L10n\.(?:text|message)\(("(?:\\.|[^"\\])*")', source.read_text()):
            key = json.loads(key_literal)
            assert key in tables[0] or key in plural_keys, f'Missing resource: {source}: {key}'
    count += 1
assert count > 0
print(f'Localization contract passed for {count} resource bundles')
