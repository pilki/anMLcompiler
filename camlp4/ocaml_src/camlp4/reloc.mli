(* camlp4r *)
(***********************************************************************)
(*                                                                     *)
(*                             Camlp4                                  *)
(*                                                                     *)
(*        Daniel de Rauglaudre, projet Cristal, INRIA Rocquencourt     *)
(*                                                                     *)
(*  Copyright 1998 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* This file has been generated by program: do not edit! *)

val zero_loc : Lexing.position;;
val shift_pos : int -> Lexing.position -> Lexing.position;;
val adjust_loc : Lexing.position -> MLast.loc -> MLast.loc;;
val linearize : MLast.loc -> MLast.loc;;
val patt :
  (MLast.loc -> MLast.loc) -> Lexing.position -> MLast.patt -> MLast.patt;;
val expr :
  (MLast.loc -> MLast.loc) -> Lexing.position -> MLast.expr -> MLast.expr;;
