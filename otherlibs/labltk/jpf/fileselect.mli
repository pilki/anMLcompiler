(***********************************************************************)
(*                                                                     *)
(*                 MLTk, Tcl/Tk interface of Objective Caml            *)
(*                                                                     *)
(*    Francois Rouaix, Francois Pessaux, Jun Furuse and Pierre Weis    *)
(*               projet Cristal, INRIA Rocquencourt                    *)
(*            Jacques Garrigue, Kyoto University RIMS                  *)
(*                                                                     *)
(*  Copyright 2002 Institut National de Recherche en Informatique et   *)
(*  en Automatique and Kyoto University.  All rights reserved.         *)
(*  This file is distributed under the terms of the GNU Library        *)
(*  General Public License, with the special exception on linking      *)
(*  described in file LICENSE found in the Objective Caml source tree. *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

open Support

val f :
  title:string ->
  action:(string list -> unit) ->
  filter:string -> file:string -> multi:bool -> sync:bool -> unit

(* action 
      []  means canceled
      if multi select is false, then the list is null or a singleton *)

(* multi select 
      if true then more than one file are selectable *)

(* sync it 
      if true then in synchronous mode *)
