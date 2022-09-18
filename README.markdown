cmem-wasm
=========

This library implements libc memory allocation functions in WebAssembly.
The implementation assumes a single page of memory, that is, a 64 KiB buffer.

Available libc functions
------------------------

- `malloc`
- `calloc`
- `free`
- `realloc`
- `memset`
- `memcpy`
- `memmove`

Usage
-----

Initialize memory with `cmem_init(start)`, where `start` is the 16 bit address of the first byte of the memory region to use. Proceed to use memory allocation functions as usual. Exceeding available memory will trap.

Additional functionality
------------------------

`cmem_end()` returns a past-the-end pointer to the last buffer in memory, effectively retrieving the current length of memory. Intended use is backing up memory states at minimal size.

Build
-----

`build.sh` runs the source code through the C language preprocessor, then translates it with `wat2wasm` from the *wabt* software package.

The result is an object file that can be linked using `wasm-ld`, as well as a WebAssembly module.

The script also produces an optimized module using `wasm-opt -O3` from the *binaryen* package.

Build options
-------------

- `EXPORT_ALL` exports the memory and functions other than `cmem_init` and `cmem_end`, including memory and list management functions.
- `PREFIX_LIBC` prepends `cmem_` to libc function names.
- `FIRST_FIT` employs a first-fit instead of a best-fit strategy for allocation.
- `BULK_MEMORY` enables use of bulk memory instructions, decreasing embedder compatibility.

Build dependencies
------------------

- [cpp](https://gcc.gnu.org/onlinedocs/gcc/Preprocessor-Options.html)
- [wabt](https://github.com/WebAssembly/wabt)
- [binaryen](https://github.com/WebAssembly/binaryen)

Implementation
--------------

Best-fit allocation. Doubly linked list to navigate buffers. 16-bit addresses constrict memory length to 64 KiB.
