(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(* Translation from closed lambda to C-- *)

open Misc
open Arch
open Asttypes
open Primitive
open Types
open Lambda
open Clambda
open Cmm
open Cmx_format

(* Local binding of complex expressions *)

let bind name arg fn =
  match arg with
    Cvar _ | Cconst_int _ | Cconst_natint _ | Cconst_symbol _
  | Cconst_pointer _ | Cconst_natpointer _ -> fn arg
  | _ -> let id = Ident.create name in Clet(id, arg, fn (Cvar id))

let bind_nonvar name arg fn =
  match arg with
    Cconst_int _ | Cconst_natint _ | Cconst_symbol _
  | Cconst_pointer _ | Cconst_natpointer _ -> fn arg
  | _ -> let id = Ident.create name in Clet(id, arg, fn (Cvar id))

(* Block headers. Meaning of the tag field: see stdlib/obj.ml *)

let float_tag = Cconst_int Obj.double_tag
let floatarray_tag = Cconst_int Obj.double_array_tag

let block_header tag sz =
  Nativeint.add (Nativeint.shift_left (Nativeint.of_int sz) 10)
                (Nativeint.of_int tag)
let closure_header sz = block_header Obj.closure_tag sz
let infix_header ofs = block_header Obj.infix_tag ofs
let float_header = block_header Obj.double_tag (size_float / size_addr)
let floatarray_header len =
      block_header Obj.double_array_tag (len * size_float / size_addr)
let string_header len =
      block_header Obj.string_tag ((len + size_addr) / size_addr)
let boxedint32_header = block_header Obj.custom_tag 2
let boxedint64_header = block_header Obj.custom_tag (1 + 8 / size_addr)
let boxedintnat_header = block_header Obj.custom_tag 2

let alloc_block_header tag sz = Cconst_natint(block_header tag sz)
let alloc_float_header = Cconst_natint(float_header)
let alloc_floatarray_header len = Cconst_natint(floatarray_header len)
let alloc_closure_header sz = Cconst_natint(closure_header sz)
let alloc_infix_header ofs = Cconst_natint(infix_header ofs)
let alloc_boxedint32_header = Cconst_natint(boxedint32_header)
let alloc_boxedint64_header = Cconst_natint(boxedint64_header)
let alloc_boxedintnat_header = Cconst_natint(boxedintnat_header)

(* Integers *)

let max_repr_int = max_int asr 1
let min_repr_int = min_int asr 1

let int_const n =
  if n <= max_repr_int && n >= min_repr_int
  then Cconst_int((n lsl 1) + 1)
  else Cconst_natint
          (Nativeint.add (Nativeint.shift_left (Nativeint.of_int n) 1) 1n)

let add_const c n =
  if n = 0 then c else Cop(Caddi, [c; Cconst_int n])

let incr_int = function
    Cconst_int n when n < max_int -> Cconst_int(n+1)
  | Cop(Caddi, [c; Cconst_int n]) when n < max_int -> add_const c (n + 1)
  | c -> add_const c 1

let decr_int = function
    Cconst_int n when n > min_int -> Cconst_int(n-1)
  | Cop(Caddi, [c; Cconst_int n]) when n > min_int -> add_const c (n - 1)
  | c -> add_const c (-1)

let add_int c1 c2 =
  match (c1, c2) with
    (Cop(Caddi, [c1; Cconst_int n1]),
     Cop(Caddi, [c2; Cconst_int n2])) when no_overflow_add n1 n2 ->
      add_const (Cop(Caddi, [c1; c2])) (n1 + n2)
  | (Cop(Caddi, [c1; Cconst_int n1]), c2) ->
      add_const (Cop(Caddi, [c1; c2])) n1
  | (c1, Cop(Caddi, [c2; Cconst_int n2])) ->
      add_const (Cop(Caddi, [c1; c2])) n2
  | (Cconst_int _, _) ->
      Cop(Caddi, [c2; c1])
  | (_, _) ->
      Cop(Caddi, [c1; c2])

let sub_int c1 c2 =
  match (c1, c2) with
    (Cop(Caddi, [c1; Cconst_int n1]),
     Cop(Caddi, [c2; Cconst_int n2])) when no_overflow_sub n1 n2 ->
      add_const (Cop(Csubi, [c1; c2])) (n1 - n2)
  | (Cop(Caddi, [c1; Cconst_int n1]), c2) ->
      add_const (Cop(Csubi, [c1; c2])) n1
  | (c1, Cop(Caddi, [c2; Cconst_int n2])) when n2 <> min_int ->
      add_const (Cop(Csubi, [c1; c2])) (-n2)
  | (c1, Cconst_int n) when n <> min_int ->
      add_const c1 (-n)
  | (c1, c2) ->
      Cop(Csubi, [c1; c2])

let mul_int c1 c2 =
  match (c1, c2) with
    (Cconst_int 0, _) -> c1
  | (Cconst_int 1, _) -> c2
  | (_, Cconst_int 0) -> c2
  | (_, Cconst_int 1) -> c1
  | (_, _) -> Cop(Cmuli, [c1; c2])

let tag_int = function
    Cconst_int n -> int_const n
  | c -> Cop(Caddi, [Cop(Clsl, [c; Cconst_int 1]); Cconst_int 1])

let force_tag_int = function
    Cconst_int n -> int_const n
  | c -> Cop(Cor, [Cop(Clsl, [c; Cconst_int 1]); Cconst_int 1])

let untag_int = function
    Cconst_int n -> Cconst_int(n asr 1)
  | Cop(Caddi, [Cop(Clsl, [c; Cconst_int 1]); Cconst_int 1]) -> c
  | Cop(Cor, [Cop(Casr, [c; Cconst_int n]); Cconst_int 1])
    when n > 0 && n < size_int * 8 ->
      Cop(Casr, [c; Cconst_int (n+1)])
  | Cop(Cor, [Cop(Clsr, [c; Cconst_int n]); Cconst_int 1])
    when n > 0 && n < size_int * 8 ->
      Cop(Clsr, [c; Cconst_int (n+1)])
  | Cop(Cor, [c; Cconst_int 1]) -> Cop(Casr, [c; Cconst_int 1])
  | c -> Cop(Casr, [c; Cconst_int 1])

let lsl_int c1 c2 =
  match (c1, c2) with
    (Cop(Clsl, [c; Cconst_int n1]), Cconst_int n2)
    when n1 > 0 && n2 > 0 && n1 + n2 < size_int * 8 ->
      Cop(Clsl, [c; Cconst_int (n1 + n2)])
  | (_, _) ->
      Cop(Clsl, [c1; c2])

let ignore_low_bit_int = function
    Cop(Caddi, [(Cop(Clsl, [_; Cconst_int 1]) as c); Cconst_int 1]) -> c
  | Cop(Cor, [c; Cconst_int 1]) -> c
  | c -> c

let is_nonzero_constant = function
    Cconst_int n -> n <> 0
  | Cconst_natint n -> n <> 0n
  | _ -> false

let safe_divmod op c1 c2 dbg =
  if !Clflags.fast || is_nonzero_constant c2 then
    Cop(op, [c1; c2])
  else
    bind "divisor" c2 (fun c2 ->
      Cifthenelse(c2,
                  Cop(op, [c1; c2]),
                  Cop(Craise dbg,
                      [Cconst_symbol "caml_bucket_Division_by_zero"])))

(* Bool *)

let test_bool = function
    Cop(Caddi, [Cop(Clsl, [c; Cconst_int 1]); Cconst_int 1]) -> c
  | Cop(Clsl, [c; Cconst_int 1]) -> c
  | c -> Cop(Ccmpi Cne, [c; Cconst_int 1])

(* Float *)

let box_float c = Cop(Calloc, [alloc_float_header; c])

let rec unbox_float = function
    Cop(Calloc, [header; c]) -> c
  | Clet(id, exp, body) -> Clet(id, exp, unbox_float body)
  | Cifthenelse(cond, e1, e2) ->
      Cifthenelse(cond, unbox_float e1, unbox_float e2)
  | Csequence(e1, e2) -> Csequence(e1, unbox_float e2)
  | Cswitch(e, tbl, el) -> Cswitch(e, tbl, Array.map unbox_float el)
  | Ccatch(n, ids, e1, e2) -> Ccatch(n, ids, unbox_float e1, unbox_float e2)
  | Ctrywith(e1, id, e2) -> Ctrywith(unbox_float e1, id, unbox_float e2)
  | c -> Cop(Cload Double_u, [c])

(* Complex *)

let box_complex c_re c_im =
  Cop(Calloc, [alloc_floatarray_header 2; c_re; c_im])

let complex_re c = Cop(Cload Double_u, [c])
let complex_im c = Cop(Cload Double_u,
                       [Cop(Cadda, [c; Cconst_int size_float])])

(* Unit *)

let return_unit c = Csequence(c, Cconst_pointer 1)

let rec remove_unit = function
    Cconst_pointer 1 -> Ctuple []
  | Csequence(c, Cconst_pointer 1) -> c
  | Csequence(c1, c2) ->
      Csequence(c1, remove_unit c2)
  | Cifthenelse(cond, ifso, ifnot) ->
      Cifthenelse(cond, remove_unit ifso, remove_unit ifnot)
  | Cswitch(sel, index, cases) ->
      Cswitch(sel, index, Array.map remove_unit cases)
  | Ccatch(io, ids, body, handler) ->
      Ccatch(io, ids, remove_unit body, remove_unit handler)
  | Ctrywith(body, exn, handler) ->
      Ctrywith(remove_unit body, exn, remove_unit handler)
  | Clet(id, c1, c2) ->
      Clet(id, c1, remove_unit c2)
  | Cop(Capply (mty, dbg), args) ->
      Cop(Capply (typ_void, dbg), args)
  | Cop(Cextcall(proc, mty, alloc, dbg), args) ->
      Cop(Cextcall(proc, typ_void, alloc, dbg), args)
  | Cexit (_,_) as c -> c
  | Ctuple [] as c -> c
  | c -> Csequence(c, Ctuple [])

(* Access to block fields *)

let field_address ptr n =
  if n = 0
  then ptr
  else Cop(Cadda, [ptr; Cconst_int(n * size_addr)])

let get_field ptr n =
  Cop(Cload Word, [field_address ptr n])

let set_field ptr n newval =
  Cop(Cstore Word, [field_address ptr n; newval])

let header ptr =
  Cop(Cload Word, [Cop(Cadda, [ptr; Cconst_int(-size_int)])])

let tag_offset =
  if big_endian then -1 else -size_int

let get_tag ptr =
  if Proc.word_addressed then           (* If byte loads are slow *)
    Cop(Cand, [header ptr; Cconst_int 255])
  else                                  (* If byte loads are efficient *)
    Cop(Cload Byte_unsigned,
        [Cop(Cadda, [ptr; Cconst_int(tag_offset)])])

let get_size ptr =
  Cop(Clsr, [header ptr; Cconst_int 10])

(* Array indexing *)

let log2_size_addr = Misc.log2 size_addr
let log2_size_float = Misc.log2 size_float

let wordsize_shift = 9
let numfloat_shift = 9 + log2_size_float - log2_size_addr

let is_addr_array_hdr hdr =
  Cop(Ccmpi Cne, [Cop(Cand, [hdr; Cconst_int 255]); floatarray_tag])

let is_addr_array_ptr ptr =
  Cop(Ccmpi Cne, [get_tag ptr; floatarray_tag])

let addr_array_length hdr = Cop(Clsr, [hdr; Cconst_int wordsize_shift])
let float_array_length hdr = Cop(Clsr, [hdr; Cconst_int numfloat_shift])

let lsl_const c n =
  Cop(Clsl, [c; Cconst_int n])

let array_indexing log2size ptr ofs =
  match ofs with
    Cconst_int n ->
      let i = n asr 1 in
      if i = 0 then ptr else Cop(Cadda, [ptr; Cconst_int(i lsl log2size)])
  | Cop(Caddi, [Cop(Clsl, [c; Cconst_int 1]); Cconst_int 1]) ->
      Cop(Cadda, [ptr; lsl_const c log2size])
  | Cop(Caddi, [c; Cconst_int n]) ->
      Cop(Cadda, [Cop(Cadda, [ptr; lsl_const c (log2size - 1)]);
                   Cconst_int((n-1) lsl (log2size - 1))])
  | _ ->
      Cop(Cadda, [Cop(Cadda, [ptr; lsl_const ofs (log2size - 1)]);
                   Cconst_int((-1) lsl (log2size - 1))])

let addr_array_ref arr ofs =
  Cop(Cload Word, [array_indexing log2_size_addr arr ofs])
let unboxed_float_array_ref arr ofs =
  Cop(Cload Double_u, [array_indexing log2_size_float arr ofs])
let float_array_ref arr ofs =
  box_float(unboxed_float_array_ref arr ofs)

let addr_array_set arr ofs newval =
  Cop(Cextcall("caml_modify", typ_void, false, Debuginfo.none),
      [array_indexing log2_size_addr arr ofs; newval])
let int_array_set arr ofs newval =
  Cop(Cstore Word, [array_indexing log2_size_addr arr ofs; newval])
let float_array_set arr ofs newval =
  Cop(Cstore Double_u, [array_indexing log2_size_float arr ofs; newval])

(* String length *)

let string_length exp =
  bind "str" exp (fun str ->
    let tmp_var = Ident.create "tmp" in
    Clet(tmp_var,
         Cop(Csubi,
             [Cop(Clsl,
                   [Cop(Clsr, [header str; Cconst_int 10]);
                     Cconst_int log2_size_addr]);
              Cconst_int 1]),
         Cop(Csubi,
             [Cvar tmp_var;
               Cop(Cload Byte_unsigned,
                     [Cop(Cadda, [str; Cvar tmp_var])])])))

(* Message sending *)

let lookup_tag obj tag =
  bind "tag" tag (fun tag ->
    Cop(Cextcall("caml_get_public_method", typ_addr, false, Debuginfo.none),
        [obj; tag]))

let lookup_label obj lab =
  bind "lab" lab (fun lab ->
    let table = Cop (Cload Word, [obj]) in
    addr_array_ref table lab)

let call_cached_method obj tag cache pos args dbg =
  let arity = List.length args in
  let cache = array_indexing log2_size_addr cache pos in
  Compilenv.need_send_fun arity;
  Cop(Capply (typ_addr, dbg),
      Cconst_symbol("caml_send" ^ string_of_int arity) ::
      obj :: tag :: cache :: args)

(* Allocation *)

let make_alloc_generic set_fn tag wordsize args =
  if wordsize <= Config.max_young_wosize then
    Cop(Calloc, Cconst_natint(block_header tag wordsize) :: args)
  else begin
    let id = Ident.create "alloc" in
    let rec fill_fields idx = function
      [] -> Cvar id
    | e1::el -> Csequence(set_fn (Cvar id) (Cconst_int idx) e1,
                          fill_fields (idx + 2) el) in
    Clet(id,
         Cop(Cextcall("caml_alloc", typ_addr, true, Debuginfo.none),
                 [Cconst_int wordsize; Cconst_int tag]),
         fill_fields 1 args)
  end

let make_alloc tag args =
  make_alloc_generic addr_array_set tag (List.length args) args
let make_float_alloc tag args =
  make_alloc_generic float_array_set tag
                     (List.length args * size_float / size_addr) args

(* To compile "let rec" over values *)

let fundecls_size fundecls =
  let sz = ref (-1) in
  List.iter
    (fun (label, arity, params, body) ->
      sz := !sz + 1 + (if arity = 1 then 2 else 3))
    fundecls;
  !sz

type rhs_kind =
  | RHS_block of int
  | RHS_nonrec
;;
let rec expr_size = function
  | Uclosure(fundecls, clos_vars) ->
      RHS_block (fundecls_size fundecls + List.length clos_vars)
  | Ulet(id, exp, body) ->
      expr_size body
  | Uletrec(bindings, body) ->
      expr_size body
  | Uprim(Pmakeblock(tag, mut), args, _) ->
      RHS_block (List.length args)
  | Uprim(Pmakearray(Paddrarray | Pintarray), args, _) ->
      RHS_block (List.length args)
  | Usequence(exp, exp') ->
      expr_size exp'
  | _ -> RHS_nonrec

(* Record application and currying functions *)

let apply_function n =
  Compilenv.need_apply_fun n; "caml_apply" ^ string_of_int n
let curry_function n =
  Compilenv.need_curry_fun n;
  if n >= 0
  then "caml_curry" ^ string_of_int n
  else "caml_tuplify" ^ string_of_int (-n)

(* Comparisons *)

let transl_comparison = function
    Lambda.Ceq -> Ceq
  | Lambda.Cneq -> Cne
  | Lambda.Cge -> Cge
  | Lambda.Cgt -> Cgt
  | Lambda.Cle -> Cle
  | Lambda.Clt -> Clt

(* Translate structured constants *)

(* Fabrice: moved to compilenv.ml ----
let const_label = ref 0

let new_const_label () =
  incr const_label;
  !const_label

let new_const_symbol () =
  incr const_label;
  Compilenv.make_symbol (Some (string_of_int !const_label))

let structured_constants = ref ([] : (string * structured_constant) list)
*)

let transl_constant = function
    Const_base(Const_int n) ->
      int_const n
  | Const_base(Const_char c) ->
      Cconst_int(((Char.code c) lsl 1) + 1)
  | Const_pointer n ->
      if n <= max_repr_int && n >= min_repr_int
      then Cconst_pointer((n lsl 1) + 1)
      else Cconst_natpointer
              (Nativeint.add (Nativeint.shift_left (Nativeint.of_int n) 1) 1n)
  | cst ->
      Cconst_symbol (Compilenv.new_structured_constant cst false)

(* Translate constant closures *)

let constant_closures =
  ref ([] : (string * (string * int * Ident.t list * ulambda) list) list)

(* Boxed integers *)

let box_int_constant bi n =
  match bi with
    Pnativeint -> Const_base(Const_nativeint n)
  | Pint32 -> Const_base(Const_int32 (Nativeint.to_int32 n))
  | Pint64 -> Const_base(Const_int64 (Int64.of_nativeint n))

let operations_boxed_int bi =
  match bi with
    Pnativeint -> "caml_nativeint_ops"
  | Pint32 -> "caml_int32_ops"
  | Pint64 -> "caml_int64_ops"

let alloc_header_boxed_int bi =
  match bi with
    Pnativeint -> alloc_boxedintnat_header
  | Pint32 -> alloc_boxedint32_header
  | Pint64 -> alloc_boxedint64_header

let box_int bi arg =
  match arg with
    Cconst_int n ->
      transl_constant (box_int_constant bi (Nativeint.of_int n))
  | Cconst_natint n ->
      transl_constant (box_int_constant bi n)
  | _ ->
      let arg' =
        if bi = Pint32 && size_int = 8 && big_endian
        then Cop(Clsl, [arg; Cconst_int 32])
        else arg in
      Cop(Calloc, [alloc_header_boxed_int bi;
                   Cconst_symbol(operations_boxed_int bi);
                   arg'])

let rec unbox_int bi arg =
  match arg with
    Cop(Calloc, [hdr; ops; Cop(Clsl, [contents; Cconst_int 32])])
    when bi = Pint32 && size_int = 8 && big_endian ->
      (* Force sign-extension of low 32 bits *)
      Cop(Casr, [Cop(Clsl, [contents; Cconst_int 32]); Cconst_int 32])
  | Cop(Calloc, [hdr; ops; contents])
    when bi = Pint32 && size_int = 8 && not big_endian ->
      (* Force sign-extension of low 32 bits *)
      Cop(Casr, [Cop(Clsl, [contents; Cconst_int 32]); Cconst_int 32])
  | Cop(Calloc, [hdr; ops; contents]) ->
      contents
  | Clet(id, exp, body) -> Clet(id, exp, unbox_int bi body)
  | Cifthenelse(cond, e1, e2) ->
      Cifthenelse(cond, unbox_int bi e1, unbox_int bi e2)
  | Csequence(e1, e2) -> Csequence(e1, unbox_int bi e2)
  | Cswitch(e, tbl, el) -> Cswitch(e, tbl, Array.map (unbox_int bi) el)
  | Ccatch(n, ids, e1, e2) -> Ccatch(n, ids, unbox_int bi e1, unbox_int bi e2)
  | Ctrywith(e1, id, e2) -> Ctrywith(unbox_int bi e1, id, unbox_int bi e2)
  | _ ->
      Cop(Cload(if bi = Pint32 then Thirtytwo_signed else Word),
          [Cop(Cadda, [arg; Cconst_int size_addr])])

let make_unsigned_int bi arg =
  if bi = Pint32 && size_int = 8
  then Cop(Cand, [arg; Cconst_natint 0xFFFFFFFFn])
  else arg

(* Big arrays *)

let bigarray_elt_size = function
    Pbigarray_unknown -> assert false
  | Pbigarray_float32 -> 4
  | Pbigarray_float64 -> 8
  | Pbigarray_sint8 -> 1
  | Pbigarray_uint8 -> 1
  | Pbigarray_sint16 -> 2
  | Pbigarray_uint16 -> 2
  | Pbigarray_int32 -> 4
  | Pbigarray_int64 -> 8
  | Pbigarray_caml_int -> size_int
  | Pbigarray_native_int -> size_int
  | Pbigarray_complex32 -> 8
  | Pbigarray_complex64 -> 16

let bigarray_indexing unsafe elt_kind layout b args dbg =
  let check_bound a1 a2 k =
    if unsafe then k else Csequence(Cop(Ccheckbound dbg, [a1;a2]), k) in
  let rec ba_indexing dim_ofs delta_ofs = function
    [] -> assert false
  | [arg] ->
      bind "idx" (untag_int arg)
        (fun idx ->
           check_bound (Cop(Cload Word,[field_address b dim_ofs])) idx idx)
  | arg1 :: argl ->
      let rem = ba_indexing (dim_ofs + delta_ofs) delta_ofs argl in
      bind "idx" (untag_int arg1)
        (fun idx ->
          bind "bound" (Cop(Cload Word, [field_address b dim_ofs]))
          (fun bound ->
            check_bound bound idx (add_int (mul_int rem bound) idx))) in
  let offset =
    match layout with
      Pbigarray_unknown_layout ->
        assert false
    | Pbigarray_c_layout ->
        ba_indexing (4 + List.length args) (-1) (List.rev args)
    | Pbigarray_fortran_layout ->
        ba_indexing 5 1 (List.map (fun idx -> sub_int idx (Cconst_int 2)) args)
  and elt_size =
    bigarray_elt_size elt_kind in
  let byte_offset =
    if elt_size = 1
    then offset
    else Cop(Clsl, [offset; Cconst_int(log2 elt_size)]) in
  Cop(Cadda, [Cop(Cload Word, [field_address b 1]); byte_offset])

let bigarray_word_kind = function
    Pbigarray_unknown -> assert false
  | Pbigarray_float32 -> Single
  | Pbigarray_float64 -> Double
  | Pbigarray_sint8 -> Byte_signed
  | Pbigarray_uint8 -> Byte_unsigned
  | Pbigarray_sint16 -> Sixteen_signed
  | Pbigarray_uint16 -> Sixteen_unsigned
  | Pbigarray_int32 -> Thirtytwo_signed
  | Pbigarray_int64 -> Word
  | Pbigarray_caml_int -> Word
  | Pbigarray_native_int -> Word
  | Pbigarray_complex32 -> Single
  | Pbigarray_complex64 -> Double

let bigarray_get unsafe elt_kind layout b args dbg =
  bind "ba" b (fun b ->
    match elt_kind with
      Pbigarray_complex32 | Pbigarray_complex64 ->
        let kind = bigarray_word_kind elt_kind in
        let sz = bigarray_elt_size elt_kind / 2 in
        bind "addr" (bigarray_indexing unsafe elt_kind layout b args dbg) (fun addr ->
          box_complex
            (Cop(Cload kind, [addr]))
            (Cop(Cload kind, [Cop(Cadda, [addr; Cconst_int sz])])))
    | _ ->
        Cop(Cload (bigarray_word_kind elt_kind),
            [bigarray_indexing unsafe elt_kind layout b args dbg]))

let bigarray_set unsafe elt_kind layout b args newval dbg =
  bind "ba" b (fun b ->
    match elt_kind with
      Pbigarray_complex32 | Pbigarray_complex64 ->
        let kind = bigarray_word_kind elt_kind in
        let sz = bigarray_elt_size elt_kind / 2 in
        bind "newval" newval (fun newv ->
        bind "addr" (bigarray_indexing unsafe elt_kind layout b args dbg) (fun addr ->
          Csequence(
            Cop(Cstore kind, [addr; complex_re newv]),
            Cop(Cstore kind,
                [Cop(Cadda, [addr; Cconst_int sz]); complex_im newv]))))
    | _ ->
        Cop(Cstore (bigarray_word_kind elt_kind),
            [bigarray_indexing unsafe elt_kind layout b args dbg; newval]))

(* Simplification of some primitives into C calls *)

let default_prim name =
  { prim_name = name; prim_arity = 0 (*ignored*);
    prim_alloc = true; prim_native_name = ""; prim_native_float = false }

let simplif_primitive_32bits = function
    Pbintofint Pint64 -> Pccall (default_prim "caml_int64_of_int")
  | Pintofbint Pint64 -> Pccall (default_prim "caml_int64_to_int")
  | Pcvtbint(Pint32, Pint64) -> Pccall (default_prim "caml_int64_of_int32")
  | Pcvtbint(Pint64, Pint32) -> Pccall (default_prim "caml_int64_to_int32")
  | Pcvtbint(Pnativeint, Pint64) ->
      Pccall (default_prim "caml_int64_of_nativeint")
  | Pcvtbint(Pint64, Pnativeint) ->
      Pccall (default_prim "caml_int64_to_nativeint")
  | Pnegbint Pint64 -> Pccall (default_prim "caml_int64_neg")
  | Paddbint Pint64 -> Pccall (default_prim "caml_int64_add")
  | Psubbint Pint64 -> Pccall (default_prim "caml_int64_sub")
  | Pmulbint Pint64 -> Pccall (default_prim "caml_int64_mul")
  | Pdivbint Pint64 -> Pccall (default_prim "caml_int64_div")
  | Pmodbint Pint64 -> Pccall (default_prim "caml_int64_mod")
  | Pandbint Pint64 -> Pccall (default_prim "caml_int64_and")
  | Porbint Pint64 ->  Pccall (default_prim "caml_int64_or")
  | Pxorbint Pint64 -> Pccall (default_prim "caml_int64_xor")
  | Plslbint Pint64 -> Pccall (default_prim "caml_int64_shift_left")
  | Plsrbint Pint64 -> Pccall (default_prim "caml_int64_shift_right_unsigned")
  | Pasrbint Pint64 -> Pccall (default_prim "caml_int64_shift_right")
  | Pbintcomp(Pint64, Lambda.Ceq) -> Pccall (default_prim "caml_equal")
  | Pbintcomp(Pint64, Lambda.Cneq) -> Pccall (default_prim "caml_notequal")
  | Pbintcomp(Pint64, Lambda.Clt) -> Pccall (default_prim "caml_lessthan")
  | Pbintcomp(Pint64, Lambda.Cgt) -> Pccall (default_prim "caml_greaterthan")
  | Pbintcomp(Pint64, Lambda.Cle) -> Pccall (default_prim "caml_lessequal")
  | Pbintcomp(Pint64, Lambda.Cge) -> Pccall (default_prim "caml_greaterequal")
  | Pbigarrayref(unsafe, n, Pbigarray_int64, layout) ->
      Pccall (default_prim ("caml_ba_get_" ^ string_of_int n))
  | Pbigarrayset(unsafe, n, Pbigarray_int64, layout) ->
      Pccall (default_prim ("caml_ba_set_" ^ string_of_int n))
  | p -> p

let simplif_primitive p =
  match p with
  | Pduprecord _ ->
      Pccall (default_prim "caml_obj_dup")
  | Pbigarrayref(unsafe, n, Pbigarray_unknown, layout) ->
      Pccall (default_prim ("caml_ba_get_" ^ string_of_int n))
  | Pbigarrayset(unsafe, n, Pbigarray_unknown, layout) ->
      Pccall (default_prim ("caml_ba_set_" ^ string_of_int n))
  | Pbigarrayref(unsafe, n, kind, Pbigarray_unknown_layout) ->
      Pccall (default_prim ("caml_ba_get_" ^ string_of_int n))
  | Pbigarrayset(unsafe, n, kind, Pbigarray_unknown_layout) ->
      Pccall (default_prim ("caml_ba_set_" ^ string_of_int n))
  | p ->
      if size_int = 8 then p else simplif_primitive_32bits p

(* Build switchers both for constants and blocks *)

(* constants first *)

let transl_isout h arg = tag_int (Cop(Ccmpa Clt, [h ; arg]))

exception Found of int

let make_switch_gen arg cases acts =
  let lcases = Array.length cases in
  let new_cases = Array.create lcases 0 in
  let store = Switch.mk_store (=) in

  for i = 0 to Array.length cases-1 do
    let act = cases.(i) in
    let new_act = store.Switch.act_store act in
    new_cases.(i) <- new_act
  done ;
  Cswitch
    (arg, new_cases,
     Array.map
       (fun n -> acts.(n))
       (store.Switch.act_get ()))


(* Then for blocks *)

module SArgBlocks =
struct
  type primitive = operation

  let eqint = Ccmpi Ceq
  let neint = Ccmpi Cne
  let leint = Ccmpi Cle
  let ltint = Ccmpi Clt
  let geint = Ccmpi Cge
  let gtint = Ccmpi Cgt

  type act = expression

  let default = Cexit (0,[])
  let make_prim p args = Cop (p,args)
  let make_offset arg n = add_const arg n
  let make_isout h arg =  Cop (Ccmpa Clt, [h ; arg])
  let make_isin h arg =  Cop (Ccmpa Cge, [h ; arg])
  let make_if cond ifso ifnot = Cifthenelse (cond, ifso, ifnot)
  let make_switch arg cases actions =
    make_switch_gen arg cases actions
  let bind arg body = bind "switcher" arg body

end

module SwitcherBlocks = Switch.Make(SArgBlocks)

(* Auxiliary functions for optimizing "let" of boxed numbers (floats and
   boxed integers *)

type unboxed_number_kind =
    No_unboxing
  | Boxed_float
  | Boxed_integer of boxed_integer

let is_unboxed_number = function
    Uconst(Const_base(Const_float f), _) ->
      Boxed_float
  | Uprim(p, _, _) ->
      begin match simplif_primitive p with
          Pccall p -> if p.prim_native_float then Boxed_float else No_unboxing
        | Pfloatfield _ -> Boxed_float
        | Pfloatofint -> Boxed_float
        | Pnegfloat -> Boxed_float
        | Pabsfloat -> Boxed_float
        | Paddfloat -> Boxed_float
        | Psubfloat -> Boxed_float
        | Pmulfloat -> Boxed_float
        | Pdivfloat -> Boxed_float
        | Parrayrefu Pfloatarray -> Boxed_float
        | Parrayrefs Pfloatarray -> Boxed_float
        | Pbintofint bi -> Boxed_integer bi
        | Pcvtbint(src, dst) -> Boxed_integer dst
        | Pnegbint bi -> Boxed_integer bi
        | Paddbint bi -> Boxed_integer bi
        | Psubbint bi -> Boxed_integer bi
        | Pmulbint bi -> Boxed_integer bi
        | Pdivbint bi -> Boxed_integer bi
        | Pmodbint bi -> Boxed_integer bi
        | Pandbint bi -> Boxed_integer bi
        | Porbint bi -> Boxed_integer bi
        | Pxorbint bi -> Boxed_integer bi
        | Plslbint bi -> Boxed_integer bi
        | Plsrbint bi -> Boxed_integer bi
        | Pasrbint bi -> Boxed_integer bi
        | Pbigarrayref(_, _, (Pbigarray_float32 | Pbigarray_float64), _) ->
            Boxed_float
        | Pbigarrayref(_, _, Pbigarray_int32, _) -> Boxed_integer Pint32
        | Pbigarrayref(_, _, Pbigarray_int64, _) -> Boxed_integer Pint64
        | Pbigarrayref(_, _, Pbigarray_native_int, _) -> Boxed_integer Pnativeint
        | _ -> No_unboxing
      end
  | _ -> No_unboxing

let subst_boxed_number unbox_fn boxed_id unboxed_id exp =
  let need_boxed = ref false in
  let assigned = ref false in
  let rec subst = function
      Cvar id as e ->
        if Ident.same id boxed_id then need_boxed := true; e
    | Clet(id, arg, body) -> Clet(id, subst arg, subst body)
    | Cassign(id, arg) ->
        if Ident.same id boxed_id then begin
          assigned := true;
          Cassign(unboxed_id, subst(unbox_fn arg))
        end else
          Cassign(id, subst arg)
    | Ctuple argv -> Ctuple(List.map subst argv)
    | Cop(Cload _, [Cvar id]) as e ->
        if Ident.same id boxed_id then Cvar unboxed_id else e
    | Cop(Cload _, [Cop(Cadda, [Cvar id; _])]) as e ->
        if Ident.same id boxed_id then Cvar unboxed_id else e
    | Cop(op, argv) -> Cop(op, List.map subst argv)
    | Csequence(e1, e2) -> Csequence(subst e1, subst e2)
    | Cifthenelse(e1, e2, e3) -> Cifthenelse(subst e1, subst e2, subst e3)
    | Cswitch(arg, index, cases) ->
        Cswitch(subst arg, index, Array.map subst cases)
    | Cloop e -> Cloop(subst e)
    | Ccatch(nfail, ids, e1, e2) -> Ccatch(nfail, ids, subst e1, subst e2)
    | Cexit (nfail, el) -> Cexit (nfail, List.map subst el)
    | Ctrywith(e1, id, e2) -> Ctrywith(subst e1, id, subst e2)
    | e -> e in
  let res = subst exp in
  (res, !need_boxed, !assigned)

(* Translate an expression *)

let functions = (Queue.create() : (string * Ident.t list * ulambda) Queue.t)

let rec transl = function
    Uvar id ->
      Cvar id
  | Uconst (sc, Some const_label) ->
      Cconst_symbol const_label
  | Uconst (sc, None) ->
      transl_constant sc
  | Uclosure(fundecls, []) ->
      let lbl = Compilenv.new_const_symbol() in
      constant_closures := (lbl, fundecls) :: !constant_closures;
      List.iter
        (fun (label, arity, params, body) ->
          Queue.add (label, params, body) functions)
        fundecls;
      Cconst_symbol lbl
  | Uclosure(fundecls, clos_vars) ->
      let block_size =
        fundecls_size fundecls + List.length clos_vars in
      let rec transl_fundecls pos = function
          [] ->
            List.map transl clos_vars
        | (label, arity, params, body) :: rem ->
            Queue.add (label, params, body) functions;
            let header =
              if pos = 0
              then alloc_closure_header block_size
              else alloc_infix_header pos in
            if arity = 1 then
              header ::
              Cconst_symbol label ::
              int_const 1 ::
              transl_fundecls (pos + 3) rem
            else
              header ::
              Cconst_symbol(curry_function arity) ::
              int_const arity ::
              Cconst_symbol label ::
              transl_fundecls (pos + 4) rem in
      Cop(Calloc, transl_fundecls 0 fundecls)
  | Uoffset(arg, offset) ->
      field_address (transl arg) offset
  | Udirect_apply(lbl, args, dbg) ->
      Cop(Capply(typ_addr, dbg), Cconst_symbol lbl :: List.map transl args)
  | Ugeneric_apply(clos, [arg], dbg) ->
      bind "fun" (transl clos) (fun clos ->
        Cop(Capply(typ_addr, dbg), [get_field clos 0; transl arg; clos]))
  | Ugeneric_apply(clos, args, dbg) ->
      let arity = List.length args in
      let cargs = Cconst_symbol(apply_function arity) ::
        List.map transl (args @ [clos]) in
      Cop(Capply(typ_addr, dbg), cargs)
  | Usend(kind, met, obj, args, dbg) ->
      let call_met obj args clos =
        if args = [] then
          Cop(Capply(typ_addr, dbg), [get_field clos 0;obj;clos])
        else
          let arity = List.length args + 1 in
          let cargs = Cconst_symbol(apply_function arity) :: obj ::
            (List.map transl args) @ [clos] in
          Cop(Capply(typ_addr, dbg), cargs)
      in
      bind "obj" (transl obj) (fun obj ->
        match kind, args with
          Self, _ ->
            bind "met" (lookup_label obj (transl met)) (call_met obj args)
        | Cached, cache :: pos :: args ->
            call_cached_method obj (transl met) (transl cache) (transl pos)
              (List.map transl args) dbg
        | _ ->
            bind "met" (lookup_tag obj (transl met)) (call_met obj args))
  | Ulet(id, exp, body) ->
      begin match is_unboxed_number exp with
        No_unboxing ->
          Clet(id, transl exp, transl body)
      | Boxed_float ->
          transl_unbox_let box_float unbox_float transl_unbox_float
                           id exp body
      | Boxed_integer bi ->
          transl_unbox_let (box_int bi) (unbox_int bi) (transl_unbox_int bi)
                           id exp body
      end
  | Uletrec(bindings, body) ->
      transl_letrec bindings (transl body)

  (* Primitives *)
  | Uprim(prim, args, dbg) ->
      begin match (simplif_primitive prim, args) with
        (Pgetglobal id, []) ->
          Cconst_symbol (Ident.name id)
      | (Pmakeblock(tag, mut), []) ->
          transl_constant(Const_block(tag, []))
      | (Pmakeblock(tag, mut), args) ->
          make_alloc tag (List.map transl args)
      | (Pccall prim, args) ->
          if prim.prim_native_float then
            box_float
              (Cop(Cextcall(prim.prim_native_name, typ_float, false, dbg),
                   List.map transl_unbox_float args))
          else
            Cop(Cextcall(Primitive.native_name prim, typ_addr, prim.prim_alloc, dbg),
                List.map transl args)
      | (Pmakearray kind, []) ->
          transl_constant(Const_block(0, []))
      | (Pmakearray kind, args) ->
          begin match kind with
            Pgenarray ->
              Cop(Cextcall("caml_make_array", typ_addr, true, Debuginfo.none),
                  [make_alloc 0 (List.map transl args)])
          | Paddrarray | Pintarray ->
              make_alloc 0 (List.map transl args)
          | Pfloatarray ->
              make_float_alloc Obj.double_array_tag
                              (List.map transl_unbox_float args)
          end
      | (Pbigarrayref(unsafe, num_dims, elt_kind, layout), arg1 :: argl) ->
          let elt =
            bigarray_get unsafe elt_kind layout
              (transl arg1) (List.map transl argl) dbg in
          begin match elt_kind with
            Pbigarray_float32 | Pbigarray_float64 -> box_float elt
          | Pbigarray_complex32 | Pbigarray_complex64 -> elt
          | Pbigarray_int32 -> box_int Pint32 elt
          | Pbigarray_int64 -> box_int Pint64 elt
          | Pbigarray_native_int -> box_int Pnativeint elt
          | Pbigarray_caml_int -> force_tag_int elt
          | _ -> tag_int elt
          end
      | (Pbigarrayset(unsafe, num_dims, elt_kind, layout), arg1 :: argl) ->
          let (argidx, argnewval) = split_last argl in
          return_unit(bigarray_set unsafe elt_kind layout
            (transl arg1)
            (List.map transl argidx)
            (match elt_kind with
              Pbigarray_float32 | Pbigarray_float64 ->
                transl_unbox_float argnewval
            | Pbigarray_complex32 | Pbigarray_complex64 -> transl argnewval
            | Pbigarray_int32 -> transl_unbox_int Pint32 argnewval
            | Pbigarray_int64 -> transl_unbox_int Pint64 argnewval
            | Pbigarray_native_int -> transl_unbox_int Pnativeint argnewval
            | _ -> untag_int (transl argnewval))
            dbg)
      | (p, [arg]) ->
          transl_prim_1 p arg dbg
      | (p, [arg1; arg2]) ->
          transl_prim_2 p arg1 arg2 dbg
      | (p, [arg1; arg2; arg3]) ->
          transl_prim_3 p arg1 arg2 arg3 dbg
      | (_, _) ->
          fatal_error "Cmmgen.transl:prim"
      end

  (* Control structures *)
  | Uswitch(arg, s) ->
      (* As in the bytecode interpreter, only matching against constants
         can be checked *)
      if Array.length s.us_index_blocks = 0 then
        Cswitch
          (untag_int (transl arg),
           s.us_index_consts,
           Array.map transl s.us_actions_consts)
      else if Array.length s.us_index_consts = 0 then
        transl_switch (get_tag (transl arg))
          s.us_index_blocks s.us_actions_blocks
      else
        bind "switch" (transl arg) (fun arg ->
          Cifthenelse(
          Cop(Cand, [arg; Cconst_int 1]),
          transl_switch
            (untag_int arg) s.us_index_consts s.us_actions_consts,
          transl_switch
            (get_tag arg) s.us_index_blocks s.us_actions_blocks))
  | Ustaticfail (nfail, args) ->
      Cexit (nfail, List.map transl args)
  | Ucatch(nfail, [], body, handler) ->
      make_catch nfail (transl body) (transl handler)
  | Ucatch(nfail, ids, body, handler) ->
      Ccatch(nfail, ids, transl body, transl handler)
  | Utrywith(body, exn, handler) ->
      Ctrywith(transl body, exn, transl handler)
  | Uifthenelse(Uprim(Pnot, [arg], _), ifso, ifnot) ->
      transl (Uifthenelse(arg, ifnot, ifso))
  | Uifthenelse(cond, ifso, Ustaticfail (nfail, [])) ->
      exit_if_false cond (transl ifso) nfail
  | Uifthenelse(cond, Ustaticfail (nfail, []), ifnot) ->
      exit_if_true cond nfail (transl ifnot)
  | Uifthenelse(Uprim(Psequand, _, _) as cond, ifso, ifnot) ->
      let raise_num = next_raise_count () in
      make_catch
        raise_num
        (exit_if_false cond (transl ifso) raise_num)
        (transl ifnot)
  | Uifthenelse(Uprim(Psequor, _, _) as cond, ifso, ifnot) ->
      let raise_num = next_raise_count () in
      make_catch
        raise_num
        (exit_if_true cond raise_num (transl ifnot))
        (transl ifso)
  | Uifthenelse (Uifthenelse (cond, condso, condnot), ifso, ifnot) ->
      let num_true = next_raise_count () in
      make_catch
        num_true
        (make_catch2
           (fun shared_false ->
             Cifthenelse
               (test_bool (transl cond),
                exit_if_true condso num_true shared_false,
                exit_if_true condnot num_true shared_false))
           (transl ifnot))
        (transl ifso)
  | Uifthenelse(cond, ifso, ifnot) ->
      Cifthenelse(test_bool(transl cond), transl ifso, transl ifnot)
  | Usequence(exp1, exp2) ->
      Csequence(remove_unit(transl exp1), transl exp2)
  | Uwhile(cond, body) ->
      let raise_num = next_raise_count () in
      return_unit
        (Ccatch
           (raise_num, [],
            Cloop(exit_if_false cond (remove_unit(transl body)) raise_num),
            Ctuple []))
  | Ufor(id, low, high, dir, body) ->
      let tst = match dir with Upto -> Cgt   | Downto -> Clt in
      let inc = match dir with Upto -> Caddi | Downto -> Csubi in
      let raise_num = next_raise_count () in
      let id_prev = Ident.rename id in
      return_unit
        (Clet
           (id, transl low,
            bind_nonvar "bound" (transl high) (fun high ->
              Ccatch
                (raise_num, [],
                 Cifthenelse
                   (Cop(Ccmpi tst, [Cvar id; high]), Cexit (raise_num, []),
                    Cloop
                      (Csequence
                         (remove_unit(transl body),
                         Clet(id_prev, Cvar id,
                          Csequence
                            (Cassign(id,
                               Cop(inc, [Cvar id; Cconst_int 2])),
                             Cifthenelse
                               (Cop(Ccmpi Ceq, [Cvar id_prev; high]),
                                Cexit (raise_num,[]), Ctuple [])))))),
                 Ctuple []))))
  | Uassign(id, exp) ->
      return_unit(Cassign(id, transl exp))

and transl_prim_1 p arg dbg =
  match p with
  (* Generic operations *)
    Pidentity ->
      transl arg
  | Pignore ->
      return_unit(remove_unit (transl arg))
  (* Heap operations *)
  | Pfield n ->
      get_field (transl arg) n
  | Pfloatfield n ->
      let ptr = transl arg in
      box_float(
        Cop(Cload Double_u,
            [if n = 0 then ptr
                       else Cop(Cadda, [ptr; Cconst_int(n * size_float)])]))
  (* Exceptions *)
  | Praise ->
      Cop(Craise dbg, [transl arg])
  (* Integer operations *)
  | Pnegint ->
      Cop(Csubi, [Cconst_int 2; transl arg])
  | Poffsetint n ->
      if no_overflow_lsl n then
        add_const (transl arg) (n lsl 1)
      else
        transl_prim_2 Paddint arg (Uconst (Const_base(Const_int n), None)) Debuginfo.none
  | Poffsetref n ->
      return_unit
        (bind "ref" (transl arg) (fun arg ->
          Cop(Cstore Word,
              [arg; add_const (Cop(Cload Word, [arg])) (n lsl 1)])))
  (* Floating-point operations *)
  | Pfloatofint ->
      box_float(Cop(Cfloatofint, [untag_int(transl arg)]))
  | Pintoffloat ->
     tag_int(Cop(Cintoffloat, [transl_unbox_float arg]))
  | Pnegfloat ->
      box_float(Cop(Cnegf, [transl_unbox_float arg]))
  | Pabsfloat ->
      box_float(Cop(Cabsf, [transl_unbox_float arg]))
  (* String operations *)
  | Pstringlength ->
      tag_int(string_length (transl arg))
  (* Array operations *)
  | Parraylength kind ->
      begin match kind with
        Pgenarray ->
          let len =
            if wordsize_shift = numfloat_shift then
              Cop(Clsr, [header(transl arg); Cconst_int wordsize_shift])
            else
              bind "header" (header(transl arg)) (fun hdr ->
                Cifthenelse(is_addr_array_hdr hdr,
                            Cop(Clsr, [hdr; Cconst_int wordsize_shift]),
                            Cop(Clsr, [hdr; Cconst_int numfloat_shift]))) in
          Cop(Cor, [len; Cconst_int 1])
      | Paddrarray | Pintarray ->
          Cop(Cor, [addr_array_length(header(transl arg)); Cconst_int 1])
      | Pfloatarray ->
          Cop(Cor, [float_array_length(header(transl arg)); Cconst_int 1])
      end
  (* Boolean operations *)
  | Pnot ->
      Cop(Csubi, [Cconst_int 4; transl arg]) (* 1 -> 3, 3 -> 1 *)
  (* Test integer/block *)
  | Pisint ->
      tag_int(Cop(Cand, [transl arg; Cconst_int 1]))
  (* Boxed integers *)
  | Pbintofint bi ->
      box_int bi (untag_int (transl arg))
  | Pintofbint bi ->
      force_tag_int (transl_unbox_int bi arg)
  | Pcvtbint(bi1, bi2) ->
      box_int bi2 (transl_unbox_int bi1 arg)
  | Pnegbint bi ->
      box_int bi (Cop(Csubi, [Cconst_int 0; transl_unbox_int bi arg]))
  | _ ->
      fatal_error "Cmmgen.transl_prim_1"

and transl_prim_2 p arg1 arg2 dbg =
  match p with
  (* Heap operations *)
    Psetfield(n, ptr) ->
      if ptr then
        return_unit(Cop(Cextcall("caml_modify", typ_void, false, Debuginfo.none),
                        [field_address (transl arg1) n; transl arg2]))
      else
        return_unit(set_field (transl arg1) n (transl arg2))
  | Psetfloatfield n ->
      let ptr = transl arg1 in
      return_unit(
        Cop(Cstore Double_u,
            [if n = 0 then ptr
                       else Cop(Cadda, [ptr; Cconst_int(n * size_float)]);
                   transl_unbox_float arg2]))

  (* Boolean operations *)
  | Psequand ->
      Cifthenelse(test_bool(transl arg1), transl arg2, Cconst_int 1)
      (* let id = Ident.create "res1" in
      Clet(id, transl arg1,
           Cifthenelse(test_bool(Cvar id), transl arg2, Cvar id)) *)
  | Psequor ->
      Cifthenelse(test_bool(transl arg1), Cconst_int 3, transl arg2)

  (* Integer operations *)
  | Paddint ->
      decr_int(add_int (transl arg1) (transl arg2))
  | Psubint ->
      incr_int(sub_int (transl arg1) (transl arg2))
  | Pmulint ->
      incr_int(Cop(Cmuli, [decr_int(transl arg1); untag_int(transl arg2)]))
  | Pdivint ->
      tag_int(safe_divmod Cdivi (untag_int(transl arg1)) (untag_int(transl arg2)) dbg)
  | Pmodint ->
      tag_int(safe_divmod Cmodi (untag_int(transl arg1)) (untag_int(transl arg2)) dbg)
  | Pandint ->
      Cop(Cand, [transl arg1; transl arg2])
  | Porint ->
      Cop(Cor, [transl arg1; transl arg2])
  | Pxorint ->
      Cop(Cor, [Cop(Cxor, [ignore_low_bit_int(transl arg1);
                           ignore_low_bit_int(transl arg2)]);
                Cconst_int 1])
  | Plslint ->
      incr_int(lsl_int (decr_int(transl arg1)) (untag_int(transl arg2)))
  | Plsrint ->
      Cop(Cor, [Cop(Clsr, [transl arg1; untag_int(transl arg2)]);
                Cconst_int 1])
  | Pasrint ->
      Cop(Cor, [Cop(Casr, [transl arg1; untag_int(transl arg2)]);
                Cconst_int 1])
  | Pintcomp cmp ->
      tag_int(Cop(Ccmpi(transl_comparison cmp), [transl arg1; transl arg2]))
  | Pisout ->
      transl_isout (transl arg1) (transl arg2)
  (* Float operations *)
  | Paddfloat ->
      box_float(Cop(Caddf,
                    [transl_unbox_float arg1; transl_unbox_float arg2]))
  | Psubfloat ->
      box_float(Cop(Csubf,
                    [transl_unbox_float arg1; transl_unbox_float arg2]))
  | Pmulfloat ->
      box_float(Cop(Cmulf,
                    [transl_unbox_float arg1; transl_unbox_float arg2]))
  | Pdivfloat ->
      box_float(Cop(Cdivf,
                    [transl_unbox_float arg1; transl_unbox_float arg2]))
  | Pfloatcomp cmp ->
      tag_int(Cop(Ccmpf(transl_comparison cmp),
                  [transl_unbox_float arg1; transl_unbox_float arg2]))

  (* String operations *)
  | Pstringrefu ->
      tag_int(Cop(Cload Byte_unsigned,
                  [add_int (transl arg1) (untag_int(transl arg2))]))
  | Pstringrefs ->
      tag_int
        (bind "str" (transl arg1) (fun str ->
          bind "index" (untag_int (transl arg2)) (fun idx ->
            Csequence(
              Cop(Ccheckbound dbg, [string_length str; idx]),
              Cop(Cload Byte_unsigned, [add_int str idx])))))

  (* Array operations *)
  | Parrayrefu kind ->
      begin match kind with
        Pgenarray ->
          bind "arr" (transl arg1) (fun arr ->
            bind "index" (transl arg2) (fun idx ->
              Cifthenelse(is_addr_array_ptr arr,
                          addr_array_ref arr idx,
                          float_array_ref arr idx)))
      | Paddrarray | Pintarray ->
          addr_array_ref (transl arg1) (transl arg2)
      | Pfloatarray ->
          float_array_ref (transl arg1) (transl arg2)
      end
  | Parrayrefs kind ->
      begin match kind with
        Pgenarray ->
          bind "index" (transl arg2) (fun idx ->
            bind "arr" (transl arg1) (fun arr ->
              bind "header" (header arr) (fun hdr ->
                Cifthenelse(is_addr_array_hdr hdr,
                  Csequence(Cop(Ccheckbound dbg, [addr_array_length hdr; idx]),
                            addr_array_ref arr idx),
                  Csequence(Cop(Ccheckbound dbg, [float_array_length hdr; idx]),
                            float_array_ref arr idx)))))
      | Paddrarray | Pintarray ->
          bind "index" (transl arg2) (fun idx ->
            bind "arr" (transl arg1) (fun arr ->
              Csequence(Cop(Ccheckbound dbg, [addr_array_length(header arr); idx]),
                        addr_array_ref arr idx)))
      | Pfloatarray ->
          box_float(
            bind "index" (transl arg2) (fun idx ->
              bind "arr" (transl arg1) (fun arr ->
                Csequence(Cop(Ccheckbound dbg,
                              [float_array_length(header arr); idx]),
                          unboxed_float_array_ref arr idx))))
      end

  (* Operations on bitvects *)
  | Pbittest ->
      bind "index" (untag_int(transl arg2)) (fun idx ->
        tag_int(
          Cop(Cand, [Cop(Clsr, [Cop(Cload Byte_unsigned,
                                    [add_int (transl arg1)
                                      (Cop(Clsr, [idx; Cconst_int 3]))]);
                                Cop(Cand, [idx; Cconst_int 7])]);
                     Cconst_int 1])))

  (* Boxed integers *)
  | Paddbint bi ->
      box_int bi (Cop(Caddi,
                      [transl_unbox_int bi arg1; transl_unbox_int bi arg2]))
  | Psubbint bi ->
      box_int bi (Cop(Csubi,
                      [transl_unbox_int bi arg1; transl_unbox_int bi arg2]))
  | Pmulbint bi ->
      box_int bi (Cop(Cmuli,
                      [transl_unbox_int bi arg1; transl_unbox_int bi arg2]))
  | Pdivbint bi ->
      box_int bi (safe_divmod Cdivi
                      (transl_unbox_int bi arg1) (transl_unbox_int bi arg2)
                      dbg)
  | Pmodbint bi ->
      box_int bi (safe_divmod Cmodi
                      (transl_unbox_int bi arg1) (transl_unbox_int bi arg2)
                      dbg)
  | Pandbint bi ->
      box_int bi (Cop(Cand,
                     [transl_unbox_int bi arg1; transl_unbox_int bi arg2]))
  | Porbint bi ->
      box_int bi (Cop(Cor,
                     [transl_unbox_int bi arg1; transl_unbox_int bi arg2]))
  | Pxorbint bi ->
      box_int bi (Cop(Cxor,
                     [transl_unbox_int bi arg1; transl_unbox_int bi arg2]))
  | Plslbint bi ->
      box_int bi (Cop(Clsl,
                     [transl_unbox_int bi arg1; untag_int(transl arg2)]))
  | Plsrbint bi ->
      box_int bi (Cop(Clsr,
                     [make_unsigned_int bi (transl_unbox_int bi arg1);
                      untag_int(transl arg2)]))
  | Pasrbint bi ->
      box_int bi (Cop(Casr,
                     [transl_unbox_int bi arg1; untag_int(transl arg2)]))
  | Pbintcomp(bi, cmp) ->
      tag_int (Cop(Ccmpi(transl_comparison cmp),
                     [transl_unbox_int bi arg1; transl_unbox_int bi arg2]))
  | _ ->
      fatal_error "Cmmgen.transl_prim_2"

and transl_prim_3 p arg1 arg2 arg3 dbg =
  match p with
  (* String operations *)
    Pstringsetu ->
      return_unit(Cop(Cstore Byte_unsigned,
                      [add_int (transl arg1) (untag_int(transl arg2));
                        untag_int(transl arg3)]))
  | Pstringsets ->
      return_unit
        (bind "str" (transl arg1) (fun str ->
          bind "index" (untag_int (transl arg2)) (fun idx ->
            Csequence(
              Cop(Ccheckbound dbg, [string_length str; idx]),
              Cop(Cstore Byte_unsigned,
                  [add_int str idx; untag_int(transl arg3)])))))

  (* Array operations *)
  | Parraysetu kind ->
      return_unit(begin match kind with
        Pgenarray ->
          bind "newval" (transl arg3) (fun newval ->
            bind "index" (transl arg2) (fun index ->
              bind "arr" (transl arg1) (fun arr ->
                Cifthenelse(is_addr_array_ptr arr,
                            addr_array_set arr index newval,
                            float_array_set arr index (unbox_float newval)))))
      | Paddrarray ->
          addr_array_set (transl arg1) (transl arg2) (transl arg3)
      | Pintarray ->
          int_array_set (transl arg1) (transl arg2) (transl arg3)
      | Pfloatarray ->
          float_array_set (transl arg1) (transl arg2) (transl_unbox_float arg3)
      end)
  | Parraysets kind ->
      return_unit(begin match kind with
        Pgenarray ->
          bind "newval" (transl arg3) (fun newval ->
            bind "index" (transl arg2) (fun idx ->
              bind "arr" (transl arg1) (fun arr ->
                bind "header" (header arr) (fun hdr ->
                  Cifthenelse(is_addr_array_hdr hdr,
                    Csequence(Cop(Ccheckbound dbg, [addr_array_length hdr; idx]),
                              addr_array_set arr idx newval),
                    Csequence(Cop(Ccheckbound dbg, [float_array_length hdr; idx]),
                              float_array_set arr idx
                                              (unbox_float newval)))))))
      | Paddrarray ->
          bind "index" (transl arg2) (fun idx ->
            bind "arr" (transl arg1) (fun arr ->
              Csequence(Cop(Ccheckbound dbg, [addr_array_length(header arr); idx]),
                        addr_array_set arr idx (transl arg3))))
      | Pintarray ->
          bind "index" (transl arg2) (fun idx ->
            bind "arr" (transl arg1) (fun arr ->
              Csequence(Cop(Ccheckbound dbg, [addr_array_length(header arr); idx]),
                        int_array_set arr idx (transl arg3))))
      | Pfloatarray ->
          bind "index" (transl arg2) (fun idx ->
            bind "arr" (transl arg1) (fun arr ->
              Csequence(Cop(Ccheckbound dbg, [float_array_length(header arr);idx]),
                        float_array_set arr idx (transl_unbox_float arg3))))
      end)
  | _ ->
    fatal_error "Cmmgen.transl_prim_3"

and transl_unbox_float = function
    Uconst(Const_base(Const_float f), _) -> Cconst_float f
  | exp -> unbox_float(transl exp)

and transl_unbox_int bi = function
    Uconst(Const_base(Const_int32 n), _) ->
      Cconst_natint (Nativeint.of_int32 n)
  | Uconst(Const_base(Const_nativeint n), _) ->
      Cconst_natint n
  | Uconst(Const_base(Const_int64 n), _) ->
      assert (size_int = 8); Cconst_natint (Int64.to_nativeint n)
  | Uprim(Pbintofint bi', [Uconst(Const_base(Const_int i),_)], _) when bi = bi' ->
      Cconst_int i
  | exp -> unbox_int bi (transl exp)

and transl_unbox_let box_fn unbox_fn transl_unbox_fn id exp body =
  let unboxed_id = Ident.create (Ident.name id) in
  let trbody1 = transl body in
  let (trbody2, need_boxed, is_assigned) =
    subst_boxed_number unbox_fn id unboxed_id trbody1 in
  if need_boxed && is_assigned then
    Clet(id, transl exp, trbody1)
  else
    Clet(unboxed_id, transl_unbox_fn exp,
         if need_boxed
         then Clet(id, box_fn(Cvar unboxed_id), trbody2)
         else trbody2)

and make_catch ncatch body handler = match body with
| Cexit (nexit,[]) when nexit=ncatch -> handler
| _ ->  Ccatch (ncatch, [], body, handler)

and make_catch2 mk_body handler = match handler with
| Cexit (_,[])|Ctuple []|Cconst_int _|Cconst_pointer _ ->
    mk_body handler
| _ ->
    let nfail = next_raise_count () in
    make_catch
      nfail
      (mk_body (Cexit (nfail,[])))
      handler

and exit_if_true cond nfail otherwise =
  match cond with
  | Uconst (Const_pointer 0, _) -> otherwise
  | Uconst (Const_pointer 1, _) -> Cexit (nfail,[])
  | Uprim(Psequor, [arg1; arg2], _) ->
      exit_if_true arg1 nfail (exit_if_true arg2 nfail otherwise)
  | Uprim(Psequand, _, _) ->
      begin match otherwise with
      | Cexit (raise_num,[]) ->
          exit_if_false cond (Cexit (nfail,[])) raise_num
      | _ ->
          let raise_num = next_raise_count () in
          make_catch
            raise_num
            (exit_if_false cond (Cexit (nfail,[])) raise_num)
            otherwise
      end
  | Uprim(Pnot, [arg], _) ->
      exit_if_false arg otherwise nfail
  | Uifthenelse (cond, ifso, ifnot) ->
      make_catch2
        (fun shared ->
          Cifthenelse
            (test_bool (transl cond),
             exit_if_true ifso nfail shared,
             exit_if_true ifnot nfail shared))
        otherwise
  | _ ->
      Cifthenelse(test_bool(transl cond), Cexit (nfail, []), otherwise)

and exit_if_false cond otherwise nfail =
  match cond with
  | Uconst (Const_pointer 0, _) -> Cexit (nfail,[])
  | Uconst (Const_pointer 1, _) -> otherwise
  | Uprim(Psequand, [arg1; arg2], _) ->
      exit_if_false arg1 (exit_if_false arg2 otherwise nfail) nfail
  | Uprim(Psequor, _, _) ->
      begin match otherwise with
      | Cexit (raise_num,[]) ->
          exit_if_true cond raise_num (Cexit (nfail,[]))
      | _ ->
          let raise_num = next_raise_count () in
          make_catch
            raise_num
            (exit_if_true cond raise_num (Cexit (nfail,[])))
            otherwise
      end
  | Uprim(Pnot, [arg], _) ->
      exit_if_true arg nfail otherwise
  | Uifthenelse (cond, ifso, ifnot) ->
      make_catch2
        (fun shared ->
          Cifthenelse
            (test_bool (transl cond),
             exit_if_false ifso shared nfail,
             exit_if_false ifnot shared nfail))
        otherwise
  | _ ->
      Cifthenelse(test_bool(transl cond), otherwise, Cexit (nfail, []))

and transl_switch arg index cases = match Array.length cases with
| 0 -> fatal_error "Cmmgen.transl_switch"
| 1 -> transl cases.(0)
| _ ->
    let n_index = Array.length index in
    let actions = Array.map transl cases in

    let inters = ref []
    and this_high = ref (n_index-1)
    and this_low = ref (n_index-1)
    and this_act = ref index.(n_index-1) in
    for i = n_index-2 downto 0 do
      let act = index.(i) in
      if act = !this_act then
        decr this_low
      else begin
        inters := (!this_low, !this_high, !this_act) :: !inters ;
        this_high := i ;
        this_low := i ;
        this_act := act
      end
    done ;
    inters := (0, !this_high, !this_act) :: !inters ;
    bind "switcher" arg
      (fun a ->
        SwitcherBlocks.zyva
          (0,n_index-1)
          (fun i -> Cconst_int i)
          a
          (Array.of_list !inters) actions)

and transl_letrec bindings cont =
  let bsz = List.map (fun (id, exp) -> (id, exp, expr_size exp)) bindings in
  let rec init_blocks = function
    | [] -> fill_nonrec bsz
    | (id, exp, RHS_block sz) :: rem ->
        Clet(id, Cop(Cextcall("caml_alloc_dummy", typ_addr, true, Debuginfo.none),
                     [int_const sz]),
             init_blocks rem)
    | (id, exp, RHS_nonrec) :: rem ->
        Clet (id, Cconst_int 0, init_blocks rem)
  and fill_nonrec = function
    | [] -> fill_blocks bsz
    | (id, exp, RHS_block sz) :: rem -> fill_nonrec rem
    | (id, exp, RHS_nonrec) :: rem ->
        Clet (id, transl exp, fill_nonrec rem)
  and fill_blocks = function
    | [] -> cont
    | (id, exp, RHS_block _) :: rem ->
        Csequence(Cop(Cextcall("caml_update_dummy", typ_void, false, Debuginfo.none),
                      [Cvar id; transl exp]),
                  fill_blocks rem)
    | (id, exp, RHS_nonrec) :: rem ->
        fill_blocks rem
  in init_blocks bsz

(* Translate a function definition *)

let transl_function lbl params body =
  Cfunction {fun_name = lbl;
             fun_args = List.map (fun id -> (id, typ_addr)) params;
             fun_body = transl body;
             fun_fast = !Clflags.optimize_for_speed}

(* Translate all function definitions *)

module StringSet =
  Set.Make(struct
    type t = string
    let compare = compare
  end)

let rec transl_all_functions already_translated cont =
  try
    let (lbl, params, body) = Queue.take functions in
    if StringSet.mem lbl already_translated then
      transl_all_functions already_translated cont
    else begin
      transl_all_functions (StringSet.add lbl already_translated)
                           (transl_function lbl params body :: cont)
    end
  with Queue.Empty ->
    cont

(* Emit structured constants *)

let immstrings = Hashtbl.create 17

let rec emit_constant symb cst cont =
  match cst with
    Const_base(Const_float s) ->
      Cint(float_header) :: Cdefine_symbol symb :: Cdouble s :: cont
  | Const_base(Const_string s) | Const_immstring s ->
      Cint(string_header (String.length s)) ::
      Cdefine_symbol symb ::
      emit_string_constant s cont
  | Const_base(Const_int32 n) ->
      Cint(boxedint32_header) :: Cdefine_symbol symb ::
      emit_boxed_int32_constant n cont
  | Const_base(Const_int64 n) ->
      Cint(boxedint64_header) :: Cdefine_symbol symb ::
      emit_boxed_int64_constant n cont
  | Const_base(Const_nativeint n) ->
      Cint(boxedintnat_header) :: Cdefine_symbol symb ::
      emit_boxed_nativeint_constant n cont
  | Const_block(tag, fields) ->
      let (emit_fields, cont1) = emit_constant_fields fields cont in
      Cint(block_header tag (List.length fields)) ::
      Cdefine_symbol symb ::
      emit_fields @ cont1
  | Const_float_array(fields) ->
      Cint(floatarray_header (List.length fields)) ::
      Cdefine_symbol symb ::
      Misc.map_end (fun f -> Cdouble f) fields cont
  | _ -> fatal_error "gencmm.emit_constant"

and emit_constant_fields fields cont =
  match fields with
    [] -> ([], cont)
  | f1 :: fl ->
      let (data1, cont1) = emit_constant_field f1 cont in
      let (datal, contl) = emit_constant_fields fl cont1 in
      (data1 :: datal, contl)

and emit_constant_field field cont =
  match field with
    Const_base(Const_int n) ->
      (Cint(Nativeint.add (Nativeint.shift_left (Nativeint.of_int n) 1) 1n),
       cont)
  | Const_base(Const_char c) ->
      (Cint(Nativeint.of_int(((Char.code c) lsl 1) + 1)), cont)
  | Const_base(Const_float s) ->
      let lbl = Compilenv.new_const_label() in
      (Clabel_address lbl,
       Cint(float_header) :: Cdefine_label lbl :: Cdouble s :: cont)
  | Const_base(Const_string s) ->
      let lbl = Compilenv.new_const_label() in
      (Clabel_address lbl,
       Cint(string_header (String.length s)) :: Cdefine_label lbl ::
       emit_string_constant s cont)
  | Const_immstring s ->
      begin try
        (Clabel_address (Hashtbl.find immstrings s), cont)
      with Not_found ->
        let lbl = Compilenv.new_const_label() in
        Hashtbl.add immstrings s lbl;
        (Clabel_address lbl,
         Cint(string_header (String.length s)) :: Cdefine_label lbl ::
         emit_string_constant s cont)
      end
  | Const_base(Const_int32 n) ->
      let lbl = Compilenv.new_const_label() in
      (Clabel_address lbl,
       Cint(boxedint32_header) :: Cdefine_label lbl ::
       emit_boxed_int32_constant n cont)
  | Const_base(Const_int64 n) ->
      let lbl = Compilenv.new_const_label() in
      (Clabel_address lbl,
       Cint(boxedint64_header) :: Cdefine_label lbl ::
       emit_boxed_int64_constant n cont)
  | Const_base(Const_nativeint n) ->
      let lbl = Compilenv.new_const_label() in
      (Clabel_address lbl,
       Cint(boxedintnat_header) :: Cdefine_label lbl ::
       emit_boxed_nativeint_constant n cont)
  | Const_pointer n ->
      (Cint(Nativeint.add (Nativeint.shift_left (Nativeint.of_int n) 1) 1n),
       cont)
  | Const_block(tag, fields) ->
      let lbl = Compilenv.new_const_label() in
      let (emit_fields, cont1) = emit_constant_fields fields cont in
      (Clabel_address lbl,
       Cint(block_header tag (List.length fields)) :: Cdefine_label lbl ::
       emit_fields @ cont1)
  | Const_float_array(fields) ->
      let lbl = Compilenv.new_const_label() in
      (Clabel_address lbl,
       Cint(floatarray_header (List.length fields)) :: Cdefine_label lbl ::
       Misc.map_end (fun f -> Cdouble f) fields cont)

and emit_string_constant s cont =
  let n = size_int - 1 - (String.length s) mod size_int in
  Cstring s :: Cskip n :: Cint8 n :: cont

and emit_boxed_int32_constant n cont =
  let n = Nativeint.of_int32 n in
  if size_int = 8 then
    Csymbol_address("caml_int32_ops") :: Cint32 n :: Cint32 0n :: cont
  else
    Csymbol_address("caml_int32_ops") :: Cint n :: cont

and emit_boxed_nativeint_constant n cont =
  Csymbol_address("caml_nativeint_ops") :: Cint n :: cont

and emit_boxed_int64_constant n cont =
  let lo = Int64.to_nativeint n in
  if size_int = 8 then
    Csymbol_address("caml_int64_ops") :: Cint lo :: cont
  else begin
    let hi = Int64.to_nativeint (Int64.shift_right n 32) in
    if big_endian then
      Csymbol_address("caml_int64_ops") :: Cint hi :: Cint lo :: cont
    else
      Csymbol_address("caml_int64_ops") :: Cint lo :: Cint hi :: cont
  end

(* Emit constant closures *)

let emit_constant_closure symb fundecls cont =
  match fundecls with
    [] -> assert false
  | (label, arity, params, body) :: remainder ->
      let rec emit_others pos = function
        [] -> cont
      | (label, arity, params, body) :: rem ->
          if arity = 1 then
            Cint(infix_header pos) ::
            Csymbol_address label ::
            Cint 3n ::
            emit_others (pos + 3) rem
          else
            Cint(infix_header pos) ::
            Csymbol_address(curry_function arity) ::
            Cint(Nativeint.of_int (arity lsl 1 + 1)) ::
            Csymbol_address label ::
            emit_others (pos + 4) rem in
      Cint(closure_header (fundecls_size fundecls)) ::
      Cdefine_symbol symb ::
      if arity = 1 then
        Csymbol_address label ::
        Cint 3n ::
        emit_others 3 remainder
      else
        Csymbol_address(curry_function arity) ::
        Cint(Nativeint.of_int (arity lsl 1 + 1)) ::
        Csymbol_address label ::
        emit_others 4 remainder

(* Emit all structured constants *)

let emit_all_constants cont =
  let c = ref cont in
  List.iter
    (fun (lbl, global, cst) -> 
       let cst = emit_constant lbl cst [] in
       let cst = if global then 
	 Cglobal_symbol lbl :: cst
       else cst in
	 c:= Cdata(cst):: !c)
    (Compilenv.structured_constants());
(*  structured_constants := []; done in Compilenv.reset() *)
  Hashtbl.clear immstrings;   (* PR#3979 *)
  List.iter
    (fun (symb, fundecls) ->
        c := Cdata(emit_constant_closure symb fundecls []) :: !c)
    !constant_closures;
  constant_closures := [];
  !c

(* Translate a compilation unit *)

let compunit size ulam =
  let glob = Compilenv.make_symbol None in
  let init_code = transl ulam in
  let c1 = [Cfunction {fun_name = Compilenv.make_symbol (Some "entry");
                       fun_args = [];
                       fun_body = init_code; fun_fast = false}] in
  let c2 = transl_all_functions StringSet.empty c1 in
  let c3 = emit_all_constants c2 in
  Cdata [Cint(block_header 0 size);
         Cglobal_symbol glob;
         Cdefine_symbol glob;
         Cskip(size * size_addr)] :: c3

(*
CAMLprim value caml_cache_public_method (value meths, value tag, value *cache)
{
  int li = 3, hi = Field(meths,0), mi;
  while (li < hi) { // no need to check the 1st time
    mi = ((li+hi) >> 1) | 1;
    if (tag < Field(meths,mi)) hi = mi-2;
    else li = mi;
  }
  *cache = (li-3)*sizeof(value)+1;
  return Field (meths, li-1);
}
*)

let cache_public_method meths tag cache =
  let raise_num = next_raise_count () in
  let li = Ident.create "li" and hi = Ident.create "hi"
  and mi = Ident.create "mi" and tagged = Ident.create "tagged" in
  Clet (
  li, Cconst_int 3,
  Clet (
  hi, Cop(Cload Word, [meths]),
  Csequence(
  Ccatch
    (raise_num, [],
     Cloop
       (Clet(
        mi,
        Cop(Cor,
            [Cop(Clsr, [Cop(Caddi, [Cvar li; Cvar hi]); Cconst_int 1]);
             Cconst_int 1]),
        Csequence(
        Cifthenelse
          (Cop (Ccmpi Clt,
                [tag;
                 Cop(Cload Word,
                     [Cop(Cadda,
                          [meths; lsl_const (Cvar mi) log2_size_addr])])]),
           Cassign(hi, Cop(Csubi, [Cvar mi; Cconst_int 2])),
           Cassign(li, Cvar mi)),
        Cifthenelse
          (Cop(Ccmpi Cge, [Cvar li; Cvar hi]), Cexit (raise_num, []),
           Ctuple [])))),
     Ctuple []),
  Clet (
  tagged, Cop(Cadda, [lsl_const (Cvar li) log2_size_addr;
                      Cconst_int(1 - 3 * size_addr)]),
  Csequence(Cop (Cstore Word, [cache; Cvar tagged]),
            Cvar tagged)))))

(* Generate an application function:
     (defun caml_applyN (a1 ... aN clos)
       (if (= clos.arity N)
         (app clos.direct a1 ... aN clos)
         (let (clos1 (app clos.code a1 clos)
               clos2 (app clos1.code a2 clos)
               ...
               closN-1 (app closN-2.code aN-1 closN-2))
           (app closN-1.code aN closN-1))))
*)

let apply_function_body arity =
  let arg = Array.create arity (Ident.create "arg") in
  for i = 1 to arity - 1 do arg.(i) <- Ident.create "arg" done;
  let clos = Ident.create "clos" in
  let rec app_fun clos n =
    if n = arity-1 then
      Cop(Capply(typ_addr, Debuginfo.none),
          [get_field (Cvar clos) 0; Cvar arg.(n); Cvar clos])
    else begin
      let newclos = Ident.create "clos" in
      Clet(newclos,
           Cop(Capply(typ_addr, Debuginfo.none),
               [get_field (Cvar clos) 0; Cvar arg.(n); Cvar clos]),
           app_fun newclos (n+1))
    end in
  let args = Array.to_list arg in
  let all_args = args @ [clos] in
  (args, clos,
   if arity = 1 then app_fun clos 0 else
   Cifthenelse(
   Cop(Ccmpi Ceq, [get_field (Cvar clos) 1; int_const arity]),
   Cop(Capply(typ_addr, Debuginfo.none),
       get_field (Cvar clos) 2 :: List.map (fun s -> Cvar s) all_args),
   app_fun clos 0))

let send_function arity =
  let (args, clos', body) = apply_function_body (1+arity) in
  let cache = Ident.create "cache"
  and obj = List.hd args
  and tag = Ident.create "tag" in
  let clos =
    let cache = Cvar cache and obj = Cvar obj and tag = Cvar tag in
    let meths = Ident.create "meths" and cached = Ident.create "cached" in
    let real = Ident.create "real" in
    let mask = get_field (Cvar meths) 1 in
    let cached_pos = Cvar cached in
    let tag_pos = Cop(Cadda, [Cop (Cadda, [cached_pos; Cvar meths]);
                              Cconst_int(3*size_addr-1)]) in
    let tag' = Cop(Cload Word, [tag_pos]) in
    Clet (
    meths, Cop(Cload Word, [obj]),
    Clet (
    cached, Cop(Cand, [Cop(Cload Word, [cache]); mask]),
    Clet (
    real,
    Cifthenelse(Cop(Ccmpa Cne, [tag'; tag]),
                cache_public_method (Cvar meths) tag cache,
                cached_pos),
    Cop(Cload Word, [Cop(Cadda, [Cop (Cadda, [Cvar real; Cvar meths]);
                                 Cconst_int(2*size_addr-1)])]))))

  in
  let body = Clet(clos', clos, body) in
  let fun_args =
    [obj, typ_addr; tag, typ_int; cache, typ_addr]
    @ List.map (fun id -> (id, typ_addr)) (List.tl args) in
  Cfunction
   {fun_name = "caml_send" ^ string_of_int arity;
    fun_args = fun_args;
    fun_body = body;
    fun_fast = true}

let apply_function arity =
  let (args, clos, body) = apply_function_body arity in
  let all_args = args @ [clos] in
  Cfunction
   {fun_name = "caml_apply" ^ string_of_int arity;
    fun_args = List.map (fun id -> (id, typ_addr)) all_args;
    fun_body = body;
    fun_fast = true}

(* Generate tuplifying functions:
      (defun caml_tuplifyN (arg clos)
        (app clos.direct #0(arg) ... #N-1(arg) clos)) *)

let tuplify_function arity =
  let arg = Ident.create "arg" in
  let clos = Ident.create "clos" in
  let rec access_components i =
    if i >= arity
    then []
    else get_field (Cvar arg) i :: access_components(i+1) in
  Cfunction
   {fun_name = "caml_tuplify" ^ string_of_int arity;
    fun_args = [arg, typ_addr; clos, typ_addr];
    fun_body =
      Cop(Capply(typ_addr, Debuginfo.none),
          get_field (Cvar clos) 2 :: access_components 0 @ [Cvar clos]);
    fun_fast = true}

(* Generate currying functions:
      (defun caml_curryN (arg clos)
         (alloc HDR caml_curryN_1 <arity (N-1)> caml_curry_N_1_app arg clos))
      (defun caml_curryN_1 (arg clos)
         (alloc HDR caml_curryN_2 <arity (N-2)> caml_curry_N_2_app arg clos))
      ...
      (defun caml_curryN_N-1 (arg clos)
         (let (closN-2 clos.vars[1]
               closN-3 closN-2.vars[1]
               ...
               clos1 clos2.vars[1]
               clos clos1.vars[1])
           (app clos.direct
                clos1.vars[0] ... closN-2.vars[0] clos.vars[0] arg clos)))
    Special "shortcut" functions are also generated to handle the
    case where a partially applied function is applied to all remaining
    arguments in one go.  For instance:
      (defun caml_curry_N_1_app (arg2 ... argN clos)
        (let clos' clos.vars[1]
           (app clos'.direct clos.vars[0] arg2 ... argN clos')))
*)

let final_curry_function arity =
  let last_arg = Ident.create "arg" in
  let last_clos = Ident.create "clos" in
  let rec curry_fun args clos n =
    if n = 0 then
      Cop(Capply(typ_addr, Debuginfo.none),
          get_field (Cvar clos) 2 ::
          args @ [Cvar last_arg; Cvar clos])
    else
      if n = arity - 1 then
	begin
      let newclos = Ident.create "clos" in
      Clet(newclos,
           get_field (Cvar clos) 3,
           curry_fun (get_field (Cvar clos) 2 :: args) newclos (n-1))
	end else
	begin
	  let newclos = Ident.create "clos" in
	  Clet(newclos,
               get_field (Cvar clos) 4,
               curry_fun (get_field (Cvar clos) 3 :: args) newclos (n-1))
    end in
  Cfunction
   {fun_name = "caml_curry" ^ string_of_int arity ^
               "_" ^ string_of_int (arity-1);
    fun_args = [last_arg, typ_addr; last_clos, typ_addr];
    fun_body = curry_fun [] last_clos (arity-1);
    fun_fast = true}

let rec intermediate_curry_functions arity num =
  if num = arity - 1 then
    [final_curry_function arity]
  else begin
    let name1 = "caml_curry" ^ string_of_int arity in
    let name2 = if num = 0 then name1 else name1 ^ "_" ^ string_of_int num in
    let arg = Ident.create "arg" and clos = Ident.create "clos" in
    Cfunction
     {fun_name = name2;
      fun_args = [arg, typ_addr; clos, typ_addr];
      fun_body =
	 if arity - num > 2 then
	   Cop(Calloc,
               [alloc_closure_header 5;
                Cconst_symbol(name1 ^ "_" ^ string_of_int (num+1));
                int_const (arity - num - 1);
                Cconst_symbol(name1 ^ "_" ^ string_of_int (num+1) ^ "_app");
		Cvar arg; Cvar clos])
	 else
	   Cop(Calloc,
                     [alloc_closure_header 4;
                      Cconst_symbol(name1 ^ "_" ^ string_of_int (num+1));
                      int_const 1; Cvar arg; Cvar clos]);
      fun_fast = true}
    ::
      (if arity - num > 2 then
	  let rec iter i =
	    if i <= arity then
	      let arg = Ident.create (Printf.sprintf "arg%d" i) in
	      (arg, typ_addr) :: iter (i+1)
	    else []
	  in
	  let direct_args = iter (num+2) in
	  let rec iter i args clos =
	    if i = 0 then
	      Cop(Capply(typ_addr, Debuginfo.none),
		  (get_field (Cvar clos) 2) :: args @ [Cvar clos])
	    else
	      let newclos = Ident.create "clos" in
	      Clet(newclos,
		   get_field (Cvar clos) 4,
		   iter (i-1) (get_field (Cvar clos) 3 :: args) newclos)
	  in
	  let cf =
	    Cfunction
	      {fun_name = name1 ^ "_" ^ string_of_int (num+1) ^ "_app";
	       fun_args = direct_args @ [clos, typ_addr];
	       fun_body = iter (num+1)
		  (List.map (fun (arg,_) -> Cvar arg) direct_args) clos;
	       fun_fast = true}
	  in
	  cf :: intermediate_curry_functions arity (num+1)
       else
	  intermediate_curry_functions arity (num+1))
  end

let curry_function arity =
  if arity >= 0
  then intermediate_curry_functions arity 0
  else [tuplify_function (-arity)]


module IntSet = Set.Make(
  struct
    type t = int
    let compare = compare
  end)

let default_apply = IntSet.add 2 (IntSet.add 3 IntSet.empty)
  (* These apply funs are always present in the main program because
     the run-time system needs them (cf. asmrun/<arch>.S) . *)

let generic_functions shared units =
  let (apply,send,curry) =
    List.fold_left
      (fun (apply,send,curry) ui ->
         List.fold_right IntSet.add ui.ui_apply_fun apply,
         List.fold_right IntSet.add ui.ui_send_fun send,
         List.fold_right IntSet.add ui.ui_curry_fun curry)
      (IntSet.empty,IntSet.empty,IntSet.empty)
      units in
  let apply = if shared then apply else IntSet.union apply default_apply in
  let accu = IntSet.fold (fun n accu -> apply_function n :: accu) apply [] in
  let accu = IntSet.fold (fun n accu -> send_function n :: accu) send accu in
  IntSet.fold (fun n accu -> curry_function n @ accu) curry accu

(* Generate the entry point *)

let entry_point namelist =
  let incr_global_inited =
    Cop(Cstore Word,
        [Cconst_symbol "caml_globals_inited";
         Cop(Caddi, [Cop(Cload Word, [Cconst_symbol "caml_globals_inited"]);
                     Cconst_int 1])]) in
  let body =
    List.fold_right
      (fun name next ->
        let entry_sym = Compilenv.make_symbol ~unitname:name (Some "entry") in
        Csequence(Cop(Capply(typ_void, Debuginfo.none),
                         [Cconst_symbol entry_sym]),
                  Csequence(incr_global_inited, next)))
      namelist (Cconst_int 1) in
  Cfunction {fun_name = "caml_program";
             fun_args = [];
             fun_body = body;
             fun_fast = false}

(* Generate the table of globals *)

let cint_zero = Cint 0n

let global_table namelist =
  let mksym name =
    Csymbol_address (Compilenv.make_symbol ~unitname:name None)
  in
  Cdata(Cglobal_symbol "caml_globals" ::
        Cdefine_symbol "caml_globals" ::
        List.map mksym namelist @
        [cint_zero])

let reference_symbols namelist =
  let mksym name = Csymbol_address name in
  Cdata(List.map mksym namelist)

let global_data name v =
  Cdata(Cglobal_symbol name ::
          emit_constant name
          (Const_base (Const_string (Marshal.to_string v []))) [])

let globals_map v = global_data "caml_globals_map" v

(* Generate the master table of frame descriptors *)

let frame_table namelist =
  let mksym name =
    Csymbol_address (Compilenv.make_symbol ~unitname:name (Some "frametable"))
  in
  Cdata(Cglobal_symbol "caml_frametable" ::
        Cdefine_symbol "caml_frametable" ::
        List.map mksym namelist
        @ [cint_zero])

(* Generate the table of module data and code segments *)

let segment_table namelist symbol begname endname =
  let addsyms name lst =
    Csymbol_address (Compilenv.make_symbol ~unitname:name (Some begname)) ::
    Csymbol_address (Compilenv.make_symbol ~unitname:name (Some endname)) ::
    lst
  in
  Cdata(Cglobal_symbol symbol ::
        Cdefine_symbol symbol ::
        List.fold_right addsyms namelist [cint_zero])

let data_segment_table namelist =
  segment_table namelist "caml_data_segments" "data_begin" "data_end"

let code_segment_table namelist =
  segment_table namelist "caml_code_segments" "code_begin" "code_end"

(* Initialize a predefined exception *)

let predef_exception name =
  let bucketname = "caml_bucket_" ^ name in
  let symname = "caml_exn_" ^ name in
  Cdata(Cglobal_symbol symname ::
        emit_constant symname (Const_block(0,[Const_base(Const_string name)]))
        [ Cglobal_symbol bucketname;
          Cint(block_header 0 1);
          Cdefine_symbol bucketname;
          Csymbol_address symname ])

(* Header for a plugin *)

let mapflat f l = List.flatten (List.map f l)

let plugin_header units =
  let mk (ui,crc) =
    { dynu_name = ui.ui_name;
      dynu_crc = crc;
      dynu_imports_cmi = ui.ui_imports_cmi;
      dynu_imports_cmx = ui.ui_imports_cmx;
      dynu_defines = ui.ui_defines
    } in
  global_data "caml_plugin_header"
    { dynu_magic = Config.cmxs_magic_number; dynu_units = List.map mk units }
