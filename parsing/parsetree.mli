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

(* Abstract syntax tree produced by parsing *)

open Asttypes

(* Type and pattern expressions for CDuce *)

type ext_pattern =
  { pext_desc: ext_pattern_desc;
    pext_loc: Location.t }

and ext_pattern_desc =
    Pext_cst of Cduce_types.Types.t
  | Pext_ns of string
  | Pext_or of ext_pattern * ext_pattern
  | Pext_and of ext_pattern * ext_pattern
  | Pext_diff of ext_pattern * ext_pattern
  | Pext_prod of ext_pattern * ext_pattern
  | Pext_arrow of ext_pattern * ext_pattern
  | Pext_xml of ext_pattern * ext_pattern
  | Pext_optional of ext_pattern
  | Pext_record of bool * (qname * (ext_pattern * ext_pattern option)) list
  | Pext_bind of string * ext_const
  | Pext_constant of ext_const
  | Pext_regexp of ext_regexp
  | Pext_name of Longident.t
  | Pext_recurs of ext_pattern * (string * ext_pattern) list
  | Pext_from_ml of core_type
  | Pext_concat of ext_pattern * ext_pattern
  | Pext_merge of ext_pattern * ext_pattern

and ext_regexp =
    Pext_epsilon
  | Pext_elem of ext_pattern
  | Pext_guard of ext_pattern
  | Pext_seq of ext_regexp * ext_regexp
  | Pext_alt of ext_regexp * ext_regexp
  | Pext_star of ext_regexp
  | Pext_weakstar of ext_regexp
  | Pext_capture of string * ext_regexp * Location.t

and ext_const =  
    { pextcst_desc: ext_const_desc;
      pextcst_loc: Location.t }
and ext_const_desc =
  | Pextcst_pair of ext_const * ext_const
  | Pextcst_xml of ext_const * ext_const * ext_const
  | Pextcst_record of (qname * ext_const) list
  | Pextcst_atom of qname
  | Pextcst_int of Cduce_types.Intervals.V.t
  | Pextcst_char of utf8
  | Pextcst_string of utf8 * ext_const
  | Pextcst_intern of Cduce_types.Types.Const.t
and qname = string * utf8
and utf8 = Cduce_types.Encodings.Utf8.t

(* Type expressions for the core language *)

and core_type =
  { ptyp_desc: core_type_desc;
    ptyp_loc: Location.t }

and core_type_desc = 
    Ptyp_any
  | Ptyp_var of string
  | Ptyp_arrow of label * core_type * core_type
  | Ptyp_tuple of core_type list
  | Ptyp_constr of Longident.t * core_type list
  | Ptyp_object of core_field_type list
  | Ptyp_class of Longident.t * core_type list * label list
  | Ptyp_alias of core_type * string
  | Ptyp_variant of row_field list * bool * label list option
  | Ptyp_poly of string list * core_type
  | Ptyp_ext of ext_pattern

and core_field_type =
  { pfield_desc: core_field_desc;
    pfield_loc: Location.t }

and core_field_desc =
    Pfield of string * core_type
  | Pfield_var

and row_field =
    Rtag of label * bool * core_type list
  | Rinherit of core_type

(* XXX Type expressions for the class language *)

type 'a class_infos =
  { pci_virt: virtual_flag;
    pci_params: string list * Location.t;
    pci_name: string;
    pci_expr: 'a;
    pci_variance: (bool * bool) list;
    pci_loc: Location.t }

(* Value expressions for the core language *)

type pattern =
  { ppat_desc: pattern_desc;
    ppat_loc: Location.t }

and pattern_desc =
    Ppat_any
  | Ppat_var of string
  | Ppat_alias of pattern * string
  | Ppat_constant of constant
  | Ppat_tuple of pattern list
  | Ppat_construct of Longident.t * pattern option * bool
  | Ppat_variant of label * pattern option
  | Ppat_record of (Longident.t * pattern) list
  | Ppat_array of pattern list
  | Ppat_or of pattern * pattern
  | Ppat_constraint of pattern * core_type
  | Ppat_type of Longident.t

type expression =
  { mutable pexp_desc: expression_desc;
    pexp_loc: Location.t }

and expression_desc =
    Pexp_ident of Longident.t
  | Pexp_constant of constant
  | Pexp_let of rec_flag * (pattern * expression) list * expression
  | Pexp_function of label * expression option * (pattern * expression) list
  | Pexp_apply of expression * (label * expression) list
  | Pexp_match of expression * (pattern * expression) list
  | Pexp_try of expression * (pattern * expression) list
  | Pexp_tuple of expression list
  | Pexp_construct of Longident.t * expression option * bool
  | Pexp_variant of label * expression option
  | Pexp_record of (Longident.t * expression) list * expression option
  | Pexp_field of expression * Longident.t
  | Pexp_setfield of expression * Longident.t * expression
  | Pexp_array of expression list
  | Pexp_ifthenelse of expression * expression * expression option
  | Pexp_sequence of expression * expression
  | Pexp_while of expression * expression
  | Pexp_for of string * expression * expression * direction_flag * expression
  | Pexp_constraint of expression * core_type option * core_type option
  | Pexp_when of expression * expression
  | Pexp_send of expression * string
  | Pexp_new of Longident.t
  | Pexp_setinstvar of string * expression
  | Pexp_override of (string * expression) list
  | Pexp_letmodule of string * module_expr * expression
  | Pexp_assert of expression
  | Pexp_assertfalse
  | Pexp_lazy of expression
  | Pexp_poly of expression * core_type option
  | Pexp_object of class_structure
  | Pexp_ext of ext_exp

