(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

open Format

type t =
    Pident of Ident.t
  | Pdot of t * string * int
  | Papply of t * t

let nopos = -1

let rec same p1 p2 =
  match (p1, p2) with
    (Pident id1, Pident id2) -> Ident.same id1 id2
  | (Pdot(p1, s1, pos1), Pdot(p2, s2, pos2)) -> s1 = s2 && same p1 p2
  | (Papply(fun1, arg1), Papply(fun2, arg2)) ->
       same fun1 fun2 && same arg1 arg2
  | (_, _) -> false

let rec isfree id = function
    Pident id' -> Ident.same id id'
  | Pdot(p, s, pos) -> isfree id p
  | Papply(p1, p2) -> isfree id p1 || isfree id p2

let rec binding_time = function
    Pident id -> Ident.binding_time id
  | Pdot(p, s, pos) -> binding_time p
  | Papply(p1, p2) -> max (binding_time p1) (binding_time p2)

let rec name = function
    Pident id -> Ident.name id
  | Pdot(p, s, pos) -> name p ^ "." ^ s
  | Papply(p1, p2) -> name p1 ^ "(" ^ name p2 ^ ")"

let rec head = function
    Pident id -> id
  | Pdot(p, s, pos) -> head p
  | Papply(p1, p2) -> assert false

let cmpPath_byname p1 p2 = compare (name p1) (name p2)

let rec equal p1 p2 =
  match (p1, p2) with
    (Pident id1, Pident id2) -> Ident.equal id1 id2
  | (Pdot(p1, s1, pos1), Pdot(p2, s2, pos2)) -> s1 = s2 && equal p1 p2
  | (Papply(fun1, arg1), Papply(fun2, arg2)) ->
       equal fun1 fun2 && equal arg1 arg2
  | (_, _) -> false

(* Print a path *)

let ident_pervasive = Ident.create_persistent "Pervasives" 

let rec print ppf = function
  | Pident id ->
      Ident.print ppf id
  | Pdot(Pident id, s, pos) when Ident.same id ident_pervasive -> 
      fprintf ppf "%s" s
  | Pdot(p, s, pos) ->
      fprintf ppf "%a.%s" print p s
  | Papply(p1, p2) ->
      fprintf ppf "%a(%a)" print p1 print p2

