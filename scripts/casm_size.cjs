// CASM felts of compiled classes in target/dev (bytecode length), and the largest functions when the
// Sierra debug names are there.   node scripts/casm_size.cjs <ContractName>... [top]
const names = process.argv.slice(2).filter((a) => isNaN(+a)), top = +process.argv.find((a) => !isNaN(+a)) || 0;
for (const n of names) {
  const c = require(process.cwd() + `/target/dev/loot_contracts_${n}.compiled_contract_class.json`);
  console.log(`${n}: ${c.bytecode.length} CASM felts (limit 81920)`);
  if (top && c.bytecode_segment_lengths) {
    const s = require(process.cwd() + `/target/dev/loot_contracts_${n}.contract_class.json`);
    const fns = (s.sierra_program_debug_info?.user_func_names || []).map((f) => f[1]);
    const by = {};
    c.bytecode_segment_lengths.forEach((len, i) => { const k = (fns[i] || '?').replace(/\{.*$/, ''); by[k] = (by[k] || 0) + len; });
    console.log(Object.entries(by).sort((a, b) => b[1] - a[1]).slice(0, top).map((x) => '  ' + x[1] + ' ' + x[0]).join('\n'));
  }
}
