(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 2000 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(* Description of the AMD64 processor *)

open Misc
open Arch
open Cmm
open Reg
open Mach

(* Registers available for register allocation *)

(* Register map:
    rax         0               rax - r11: Caml function arguments
    rbx         1               rdi - r9: C function arguments
    rdi         2               rax: Caml and C function results
    rsi         3               rbx, rbp, r12-r15 are preserved by C
    rdx         4
    rcx         5
    r8          6
    r9          7
    r10		8
    r11		9
    rbp         10
    r12		11
    r13		12
    r14         trap pointer
    r15         allocation pointer
    
  xmm0 - xmm15  100 - 115       xmm0 - xmm9: Caml function arguments
                                xmm0 - xmm7: C function arguments
                                xmm0: Caml and C function results *)

let int_reg_name =
  [| "%rax"; "%rbx"; "%rdi"; "%rsi"; "%rdx"; "%rcx"; "%r8"; "%r9"; 
     "%r10"; "%r11"; "%rbp"; "%r12"; "%r13" |]

let float_reg_name =
  [| "%xmm0"; "%xmm1"; "%xmm2"; "%xmm3"; "%xmm4"; "%xmm5"; "%xmm6"; "%xmm7"; 
     "%xmm8"; "%xmm9"; "%xmm10"; "%xmm11";
     "%xmm12"; "%xmm13"; "%xmm14"; "%xmm15" |]

let num_register_classes = 2

let register_class r =
  match r.typ with
    Int -> 0
  | Addr -> 0
  | Float -> 1

let num_available_registers = [| 13; 16 |]

let first_available_register = [| 0; 100 |]

let register_name r =
  if r < 100 then int_reg_name.(r) else float_reg_name.(r - 100)

(* Pack registers starting at %rax so as to reduce the number of REX
   prefixes and thus improve code density *)
let rotate_registers = false

(* Representation of hard registers by pseudo-registers *)

let hard_int_reg =
  let v = Array.create 13 Reg.dummy in
  for i = 0 to 12 do v.(i) <- Reg.at_location Int (Reg i) done;
  v

let hard_float_reg =
  let v = Array.create 16 Reg.dummy in
  for i = 0 to 15 do v.(i) <- Reg.at_location Float (Reg (100 + i)) done;
  v

let all_phys_regs =
  Array.append hard_int_reg hard_float_reg

let phys_reg n =
  if n < 100 then hard_int_reg.(n) else hard_float_reg.(n - 100)

let rax = phys_reg 0
let rcx = phys_reg 5
let rdx = phys_reg 4
let r11 = phys_reg 9
let rxmm15 = phys_reg 115

let stack_slot slot ty =
  Reg.at_location ty (Stack slot)

(* Instruction selection *)

let word_addressed = false

(* Calling conventions *)

let calling_conventions first_int last_int first_float last_float make_stack
                        arg =
  let loc = Array.create (Array.length arg) Reg.dummy in
  let int = ref first_int in
  let float = ref first_float in
  let ofs = ref 0 in
  for i = 0 to Array.length arg - 1 do
    match arg.(i).typ with
      Int | Addr as ty ->
        if !int <= last_int then begin
          loc.(i) <- phys_reg !int;
          incr int
        end else begin
          loc.(i) <- stack_slot (make_stack !ofs) ty;
          ofs := !ofs + size_int
        end
    | Float ->
        if !float <= last_float then begin
          loc.(i) <- phys_reg !float;
          incr float
        end else begin
          loc.(i) <- stack_slot (make_stack !ofs) Float;
          ofs := !ofs + size_float
        end
  done;
  (loc, Misc.align !ofs 16)  (* keep stack 16-aligned *)

let incoming ofs = Incoming ofs
let outgoing ofs = Outgoing ofs
let not_supported ofs = fatal_error "Proc.loc_results: cannot call"

let loc_arguments arg =
  calling_conventions 0 9 100 109 outgoing arg
let loc_parameters arg =
  let (loc, ofs) = calling_conventions 0 9 100 109 incoming arg in loc
let loc_results res =
  let (loc, ofs) = calling_conventions 0 0 100 100 not_supported res in loc

(* C calling convention:
     first integer args in rdi, rsi, rdx, rcx, r8, r9
     first float args in xmm0 ... xmm7
     remaining args on stack.
   Return value in rax or xmm0. *)

let loc_external_arguments arg =
  calling_conventions 2 7 100 107 outgoing arg
let loc_external_results res =
  let (loc, ofs) = calling_conventions 0 0 100 100 not_supported res in loc

let loc_exn_bucket = rax

(* Registers destroyed by operations *)

let destroyed_at_c_call =         (* rbp, rbx, r12-r15 preserved *)
  Array.of_list(List.map phys_reg
    [0;2;3;4;5;6;7;8;9;
     100;101;102;103;104;105;106;107;
     108;109;110;111;112;113;114;115])

let destroyed_at_oper = function
    Iop(Icall_ind | Icall_imm _ | Iextcall(_, true)) -> all_phys_regs
  | Iop(Iextcall(_, false)) -> destroyed_at_c_call
  | Iop(Iintop(Idiv | Imod)) -> [| rax; rdx |]
  | Iop(Istore(Single, _)) -> [| rxmm15 |]
  | Iop(Ialloc _ | Iintop(Icomp _) | Iintop_imm((Idiv|Imod|Icomp _), _))
        -> [| rax |]
  | Iswitch(_, _) when !pic_code -> [| r11 |]
  | _ -> [||]

let destroyed_at_raise = all_phys_regs

(* Maximal register pressure *)

let safe_register_pressure = function
    Iextcall(_,_) -> 0
  | _ -> 11

let max_register_pressure = function
    Iextcall(_, _) -> [| 4; 0 |]
  | Iintop(Idiv | Imod) -> [| 11; 16 |]
  | Ialloc _ | Iintop(Icomp _) | Iintop_imm((Idiv|Imod|Icomp _), _)
        -> [| 12; 16 |]
  | Istore(Single, _) -> [| 13; 15 |]
  | _ -> [| 13; 16 |]

(* Layout of the stack frame *)

let num_stack_slots = [| 0; 0 |]
let contains_calls = ref false

(* Calling the assembler *)

let assemble_file infile outfile =
  Ccomp.command (Config.asm ^ " -o " ^ outfile ^ " " ^ infile)

