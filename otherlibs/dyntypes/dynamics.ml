(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*         Gilles Peskine, projet Cristal, INRIA Rocquencourt          *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License.         *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(* This type resembles [Types.type_desc] in the compiler, although it differs
   in quite a few ways. *)
type type_expr =
  | Pvar of int
  | Builtin of string * type_expr list
  | Tuple of type_expr list
  | Arrow of string * type_expr * type_expr * bool
  | Variant of row_desc
  | Classical_variant of string * type_expr list

and row_desc =
    { row_fields: (string * row_field) list;
      row_more: type_expr;
      row_bound: type_expr list;
      row_closed: bool;
      row_name: (string * type_expr list) option }

and row_field =
    Rpresent of type_expr option
  | Reither of bool * type_expr list * bool * row_field option
        (* 1st true denotes a constant constructor *)
        (* 2nd true denotes a tag in a pattern matching, and
           is erased later *)
  | Rabsent

type type_repr = {
    expr : type_expr;
  }



type module_type_repr

let compare_module_types amty emty =
  amty = emty



type anything
type nothing (* a module, in fact *)

exception Type_error of type_repr * type_repr
exception Module_type_error of module_type_repr * module_type_repr

external type_of : dyn -> type_repr = "%field0"
external module_type_of : dynamically_typed_module -> module_type_repr = "%field0"

let coerce_internal d expected_type =
  let (sent_type, v) = Obj.magic (d : dyn) in
  if sent_type.expr = expected_type.expr
  then (Obj.magic v : anything)
  else raise (Type_error (sent_type, expected_type))

let coerce_module d expected_module_type =
  let (actual_module_type, m) = Obj.magic (d : dynamically_typed_module) in
  if compare_module_types actual_module_type expected_module_type
  then (Obj.magic m : nothing)
  else raise (Module_type_error (actual_module_type, expected_module_type))
