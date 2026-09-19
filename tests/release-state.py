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
    lines = text.splitlines()
    for prefix, expected in (
        ('Overlay:', 'Overlay: ready'),
        ('Pending recovery:', 'Pending recovery: False'),
        ('Needs sync:', 'Needs sync: False'),
    ):
        if [line for line in lines if line.startswith(prefix)] != [expected]:
            raise ValueError(f'rk is not ready for release: expected {expected}')


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
