#!/usr/bin/env bash
set -e
mkdir -p out
cpp -P -nostdinc -o out/cmem.wat -DEXPORT_ALL -DEXPORT_PREFIX="" cmem.wat
FEATURES="--disable-mutable-globals \
--disable-saturating-float-to-int \
--disable-sign-extension \
--disable-simd \
--disable-multi-value \
--disable-bulk-memory \
--disable-reference-types"
wat2wasm $FEATURES -ro out/cmem.o out/cmem.wat
wat2wasm $FEATURES -o out/cmem.wasm out/cmem.wat
wasm-opt -O3 -o out/cmem.O3.wasm out/cmem.wasm
