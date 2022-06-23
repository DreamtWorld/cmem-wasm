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

#define INDIR(M, ...) M(__VA_ARGS__)
#define QUOTE(S) #S
#define CONCAT(A, B) A##B

#ifndef EXPORT_PREFIX
#define EXPORT_PREFIX cmem_
#endif

#define EXPORT(F) $##F (export INDIR(QUOTE, INDIR(CONCAT, EXPORT_PREFIX, F)))

#ifdef EXPORT_ALL
#define FUNC(F) EXPORT(F)
#else
#define FUNC(F) $##F
#endif

#define PREV_OFS 2
#define NEXT_OFS 4
#define HEAD_LEN 6

(module

	(memory (export "memory") 1)
	(global $begin (mut i32) (i32.const 0))
	(global $last (mut i32) (i32.const 0))

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

	(func FUNC(list_push) (param $list i32) (param $val i32) (result i32) (local $next i32) (local $addr i32)
		;; Retrieve address of next segment
		(local.set $next (call $list_next (local.get $list)))
		;; Determine address for new segment
		(local.set $addr (i32.add (i32.add
			(local.get $list) ;; begin
			(i32.const HEAD_LEN)) ;; head
			(call $list_get (local.get $list))) ;; body
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

	(func FUNC(list_rem) (param $list i32) (local $prev i32) (local $next i32)
		(local.set $prev (call $list_prev (local.get $list)))
		(local.set $next (call $list_next (local.get $list)))
		(i32.store16 (i32.add (local.get $next) (i32.const PREV_OFS)) (local.get $prev))
		(i32.store16 (i32.add (local.get $prev) (i32.const NEXT_OFS)) (local.get $next))
	)

	;; Memory
	;; ======

	(func FUNC(list_gap) (param $list i32) (result i32)
		(call $list_next (local.get $list))
		if (result i32)
			(call $list_next (local.get $list))
		else
			i32.const 0xFFFF
		end
		(i32.add (i32.add (local.get $list) (i32.const HEAD_LEN)) (call $list_get (local.get $list)))
		i32.sub
	)

	(func FUNC(malloc) (param $len i32) (result i32) (local $list i32) (local $gap_len i32) (local $best_prev i32) (local $best_len i32)

		(local.set $list (global.get $begin))
		(local.set $best_prev (local.tee $best_len (i32.const 0xFFFF)))

		loop $iter
			(local.set $gap_len (call $list_gap (local.get $list)))
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
			(i32.eqz (call $list_next (local.get $list)))
			(i32.eq (local.get $best_len) (local.get $len))
			i32.or
			if
				;; Grow memory if necessary
				(i32.eq (local.get $best_prev) (i32.const 0xFFFF))
				if
					;; Determine past-the-end address
					local.get $list
					i32.const 12 ;; 2 HEAD_LEN
					(call $list_get (local.get $list))
					local.get $len
					;; Give up if buffer doesn't fit into page
					(if (i32.gt_u (i32.add (i32.add) (i32.add)) (i32.const 0xFFFF)) (then unreachable))
					(local.set $best_prev (local.get $list))
				end
				(call $list_push (local.get $best_prev) (local.get $len))
				;; Update last block
				local.tee $list
				global.get $last
				i32.gt_u
				if
					(global.set $last (local.get $list))
				end
			else
				(local.set $list (call $list_next (local.get $list)))
				br $iter
			end
		end
		(i32.add (local.get $list) (i32.const HEAD_LEN))
	)

	(func FUNC(calloc) (param $count i32) (param $len i32) (result i32) (local $addr i32)
		(local.set $addr (call $malloc (i32.mul (local.get $count) (local.get $len))))
#ifdef BULK_MEMORY_ENABLED
		(memory.fill
#else
		(call $memset
#endif
			(local.get $addr)
			(i32.const 0)
			(local.get $len)
		)
	)

	(func FUNC(free) (param $addr i32)
		(if (i32.eqz (local.get $addr)) (then return))
		(local.tee $addr (i32.sub (local.get $addr) (i32.const HEAD_LEN)))
		call $list_rem
		(i32.eq (local.get $addr) (global.get $last))
		if
			(i32.load (i32.add (local.get $addr) (i32.const PREV_OFS)))
			global.set $last
		end
	)

	(func FUNC(realloc) (param $list i32) (param $len i32) (result i32) (local $curlen i32) (local $newaddr i32)
		;; list still points past header for this line
		(if (i32.eqz (local.get $list)) (then (return (call $malloc (local.get $len)))))
		;; Undefined behaviour
		(if (i32.eqz (local.get $len)) (then unreachable))
		;; Access list header
		(local.set $list (i32.sub (local.get $list) (i32.const HEAD_LEN)))
		(local.set $curlen (call $list_get (local.get $list)))

		;; Check for sufficient space with following gap
		(i32.add (local.get $curlen) (call $list_gap (local.get $list)))
		(local.get $len)
		i32.ge_u
		if (result i32)
			(call $list_set (local.get $list) (local.get $len))
			(i32.add (local.get $list) (i32.const HEAD_LEN))
		else
			;; Check for sufficient space before and after
			(i32.add (i32.add
				(local.get $curlen)
				(call $list_gap (local.get $list)))
				(call $list_gap (call $list_prev (local.get $list)))
			)
			(local.get $len)
			i32.ge_u
			;; Check if header fits
			(i32.ge_u (call $list_gap (call $list_prev (local.get $list))) (i32.const HEAD_LEN))
			i32.and
			if (result i32)
				(call $list_push (call $list_prev (local.get $list)) (local.get $len))
				(call $list_rem (local.get $list))
				(call $memmove
					;; Add to list_push result
					(local.tee $newaddr (i32.add (i32.const HEAD_LEN)))
					(i32.add (local.get $list) (i32.const HEAD_LEN))
					(local.get $curlen)
				)
				drop
				(i32.eq (local.get $list) (global.get $last))
				if
					(global.set $last (local.get $newaddr))
				end
				local.get $newaddr
			else
				(call $malloc (local.get $len))
				(call $free (i32.add (local.get $list) (i32.const HEAD_LEN)))
				(i32.add (local.get $list) (i32.const HEAD_LEN))
				local.get $curlen
				call $memmove
			end
		end
	)

	(func FUNC(memset) (param $addr i32) (param $val i32) (param $len i32) (result i32) (local $i i32)
		(if (i32.eqz (local.get $len)) (then (return (local.get $addr))))
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
				;; 8_u loop writes last bytes
				(br_if $iter (i32.lt_u (i32.add (local.get $i) (i32.const 4)) (local.get $len)))
			end
		end
		loop $iter
			(i32.store8 (i32.add (local.get $addr) (local.get $i)) (local.get $val))
			(local.set $i (i32.add (local.get $i) (i32.const 1)))
			(br_if $iter (i32.lt_u (local.get $i) (local.get $len)))
		end
		(local.get $addr)
	)

	(func FUNC(memcpy) (param $dest i32) (param $src i32) (param $len i32) (result i32) (local $i i32)
		(if (i32.eqz (local.get $len)) (then (return (local.get $dest))))
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
		(local.get $dest)
	)

	(func FUNC(memmove) (param $dest i32) (param $src i32) (param $len i32) (result i32) (local $i i32)
		(i32.eq (local.get $src) (local.get $dest))
		(i32.eqz (local.get $len))
		(if (i32.or) (then (return (local.get $dest))))

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
			(call $memcpy (local.get $dest) (local.get $src) (local.get $len))
			drop
		end
		local.get $dest
	)

	(func EXPORT(init) (param $begin i32)
		(global.set $begin (local.get $begin))
		(i32.store16 (global.get $begin) (i32.const 0))
		(i32.store16 (i32.add (global.get $begin) (i32.const PREV_OFS)) (i32.const 0xFFFF))
	)

	(func EXPORT(end) (result i32)
		global.get $last
		i32.const HEAD_LEN
		(call $list_get (global.get $last))
		(i32.add (i32.add))
	)
)
