#!/usr/bin/env python3
"""Reproduce PR34's four TrackWriter annotation tradeoff (stdlib; see bench/README.md)."""
import argparse
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BASELINE = '61379cb6425cb99b9b715e5f68efc2658173ffdf'
TEMPLATE = Path(__file__).with_suffix('.cairo')
SCHEMA = 'midi_bench/writer-tradeoff/1'
PREFIX = 'midi_bench::writer_pr34::row_'
SUMMARY = dict(passed=47, failed=0, ignored=0, filtered=286)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def json_hash(value):
    return sha(json.dumps(value, sort_keys=True, separators=(',', ':')).encode())


def workloads():
    rows = []
    for kind, label, species in [(0, 'check', [1, 64]),
                                 (1, 'song', [1, 21, 32, 44, 68]), (2, 'named', [44])]:
        for sid in species:
            for fx in range(4):
                rows.append(dict(name=f'pure_{label}_{sid}_{fx}', route='pure', kind=kind,
                                 sid=sid, fx=fx, contract='BeastPureComposer', selector='compose'))
    for sid in [1, 64]:
        for ceiling in [1, 127]:
            rows.append(dict(name=f'pure_check_boundary_{sid}_{ceiling}', route='pure', kind=3,
                             sid=sid, fx=0, ceiling=ceiling,
                             contract='BeastPureComposer', selector='compose'))
    for sid in [1, 21, 32, 68]:
        for shiny in range(2):
            rows.append(dict(name=f'legacy_song_{sid}_{shiny}', route='legacy', sid=sid,
                             shiny=shiny, contract='BeastMidiProvider', selector='get_midi'))
    for token in [1, 42, 100000]:
        rows.append(dict(name=f'scale_{token}', route='scale', token=token,
                         contract='ScaleMidiProvider', selector='get_midi'))
    return rows


CASES = workloads()


def provenance(archive):
    return dict(schema=SCHEMA, baseline=BASELINE, archive_sha256=sha(archive),
                script_sha256=sha(Path(__file__).read_bytes()),
                template_sha256=sha(TEMPLATE.read_bytes()), cases=CASES)


def source_archive():
    result = subprocess.run(['git', 'archive', '--format=tar', BASELINE], cwd=ROOT,
                            capture_output=True)
    require(result.returncode == 0,
            f'baseline {BASELINE} must exist locally: {result.stderr.decode().strip()}')
    return result.stdout


def harness(rows=None):
    frozen = ''
    if rows is not None:
        arms = []
        for i, row in enumerate(rows):
            arrays = [f'array![{", ".join(map(str, row[key]))}]' for key in ['input', 'out']]
            arms.append(f'        {i} => ({arrays[0]}, {arrays[1]}),')
        frozen = ("#[cfg(not(feature: 'record'))]\n"
                  'fn frozen(case: u32) -> (Array<felt252>, Array<felt252>) {\n    match case {\n'
                  + '\n'.join(arms) + '\n        _ => panic!("unknown writer case"),\n    }\n}\n')
    tests = []
    for i, row in enumerate(CASES):
        if row['route'] == 'pure':
            args = [i, row['kind'], row['sid'], row['fx'], row.get('ceiling', 127)]
        elif row['route'] == 'legacy':
            args = [i, row['sid'], row['shiny']]
        else:
            args = [i, row['token']]
        call = row['route']
        tests.append(f'#[test]\nfn row_{i:03}() {{ {call}({", ".join(map(str, args))}); }}')
    return TEMPLATE.read_text().replace('// FROZEN_ARRAYS', frozen).replace(
        '// CASE_TESTS', '\n\n'.join(tests))


def prepare(directory, archive, rows=None, no_annotations=False):
    directory.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        source_files = [m.name for m in tar.getmembers() if m.isfile() or m.issym()]
        tar.extractall(directory, filter='data')
    smf = directory / 'core/midi/src/smf.cairo'
    if no_annotations:
        source = smf.read_text()
        for name in ['message', 'control', 'meta', 'finish_at']:
            old = f'    #[inline(never)]\n    fn {name}('
            require(source.count(old) == 1, f'missing unique TrackWriter.{name} annotation')
            source = source.replace(old, f'    fn {name}(')
        smf.write_text(source)
    lib = directory / 'bench/src/lib.cairo'
    lib.write_text(lib.read_text() + '\n#[cfg(test)]\nmod writer_pr34;\n')
    manifest = directory / 'bench/Scarb.toml'
    target = '    "beast_contracts::provider::BeastMidiProvider",'
    require(manifest.read_text().count(target) == 1, 'missing bench external-contract list')
    manifest.write_text(manifest.read_text().replace(target, target + '\n'
                        '    "beast_contracts::pure_composer::BeastPureComposer",'))
    (directory / 'bench/src/writer_pr34.cairo').write_text(harness(rows))
    spec = importlib.util.spec_from_file_location('writer_gas_bench',
                                                 directory / 'bench/scripts/gas_bench.py')
    gas = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gas)
    gas.writer_sources = source_files + ['bench/src/writer_pr34.cairo']
    gas.CLASSES.append(('BeastPureComposer', 'beast_contracts',
                       'beast_contracts::pure_composer::BeastPureComposer'))
    return gas


