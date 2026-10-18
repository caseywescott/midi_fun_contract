#!/usr/bin/env python3
"""Gas benchmark of the production classes: capture, compare, freeze (Python 3 stdlib only).

  python3 bench/scripts/gas_bench.py run --out bench/snapshots/candidate.json [--threads N]
  python3 bench/scripts/gas_bench.py compare base.json cand.json [--markdown] [--fail-on-regression]
  python3 bench/scripts/gas_bench.py test [FILTER]       # run (some) bench tests, no snapshot
  python3 bench/scripts/gas_bench.py freeze --baseline-rev <rev>   # baseline only, see README

`run` builds the production classes at the repository root (`scarb build`), runs the bench
(`snforge test --no-optimization` in bench/), checks that the classes the bench executed are the
production ones byte for byte, and writes one JSON with the gas of every case. It fails on any
failed, ignored, missing, duplicate or unexpected case, a missing call row, or a parse problem.
See bench/README.md for what each number means.
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import threading
import time

BENCH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(BENCH)
CASES_JSON = os.path.join(BENCH, 'expected', 'cases.json')
FROZEN_JSON = os.path.join(BENCH, 'expected', 'frozen.json')
GEN_EXPECTED = os.path.join(BENCH, 'scripts', 'gen_expected.mjs')
WORK = os.path.join(BENCH, 'target', 'gas_bench')

SCHEMA = 'midi_bench/gas-snapshot/1'
TEST_PREFIX = 'midi_bench::tests::'
# The four production classes: root `scarb build` artifacts target/dev/<package>_<contract>.*
CLASSES = [
    ('BeastMidiProvider', 'beast_contracts', 'beast_contracts::provider::BeastMidiProvider'),
    ('BeastSoundComposer', 'beast_contracts', 'beast_contracts::BeastSoundComposer'),
    ('MidiSoundPage', 'midi_contracts', 'midi_contracts::page::MidiSoundPage'),
    ('ScaleMidiProvider', 'midi_contracts', 'midi_contracts::examples::scale::ScaleMidiProvider'),
]
CASM_LIMIT = 81920  # Starknet's maximum CASM bytecode size, felts
# Starknet 0.14.x versioned constants: os_constants.execute_max_sierra_gas, the L2 gas a
# transaction's execution may use. snforge does not enforce it (it caps VM steps instead).
EXECUTE_MAX_SIERRA_GAS = 1_110_000_000
MAX_N_STEPS = 50_000_000  # passed to snforge (its default is 10,000,000 VM steps per test)
DEFAULT_THREADS = 4  # at most half of a current laptop's cores; gas does not depend on it
PRODUCTION_PATHS = ['core', 'beasts', 'Scarb.toml', 'Scarb.lock', '.tool-versions']

# What a gas number means. `compare` refuses snapshots whose definitions differ.
MEASUREMENT = {
    'definition_version': 1,
    'quantity': 'L2 gas (Sierra gas) of the case\'s one top-level call from the test, inclusive of '
                'the calls it makes (e.g. get_midi includes the NFT\'s get_beast_rank)',
    'source': 'the [L2 gas] of that call in `snforge test --trace-components contract-name gas`',
    'tracked_resource': 'sierra-gas',
    'snforge_mode': '--no-optimization (contracts from the bench package\'s starknet-contract '
                    'target, checked identical to the root scarb build)',
    'max_n_steps': MAX_N_STEPS,
    'excludes': 'the test body (deploys, mock setup, output digests) and transaction overheads',
}


def die(msg, code=1):
    print(f'gas_bench: {msg}', file=sys.stderr)
    sys.exit(code)


def sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def sha256_file(path):
    with open(path, 'rb') as f:
        return sha256_bytes(f.read())


def sha256_json(value):
    return sha256_bytes(json.dumps(value, separators=(',', ':')).encode())


def read_json(path):
    with open(path) as f:
        return json.load(f)


def tool_versions(directory):
    out = {}
    with open(os.path.join(directory, '.tool-versions')) as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 2:
                out[parts[0]] = parts[1]
    return out


# ── tools ────────────────────────────────────────────────────────────────────────────────────

def resolve(name, cwd, env_var=None):
    """The real binary `name` resolves to from `cwd` (asdf shims resolved), or $env_var."""
    if env_var and os.environ.get(env_var):
        return os.path.realpath(os.environ[env_var])
    if shutil.which('asdf'):
        r = subprocess.run(['asdf', 'which', name], cwd=cwd, capture_output=True, text=True)
        if r.returncode == 0 and r.stdout.strip():
            return os.path.realpath(r.stdout.strip())
    found = shutil.which(name)
    if not found:
        die(f'{name} not found')
    return os.path.realpath(found)


def version_of(path):
    r = subprocess.run([path, '--version'], capture_output=True, text=True)
    return (r.stdout or r.stderr).strip()


def tools(allow_mismatch=False):
    pins = tool_versions(BENCH)
    t = {
        'scarb': resolve('scarb', BENCH, 'SCARB'),
        'snforge': resolve('snforge', BENCH, 'SNFORGE'),
        'universal_sierra_compiler': resolve('universal-sierra-compiler', BENCH,
                                             'UNIVERSAL_SIERRA_COMPILER'),
        'node': resolve('node', ROOT, 'NODE'),
    }
    info = {k: {'path': p, 'version': version_of(p)} for k, p in t.items()}
    root_scarb = resolve('scarb', ROOT, 'SCARB')
    if root_scarb != t['scarb']:
        die(f'root and bench resolve different scarb binaries: {root_scarb} vs {t["scarb"]}')
    wanted = {'scarb': pins.get('scarb'), 'snforge': pins.get('starknet-foundry')}
    for k, v in wanted.items():
        first = info[k]['version'].split('\n')[0]
        if v and f' {v}' not in f' {first} ' and not allow_mismatch:
            die(f'{k} is "{first}", bench/.tool-versions pins {v} (--allow-tool-mismatch to '
                'override; compare will refuse to mix versions)')
    return t, info


def tool_env(t):
    """snforge runs scarb from PATH: put the resolved scarb first, and pin the Sierra compiler."""
    env = dict(os.environ)
    env['PATH'] = os.path.dirname(t['scarb']) + os.pathsep + env.get('PATH', '')
    env['UNIVERSAL_SIERRA_COMPILER'] = t['universal_sierra_compiler']
    env['SCARB'] = t['scarb']
    env.pop('SNFORGE_BACKTRACE', None)
    return env


# ── git and source hashes ────────────────────────────────────────────────────────────────────

def git(*args, check=True):
    r = subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        die(f'git {" ".join(args)}: {r.stderr.strip()}')
    return r.stdout


def tree_hash(paths=None):
    """sha256 over the working-tree content of the tracked files (under `paths`)."""
    files = git('ls-files', '-z', '--', *(paths or [])).split('\0')
    h = hashlib.sha256()
    n = 0
    for f in sorted(x for x in files if x):
        full = os.path.join(ROOT, f)
        if os.path.islink(full):
            digest = 'link:' + os.readlink(full)
        elif os.path.isfile(full):
            digest = sha256_file(full)
        else:
            digest = 'missing'
        h.update(f'{f}\0{digest}\n'.encode())
        n += 1
    return {'sha256': h.hexdigest(), 'files': n}


def git_info():
    status = [line for line in git('status', '--porcelain').split('\n') if line]
    return {
        'rev': git('rev-parse', 'HEAD').strip(),
        'dirty': bool(status),
        'status': status,
        'tracked_tree': tree_hash(),
        'production_tree': tree_hash(PRODUCTION_PATHS),
        'bench_tree': tree_hash(['bench']),
        'root_scarb_lock_sha256': sha256_file(os.path.join(ROOT, 'Scarb.lock')),
        'bench_scarb_lock_sha256': sha256_file(os.path.join(BENCH, 'Scarb.lock')),
    }


# ── process with peak memory ─────────────────────────────────────────────────────────────────

def _tree_rss(root_pid):
    children = {}
    for p in os.listdir('/proc'):
        if not p.isdigit():
            continue
        try:
            with open(f'/proc/{p}/stat') as f:
                ppid = int(f.read().rsplit(')', 1)[1].split()[1])
            children.setdefault(ppid, []).append(int(p))
        except (OSError, IndexError, ValueError):
            pass
    total, stack, page = 0, [root_pid], os.sysconf('SC_PAGE_SIZE')
    while stack:
        q = stack.pop()
        try:
            with open(f'/proc/{q}/statm') as f:
                total += int(f.read().split()[1]) * page
        except (OSError, IndexError, ValueError):
            pass
        stack.extend(children.get(q, []))
    return total


def run_measured(cmd, cwd, env, log_path):
    """Runs cmd (stdout and stderr to log_path); returns (exit code, wall s, peak tree RSS MB)."""
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, 'w') as log:
        t0 = time.time()
        p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
        peak = [0]
        has_proc = os.path.isdir('/proc')

        def sample():
            while p.poll() is None:
                if has_proc:
                    peak[0] = max(peak[0], _tree_rss(p.pid))
                time.sleep(0.25)
        th = threading.Thread(target=sample, daemon=True)
        th.start()
        code = p.wait()
        th.join()
    return code, round(time.time() - t0, 1), (round(peak[0] / 2**20) if has_proc else None)


# ── production classes and artifact identity ─────────────────────────────────────────────────

def casm_summary(path):
    c = read_json(path)
    return {'casm_bytecode_len': len(c['bytecode']), 'casm_bytecode_sha256': sha256_json(c['bytecode']),
            'casm_file_sha256': sha256_file(path)}


def sierra_summary(path):
    s = read_json(path)
    return {'sierra_program_len': len(s['sierra_program']),
            'sierra_program_sha256': sha256_json(s['sierra_program']),
            'sierra_file_sha256': sha256_file(path)}


def build_production(t, env):
    lock_before = sha256_file(os.path.join(ROOT, 'Scarb.lock'))
    r = subprocess.run([t['scarb'], 'build'], cwd=ROOT, env=env, capture_output=True, text=True)
    if r.returncode != 0:
        die(f'root scarb build failed:\n{r.stdout}\n{r.stderr}')
    if sha256_file(os.path.join(ROOT, 'Scarb.lock')) != lock_before:
        die('root scarb build changed Scarb.lock')
    out = []
    for contract, package, module in CLASSES:
        base = os.path.join(ROOT, 'target', 'dev', f'{package}_{contract}')
        row = {'contract': contract, 'package': package, 'module': module,
               **casm_summary(base + '.compiled_contract_class.json'),
               **sierra_summary(base + '.contract_class.json'), 'casm_limit': CASM_LIMIT}
        row['casm_headroom'] = CASM_LIMIT - row['casm_bytecode_len']
        out.append(row)
    return out


def artifact_identity(t, production):
    """The bench's copies of the four classes (every starknet_artifacts.json snforge may load) are
    the production ones: same Sierra class file, same scarb CASM, and the CASM the pinned
    universal-sierra-compiler (the compiler snforge runs) makes from that Sierra."""
    dev = os.path.join(BENCH, 'target', 'dev')
    manifests = sorted(f for f in os.listdir(dev) if f.endswith('.starknet_artifacts.json'))
    if 'midi_bench.starknet_artifacts.json' not in manifests:
        die('bench/target/dev/midi_bench.starknet_artifacts.json missing (not a --no-optimization build?)')
    usc_dir = os.path.join(WORK, 'usc')
    os.makedirs(usc_dir, exist_ok=True)
    rows, ok = [], True
    for prod in production:
        copies = []
        for m in manifests:
            for c in read_json(os.path.join(dev, m))['contracts']:
                if c['module_path'] != prod['module']:
                    continue
                sierra_path = os.path.join(dev, c['artifacts']['sierra'])
                copy = {'manifest': m, 'sierra': c['artifacts']['sierra'], **sierra_summary(sierra_path)}
                copy['sierra_identical'] = copy['sierra_file_sha256'] == prod['sierra_file_sha256']
                if c['artifacts'].get('casm'):
                    cs = casm_summary(os.path.join(dev, c['artifacts']['casm']))
                    copy['scarb_casm_bytecode_sha256'] = cs['casm_bytecode_sha256']
                    copy['scarb_casm_identical'] = cs['casm_bytecode_sha256'] == prod['casm_bytecode_sha256']
                out = os.path.join(usc_dir, f'{m}.{prod["contract"]}.casm.json')
                r = subprocess.run([t['universal_sierra_compiler'], 'compile-contract', '--sierra-path',
                                    sierra_path, '--output-path', out], capture_output=True, text=True)
                if r.returncode != 0:
                    die(f'universal-sierra-compiler failed on {sierra_path}: {r.stderr}')
                usc = read_json(out)
                copy['usc_casm_bytecode_sha256'] = sha256_json(usc['bytecode'])
                copy['usc_casm_identical'] = (
                    copy['usc_casm_bytecode_sha256'] == prod['casm_bytecode_sha256']
                    and usc['hints'] == read_json(os.path.join(
                        ROOT, 'target', 'dev', f'{prod["package"]}_{prod["contract"]}.compiled_contract_class.json'))['hints'])
                copies.append(copy)
        good = bool(copies) and all(
            c['sierra_identical'] and c['usc_casm_identical'] and c.get('scarb_casm_identical', True)
            for c in copies)
        ok = ok and good
        rows.append({'contract': prod['contract'], 'identical': good, 'copies': copies})
    return {'mode': '--no-optimization', 'all_identical': ok, 'classes': rows}


# ── snforge output ───────────────────────────────────────────────────────────────────────────

RESULT_RE = re.compile(r'^\[(PASS|FAIL|IGNORE|SKIP)\] (\S+)(?: \(l1_gas: ~(\d+), l1_data_gas: ~(\d+), l2_gas: ~(\d+)\))?')
SUMMARY_RE = re.compile(r'^Tests: (\d+) passed, (\d+) failed, (\d+) ignored, (\d+) filtered out')
TRACE_LINE_RE = re.compile(r'^((?:[│ ] {2})*)[├└]─ \[([a-zA-Z0-9 ]+)\] (.*)$')


def parse_output(text):
    """Test results and per-test call trees from `snforge test --trace-components contract-name gas`."""
    results, traces, summary, problems = {}, {}, None, []
    lines = text.split('\n')
    i = 0
    while i < len(lines):
        line = lines[i]
        m = RESULT_RE.match(line)
        if m:
            name = m.group(2)
            if name in results:
                problems.append(f'test {name} reported twice')
            results[name] = {'status': m.group(1),
                             'test_l2_gas': int(m.group(5)) if m.group(5) else None}
        m = SUMMARY_RE.match(line)
        if m:
            summary = dict(zip(['passed', 'failed', 'ignored', 'filtered'], map(int, m.groups())))
        if line.startswith('[test name] '):
            name = line[len('[test name] '):].strip()
            if name in traces:
                problems.append(f'trace of {name} printed twice')
            roots, stack = [], []  # stack of (depth, node)
            i += 1
            while i < len(lines) and lines[i].strip():
                tm = TRACE_LINE_RE.match(lines[i])
                if not tm:
                    problems.append(f'{name}: unparsed trace line {lines[i]!r}')
                    break
                depth = len(tm.group(1)) // 3
                tag, value = tm.group(2), tm.group(3).strip()
                if tag == 'selector':
                    node = {'selector': value, 'contract': None, 'gas': None, 'calls': []}
                    while stack and stack[-1][0] >= depth:
                        stack.pop()
                    if depth == 0:
                        roots.append(node)
                    elif stack and stack[-1][0] == depth - 1:
                        stack[-1][1]['calls'].append(node)
                    else:
                        problems.append(f'{name}: orphan call at depth {depth}')
                    stack.append((depth, node))
                else:
                    owner = [n for d, n in stack if d == depth - 1]
                    if not owner:
                        problems.append(f'{name}: attribute without a call: {lines[i]!r}')
                    elif tag == 'contract name':
                        owner[-1]['contract'] = value
                    elif tag == 'L2 gas':
                        owner[-1]['gas'] = int(value)
                    else:
                        problems.append(f'{name}: unexpected trace component {tag}')
                i += 1
            traces[name] = roots
            continue
        i += 1
    return results, traces, summary, problems


def flatten(calls, depth=1):
    out = []
    for c in calls:
        out.append({'depth': depth, 'contract': c['contract'], 'selector': c['selector'], 'gas': c['gas']})
        out.extend(flatten(c['calls'], depth + 1))
    return out


def check_tree(node, problems, where):
    if node['gas'] is None or node['contract'] is None:
        problems.append(f'{where}: call {node["selector"]} without gas or contract name')
        return
    nested = sum(c['gas'] or 0 for c in node['calls'])
    if nested > node['gas']:
        problems.append(f'{where}: {node["selector"]} gas {node["gas"]} < its nested calls {nested}')
    for c in node['calls']:
        check_tree(c, problems, where)


# ── snforge invocation ───────────────────────────────────────────────────────────────────────

def snforge_cmd(t, threads, extra=()):
    return [t['snforge'], 'test', '--no-optimization', '--tracked-resource', 'sierra-gas',
            '--max-n-steps', str(MAX_N_STEPS), '--trace-components', 'contract-name', 'gas',
            '--color', 'never', '--max-threads', str(threads), *extra]


def check_expected_table(t, env):
    r = subprocess.run([t['node'], GEN_EXPECTED, '--check'], cwd=ROOT, env=env,
                       capture_output=True, text=True)
    if r.returncode != 0:
        die('the expected table is not what bench/scripts/gen_expected.mjs generates:\n'
            + r.stdout + r.stderr)
    return r.stdout.strip().split('\n')[-1]


# ── commands ─────────────────────────────────────────────────────────────────────────────────

def cmd_run(args):
    t, info = tools(args.allow_tool_mismatch)
    env = tool_env(t)
    cases = read_json(CASES_JSON)['cases']
    started = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')
    git_before = git_info()

    print('gas_bench: checking the expected table (gen_expected.mjs --check)', file=sys.stderr)
    expected_check = check_expected_table(t, env)

    print('gas_bench: root scarb build (production classes)', file=sys.stderr)
    production = build_production(t, env)

    log = os.path.join(WORK, 'snforge.log')
    cmd = snforge_cmd(t, args.threads)
    print(f'gas_bench: {" ".join(cmd)}  (log: {log})', file=sys.stderr)
    code, wall, peak = run_measured(cmd, BENCH, env, log)
    with open(log) as f:
        text = f.read()
    if code != 0:
        tail = '\n'.join(text.split('\n')[-60:])
        die(f'snforge exited with {code} (log {log}):\n{tail}')
    if sha256_file(os.path.join(BENCH, 'Scarb.lock')) != git_before['bench_scarb_lock_sha256']:
        die('the bench build changed bench/Scarb.lock')

    identity = artifact_identity(t, production)
    if not identity['all_identical']:
        die('the classes the bench executed are not the production ones:\n'
            + json.dumps(identity, indent=2))

    results, traces, summary, problems = parse_output(text)
    expected_names = [TEST_PREFIX + c['name'] for c in cases]
    if len(set(expected_names)) != len(expected_names):
        problems.append('cases.json has duplicate case names')
    if summary is None:
        problems.append('no "Tests: ..." summary line')
    elif summary['passed'] != len(cases) or summary['failed'] or summary['ignored'] or summary['filtered']:
        problems.append(f'summary {summary}, expected {len(cases)} passed and nothing else')
    for name in set(results) - set(expected_names):
        problems.append(f'unexpected test {name}')
    rows = []
    for c in cases:
        name = TEST_PREFIX + c['name']
        r = results.get(name)
        if r is None:
            problems.append(f'missing test {name}')
            continue
        if r['status'] != 'PASS':
            problems.append(f'{name}: {r["status"]}')
            continue
        roots = traces.get(name)
        if roots is None:
            problems.append(f'{name}: no call trace')
            continue
        for n in roots:
            check_tree(n, problems, name)
        hits = [n for n in roots if n['selector'] == c['selector'] and n['contract'] == c['contract']]
        if len(hits) != 1:
            problems.append(f'{name}: {len(hits)} top-level calls to {c["contract"]}.{c["selector"]}, expected 1')
            continue
        call = hits[0]
        rows.append({
            'name': c['name'], 'group': c['group'], 'contract': c['contract'], 'selector': c['selector'],
            'gas': call['gas'], 'nested': flatten(call['calls']), 'test_l2_gas': r['test_l2_gas'],
            'over_execute_max_sierra_gas': call['gas'] > EXECUTE_MAX_SIERRA_GAS,
            'output': 'checked: ' + ', '.join(f'{k["key"]} ({k["source"]})' for k in c['checks']),
            'labels': c['labels'],
        })
    if problems:
        die('the bench output is not usable:\n  ' + '\n  '.join(problems[:80]))

    by_name = {r['name']: r for r in rows}
    checks = {}
    # A call's gas includes its nested calls: get_midi grows by exactly what get_beast_rank grows.
    a, m = by_name.get('a_get_midi_s021_n'), by_name.get('m_get_midi_s021_n_burn_rank')
    if a and m:
        def rank(row):
            g = [n['gas'] for n in row['nested'] if n['selector'] == 'get_beast_rank' and n['depth'] == 1]
            return g[0] if len(g) == 1 else None
        d_call, d_rank = m['gas'] - a['gas'], (rank(m) or 0) - (rank(a) or 0)
        checks['inclusive_of_nested_calls'] = {
            'cases': [a['name'], m['name']], 'get_midi_delta': d_call, 'get_beast_rank_delta': d_rank,
            'holds': d_call == d_rank and d_rank > 0 and rank(a) is not None,
        }
        if not checks['inclusive_of_nested_calls']['holds']:
            die(f'nested-call check failed: {checks["inclusive_of_nested_calls"]}')
    over = [r['name'] for r in rows if r['over_execute_max_sierra_gas']]
    checks['execute_max_sierra_gas'] = {'limit': EXECUTE_MAX_SIERRA_GAS, 'over': over,
                                        'max_case': max(rows, key=lambda r: r['gas'])['name'],
                                        'max_gas': max(r['gas'] for r in rows)}
    if over:
        print(f'gas_bench: WARNING {len(over)} cases exceed Starknet execute_max_sierra_gas: {over}',
              file=sys.stderr)

    git_after = git_info()
    if git_after['tracked_tree'] != git_before['tracked_tree']:
        die('tracked files changed during the run')
    snapshot = {
        'schema': SCHEMA,
        'created_utc': started,
        'measurement': MEASUREMENT,
        'tools': info,
        'git': git_before,
        'expected_table': {
            'cases_json_sha256': sha256_file(CASES_JSON),
            'frozen_json_sha256': sha256_file(FROZEN_JSON) if os.path.exists(FROZEN_JSON) else None,
            'generator_check': expected_check,
        },
        'classes': production,
        'artifact_identity': identity,
        'run': {'command': cmd, 'threads': args.threads, 'wall_s': wall, 'peak_rss_mb': peak,
                'tests_passed': summary['passed']},
        'checks': checks,
        'groups': group_summary(rows),
        'derived': derived(rows, cases),
        'cases': rows,
    }
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, 'w') as f:
        json.dump(snapshot, f, indent=1)
        f.write('\n')
    print(f'gas_bench: {len(rows)} cases, wall {wall} s, peak RSS {peak} MB -> {args.out}',
          file=sys.stderr)


def derived(rows, cases):
    """Attribution from the group E rows (each a difference of two measured calls)."""
    g = {r['name']: r['gas'] for r in rows}
    exp_len = {c['name']: c['checks'][0]['len'] for c in cases}
    stages = []
    for sp in ('s021_n', 's001_n', 's032_s'):
        t0n, t1n = f'e_genesis_smf_bytes_{sp}', f'e_genesis_score_{sp}'
        nbytes, nfelts = exp_len.get(t0n), (exp_len.get(t1n) or 1) - 1
        names = [f'a_get_midi_{sp}', t0n, t1n, f'e_u8_output_l{nbytes}', f'e_pack_input_l{nbytes:04d}',
                 f'e_felt_output_n{nfelts}']
        if not all(n in g for n in names):
            continue
        get_midi, t0, t1, u8_out, u8_in, felt_out = (g[n] for n in names)
        t0_net, t1_net = t0 - (u8_out - u8_in), t1 - felt_out
        stages.append({
            'species': sp, 'midi_bytes': nbytes, 'get_midi': get_midi,
            'T0_genesis_smf_bytes': t0, 'T0_return_cost': u8_out - u8_in, 'T0_net': t0_net,
            'T1_params_and_score': t1, 'T1_build_and_return_cost': felt_out, 'T1_net': t1_net,
            'T1_share_of_T0_net': round(t1_net / t0_net, 4),
            'after_score': t0_net - t1_net,
            'provider_dispatch_and_packing': get_midi - t0_net,
        })
    pack = []
    for n in sorted(x for x in g if x.startswith('e_pack_input_l')):
        tag = n[len('e_pack_input_'):]
        row = {'len': int(tag[1:]), 'input': g[n]}
        for f in ('bytes_to_byte_array', 'to_felt252_array'):
            if f'e_{f}_{tag}' in g:
                row[f + '_net'] = g[f'e_{f}_{tag}'] - g[n]
        pack.append(row)
    b64 = []
    for n in sorted(x for x in g if x.startswith('e_b64_input_l')):
        tag = n[len('e_b64_input_'):]
        b64.append({'len': int(tag[1:]), 'input': g[n],
                    **{f + '_net': g[f'e_{f}_{tag}'] - g[n] for f in ('append_base64', 'midi_html')
                       if f'e_{f}_{tag}' in g}})
    return {'note': 'net = probe - its input-only (or return-cost) probe; see bench/README.md',
            'stages': stages, 'pack': pack, 'base64': b64}


def group_summary(rows):
    out = {}
    for r in rows:
        g = out.setdefault(r['group'], {'count': 0, 'sum': 0, 'min': None, 'max': None})
        g['count'] += 1
        g['sum'] += r['gas']
        g['min'] = r['gas'] if g['min'] is None else min(g['min'], r['gas'])
        g['max'] = r['gas'] if g['max'] is None else max(g['max'], r['gas'])
    return dict(sorted(out.items()))


def cmd_test(args):
    t, _ = tools(args.allow_tool_mismatch)
    cmd = snforge_cmd(t, args.threads, [args.filter] if args.filter else [])
    print(' '.join(cmd), file=sys.stderr)
    sys.exit(subprocess.run(cmd, cwd=BENCH, env=tool_env(t)).returncode)


def cmd_freeze(args):
    """Records the baseline's digests into bench/expected/frozen.json. Refuses unless the
    production sources are exactly those of --baseline-rev, and never overwrites frozen.json."""
    if os.path.exists(FROZEN_JSON):
        die('bench/expected/frozen.json exists: the expected table is frozen from the baseline and '
            'is never regenerated (delete it by hand only to re-freeze at the same baseline)')
    rev = git('rev-parse', args.baseline_rev).strip()
    diff = subprocess.run(['git', 'diff', '--quiet', rev, '--', *PRODUCTION_PATHS], cwd=ROOT)
    untracked = git('ls-files', '--others', '--exclude-standard', '--', *PRODUCTION_PATHS).strip()
    if diff.returncode != 0 or untracked:
        die(f'the production sources differ from {rev}: freeze only at the baseline')
    t, info = tools(args.allow_tool_mismatch)
    env = tool_env(t)
    log = os.path.join(WORK, 'freeze.log')
    cmd = snforge_cmd(t, args.threads, ['--features', 'record'])
    code, wall, peak = run_measured(cmd, BENCH, env, log)
    with open(log) as f:
        text = f.read()
    if code != 0:
        die(f'snforge exited with {code} (log {log})')
    values = {}
    for line in text.split('\n'):
        if line.startswith('EXPECT '):
            _, key, length, digest = line.split()
            if key in values:
                die(f'{key} recorded twice')
            values[key] = [int(length), hex(int(digest))]
    keys = {k['key'] for c in read_json(CASES_JSON)['cases'] for k in c['checks']}
    if set(values) != keys:
        die(f'recorded keys differ from cases.json: missing {sorted(keys - set(values))[:10]}, '
            f'extra {sorted(set(values) - keys)[:10]}')
    frozen = {
        'note': 'Cairo outputs at the baseline, recorded by gas_bench.py freeze. Never regenerate '
                'from a candidate.',
        'baseline': {'rev': rev, 'production_tree': tree_hash(PRODUCTION_PATHS),
                     'created_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
                     'scarb': info['scarb']['version'].split('\n')[0],
                     'snforge': info['snforge']['version'].split('\n')[0]},
        'values': dict(sorted(values.items())),
    }
    with open(FROZEN_JSON, 'w') as f:
        json.dump(frozen, f, indent=1)
        f.write('\n')
    print(f'gas_bench: froze {len(values)} digests ({wall} s, peak {peak} MB); regenerating the table',
          file=sys.stderr)
    r = subprocess.run([t['node'], GEN_EXPECTED], cwd=ROOT, env=env)
    sys.exit(r.returncode)


# ── compare ──────────────────────────────────────────────────────────────────────────────────

def pct(base, cand):
    return (cand - base) / base * 100 if base else (0.0 if cand == base else float('inf'))


def fmt_int(n):
    return f'{n:,}'


def cmd_compare(args):
    base, cand = read_json(args.base), read_json(args.cand)
    refuse = []
    for s, label in ((base, 'base'), (cand, 'candidate')):
        if s.get('schema') != SCHEMA:
            refuse.append(f'{label} schema {s.get("schema")!r} is not {SCHEMA}')
    if base.get('measurement') != cand.get('measurement'):
        refuse.append('the measurement definitions differ')
    for k in ('scarb', 'snforge', 'universal_sierra_compiler'):
        if base['tools'][k]['version'] != cand['tools'][k]['version']:
            refuse.append(f'{k} versions differ: {base["tools"][k]["version"]!r} vs {cand["tools"][k]["version"]!r}')
    key = lambda r: (r['name'], r['group'], r['contract'], r['selector'], r['output'])
    bset, cset = {key(r) for r in base['cases']}, {key(r) for r in cand['cases']}
    if bset != cset:
        diff = sorted(bset ^ cset)[:10]
        refuse.append(f'the case sets (or their output checks) differ, e.g. {diff}')
    if base['expected_table']['cases_json_sha256'] != cand['expected_table']['cases_json_sha256']:
        refuse.append('the expected tables differ (bench/expected/cases.json)')
    if refuse:
        die('refusing to compare:\n  ' + '\n  '.join(refuse), code=2)
    if base['git']['bench_tree']['sha256'] != cand['git']['bench_tree']['sha256']:
        print('gas_bench: WARNING bench/ differs between the snapshots: the mocks and probes are '
              'inside the inclusive numbers, so a delta may come from the bench itself',
              file=sys.stderr)
    for s, label in ((base, 'base'), (cand, 'candidate')):
        if s['git']['dirty']:
            print(f'gas_bench: note: the {label} snapshot was taken from a dirty tree '
                  f'({len(s["git"]["status"])} status lines)', file=sys.stderr)

    md = args.markdown
    out = []
    regressions = []
    cand_by = {r['name']: r for r in cand['cases']}
    rows = []
    for r in base['cases']:
        c = cand_by[r['name']]
        d = c['gas'] - r['gas']
        rows.append((r, c, d, pct(r['gas'], c['gas'])))
        if d > 0:
            regressions.append(f'{r["name"]}: +{fmt_int(d)} ({pct(r["gas"], c["gas"]):+.4f}%)')
        if c['over_execute_max_sierra_gas']:
            regressions.append(f'{r["name"]}: {fmt_int(c["gas"])} exceeds execute_max_sierra_gas')

    def table(header, body):
        if md:
            out.append('| ' + ' | '.join(header) + ' |')
            out.append('|' + '|'.join('---' if i == 0 else '---:' for i in range(len(header))) + '|')
            out.extend('| ' + ' | '.join(row) + ' |' for row in body)
        else:
            widths = [max(len(str(x)) for x in col) for col in zip(header, *body)] if body else [len(h) for h in header]
            out.append('  '.join(h.ljust(w) if i == 0 else h.rjust(w) for i, (h, w) in enumerate(zip(header, widths))))
            out.extend('  '.join(str(x).ljust(w) if i == 0 else str(x).rjust(w)
                                 for i, (x, w) in enumerate(zip(row, widths))) for row in body)
        out.append('')

    h = (lambda s: f'## {s}') if md else (lambda s: f'== {s}')
    out.append(h(f'Gas: {args.base} -> {args.cand}'))
    out.append(f'base {base["git"]["rev"][:12]}{" (dirty)" if base["git"]["dirty"] else ""}, '
               f'candidate {cand["git"]["rev"][:12]}{" (dirty)" if cand["git"]["dirty"] else ""}; '
               f'{MEASUREMENT["quantity"]}.')
    out.append('')
    out.append(h('Per group'))
    body = []
    groups = sorted({r['group'] for r in base['cases']})
    for g in groups:
        gr = [x for x in rows if x[0]['group'] == g]
        ds = [x[3] for x in gr]
        bsum, csum = sum(x[0]['gas'] for x in gr), sum(x[1]['gas'] for x in gr)
        body.append([g, str(len(gr)), fmt_int(bsum), fmt_int(csum), f'{pct(bsum, csum):+.4f}%',
                     f'{min(ds):+.4f}%', f'{statistics.median(ds):+.4f}%', f'{max(ds):+.4f}%',
                     str(sum(1 for x in gr if x[2] > 0))])
    table(['group', 'cases', 'base sum', 'cand sum', 'sum delta', 'min delta', 'median delta',
           'max delta', 'regressed'], body)
    out.append(h('Class sizes (CASM limit 81,920 felts)'))
    cb = {c['contract']: c for c in cand['classes']}
    body = []
    for b in base['classes']:
        c = cb.get(b['contract'])
        if c is None:
            continue
        flag = ''
        if c['casm_bytecode_len'] > CASM_LIMIT:
            flag = 'OVER LIMIT'
            regressions.append(f'{b["contract"]}: CASM {fmt_int(c["casm_bytecode_len"])} > {fmt_int(CASM_LIMIT)}')
        elif c['casm_bytecode_len'] > b['casm_bytecode_len']:
            flag = 'grew'
        body.append([b['contract'], fmt_int(b['casm_bytecode_len']), fmt_int(c['casm_bytecode_len']),
                     f'{c["casm_bytecode_len"] - b["casm_bytecode_len"]:+,}', fmt_int(CASM_LIMIT - c['casm_bytecode_len']),
                     fmt_int(b['sierra_program_len']), fmt_int(c['sierra_program_len']),
                     f'{c["sierra_program_len"] - b["sierra_program_len"]:+,}',
                     'same' if b['casm_bytecode_sha256'] == c['casm_bytecode_sha256'] else 'changed', flag])
    table(['class', 'CASM base', 'CASM cand', 'delta', 'headroom', 'Sierra base', 'Sierra cand',
           'delta', 'bytecode', 'flag'], body)
    out.append(h('Every case'))
    body = []
    for r, c, d, p in rows:
        body.append([r['name'], fmt_int(r['gas']), fmt_int(c['gas']), f'{d:+,}', f'{p:+.4f}%',
                     'REGRESSION' if d > 0 else ''])
    table(['case', 'base', 'candidate', 'delta', 'delta %', 'flag'], body)
    if regressions:
        out.append(h(f'REGRESSIONS ({len(regressions)})'))
        out.extend(('- ' if md else '  ') + x for x in regressions)
    else:
        out.append(h('No regressions: no case costs more, no class is over the CASM limit'))
    print('\n'.join(out))
    if regressions and args.fail_on_regression:
        sys.exit(3)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)
    r = sub.add_parser('run', help='capture a snapshot')
    r.add_argument('--out', required=True)
    r.add_argument('--threads', type=int, default=DEFAULT_THREADS)
    r.add_argument('--allow-tool-mismatch', action='store_true')
    c = sub.add_parser('compare', help='compare two snapshots')
    c.add_argument('base')
    c.add_argument('cand')
    c.add_argument('--markdown', action='store_true')
    c.add_argument('--fail-on-regression', action='store_true')
    t = sub.add_parser('test', help='run bench tests with the pinned tools (no snapshot)')
    t.add_argument('filter', nargs='?')
    t.add_argument('--threads', type=int, default=DEFAULT_THREADS)
    t.add_argument('--allow-tool-mismatch', action='store_true')
    f = sub.add_parser('freeze', help='record the baseline digests (baseline only)')
    f.add_argument('--baseline-rev', required=True)
    f.add_argument('--threads', type=int, default=DEFAULT_THREADS)
    f.add_argument('--allow-tool-mismatch', action='store_true')
    args = p.parse_args()
    {'run': cmd_run, 'compare': cmd_compare, 'test': cmd_test, 'freeze': cmd_freeze}[args.cmd](args)


if __name__ == '__main__':
    main()
