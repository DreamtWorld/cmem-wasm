;; Single-page C memory management in WebAssembly
;; including malloc, calloc, free, realloc, memset, memcpy and memmove

;; Copyright Dreamt world https://dreamt.world
;;
;; Redistribution and use in source and binary forms, with or without modification, are permitted provided that the
;; following conditions are met:
;;
;; 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following
;; disclaimer.
;;
;; 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the
;; following disclaimer in the documentation and/or other materials provided with the distribution.
;;
;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
;; INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
;; DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
;; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
;; WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
;; USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#define QUOTE(S) #S

#define EXPORT(I) $cmem_##I (export QUOTE(cmem_##I))

#ifdef PREFIX_LIBC
#define F(I) $##cmem_##I
#define EXP(I) QUOTE(cmem_##I)
#else
#define F(I) $##I
#define EXP(I) #I
#endif

#ifdef EXPORT_ALL
#define FUNC EXPORT
#define FUNCLIBC(I) F(I) (export EXP(I))
#else
#define FUNC(I) $cmem_##I
#define FUNCLIBC F
#endif

#define PREV_OFS 2
#define NEXT_OFS 4
#define HEAD_LEN 6

(module

	(memory
#ifdef EXPORT_ALL
		(export "memory")
#endif
	1)

	(global $cmem_begin (mut i32) (i32.const 0))
	(global $cmem_last (mut i32) (i32.const 0))

	;; List
	;; ====
	;; 16 bits buffer length, 16 bits address of previous list, 16 bits address of next list

	(func FUNC(list_next) (param $list i32) (result i32)
		(i32.load16_u (i32.add (local.get $list) (i32.const NEXT_OFS)))
	)

	(func FUNC(list_prev) (param $list i32) (result i32)
		(i32.load16_u (i32.add (local.get $list) (i32.const PREV_OFS)))
	)

	(func FUNC(list_get) (param $list i32) (result i32)
		(i32.load16_u (local.get $list))
	)

	(func FUNC(list_set) (param $list i32) (param $new i32)
		(i32.store16 (local.get $list) (local.get $new))
	)

	(func FUNC(list_push) (param $list i32) (param $val i32) (result i32)
		(local $next i32)
		(local $addr i32)
		;; Retrieve address of next segment
		(local.set $next (call $cmem_list_next (local.get $list)))
		;; Determine address for new segment
		(local.set $addr (i32.add (i32.add
			(local.get $list) ;; begin
			(i32.const HEAD_LEN)) ;; head
			(call $cmem_list_get (local.get $list))) ;; body
		)
		;; Insert new segment
		(i32.store16 (local.get $addr) (local.get $val))
		;; Store addresses
		(if (local.get $next)
			(then (i32.store16 (i32.add (local.get $next) (i32.const PREV_OFS)) (local.get $addr)))
		)
		(i32.store16 (i32.add (local.get $list) (i32.const NEXT_OFS)) (local.get $addr))
		(i32.store16 (i32.add (local.get $addr) (i32.const PREV_OFS)) (local.get $list))
		(i32.store16 (i32.add (local.get $addr) (i32.const NEXT_OFS)) (local.get $next))
		local.get $addr
	)

	(func FUNC(list_rem) (param $list i32)
		(local $prev i32)
		(local $next i32)
		(local.set $prev (call $cmem_list_prev (local.get $list)))
		(local.tee $next (call $cmem_list_next (local.get $list)))
		if
			(i32.store16 (i32.add (local.get $next) (i32.const PREV_OFS)) (local.get $prev))
		end
		(i32.store16 (i32.add (local.get $prev) (i32.const NEXT_OFS)) (local.get $next))
	)

	;; Memory
	;; ======

	(func FUNC(list_gap) (param $list i32) (result i32)
		(call $cmem_list_next (local.get $list))
		if (result i32)
			(call $cmem_list_next (local.get $list))
		else
			i32.const 0xFFFF
		end
		(i32.add (i32.add (local.get $list) (i32.const HEAD_LEN)) (call $cmem_list_get (local.get $list)))
		i32.sub
	)

	(func FUNCLIBC(malloc) (param $len i32) (result i32)
		(local $list i32)
		(local $gap_len i32)
		(local $best_prev i32)
		(local $best_len i32)

		(local.set $list (global.get $cmem_begin))
		(local.set $best_prev (local.tee $best_len (i32.const 0xFFFF)))

		loop $iter
			(local.set $gap_len (call $cmem_list_gap (local.get $list)))
			;; Check if header fits
			(i32.ge_u (local.get $gap_len) (i32.const HEAD_LEN))
			;; Subtract header
			(local.set $gap_len (i32.sub (local.get $gap_len) (i32.const 6)))
			;; Check for short gap
			(i32.ge_u (local.get $gap_len) (local.get $len))
			i32.and
			if
				;; Check for new best gap
				(i32.lt_u (local.get $gap_len) (local.get $best_len))
				if
					(local.set $best_prev (local.get $list))
					(local.set $best_len (local.get $gap_len))
				end
			end

			;; Iterate
			(i32.eqz (call $cmem_list_next (local.get $list)))
#ifdef FIRST_FIT
			(i32.ne (local.get $best_len) (i32.const 0xFFFF))
#else
			(i32.eq (local.get $best_len) (local.get $len))
#endif
			i32.or
			if
				;; Grow memory if necessary
				(i32.eq (local.get $best_prev) (i32.const 0xFFFF))
				if
					;; Determine past-the-end address
					local.get $list
					(i32.mul (i32.const HEAD_LEN) (i32.const 2))
					(call $cmem_list_get (local.get $list))
					local.get $len
					;; Give up if buffer doesn't fit into page
					(if (i32.gt_u (i32.add (i32.add) (i32.add)) (i32.const 0xFFFF)) (then unreachable))
					(local.set $best_prev (local.get $list))
				end
				(call $cmem_list_push (local.get $best_prev) (local.get $len))
				;; Update last block
				local.tee $list
				global.get $cmem_last
				i32.gt_u
				if
					(global.set $cmem_last (local.get $list))
				end
			else
				(local.set $list (call $cmem_list_next (local.get $list)))
				br $iter
			end
		end
		(i32.add (local.get $list) (i32.const HEAD_LEN))
	)

	(func FUNCLIBC(calloc) (param $count i32) (param $len i32) (result i32)
		(local $addr i32)
		(local.set $addr (call F(malloc) (i32.mul (local.get $count) (local.get $len))))
		(call F(memset) (local.get $addr) (i32.const 0) (local.get $len)
		)
	)

	(func FUNCLIBC(free) (param $addr i32)
		(if (i32.eqz (local.get $addr)) (then return))
		(local.tee $addr (i32.sub (local.get $addr) (i32.const HEAD_LEN)))
		call $cmem_list_rem
		(i32.eq (local.get $addr) (global.get $cmem_last))
		if
			(global.set $cmem_last (call $cmem_list_prev (local.get $addr)))
		end
	)

	(func FUNCLIBC(realloc) (param $list i32) (param $len i32) (result i32)
		(local $curlen i32)
		(local $newaddr i32)
		;; list still points past header for this line
		(if (i32.eqz (local.get $list)) (then (return (call F(malloc) (local.get $len)))))
		;; Undefined behaviour
		(if (i32.eqz (local.get $len)) (then unreachable))
		;; Access list header
		(local.set $list (i32.sub (local.get $list) (i32.const HEAD_LEN)))
		(local.set $curlen (call $cmem_list_get (local.get $list)))

		;; Check for sufficient space with following gap
		(i32.add (local.get $curlen) (call $cmem_list_gap (local.get $list)))
		(local.get $len)
		i32.ge_u
		if (result i32)
			(call $cmem_list_set (local.get $list) (local.get $len))
			(i32.add (local.get $list) (i32.const HEAD_LEN))
		else
			;; Check for sufficient space before and after
			(i32.add (i32.add
				(local.get $curlen)
				(call $cmem_list_gap (local.get $list)))
				(call $cmem_list_gap (call $cmem_list_prev (local.get $list)))
			)
			(local.get $len)
			i32.ge_u
			if (result i32)
				;; list_rem won't modify $list, allowing usage with overlapping heads
				(call $cmem_list_rem (local.get $list))
				(call $cmem_list_push (call $cmem_list_prev (local.get $list)) (local.get $len))
				(call F(memmove)
					;; Add to list_push result
					(local.tee $newaddr (i32.add (i32.const HEAD_LEN)))
					(i32.add (local.get $list) (i32.const HEAD_LEN))
					(local.get $curlen)
				)
				drop
				(i32.eq (local.get $list) (global.get $cmem_last))
				if
					(global.set $cmem_last (local.get $newaddr))
				end
				local.get $newaddr
			else
				(call F(malloc) (local.get $len))
				(call F(free) (i32.add (local.get $list) (i32.const HEAD_LEN)))
				(i32.add (local.get $list) (i32.const HEAD_LEN))
				local.get $curlen
				call F(memmove)
			end
		end
	)

	(func FUNCLIBC(memset) (param $addr i32) (param $val i32) (param $len i32) (result i32)
		(local $i i32)
		(if (i32.eqz (local.get $len)) (then (return (local.get $addr))))
#ifdef BULK_MEMORY
		(memory.fill (local.get $addr) (local.get $val) (local.get $len))
#else
		(i32.gt_u (local.get $len) (i32.const 4))
		if
			(local.set $val
				(i32.or (i32.or (i32.or
					(i32.shl (local.get $val) (i32.const 24))
					(i32.shl (local.get $val) (i32.const 16)))
					(i32.shl (local.get $val) (i32.const 8)))
					(local.get $val)
				)
			)
			loop $iter
				(i32.store (i32.add (local.get $addr) (local.get $i)) (local.get $val))
				(local.set $i (i32.add (local.get $i) (i32.const 4)))
				;; store8 loop writes last bytes
				(br_if $iter (i32.lt_u (i32.add (local.get $i) (i32.const 4)) (local.get $len)))
			end
		end
		loop $iter
			(i32.store8 (i32.add (local.get $addr) (local.get $i)) (local.get $val))
			(local.set $i (i32.add (local.get $i) (i32.const 1)))
			(br_if $iter (i32.lt_u (local.get $i) (local.get $len)))
		end
#endif
		(local.get $addr)
	)

	(func FUNCLIBC(memcpy) (param $dest i32) (param $src i32) (param $len i32) (result i32)
		(local $i i32)
		(if (i32.eqz (local.get $len)) (then (return (local.get $dest))))
#ifdef BULK_MEMORY
		(memory.copy (local.get $dest) (local.get $src) (local.get $len))
#else
		(i32.gt_u (local.get $len) (i32.const 4))
		if
			loop $iter
				(i32.add (local.get $dest) (local.get $i))
				(i32.load (i32.add (local.get $src) (local.get $i)))
				i32.store
				(local.set $i (i32.add (local.get $i) (i32.const 4)))
				;; 8_u loop writes last bytes
				(br_if $iter (i32.lt_u (i32.add (local.get $i) (i32.const 4)) (local.get $len)))
			end
		end
		loop $iter
			(i32.add (local.get $dest) (local.get $i))
			(i32.load8_u (i32.add (local.get $src) (local.get $i)))
			i32.store8
			(local.set $i (i32.add (local.get $i) (i32.const 1)))
			(br_if $iter (i32.lt_u (local.get $i) (local.get $len)))
		end
#endif
		(local.get $dest)
	)

	(func FUNCLIBC(memmove) (param $dest i32) (param $src i32) (param $len i32) (result i32)
		(local $i i32)
		(i32.eq (local.get $src) (local.get $dest))
		(i32.eqz (local.get $len))
		(if (i32.or) (then (return (local.get $dest))))

#ifdef BULK_MEMORY
		(memory.copy (local.get $dest) (local.get $src) (local.get $len))
#else
		;; Copy backwards if overlapping with src lesser
		(i32.lt_u (local.get $src) (local.get $dest))
		(i32.ge_u (i32.add (local.get $src) (local.get $len)) (local.get $dest))
		i32.and
		if
			(local.set $i (local.get $len))
			(i32.gt_u (local.get $len) (i32.const 4))
			if
				loop $iter
					(i32.sub (i32.add (local.get $dest) (local.get $i)) (i32.const 4))
					(i32.load (i32.sub (i32.add (local.get $src) (local.get $i)) (i32.const 4)))
					i32.store
					(local.set $i (i32.sub (local.get $i) (i32.const 4)))
					(br_if $iter (i32.gt_u (local.get $i) (i32.const 4)))
				end
			end
			loop $iter
				(i32.sub (i32.add (local.get $dest) (local.get $i)) (i32.const 1))
				(i32.load8_u (i32.sub (i32.add (local.get $src) (local.get $i)) (i32.const 1)))
				i32.store8
				(local.set $i (i32.sub (local.get $i) (i32.const 1)))
				(br_if $iter (i32.gt_u (local.get $i) (i32.const 0)))
			end
		else
			(call F(memcpy) (local.get $dest) (local.get $src) (local.get $len))
			drop
		end
#endif
		local.get $dest
	)

	(func EXPORT(init) (param $begin i32)
		(global.set $cmem_begin (local.get $begin))
		(i32.store16 (global.get $cmem_begin) (i32.const 0))
		(i32.store16 (i32.add (global.get $cmem_begin) (i32.const PREV_OFS)) (i32.const 0xFFFF))
	)

	(func EXPORT(end) (result i32)
		global.get $cmem_last
		i32.const HEAD_LEN
		(call $cmem_list_get (global.get $cmem_last))
		(i32.add (i32.add))
	)
)