def source_hash(gas):
    # Hash the archived inputs and generated harness, excluding newly created build caches.
    directory = Path(gas.ROOT)
    values = {}
    for name in gas.writer_sources:
        path = directory / name
        values[name] = sha(('link:' + str(path.readlink())).encode() if path.is_symlink()
                           else path.read_bytes())
    return json_hash(values)


def capture(gas, output, label, threads, record=False, classes=None):
    t, tools = gas.tools()
    env = gas.tool_env(t)
    before = source_hash(gas)
    classes = classes if classes is not None else gas.build_production(t, env)
    command = gas.snforge_cmd(t, threads, ['writer_pr34'] + (['--features', 'record'] if record else []))
    log = output / f'{label}.log'
    code, wall, peak = gas.run_measured(command, gas.BENCH, env, str(log))
    require(code == 0, f'{label} failed ({code}); see {log}')
    identity = gas.artifact_identity(t, classes)
    require(identity['all_identical'], f'{label}: bench classes differ from production')
    results, traces, summary, problems = gas.parse_output(log.read_text())
    require(not problems, f'{label}: parse errors: {problems}')
    require(summary == SUMMARY, f'{label}: unexpected summary {summary}')
    names = {f'{PREFIX}{i:03}' for i in range(len(CASES))}
    require(set(results) == names and set(traces) == names, f'{label}: missing/extra cases/traces')
    rows = []
    for i, case in enumerate(CASES):
        name = f'{PREFIX}{i:03}'
        require(results[name]['status'] == 'PASS', f'{name} did not pass')
        for root in traces[name]:
            gas.check_tree(root, problems, name)
        hits = [root for root in traces[name]
                if root['contract'] == case['contract'] and root['selector'] == case['selector']]
        require(len(hits) == 1, f'{name}: expected one top-level contract selector')
        rows.append(dict(**case, gas=hits[0]['gas'], nested=gas.flatten(hits[0]['calls'])))
    require(not problems, f'{label}: invalid gas tree: {problems}')
    require(before == source_hash(gas), f'{label}: sources/locks changed during capture')
    snapshot = dict(label=label, tools=tools,
                    tool_sha256={k: gas.sha256_file(v['path']) for k, v in tools.items()},
                    source_sha256=before, harness_sha256=gas.sha256_file(
                        Path(gas.BENCH) / 'src/writer_pr34.cairo'),
                    command=command, wall_seconds=wall, peak_rss_mb=peak,
                    measurement=gas.MEASUREMENT, classes=classes,
                    artifact_identity=identity, rows=rows)
    (output / f'{label}.json').write_text(json.dumps(snapshot, indent=2) + '\n')
    print(f'{label}: 47/47 passed; production artifact identity verified ({wall}s)', flush=True)
    return snapshot


def read_record(path):
    rows = {}
    for match in re.finditer(r'^WRITER case=(\d+) input=(\[[^\n]*?\]) out=(\[[^\n]*?\])$',
                             path.read_text(), re.MULTILINE):
        i = int(match[1])
        require(i not in rows, f'duplicate recorded row {i}')
        rows[i] = dict(input=json.loads(match[2]), out=json.loads(match[3]))
    require(set(rows) == set(range(len(CASES))), 'missing/extra baseline Serde recordings')
    for row in rows.values():
        require(all(type(x) is int and 0 <= x < 2**251 + 17 * 2**192 + 1
                    for values in row.values() for x in values), 'invalid recorded felt')
    return [rows[i] for i in range(len(CASES))]


