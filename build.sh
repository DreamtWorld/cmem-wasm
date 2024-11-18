#!/usr/bin/env bash
set -e
cd $(dirname $0)

mkdir -p out
FEATURES="--disable-mutable-globals \
--disable-saturating-float-to-int \
--disable-sign-extension \
--disable-simd \
--disable-multi-value \
--disable-reference-types"

if [ "$1" == --bulk-memory ]; then
	OPTFLAGS=--enable-bulk-memory
	CPPFLAGS=-DBULK_MEMORY
else
	FEATURES="$FEATURES --disable-bulk-memory"
fi

cpp -P -nostdinc -o out/cmem.wat $CPPFLAGS cmem.wat
wat2wasm $FEATURES -ro out/cmem.o out/cmem.wat

cpp -P -nostdinc -o out/cmemdbg.wat $CPPFLAGS -DEXPORT_ALL cmem.wat
wat2wasm $FEATURES -o out/cmem.wasm out/cmemdbg.wat
wasm-opt -O3 $OPTFLAGS -o out/cmem.O3.wasm out/cmem.wasm
