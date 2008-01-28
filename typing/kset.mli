(***********************************************************************)
(*                                                                     *)
(*                               G'Caml                                *)
(*                                                                     *)
(*                  Jun Furuse, University of Tokyo                    *)
(*                                                                     *)
(*  Copyright 2005 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

open Types
open Typedtree

val debug : bool
type elem = { kelem_type : type_expr;
	      kelem_vdesc : value_description;
	      kelem_instinfo : instance_info ref } 
type t = elem list ref
val empty : unit -> t
val add : t -> elem -> unit
val get : t -> elem list
val create : elem list -> t
val print :
  Format.formatter -> t -> unit
val instance :
    t -> value_description -> type_expr * instance_info ref
val resolve_kset : Env.t -> t ->  unit
