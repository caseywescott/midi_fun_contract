#!/usr/bin/env python3
"""Run every ignored composer fixture in its own process, then compare all JS references.
Usage: python3 scripts/verify_music_parity.py --out /tmp/beast-music-parity
Requires the pinned Scarb/Foundry tools and installed offchain/beast-sound dependencies.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
COMPOSER = ROOT / 'beasts/beast_composer'
COMPARISONS = ['beast_v3', 'full_midi', 'v11', 'genesis', 'name', 'seeded',
               'drift', 'sound_check', 'yeti', 'echo', 'editions', 'editions_drift', 'low_tonic']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    out = args.out.resolve()
    # Refuse to mix a new run with old captures or overwrite their provenance.
    out.mkdir(parents=True, exist_ok=False)
    fixtures = []
    for source in sorted((COMPOSER / 'src').rglob('*.cairo')):
        module = '::'.join(source.relative_to(COMPOSER / 'src').with_suffix('').parts)
        if module == 'composition::yeti':
            module += '::degree_tests'
        for attributes, name in re.findall(r'((?:#\[[^\]]+\]\s*)+)fn\s+(\w+)', source.read_text()):
            if '#[test]' in attributes and '#[ignore]' in attributes:
                fixtures.append(f'beast_composer::{module}::{name}')
    if not fixtures or len(set(fixtures)) != len(fixtures):
        raise RuntimeError('Empty or duplicate ignored-fixture inventory')
    report = {'source': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
              'fixtures': fixtures, 'completed': [], 'comparisons': []}
    combined = out / 'captures.log'
    with combined.open('w') as all_logs:
        for index, fixture in enumerate(fixtures):
            log = out / f'{index:03d}-{fixture.split("::")[-1]}.log'
            command = ['snforge', 'test', '--max-n-steps', '4294967295', '--max-threads', '2',
                       '--exact', fixture, '--include-ignored']
            with log.open('w') as target:
                result = subprocess.run(command, cwd=COMPOSER, stdout=target, stderr=subprocess.STDOUT)
            captured = log.read_text(errors='replace')
            if result.returncode or f'[PASS] {fixture} ' not in captured or 'Tests: 1 passed, 0 failed' not in captured:
                raise RuntimeError(f'Fixture failed or did not run exactly once: {fixture}; see {log}')
            all_logs.write(captured + '\n')
            all_logs.flush()
            report['completed'].append(fixture)
            (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
            print(f'{index + 1}/{len(fixtures)} PASS {fixture}', flush=True)
    for name in COMPARISONS:
        log = out / f'compare-{name}.log'
        with log.open('w') as target:
            result = subprocess.run(['node', str(ROOT / f'scripts/{name}_parity.mjs'), str(combined)],
                                    cwd=ROOT, stdout=target, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f'JS/Cairo comparison failed: {name}; see {log}')
        report['comparisons'].append(name)
        print(log.read_text().strip(), flush=True)
    report['captures_sha256'] = hashlib.sha256(combined.read_bytes()).hexdigest()
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(f'PASS {len(fixtures)} ignored fixtures and {len(COMPARISONS)} JS/Cairo comparisons')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
