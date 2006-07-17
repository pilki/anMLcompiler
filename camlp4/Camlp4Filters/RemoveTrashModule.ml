(* camlp4r *)
(****************************************************************************)
(*                                                                          *)
(*                              Objective Caml                              *)
(*                                                                          *)
(*                            INRIA Rocquencourt                            *)
(*                                                                          *)
(*  Copyright   2006    Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed under   *)
(*  the terms of the GNU Library General Public License, with the special   *)
(*  exception on linking described in LICENSE at the top of the Objective   *)
(*  Caml source tree.                                                       *)
(*                                                                          *)
(****************************************************************************)

(* Authors:
 * - Nicolas Pouillard: initial version
 *)


open Camlp4;

module Id = struct
  value name    = "Camlp4Filters.RemoveTrashModule";
  value version = "$Id$";
end;

module Make (AstFilters : Camlp4.Sig.AstFilters.S) = struct
  open AstFilters;
  open Ast;

  register_str_item_filter
    (new Ast.c_str_item
      (fun
       [ <:str_item@_loc< module Camlp4FiltersTrash = $_$ >> ->
            <:str_item<>>
       | st -> st ]))#str_item;

end;

let module M = Camlp4.Register.AstFilter Id Make in ();
