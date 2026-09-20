#!/usr/bin/python3
"""Strict read-only state checks shared by local and SSH release validation."""
import argparse
import json
from pathlib import Path
import sys


def check_image(document, expected):
    try:
        actual = document['status']['booted']['image']['image']['image']
    except (KeyError, TypeError):
        raise ValueError('Missing booted image in bootc status') from None
    if actual != expected:
        raise ValueError(f'Booted image mismatch: expected {expected}, found {actual}')


def check_rk(text):
    try:
        data = json.loads(text)
    except json.JSONDecodeError as error:
        raise ValueError('Invalid rk status JSON') from error
    if data.get('schema') != 1:
        raise ValueError('Unsupported rk status schema')
    if data.get('overlay') != 'ready':
        raise ValueError('RK overlay is not ready')
    if data.get('pending_recovery') is not False:
        raise ValueError('RK pending recovery is not clear')
    if data.get('needs_sync') is not False:
        raise ValueError('RK needs-sync is not clear')
    if not isinstance(data.get('requests'), list):
        raise ValueError('RK requests is not a list')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('check', choices=('image', 'rk'))
    parser.add_argument('file', type=Path)
    parser.add_argument('expected', nargs='?')
    args = parser.parse_args()
    if args.check == 'image':
        if not args.expected:
            parser.error('image requires an exact expected reference')
        check_image(json.loads(args.file.read_text()), args.expected)
    else:
        check_rk(args.file.read_text())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
