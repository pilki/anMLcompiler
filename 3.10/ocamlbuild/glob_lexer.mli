(***********************************************************************)
(*                             ocamlbuild                              *)
(*                                                                     *)
(*  Nicolas Pouillard, Berke Durak, projet Gallium, INRIA Rocquencourt *)
(*                                                                     *)
(*  Copyright 2007 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)
(* Original author: Berke Durak *)
open Glob_ast

type token =
| ATOM of pattern atom
| AND
| OR
| NOT
| LPAR
| RPAR
| TRUE
| FALSE
| EOF

val token : Lexing.lexbuf -> token
