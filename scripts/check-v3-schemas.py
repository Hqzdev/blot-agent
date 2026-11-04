#!/usr/bin/env python3
"""Validate every public fixture and enum variant with JSON Schema 2020-12.

Install the test-only dependency with: python3 -m pip install jsonschema==4.26.0
"""
import json
from pathlib import Path
import sys
from jsonschema import Draft202012Validator, FormatChecker
root = Path(__file__).resolve().parents[1]
schema = json.loads((root / 'contracts/v3/entities.schema.json').read_text())
Draft202012Validator.check_schema(schema)
for name in ['command', 'event']:
    Draft202012Validator.check_schema(json.loads((root / f'contracts/v3/{name}.schema.json').read_text()))
forbidden = {'password', 'passwordHash', 'privateKey', 'refreshToken', 'apiKey', 'pairingSecret'}
assert not forbidden.intersection({k for definition in schema['$defs'].values() for k in definition.get('properties', {})})
count = 0
for file in sorted((root / 'fixtures/v3').rglob('*.json')):
    if file.name in ['states.json', 'presentation.json']: continue
    name = file.stem.split('-')[0]
    record_schema = dict(schema, **{'$ref': '#/$defs/' + name})
    record_schema.pop('oneOf', None)
    Draft202012Validator(record_schema, format_checker=FormatChecker()).validate(json.loads(file.read_text()))
    count += 1
print(f'PASS: {count} fixtures, all schema definitions and secret-field boundaries')
