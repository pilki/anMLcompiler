(***********************************************************************)
(*                                                                     *)
(*                                OCaml                                *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(* Registering Caml values with the C runtime for later callbacks *)

external register_named_value : string -> Obj.t -> unit
                              = "caml_register_named_value"

let register name v =
  register_named_value name (Obj.repr v)

let register_exception name (exn : exn) =
  register_named_value name (Obj.field (Obj.repr exn) 0)