def compare(args, archive, authority):
    fixture_path = args.baseline.resolve()
    require(fixture_path.is_file(), 'run --capture-baseline explicitly first; no automatic capture')
    fixture_bytes = fixture_path.read_bytes()
    fixture = json.loads(fixture_bytes)
    require(fixture['provenance'] == authority,
            'fixture provenance differs: only the pinned baseline and unchanged harness are accepted')
    rows = fixture['rows']
    require(len(rows) == len(CASES) and json_hash(rows) == fixture['rows_sha256'],
            'fixture rows/hash differ')
    snapshots = {}
    with tempfile.TemporaryDirectory(prefix='writer-tradeoff-') as temp:
        for label, no_annotations in [('outlined', False), ('without_annotations', True)]:
            directory = Path(temp) / label
            gas = prepare(directory, archive, rows, no_annotations)
            runs = [capture(gas, args.out, f'{label}-a', args.threads)]
            runs.append(capture(gas, args.out, f'{label}-b', args.threads, classes=runs[0]['classes']))
            require(runs[0]['rows'] == runs[1]['rows'], f'{label}: independent gas captures differ')
            require(runs[0]['tools'] == runs[1]['tools'] and
                    runs[0]['tool_sha256'] == runs[1]['tool_sha256'], f'{label}: tools changed')
            snapshots[label] = runs[0]
        a, b = snapshots.values()
        require(a['tools'] == b['tools'] and a['tool_sha256'] == b['tool_sha256'],
                'variant toolchains differ')
        summary = dict(provenance=authority, authority_sha256=sha(fixture_bytes),
                       full_serde_equal=True, independent_captures_per_variant=2,
                       classes=[dict(contract=x['contract'], outlined=x['casm_bytecode_len'],
                                     without_annotations=y['casm_bytecode_len'],
                                     delta=y['casm_bytecode_len'] - x['casm_bytecode_len'])
                                for x, y in zip(a['classes'], b['classes'])],
                       rows=[dict(name=x['name'], outlined=x['gas'], without_annotations=y['gas'],
                                  delta=y['gas'] - x['gas'],
                                  percent=round(100 * (y['gas'] / x['gas'] - 1), 4))
                             for x, y in zip(a['rows'], b['rows'])])
        if args.check_fault:
            # Mutate the real compiled source, never the expected values, and restore it even on error.
            smf = directory / 'core/midi/src/smf.cairo'
            original = smf.read_text()
            old = 'self.meta(time, 0x51, data.span());'
            require(original.count(old) == 1, 'missing unique tempo meta call')
            try:
                smf.write_text(original.replace(old, 'self.meta(time, 0x52, data.span());'))
                t, _ = gas.tools()
                log = args.out / 'fault-control.log'
                command = gas.snforge_cmd(t, args.threads, ['writer_pr34::row_000'])
                code, _, _ = gas.run_measured(command, gas.BENCH, gas.tool_env(t), str(log))
                results, _, count, problems = gas.parse_output(log.read_text())
                require(code != 0 and not problems and
                        count == dict(passed=0, failed=1, ignored=0, filtered=332) and
                        results.get(f'{PREFIX}000', {}).get('status') == 'FAIL' and
                        'writer full output changed' in log.read_text(),
                        f'fault control did not fail the intended full-output assertion; see {log}')
                summary['fault_control'] = 'compiled tempo 0x51 -> 0x52 rejected by full Serde assertion'
                print('fault-control: intended full-output assertion failed', flush=True)
            finally:
                smf.write_text(original)
    require(fixture_path.read_bytes() == fixture_bytes, 'baseline fixture changed during comparison')
    (args.out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(f'Paired measurements and CASM sizes: {args.out / "summary.json"}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True, help='external full-Serde baseline JSON')
    parser.add_argument('--capture-baseline', action='store_true',
                        help='explicitly record only pinned 61379cb; refuse to overwrite')
    parser.add_argument('--out', type=Path, required=True, help='new external log/report directory')
    parser.add_argument('--threads', type=int, choices=[1, 2], default=2)
    parser.add_argument('--check-fault', action='store_true', help='also prove a compiled tempo fault fails')
    args = parser.parse_args()
    require(not args.capture_baseline or not args.check_fault, '--check-fault belongs to comparison')
    require(not args.capture_baseline or not args.baseline.exists(), 'baseline exists; refusing overwrite')
    require(not args.out.exists(), '--out must be a new directory')
    args.out = args.out.resolve()
    require(not args.out.is_relative_to(ROOT) and not args.baseline.resolve().is_relative_to(ROOT),
            'keep captures/reports outside the checkout (for example /tmp)')
    archive = source_archive()
    authority = provenance(archive)
    args.out.mkdir(parents=True)
    if args.capture_baseline:
        with tempfile.TemporaryDirectory(prefix='writer-baseline-') as temp:
            gas = prepare(Path(temp) / 'baseline', archive)
            capture(gas, args.out, 'baseline-record', args.threads, record=True)
            rows = read_record(args.out / 'baseline-record.log')
            fixture = dict(provenance=authority, rows=rows, rows_sha256=json_hash(rows))
            # Exclusive creation prevents an accidental/racing overwrite of authority.
            with args.baseline.open('x') as out:
                json.dump(fixture, out, indent=2)
                out.write('\n')
        print(f'Captured pinned baseline {BASELINE}: {args.baseline}')
    else:
        compare(args, archive, authority)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, KeyError, ValueError) as error:
        raise SystemExit(f'writer_tradeoff: {error}')
