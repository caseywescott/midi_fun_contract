"""Inline the engine bundle and mainnet snapshot into a single-file page.

python3 build.py <bundle.js> <snapshot.min.json> <out.html>
Bundle: npx esbuild entry.mjs --bundle --minify --format=iife (see README.md)."""
import sys
src = open('index.src.html').read()
bundle = open(sys.argv[1]).read().replace('</script', '<\\/script')
snap = open(sys.argv[2]).read()
out = src.replace('/*BUNDLE*/', bundle, 1).replace('/*SNAPSHOT*/', snap, 1)
open(sys.argv[3], 'w').write(out)
print(len(out), 'bytes ->', sys.argv[3])
