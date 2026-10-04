Built copies from PR #3 (`offchain/beast-sound/onchain/dist/` on `pr1-rebased`, commit after the Triangle Bass trim), used by
`beatsync-demo.mjs`:

- `tinychip.min.js`: the onchain TinyChip runtime (20 essentials, chip kit, orchestration `tinychip-2`).
- `tinychip-bank.min.js`: the full 100-preset bank (`TinyChipBank`), the client add-on.

Refresh them from PR #3's `node onchain/build.mjs` output when TinyChip changes.