and ext_exp =
  | Pextexp_cst of ext_const
  | Pextexp_match of expression * ext_branch list
  | Pextexp_map of expression * ext_branch list
  | Pextexp_xmap of expression * ext_branch list
  | Pextexp_record of (qname * expression) list
  | Pextexp_removefield of expression * qname
  | Pextexp_op of string * expression list
  | Pextexp_namespace of string * utf8 * expression
  | Pextexp_from_ml of expression
  | Pextexp_to_ml of expression
  | Pextexp_check of expression * ext_pattern
  | Pextexp_id of expression

and ext_branch = 
    ext_pattern * ((string * Location.t) list option ref) * expression
    (* The second argument is the list of capture variables.
       This is computed during type-checking and used
       in Unused_var. *)

(* Value descriptions *)

and value_description =
  { pval_type: core_type;
    pval_prim: string list }

(* Type declarations *)

and type_declaration =
  { ptype_params: string list;
    ptype_cstrs: (core_type * core_type * Location.t) list;
    ptype_kind: type_kind;
    ptype_manifest: core_type option;
    ptype_variance: (bool * bool) list;
    ptype_loc: Location.t }

and type_kind =
    Ptype_abstract
  | Ptype_variant of (string * core_type list * Location.t) list * private_flag
  | Ptype_record of
      (string * mutable_flag * core_type * Location.t) list * private_flag
  | Ptype_private

and exception_declaration = core_type list

(* Type expressions for the class language *)

and class_type =
  { pcty_desc: class_type_desc;
    pcty_loc: Location.t }

and class_type_desc =
    Pcty_constr of Longident.t * core_type list
  | Pcty_signature of class_signature
  | Pcty_fun of label * core_type * class_type

and class_signature = core_type * class_type_field list

and class_type_field =
    Pctf_inher of class_type
  | Pctf_val   of (string * mutable_flag * core_type option * Location.t)
  | Pctf_virt  of (string * private_flag * core_type * Location.t)
  | Pctf_meth  of (string * private_flag * core_type * Location.t)
  | Pctf_cstr  of (core_type * core_type * Location.t)

and class_description = class_type class_infos

and class_type_declaration = class_type class_infos

(* Value expressions for the class language *)

and class_expr =
  { pcl_desc: class_expr_desc;
    pcl_loc: Location.t }

and class_expr_desc =
    Pcl_constr of Longident.t * core_type list
  | Pcl_structure of class_structure
  | Pcl_fun of label * expression option * pattern * class_expr
  | Pcl_apply of class_expr * (label * expression) list
  | Pcl_let of rec_flag * (pattern * expression) list * class_expr
  | Pcl_constraint of class_expr * class_type

and class_structure = pattern * class_field list

and class_field =
    Pcf_inher of class_expr * string option
  | Pcf_val   of (string * mutable_flag * expression * Location.t)
  | Pcf_virt  of (string * private_flag * core_type * Location.t)
  | Pcf_meth  of (string * private_flag * expression * Location.t)
  | Pcf_cstr  of (core_type * core_type * Location.t)
  | Pcf_let   of rec_flag * (pattern * expression) list * Location.t
  | Pcf_init  of expression

and class_declaration = class_expr class_infos

(* Type expressions for the module language *)

and module_type =
  { pmty_desc: module_type_desc;
    pmty_loc: Location.t }

and module_type_desc =
    Pmty_ident of Longident.t
  | Pmty_signature of signature
  | Pmty_functor of string * module_type * module_type
  | Pmty_with of module_type * (Longident.t * with_constraint) list

and signature = signature_item list

and signature_item =
  { psig_desc: signature_item_desc;
    psig_loc: Location.t }

and signature_item_desc =
    Psig_value of string * value_description
  | Psig_type of (string * type_declaration) list
  | Psig_exception of string * exception_declaration
  | Psig_module of string * module_type
  | Psig_recmodule of (string * module_type) list
  | Psig_modtype of string * modtype_declaration
  | Psig_open of Longident.t
  | Psig_include of module_type
  | Psig_class of class_description list
  | Psig_class_type of class_type_declaration list
  | Psig_namespace of string * utf8

and modtype_declaration =
    Pmodtype_abstract
  | Pmodtype_manifest of module_type

and with_constraint =
    Pwith_type of type_declaration
  | Pwith_module of Longident.t

(* Value expressions for the module language *)

and module_expr =
  { pmod_desc: module_expr_desc;
    pmod_loc: Location.t }

and module_expr_desc =
    Pmod_ident of Longident.t
  | Pmod_structure of structure
  | Pmod_functor of string * module_type * module_expr
  | Pmod_apply of module_expr * module_expr
  | Pmod_constraint of module_expr * module_type

and structure = structure_item list

and structure_item =
  { pstr_desc: structure_item_desc;
    pstr_loc: Location.t }

and structure_item_desc =
    Pstr_eval of expression
  | Pstr_value of rec_flag * (pattern * expression) list
  | Pstr_primitive of string * value_description
  | Pstr_type of (string * type_declaration) list
  | Pstr_exception of string * exception_declaration
  | Pstr_exn_rebind of string * Longident.t
  | Pstr_module of string * module_expr
  | Pstr_recmodule of (string * module_type * module_expr) list
  | Pstr_modtype of string * module_type
  | Pstr_open of Longident.t
  | Pstr_class of class_declaration list
  | Pstr_class_type of class_type_declaration list
  | Pstr_include of module_expr
  | Pstr_namespace of string * utf8

(* Toplevel phrases *)

type toplevel_phrase =
    Ptop_def of structure
  | Ptop_dir of string * directive_argument

and directive_argument =
    Pdir_none
  | Pdir_string of string
  | Pdir_int of int
  | Pdir_ident of Longident.t
  | Pdir_bool of bool
