(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(* Instruction scheduling for the Power PC *)

open Arch
open Mach

class scheduler () as self =

inherit Schedgen.scheduler_generic () as super

(* Latencies (in cycles). Based roughly on the "common model". *)

method oper_latency = function
    Ireload -> 2
  | Iload(_, _) -> 2
  | Iconst_float _ -> 2 (* turned into a load *)
  | Iconst_symbol _ -> if toc then 2 (* turned into a load *) else 1
  | Iintop Imul -> 9
  | Iintop_imm(Imul, _) -> 5
  | Iintop(Idiv | Imod) -> 36
  | Iaddf | Isubf -> 4
  | Imulf -> 5
  | Idivf -> 33
  | Ispecific(Imultaddf | Imultsubf) -> 5
  | _ -> 1

(* Issue cycles.  Rough approximations. *)

method oper_issue_cycles = function
    Iconst_float _ | Iconst_symbol _ -> if toc then 1 else 2
  | Iload(_, Ibased(_, _)) -> 2
  | Istore(_, Ibased(_, _)) -> 2
  | Ialloc _ -> 4
  | Iintop(Imod) -> 40 (* assuming full stall *)
  | Iintop(Icomp _) -> 4
  | Iintop_imm(Idiv, _) -> 2
  | Iintop_imm(Imod, _) -> 4
  | Iintop_imm(Icomp _, _) -> 4
  | Ifloatofint -> 9
  | Iintoffloat -> 4
  | _ -> 1
end

let fundecl f = (new scheduler ())#schedule_fundecl f

