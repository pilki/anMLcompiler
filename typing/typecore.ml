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

(* Typechecking for the core language *)

open Misc
open Asttypes
open Parsetree
open Types
open Typedtree
open Btype
open Ctype


type error =
    Unbound_value of Longident.t
  | Unbound_constructor of Longident.t
  | Unbound_label of Longident.t
  | Constructor_arity_mismatch of Longident.t * int * int
  | Label_mismatch of Longident.t * (type_expr * type_expr) list
  | Pattern_type_clash of (type_expr * type_expr) list
  | Multiply_bound_variable
  | Orpat_vars of Ident.t
  | Expr_type_clash of (type_expr * type_expr) list
  | Apply_non_function of type_expr
  | Apply_wrong_label of label * type_expr
  | Label_multiply_defined of Longident.t
  | Label_missing of string list
  | Label_not_mutable of Longident.t
  | Bad_format of string
  | Undefined_method of type_expr * string
  | Undefined_inherited_method of string
  | Unbound_class of Longident.t
  | Virtual_class of Longident.t
  | Unbound_instance_variable of string
  | Instance_variable_not_mutable of string
  | Not_subtype of (type_expr * type_expr) list * (type_expr * type_expr) list
  | Outside_class
  | Value_multiply_overridden of string
  | Coercion_failure of type_expr * type_expr * (type_expr * type_expr) list
  | Too_many_arguments
  | Abstract_wrong_label of label * type_expr
  | Scoping_let_module of string * type_expr
  | Masked_instance_variable of Longident.t
  | Not_a_variant_type of Longident.t
  | Incoherent_label_order
(*> JOCAML *)
  | Expr_as_proc
  | Proc_as_expr
  | Garrigue_illegal of string (* merci Jacques ! *)
  | Vouillon_illegal of string (* merci Jerome ! *)
  | Send_non_channel of type_expr
  | Join_pattern_type_clash of (type_expr * type_expr) list
(*< JOCAML *)

exception Error of Location.t * error

(* Forward declaration, to be filled in by Typemod.type_module *)

let type_module =
  ref ((fun env md -> assert false) :
       Env.t -> Parsetree.module_expr -> Typedtree.module_expr)

(* Typing of constants *)

let type_constant = function
    Const_int _ -> instance Predef.type_int
  | Const_char _ -> instance Predef.type_char
  | Const_string _ -> instance Predef.type_string
  | Const_float _ -> instance Predef.type_float

(* Specific version of type_option, using newty rather than newgenty *)

let type_option ty =
  newty (Tconstr(Predef.path_option,[ty], ref Mnil))

let option_none ty loc =
  let cnone = Env.lookup_constructor (Longident.Lident "None") Env.initial in
  { exp_desc = Texp_construct(cnone, []);
    exp_type = ty; exp_loc = loc; exp_env = Env.initial }

let option_some texp =
  let csome = Env.lookup_constructor (Longident.Lident "Some") Env.initial in
  { exp_desc = Texp_construct(csome, [texp]); exp_loc = texp.exp_loc;
    exp_type = type_option texp.exp_type; exp_env = texp.exp_env }

let extract_option_type env ty =
  match expand_head env ty with {desc = Tconstr(path, [ty], _)}
    when Path.same path Predef.path_option -> ty
  | _ -> assert false

let rec extract_label_names env ty =
  let ty = repr ty in
  match ty.desc with
  | Tconstr (path, _, _) ->
      let td = Env.find_type path env in
      begin match td.type_kind with
      | Type_record (fields, _) -> List.map (fun (name, _, _) -> name) fields
      | Type_abstract when td.type_manifest <> None ->
          extract_label_names env (expand_head env ty)
      | _ -> assert false
      end
  | _ ->
      assert false

(* Typing of patterns *)

(* Creating new conjunctive types is not allowed when typing patterns *)
let unify_pat env pat expected_ty =
  try
    unify env pat.pat_type expected_ty
  with Unify trace ->
    raise(Error(pat.pat_loc, Pattern_type_clash(trace)))

let pattern_variables = ref ([]: (Ident.t * type_expr) list)

let enter_variable loc name ty =
  if List.exists (fun (id, _) -> Ident.name id = name) !pattern_variables
  then raise(Error(loc, Multiply_bound_variable));
  let id = Ident.create name in
  pattern_variables := (id, ty) :: !pattern_variables;
  id

let sort_pattern_variables vs =
  List.sort
    (fun (x,_) (y,_) -> Pervasives.compare (Ident.name x) (Ident.name y))
    vs

let enter_orpat_variables loc env  p1_vs p2_vs =
  (* unify_vars operate on sorted lists *)
  
  let p1_vs = sort_pattern_variables p1_vs
  and p2_vs = sort_pattern_variables p2_vs in

  let rec unify_vars p1_vs p2_vs = match p1_vs, p2_vs with  
      | (x1,t1)::rem1, (x2,t2)::rem2 when Ident.equal x1 x2 ->
          if x1==x2 then
            unify_vars rem1 rem2
          else begin
            begin try
              unify env t1 t2
            with
            | Unify trace ->
                raise(Error(loc, Pattern_type_clash(trace)))
            end ;
          (x2,x1)::unify_vars rem1 rem2
          end
      | [],[] -> []
      | (x,_)::_, [] -> raise (Error (loc, Orpat_vars x))
      | [],(x,_)::_  -> raise (Error (loc, Orpat_vars x))
      | (x,_)::_, (y,_)::_ ->
          let min_var =
            if Ident.name x < Ident.name y then x
            else y in
          raise (Error (loc, Orpat_vars min_var)) in
  unify_vars p1_vs p2_vs


let rec build_as_type env p =
  match p.pat_desc with
    Tpat_alias(p1, _) -> build_as_type env p1
  | Tpat_tuple pl ->
      let tyl = List.map (build_as_type env) pl in
      newty (Ttuple tyl)
  | Tpat_construct(cstr, pl) ->
      let tyl = List.map (build_as_type env) pl in
      let ty_args, ty_res = instance_constructor cstr in
      List.iter2 (fun (p,ty) -> unify_pat env {p with pat_type = ty})
        (List.combine pl tyl) ty_args;
      ty_res
  | Tpat_variant(l, p', _) ->
      let ty = may_map (build_as_type env) p' in
      newty (Tvariant{row_fields=[l, Rpresent ty]; row_more=newvar();
                      row_bound=[]; row_name=None; row_closed=false})
  | Tpat_record lpl ->
      let lbl = fst(List.hd lpl) in
      let ty = newvar () in
      let do_label lbl =
        let ty_arg, ty_res = instance_label lbl in
        unify_pat env {p with pat_type = ty} ty_res;
        if lbl.lbl_mut = Immutable && List.mem_assoc lbl lpl then begin
          let arg = List.assoc lbl lpl in
          unify_pat env {arg with pat_type = build_as_type env arg} ty_arg
        end else begin
          let ty_arg', ty_res' = instance_label lbl in
          unify env ty_arg ty_arg';
          unify_pat env p ty_res'
        end in
      Array.iter do_label lbl.lbl_all;
      ty
  | Tpat_or(p1, p2, path) ->
      let ty1 = build_as_type env p1 and ty2 = build_as_type env p2 in
      unify_pat env {p2 with pat_type = ty2} ty1;
      begin match path with None -> ()
      | Some path ->
          let td = try Env.find_type path env with Not_found -> assert false in
          let params = List.map (fun _ -> newvar()) td.type_params in
          match expand_head env (newty (Tconstr (path, params, ref Mnil)))
          with {desc=Tvariant row} when static_row row ->
            unify_pat env {p1 with pat_type = ty1}
              (newty (Tvariant{row with row_closed=false; row_more=newvar()}))
          | _ -> ()
      end;
      ty1
  | Tpat_any | Tpat_var _ | Tpat_constant _ | Tpat_array _ -> p.pat_type

let build_or_pat env loc lid =
  let path, decl =
    try Env.lookup_type lid env
    with Not_found ->
      raise(Typetexp.Error(loc, Typetexp.Unbound_type_constructor lid))
  in
  let tyl = List.map (fun _ -> newvar()) decl.type_params in
  let fields =
    let ty = expand_head env (newty(Tconstr(path, tyl, ref Mnil))) in
    match ty.desc with
      Tvariant row when static_row row ->
        (row_repr row).row_fields
    | _ -> raise(Error(loc, Not_a_variant_type lid))
  in
  let bound = ref [] in
  let pats, fields =
    List.fold_left
      (fun (pats,fields) (l,f) ->
        match row_field_repr f with
          Rpresent None ->
            (l,None) :: pats,
            (l, Reither(true,[], true, ref None)) :: fields
        | Rpresent (Some ty) ->
            bound := ty :: !bound;
            (l, Some{pat_desc=Tpat_any; pat_loc=Location.none; pat_env=env;
                     pat_type=ty})
            :: pats,
            (l, Reither(false, [ty], true, ref None)) :: fields
        | _ -> pats, fields)
      ([],[]) fields in
  let row =
    { row_fields = List.rev fields; row_more = newvar(); row_bound = !bound;
      row_closed = false; row_name = Some (path, tyl) }
  in
  let ty = newty (Tvariant row) in
  let pats =
    List.map (fun (l,p) -> {pat_desc=Tpat_variant(l,p,row); pat_loc=loc;
                            pat_env=env; pat_type=ty})
      pats
  in
  match pats with
    [] -> raise(Error(loc, Not_a_variant_type lid))
  | pat :: pats ->
      List.fold_left
        (fun pat pat0 -> {pat_desc=Tpat_or(pat0,pat,Some path); pat_loc=loc;
                          pat_env=env; pat_type=ty})
        pat pats

let rec type_pat env sp =
  match sp.ppat_desc with
    Ppat_any ->
      { pat_desc = Tpat_any;
        pat_loc = sp.ppat_loc;
        pat_type = newvar();
        pat_env = env }
  | Ppat_var name ->
      let ty = newvar() in
      let id = enter_variable sp.ppat_loc name ty in
      { pat_desc = Tpat_var id;
        pat_loc = sp.ppat_loc;
        pat_type = ty;
        pat_env = env }
  | Ppat_alias(sq, name) ->
      let q = type_pat env sq in
      begin_def ();
      let ty_var = build_as_type env q in
      end_def ();
      generalize ty_var;
      let id = enter_variable sp.ppat_loc name ty_var in
      { pat_desc = Tpat_alias(q, id);
        pat_loc = sp.ppat_loc;
        pat_type = q.pat_type;
        pat_env = env }
  | Ppat_constant cst ->
      { pat_desc = Tpat_constant cst;
        pat_loc = sp.ppat_loc;
        pat_type = type_constant cst;
        pat_env = env }
  | Ppat_tuple spl ->
      let pl = List.map (type_pat env) spl in
      { pat_desc = Tpat_tuple pl;
        pat_loc = sp.ppat_loc;
        pat_type = newty (Ttuple(List.map (fun p -> p.pat_type) pl));
        pat_env = env }
  | Ppat_construct(lid, sarg, explicit_arity) ->
      let constr =
        try
          Env.lookup_constructor lid env
        with Not_found ->
          raise(Error(sp.ppat_loc, Unbound_constructor lid)) in
      let sargs =
        match sarg with
          None -> []
        | Some {ppat_desc = Ppat_tuple spl} when explicit_arity -> spl
        | Some {ppat_desc = Ppat_tuple spl} when constr.cstr_arity > 1 -> spl
        | Some({ppat_desc = Ppat_any} as sp) when constr.cstr_arity > 1 ->
            replicate_list sp constr.cstr_arity
        | Some sp -> [sp] in
      if List.length sargs <> constr.cstr_arity then
        raise(Error(sp.ppat_loc, Constructor_arity_mismatch(lid,
                                     constr.cstr_arity, List.length sargs)));
      let args = List.map (type_pat env) sargs in
      let (ty_args, ty_res) = instance_constructor constr in
      List.iter2 (unify_pat env) args ty_args;
      { pat_desc = Tpat_construct(constr, args);
        pat_loc = sp.ppat_loc;
        pat_type = ty_res;
        pat_env = env }
  | Ppat_variant(l, sarg) ->
      let arg = may_map (type_pat env) sarg in
      let arg_type = match arg with None -> [] | Some arg -> [arg.pat_type]  in
      let row = { row_fields =
                    [l, Reither(arg = None, arg_type, true, ref None)];
                  row_bound = arg_type;
                  row_closed = false;
                  row_more = newvar ();
                  row_name = None } in
      { pat_desc = Tpat_variant(l, arg, row);
        pat_loc = sp.ppat_loc;
        pat_type = newty (Tvariant row);
        pat_env = env }
  | Ppat_record lid_sp_list ->
      let rec check_duplicates = function
        [] -> ()
      | (lid, sarg) :: remainder ->
          if List.mem_assoc lid remainder
          then raise(Error(sp.ppat_loc, Label_multiply_defined lid))
          else check_duplicates remainder in
      check_duplicates lid_sp_list;
      let ty = newvar() in
      let type_label_pat (lid, sarg) =
        let label =
          try
            Env.lookup_label lid env
          with Not_found ->
            raise(Error(sp.ppat_loc, Unbound_label lid)) in
        let (ty_arg, ty_res) = instance_label label in
        begin try
          unify env ty_res ty
        with Unify trace ->
          raise(Error(sp.ppat_loc, Label_mismatch(lid, trace)))
        end;
        let arg = type_pat env sarg in
        unify_pat env arg ty_arg;
        (label, arg)
      in
      { pat_desc = Tpat_record(List.map type_label_pat lid_sp_list);
        pat_loc = sp.ppat_loc;
        pat_type = ty;
        pat_env = env }
  | Ppat_array spl ->
      let pl = List.map (type_pat env) spl in
      let ty_elt = newvar() in
      List.iter (fun p -> unify_pat env p ty_elt) pl;
      { pat_desc = Tpat_array pl;
        pat_loc = sp.ppat_loc;
        pat_type = instance (Predef.type_array ty_elt);
        pat_env = env }
  | Ppat_or(sp1, sp2) ->
      let initial_pattern_variables = !pattern_variables in
      let p1 = type_pat env sp1 in
      let p1_variables = !pattern_variables in
      pattern_variables := initial_pattern_variables ;
      let p2 = type_pat env sp2 in
      let p2_variables = !pattern_variables in
      unify_pat env p2 p1.pat_type;
      let alpha_env =
        enter_orpat_variables sp.ppat_loc env p1_variables p2_variables in
      pattern_variables := p1_variables ;
      { pat_desc = Tpat_or(p1, alpha_pat alpha_env p2, None);
        pat_loc = sp.ppat_loc;
        pat_type = p1.pat_type;
        pat_env = env }
  | Ppat_constraint(sp, sty) ->
      let p = type_pat env sp in
      let ty = Typetexp.transl_simple_type env false sty in
      unify_pat env p ty;
      p
  | Ppat_type lid ->
      build_or_pat env sp.ppat_loc lid

let add_pattern_variables env =
  let pv = !pattern_variables in
  pattern_variables := [];
  List.fold_right
    (fun (id, ty) env ->
       Env.add_value id {val_type = ty; val_kind = Val_reg} env)
    pv env

let type_pattern env spat =
  pattern_variables := [];
  let pat = type_pat env spat in
  let new_env = add_pattern_variables env in
  (pat, new_env)

let type_pattern_list env spatl =
  pattern_variables := [];
  let patl = List.map (type_pat env) spatl in
  let new_env = add_pattern_variables env in
  (patl, new_env)

(*> JOCAML *)

(**************************)
(* Collecting port names  *)
(* + linearity is checked *)
(**************************)

let rec enter_channel all_chans auto_chans cl_ids chan = function
  | [] ->
      (* check linearity *)
      let name = chan.pjident_desc in
      let p id = Ident.name id = name in  
      if
        List.exists p all_chans ||
        List.exists p !cl_ids
      then
        raise (Error (chan.pjident_loc, Multiply_bound_variable));      
      (* create and register id *)
      let (id, ty) as r = (Ident.create  chan.pjident_desc, newvar()) in
      auto_chans := (id, ty, chan.pjident_loc) :: !auto_chans ;
      cl_ids := id :: !cl_ids ;
      r
  | (id, ty, _)::rem ->
      if Ident.name id = chan.pjident_desc then
        (id, ty)
      else
        enter_channel all_chans auto_chans cl_ids chan rem

let enter_location all_chans jid =
  let name = jid.pjident_desc in
  if
    List.exists (fun id -> Ident.name id = name) !all_chans
  then
    raise (Error (jid.pjident_loc, Multiply_bound_variable));  
  let id = Ident.create name
  and ty = instance (Predef.type_location) in
  all_chans := id :: !all_chans ;
  (id, ty)

let enter_jarg cl_ids arg = match arg.pjarg_desc with
| Some name ->
  let p id = Ident.name id = name in
  (* check linearity *)
  if
    List.exists p !cl_ids
  then
    raise (Error (arg.pjarg_loc, Multiply_bound_variable));      
  (* create identifier *)
  let id = Ident.create name in
  cl_ids := id :: !cl_ids ;
  Some id
| None -> None

let mk_jident id loc ty env =
  {
    jident_desc = id;
    jident_loc  = loc;
    jident_type = ty;
    jident_env  = env;
  } 

and mk_jarg id loc ty env =
  {
    jarg_desc = id;
    jarg_loc  = loc;
    jarg_type = ty;
    jarg_env  = env;
  } 

let type_auto_lhs all_chans env {pjauto_desc=sauto ; pjauto_loc=auto_loc}  =
  let auto_chans = ref [] in
  let auto =
    List.map
      (fun cl ->
        let sjpats, _ = cl.pjclause_desc in
        let cl_ids = ref [] in
        let jpat =
          List.map
            (fun sjpat ->
              let schan, sargs = sjpat.pjpat_desc in
              let (id, ty) =
                enter_channel
                  !all_chans auto_chans cl_ids schan !auto_chans in
              let chan = mk_jident id schan.pjident_loc ty env
              and args =
                List.map
                  (fun jid ->
                    let idopt = enter_jarg cl_ids jid in
                    mk_jarg idopt jid.pjarg_loc (newvar()) env)
                  sargs in
              {jpat_desc = chan, args;
               jpat_loc  = sjpat.pjpat_loc;})
            sjpats in
        jpat)
      sauto in

  (* check linearity and collect defined channel names *)
  let old_all_chans = !all_chans in
  let names_defined =
    List.map
      (fun (id,ty,loc) ->
        if
          List.exists (fun oid -> Ident.equal oid id) old_all_chans
        then
          raise (Error (loc, Multiply_bound_variable));
        all_chans := id :: !all_chans;
        (id,ty))
      !auto_chans in
  (names_defined, auto)

let rec do_type_autos_lhs all_chans env = function
  | [] -> []
  | sauto::rem ->
      let r = type_auto_lhs all_chans env sauto in
      r::do_type_autos_lhs all_chans env rem

let type_autos_lhs env sautos = do_type_autos_lhs (ref []) env sautos

let rec do_type_locs_lhs all_chans env = function
  | [] -> []
  | loc_def::rem ->
      let slocation, sautos, _ = loc_def.pjloc_desc in
      let id_loc, ty = enter_location all_chans slocation in
      let location = mk_jident id_loc slocation.pjident_loc ty env in
      let r = do_type_autos_lhs all_chans env sautos in
      (location, r)::
      do_type_locs_lhs all_chans env rem

let type_locs_lhs env sdefs = do_type_locs_lhs (ref []) env sdefs
(*< JOCAML *)

let type_class_arg_pattern cl_num val_env met_env l spat =
  pattern_variables := [];
  let pat = type_pat val_env spat in
  if is_optional l then unify_pat val_env pat (type_option (newvar ()));
  let (pv, met_env) =
    List.fold_right
      (fun (id, ty) (pv, env) ->
         let id' = Ident.create (Ident.name id) in
         ((id', id, ty)::pv,
          Env.add_value id' {val_type = ty;
                             val_kind = Val_ivar (Immutable, cl_num)}
            env))
      !pattern_variables ([], met_env)
  in
  let val_env = add_pattern_variables val_env in
  (pat, pv, val_env, met_env)

let mkpat d = { ppat_desc = d; ppat_loc = Location.none }
let type_self_pattern cl_num val_env met_env par_env spat =
  let spat = 
    mkpat (Ppat_alias (mkpat(Ppat_alias (spat, "selfpat-*")),
                       "selfpat-" ^ cl_num))
  in
  pattern_variables := [];
  let pat = type_pat val_env spat in
  let meths = ref Meths.empty in
  let vars = ref Vars.empty in
  let pv = !pattern_variables in
  pattern_variables := [];
  let (val_env, met_env, par_env) =
    List.fold_right
      (fun (id, ty) (val_env, met_env, par_env) ->
         (Env.add_value id {val_type = ty; val_kind = Val_unbound} val_env,
          Env.add_value id {val_type = ty;
                            val_kind = Val_self (meths, vars, cl_num)}
            met_env,
          Env.add_value id {val_type = ty; val_kind = Val_unbound} par_env))
      pv (val_env, met_env, par_env)
  in
  (pat, meths, vars, val_env, met_env, par_env)

let check_unused_variant pat =
  match pat.pat_desc with
    Tpat_variant(tag, opat, row) ->
      let row = row_repr row in
      begin match
        try row_field_repr (List.assoc tag row.row_fields)
        with Not_found -> Rabsent
      with
      | Rpresent _ -> ()
      | Rabsent ->
          Location.prerr_warning pat.pat_loc Warnings.Unused_match
      | Reither (true, [], _, e) when not row.row_closed ->
          e := Some (Rpresent None)
      | Reither (false, ty::tl, _, e) when not row.row_closed ->
          e := Some (Rpresent (Some ty));
          begin match opat with None -> assert false
          | Some pat -> List.iter (unify_pat pat.pat_env pat) (ty::tl)
          end
      | Reither (c, l, true, e) ->
          e := Some (Reither (c, l, false, ref None))
      | _ -> ()
      end
  | _ -> ()

let rec iter_pattern f p =
  f p;
  match p.pat_desc with
    Tpat_any | Tpat_var _ | Tpat_constant _ ->
      ()
  | Tpat_alias (p, _) ->
      iter_pattern f p
  | Tpat_tuple pl ->
      List.iter (iter_pattern f) pl
  | Tpat_construct (_, pl) ->
      List.iter (iter_pattern f) pl
  | Tpat_variant (_, p, _) ->
      may (iter_pattern f) p
  | Tpat_record fl ->
      List.iter (fun (_, p) -> iter_pattern f p) fl
  | Tpat_or (p, p', _) ->
      iter_pattern f p;
      iter_pattern f p'
  | Tpat_array pl ->
      List.iter (iter_pattern f) pl

(* Generalization criterion for expressions *)

let rec is_nonexpansive exp =
  match exp.exp_desc with
    Texp_ident(_,_) -> true
  | Texp_constant _ -> true
  | Texp_let(rec_flag, pat_exp_list, body) ->
      List.for_all (fun (pat, exp) -> is_nonexpansive exp) pat_exp_list &&
      is_nonexpansive body
  | Texp_apply(e, (None,_)::el) ->
      is_nonexpansive e && List.for_all is_nonexpansive_opt (List.map fst el)
  | Texp_function _ -> true
  | Texp_tuple el ->
      List.for_all is_nonexpansive el
  | Texp_construct(_, el) ->
      List.for_all is_nonexpansive el
  | Texp_variant(_, arg) -> is_nonexpansive_opt arg
  | Texp_record(lbl_exp_list, opt_init_exp) ->
      List.for_all
        (fun (lbl, exp) -> lbl.lbl_mut = Immutable && is_nonexpansive exp)
        lbl_exp_list 
      && is_nonexpansive_opt opt_init_exp
  | Texp_field(exp, lbl) -> is_nonexpansive exp
  | Texp_array [] -> true
  | Texp_ifthenelse(cond, ifso, ifnot) ->
      is_nonexpansive ifso && is_nonexpansive_opt ifnot
  | Texp_new (_, cl_decl) when Ctype.class_type_arity cl_decl.cty_type > 0 ->
      true
  | Texp_def (_,e) -> is_nonexpansive e
  | Texp_loc (_,e) -> is_nonexpansive e
  | _ -> false

and is_nonexpansive_opt = function
    None -> true
  | Some e -> is_nonexpansive e

(* Typing of printf formats *)

let type_format loc fmt =
  let len = String.length fmt in
  let ty_input = newvar()
  and ty_result = newvar() in
  let rec skip_args j =
    if j >= len then j else
      match fmt.[j] with
        '0' .. '9' | ' ' | '.' | '-' -> skip_args (j+1)
      | _ -> j in
  let ty_arrow gty ty = newty (Tarrow("", instance gty, ty, Cok)) in
  let rec scan_format i =
    if i >= len then ty_result else
    match fmt.[i] with
      '%' ->
        let j = skip_args(i+1) in
        if j >= len then raise(Error(loc, Bad_format "%"));
        begin match fmt.[j] with
          '%' ->
            scan_format (j+1)
        | 's' ->
            ty_arrow Predef.type_string (scan_format (j+1))
        | 'c' ->
            ty_arrow Predef.type_char (scan_format (j+1))
        | 'd' | 'i' | 'o' | 'x' | 'X' | 'u' ->
            ty_arrow Predef.type_int (scan_format (j+1))
        | 'f' | 'e' | 'E' | 'g' | 'G' ->
            ty_arrow Predef.type_float (scan_format (j+1))
        | 'b' ->
            ty_arrow Predef.type_bool (scan_format (j+1))
        | 'a' ->
            let ty_arg = newvar() in
            ty_arrow (ty_arrow ty_input (ty_arrow ty_arg ty_result))
                     (ty_arrow ty_arg (scan_format (j+1)))
        | 't' ->
            ty_arrow (ty_arrow ty_input ty_result) (scan_format (j+1))
        | c ->
            raise(Error(loc, Bad_format(String.sub fmt i (j-i+1))))
        end
    | _ -> scan_format (i+1) in
  newty
    (Tconstr(Predef.path_format, [scan_format 0; ty_input; ty_result],
             ref Mnil))

(* Approximate the type of an expression, for better recursion *)

let rec approx_type sty =
  match sty.ptyp_desc with
    Ptyp_arrow (p, _, sty) ->
      let ty1 = if is_optional p then type_option (newvar ()) else newvar () in
      newty (Tarrow (p, ty1, approx_type sty, Cok))
  | _ -> newvar ()

let rec type_approx env sexp =
  match sexp.pexp_desc with
    Pexp_let (_, _, e) -> type_approx env e
  | Pexp_function (p,_,(_,e)::_) when is_optional p ->
       newty (Tarrow(p, type_option (newvar ()), type_approx env e, Cok))
  | Pexp_function (p,_,(_,e)::_) ->
       newty (Tarrow(p, newvar (), type_approx env e, Cok))
  | Pexp_match (_, (_,e)::_) -> type_approx env e
  | Pexp_try (e, _) -> type_approx env e
  | Pexp_tuple l -> newty (Ttuple(List.map (type_approx env) l))
  | Pexp_ifthenelse (_,e,_) -> type_approx env e
  | Pexp_sequence (_,e) -> type_approx env e
  | Pexp_constraint (e, sty1, sty2) ->
      let ty = type_approx env e
      and ty1 = match sty1 with None -> newvar () | Some sty -> approx_type sty
      and ty2 = match sty1 with None -> newvar () | Some sty -> approx_type sty
      in begin
        try unify env ty ty1; unify env ty1 ty2; ty2
        with Unify trace ->
          raise(Error(sexp.pexp_loc, Expr_type_clash trace))
      end
  | _ -> newvar ()

(* Typing of expressions *)

let unify_exp env exp expected_ty =
  try
    unify env exp.exp_type expected_ty
  with Unify trace ->
    raise(Error(exp.exp_loc, Expr_type_clash(trace)))

(*> JOCAML *)
type ctx = E | P (* Expression or Process *)

(* Check the expression/process nature of parsed expressions *)
let check_expression ctx sexp = match ctx with
| E -> ()
| P ->  raise (Error (sexp.pexp_loc, Expr_as_proc))

and check_process ctx sexp = match ctx with
| E ->  raise (Error (sexp.pexp_loc, Proc_as_expr))
| P -> ()


(* split n-1 first arguments / last argument *)
let rec last_arg = function
  | [] -> assert false
  | [x] -> [],x
  | x::rem ->
      let r,last = last_arg rem in
      x::r, x
(* Build a new application *)

let rec get_loc_end = function
  | [] -> assert false
  | [_, x] -> x.pexp_loc.Location.loc_end
  | _::rem -> get_loc_end rem

let mk_sapp f args = match args with
| [] -> f
| _  ->
   let loc_app = {f.pexp_loc with Location.loc_end = get_loc_end args} in
   {
     pexp_desc = Pexp_apply (f, args) ;
     pexp_loc = loc_app
   } 


let rec do_type_exp ctx env sexp =
  match sexp.pexp_desc with
  | Pexp_ident lid ->
      check_expression ctx sexp ;
      begin try
        let (path, desc) = Env.lookup_value lid env in
        { exp_desc =
            begin match desc.val_kind with
              Val_ivar (_, cl_num) ->
                let (self_path, _) =
                  Env.lookup_value (Longident.Lident ("self-" ^ cl_num)) env
                in
                Texp_instvar(self_path, path)
            | Val_self (_, _, cl_num) ->
                let (path, _) =
                  Env.lookup_value (Longident.Lident ("self-" ^ cl_num)) env
                in
                Texp_ident(path, desc)
            | Val_unbound ->
                raise(Error(sexp.pexp_loc, Masked_instance_variable lid))
            | _ ->
                Texp_ident(path, desc)
            end;
          exp_loc = sexp.pexp_loc;
          exp_type = instance desc.val_type;
          exp_env = env }
      with Not_found ->
        raise(Error(sexp.pexp_loc, Unbound_value lid))
      end
  | Pexp_constant cst ->
      check_expression ctx sexp ;
      { exp_desc = Texp_constant cst;
        exp_loc = sexp.pexp_loc;
        exp_type = type_constant cst;
        exp_env = env }
  | Pexp_let(rec_flag, spat_sexp_list, sbody) ->
      let (pat_exp_list, new_env) = type_let env rec_flag spat_sexp_list in
      let body = do_type_exp ctx new_env sbody in
      { exp_desc = Texp_let(rec_flag, pat_exp_list, body);
        exp_loc = sexp.pexp_loc;
        exp_type = body.exp_type;
        exp_env = env }
  | Pexp_function _ ->     (* defined in type_expect *)
      check_expression ctx sexp ;
      type_expect env sexp (newvar())
  | Pexp_apply(sfunct, sargs) ->
      begin match ctx with
      | E ->
          let funct = do_type_exp E env sfunct in
          let (args, ty_res) = type_application env funct sargs in
          { exp_desc = Texp_apply(funct, args);
            exp_loc = sexp.pexp_loc;
            exp_type = ty_res;
            exp_env = env }
      | P ->
          let spref, sarg = last_arg sargs in
          let sfunct = mk_sapp sfunct spref in
          let funct = do_type_exp E env sfunct in
          let ty =
            try
              filter_channel env funct.exp_type
            with
            | Unify _ ->
                raise
                  (Error
                     (sfunct.pexp_loc, Send_non_channel funct.exp_type)) in
          let arg = 
            type_expect env
              (match sarg with
              | "",sarg -> sarg
              | _, sarg ->
                  raise
                    (Error
                       (sarg.pexp_loc, Garrigue_illegal "message")))
              ty in
          { exp_desc = Texp_asend (funct, arg);
            exp_loc = sexp.pexp_loc;
            exp_type = instance Predef.type_process;
            exp_env = env }
      end
  | Pexp_match(sarg, caselist) ->
      let arg = do_type_exp E env sarg in
      let ty_res = newvar() in
      let cases, partial =
        type_cases ctx env arg.exp_type ty_res (Some sexp.pexp_loc) caselist in
      { exp_desc = Texp_match(arg, cases, partial);
        exp_loc = sexp.pexp_loc;
        exp_type = ty_res;
        exp_env = env }
  | Pexp_try(sbody, caselist) ->
      check_expression ctx sexp ;
      let body = do_type_exp ctx env sbody in
      let cases, _ =
        type_cases E env (instance Predef.type_exn) body.exp_type None
          caselist in
      { exp_desc = Texp_try(body, cases);
        exp_loc = sexp.pexp_loc;
        exp_type = body.exp_type;
        exp_env = env }
  | Pexp_tuple sexpl ->
      check_expression ctx sexp ;
      let expl = List.map (do_type_exp E env) sexpl in
      { exp_desc = Texp_tuple expl;
        exp_loc = sexp.pexp_loc;
        exp_type = newty (Ttuple(List.map (fun exp -> exp.exp_type) expl));
        exp_env = env }
  | Pexp_construct(lid, sarg, explicit_arity) ->
      check_expression ctx sexp ;
      type_construct env sexp.pexp_loc lid sarg explicit_arity (newvar ())
  | Pexp_variant(l, sarg) ->
      check_expression ctx sexp ;
      let arg = may_map (do_type_exp E env) sarg in
      let arg_type = may_map (fun arg -> arg.exp_type) arg in
      { exp_desc = Texp_variant(l, arg);
        exp_loc = sexp.pexp_loc;
        exp_type= newty (Tvariant{row_fields = [l, Rpresent arg_type];
                                  row_more = newvar ();
                                  row_bound = [];
                                  row_closed = false;
                                  row_name = None});
        exp_env = env }
  | Pexp_record(lid_sexp_list, opt_sexp) ->
      check_expression ctx sexp ;
      let ty = newvar() in
      let num_fields = ref 0 in
      let type_label_exp (lid, sarg) =
        let label =
          try
            Env.lookup_label lid env
          with Not_found ->
            raise(Error(sexp.pexp_loc, Unbound_label lid)) in
        let (ty_arg, ty_res) = instance_label label in
        begin try
          unify env ty_res ty
        with Unify trace ->
          raise(Error(sexp.pexp_loc, Label_mismatch(lid, trace)))
        end;
        let arg = type_expect env sarg ty_arg in
        num_fields := Array.length label.lbl_all;
        (label, arg) in
      let lbl_exp_list = List.map type_label_exp lid_sexp_list in
      let rec check_duplicates = function
        [] -> ()
      | (lid, sarg) :: remainder ->
          if List.mem_assoc lid remainder
          then raise(Error(sexp.pexp_loc, Label_multiply_defined lid))
          else check_duplicates remainder in
      check_duplicates lid_sexp_list;
      let opt_exp =
        match opt_sexp, lbl_exp_list with
          None, _ -> None
        | Some sexp, (lbl, _) :: _ ->
            let ty_exp = newvar () in
            let unify_kept lbl =
              if List.for_all (fun (lbl',_) -> lbl'.lbl_pos <> lbl.lbl_pos)
                  lbl_exp_list
              then begin
                let ty_arg1, ty_res1 = instance_label lbl
                and ty_arg2, ty_res2 = instance_label lbl in
                unify env ty_exp ty_res1;
                unify env ty ty_res2;
                unify env ty_arg1 ty_arg2
              end in
            Array.iter unify_kept lbl.lbl_all;
            Some(type_expect env sexp ty_exp)
        | _ -> assert false
      in
      if opt_sexp = None && List.length lid_sexp_list <> !num_fields then begin
        let present_indices =
          List.map (fun (lbl, _) -> lbl.lbl_pos) lbl_exp_list in
        let label_names = extract_label_names env ty in
        let rec missing_labels n = function
            [] -> []
          | lbl :: rem ->
              if List.mem n present_indices then missing_labels (n+1) rem
              else lbl :: missing_labels (n+1) rem
        in
        let missing = missing_labels 0 label_names in
        raise(Error(sexp.pexp_loc, Label_missing missing))
      end;
      { exp_desc = Texp_record(lbl_exp_list, opt_exp);
        exp_loc = sexp.pexp_loc;
        exp_type = ty;
        exp_env = env }
  | Pexp_field(sarg, lid) ->
      check_expression ctx sexp ;
      let arg = do_type_exp E env sarg in
      let label =
        try
          Env.lookup_label lid env
        with Not_found ->
          raise(Error(sexp.pexp_loc, Unbound_label lid)) in
      let (ty_arg, ty_res) = instance_label label in
      unify_exp env arg ty_res;
      { exp_desc = Texp_field(arg, label);
        exp_loc = sexp.pexp_loc;
        exp_type = ty_arg;
        exp_env = env }
  | Pexp_setfield(srecord, lid, snewval) ->
      check_expression ctx sexp ;
      let record = do_type_exp E env srecord in
      let label =
        try
          Env.lookup_label lid env
        with Not_found ->
          raise(Error(sexp.pexp_loc, Unbound_label lid)) in
      if label.lbl_mut = Immutable then
        raise(Error(sexp.pexp_loc, Label_not_mutable lid));
      let (ty_arg, ty_res) = instance_label label in
      unify_exp env record ty_res;
      let newval = type_expect env snewval ty_arg in
      { exp_desc = Texp_setfield(record, label, newval);
        exp_loc = sexp.pexp_loc;
        exp_type = instance Predef.type_unit;
        exp_env = env }
  | Pexp_array(sargl) ->
      check_expression ctx sexp ;
      let ty = newvar() in
      let argl = List.map (fun sarg -> type_expect env sarg ty) sargl in
      { exp_desc = Texp_array argl;
        exp_loc = sexp.pexp_loc;
        exp_type = instance (Predef.type_array ty);
        exp_env = env }
  | Pexp_ifthenelse(scond, sifso, sifnot) ->
      let cond = type_expect env scond (instance Predef.type_bool) in
      begin match ctx with
      | E ->
          begin match sifnot with
          | None ->
              let ifso = type_expect env sifso (instance Predef.type_unit) in
              { exp_desc = Texp_ifthenelse(cond, ifso, None);
                exp_loc = sexp.pexp_loc;
                exp_type = instance Predef.type_unit;
                exp_env = env }
          | Some sifnot ->
              let ifso = do_type_exp E env sifso in
              let ifnot = type_expect env sifnot ifso.exp_type in
              { exp_desc = Texp_ifthenelse(cond, ifso, Some ifnot);
                exp_loc = sexp.pexp_loc;
                exp_type = ifso.exp_type;
                exp_env = env }
          end
      | P ->
        begin match sifnot with
          | None ->
              let ifso = do_type_exp P env sifso in
              { exp_desc = Texp_ifthenelse(cond, ifso, None);
                exp_loc = sexp.pexp_loc;
                exp_type = instance Predef.type_process;
                exp_env = env }
          | Some sifnot ->
              let ifso = do_type_exp P env sifso in
              let ifnot = do_type_exp P env sifnot in
              { exp_desc = Texp_ifthenelse(cond, ifso, Some ifnot);
                exp_loc = sexp.pexp_loc;
                exp_type = instance Predef.type_process;
                exp_env = env }
          end  
      end
  | Pexp_sequence(sexp1, sexp2) ->
      let exp1 = type_statement env sexp1 in
      let exp2 = do_type_exp ctx env sexp2 in
      { exp_desc = Texp_sequence(exp1, exp2);
        exp_loc = sexp.pexp_loc;
        exp_type = exp2.exp_type;
        exp_env = env }
  | Pexp_while(scond, sbody) ->
      check_expression ctx sexp;
      let env = Env.remove_continuations env in
      let cond = type_expect env scond (instance Predef.type_bool) in
      let body = type_statement env sbody in
      { exp_desc = Texp_while(cond, body);
        exp_loc = sexp.pexp_loc;
        exp_type = instance Predef.type_unit;
        exp_env = env }
  | Pexp_for(param, slow, shigh, dir, sbody) ->
      check_expression ctx sexp;
      let env = Env.remove_continuations env in
      let low = type_expect env slow (instance Predef.type_int) in
      let high = type_expect env shigh (instance Predef.type_int) in
      let (id, new_env) =
        Env.enter_value param {val_type = instance Predef.type_int;
                                val_kind = Val_reg} env in
      let body = type_statement new_env sbody in
      { exp_desc = Texp_for(id, low, high, dir, body);
        exp_loc = sexp.pexp_loc;
        exp_type = instance Predef.type_unit;
        exp_env = env }
  | Pexp_constraint(sarg, sty, sty') ->
      check_expression ctx sexp;
      let (arg, ty') =
        match (sty, sty') with
          (None, None) ->               (* Case actually unused *)
            let arg = do_type_exp ctx env sarg in
            (arg, arg.exp_type)
        | (Some sty, None) ->
            let ty = Typetexp.transl_simple_type env false sty in
            (type_expect env sarg ty, ty)
        | (None, Some sty') ->
            let (ty', force) =
              Typetexp.transl_simple_type_delayed env sty'
            in
            let ty = enlarge_type env ty' in
            force ();
            let arg = do_type_exp ctx env sarg in
            begin try Ctype.unify env arg.exp_type ty with Unify trace ->
              raise(Error(sarg.pexp_loc,
                    Coercion_failure(ty', full_expand env ty', trace)))
            end;
            (arg, ty')
        | (Some sty, Some sty') ->
            let (ty, force) =
              Typetexp.transl_simple_type_delayed env sty
            and (ty', force') =
              Typetexp.transl_simple_type_delayed env sty'
            in
            begin try
              let force'' = subtype env ty ty' in
              force (); force' (); force'' ()
            with Subtype (tr1, tr2) ->
              raise(Error(sexp.pexp_loc, Not_subtype(tr1, tr2)))
            end;
            (type_expect env sarg ty, ty')
      in
      { exp_desc = arg.exp_desc;
        exp_loc = arg.exp_loc;
        exp_type = ty';
        exp_env = env }
  | Pexp_when(scond, sbody) ->
      let cond = type_expect env scond (instance Predef.type_bool) in
      let body = do_type_exp ctx env sbody in
      { exp_desc = Texp_when(cond, body);
        exp_loc = sexp.pexp_loc;
        exp_type = body.exp_type;
        exp_env = env }
  | Pexp_send (e, met) ->
      check_expression ctx sexp ;
      let obj = do_type_exp E env e in
      begin try
        let (exp, typ) =
          match obj.exp_desc with
            Texp_ident(path, {val_kind = Val_self (meths, _, _)}) ->
              let (id, typ) =
                filter_self_method env met Private meths obj.exp_type
              in
              (Texp_send(obj, Tmeth_val id), typ)
          | Texp_ident(path, {val_kind = Val_anc (methods, cl_num)}) ->
              let method_id =
                begin try List.assoc met methods with Not_found ->
                  raise(Error(e.pexp_loc, Undefined_inherited_method met))
                end
              in
              begin match
                Env.lookup_value (Longident.Lident ("selfpat-" ^ cl_num)) env,
                Env.lookup_value (Longident.Lident ("self-" ^cl_num)) env
              with
                (_, ({val_kind = Val_self (meths, _, _)} as desc)),
                (path, _) ->
                  let (_, typ) =
                    filter_self_method env met Private meths obj.exp_type
                  in
                  let method_type = newvar () in
                  let (obj_ty, res_ty) = filter_arrow env method_type "" in
                  unify env obj_ty desc.val_type;
                  unify env res_ty typ;
                  (Texp_apply({exp_desc = Texp_ident(Path.Pident method_id,
                                                     {val_type = method_type;
                                                       val_kind = Val_reg});
                                exp_loc = sexp.pexp_loc;
                                exp_type = method_type;
                                exp_env = env },
                              [Some {exp_desc = Texp_ident(path, desc);
                                     exp_loc = obj.exp_loc;
                                     exp_type = desc.val_type;
                                     exp_env = env },
                               Required]),
                   typ)
              |  _ ->
                  assert false
              end
          | _ ->
              (Texp_send(obj, Tmeth_name met),
               filter_method env met Public obj.exp_type)
        in
          { exp_desc = exp;
            exp_loc = sexp.pexp_loc;
            exp_type = typ;
            exp_env = env }
      with Unify _ ->
        raise(Error(e.pexp_loc, Undefined_method (obj.exp_type, met)))
      end
  | Pexp_new cl ->
      check_expression ctx sexp ;
      let (cl_path, cl_decl) =
        try Env.lookup_class cl env with Not_found ->
          raise(Error(sexp.pexp_loc, Unbound_class cl))
      in
        begin match cl_decl.cty_new with
          None ->
            raise(Error(sexp.pexp_loc, Virtual_class cl))
        | Some ty ->
            { exp_desc = Texp_new (cl_path, cl_decl);
              exp_loc = sexp.pexp_loc;
              exp_type = instance ty;
              exp_env = env }
        end
  | Pexp_setinstvar (lab, snewval) ->
      check_expression ctx sexp ;
      begin try
        let (path, desc) = Env.lookup_value (Longident.Lident lab) env in
        match desc.val_kind with
          Val_ivar (Mutable, cl_num) ->
            let newval = type_expect env snewval desc.val_type in
            let (path_self, _) =
              Env.lookup_value (Longident.Lident ("self-" ^ cl_num)) env
            in
            { exp_desc = Texp_setinstvar(path_self, path, newval);
              exp_loc = sexp.pexp_loc;
              exp_type = instance Predef.type_unit;
              exp_env = env }
        | Val_ivar _ ->
            raise(Error(sexp.pexp_loc, Instance_variable_not_mutable lab))
        | _ ->
            raise(Error(sexp.pexp_loc, Unbound_instance_variable lab))
      with
        Not_found ->
          raise(Error(sexp.pexp_loc, Unbound_instance_variable lab))
      end        
  | Pexp_override lst ->
      check_expression ctx sexp ;
      let _ = 
       List.fold_right
        (fun (lab, _) l ->
           if List.exists ((=) lab) l then
             raise(Error(sexp.pexp_loc,
                         Value_multiply_overridden lab));
           lab::l)
        lst
        [] in
      begin match
        try
          Env.lookup_value (Longident.Lident "selfpat-*") env,
          Env.lookup_value (Longident.Lident "self-*") env
        with Not_found ->
          raise(Error(sexp.pexp_loc, Outside_class))
      with
        (_, {val_type = self_ty; val_kind = Val_self (_, vars, _)}),
        (path_self, _) ->
          let type_override (lab, snewval) =
            begin try
              let (id, _, ty) = Vars.find lab !vars in
              (Path.Pident id, type_expect env snewval ty)
            with
              Not_found ->
                raise(Error(sexp.pexp_loc, Unbound_instance_variable lab))
            end
          in
          let modifs = List.map type_override lst in
          { exp_desc = Texp_override(path_self, modifs);
            exp_loc = sexp.pexp_loc;
            exp_type = self_ty;
            exp_env = env }
      | _ ->
          assert false
      end
  | Pexp_letmodule(name, smodl, sbody) ->
      let ty = newvar() in
      Ident.set_current_time ty.level;
      let modl = !type_module env smodl in
      let (id, new_env) = Env.enter_module name modl.mod_type env in
      Ctype.init_def(Ident.current_time());
      let body = do_type_exp ctx new_env sbody in
      (* Unification of body.exp_type with the fresh variable ty
         fails if and only if the prefix condition is violated,
         i.e. if generative types rooted at id show up in the
         type body.exp_type.  Thus, this unification enforces the
         scoping condition on "let module". *)
      begin try
        Ctype.unify new_env body.exp_type ty
      with Unify _ ->
        raise(Error(sexp.pexp_loc, Scoping_let_module(name, body.exp_type)))
      end;
      { exp_desc = Texp_letmodule(id, modl, body);
        exp_loc = sexp.pexp_loc;
        exp_type = ty;
        exp_env = env }
  | Pexp_assert (e) ->
      check_expression ctx sexp ;
       let cond = type_expect env e (instance Predef.type_bool) in
       {
         exp_desc = Texp_assert (cond);
         exp_loc = sexp.pexp_loc;
         exp_type = instance Predef.type_unit;
         exp_env = env;
       }
  | Pexp_assertfalse ->
      check_expression ctx sexp ;
       {
         exp_desc = Texp_assertfalse;
         exp_loc = sexp.pexp_loc;
         exp_type = newvar ();
         exp_env = env;
       }
  | Pexp_spawn (sarg) ->
      check_expression ctx sexp ;
      let arg = do_type_exp P env sarg in
      {
        exp_desc = Texp_spawn arg;
        exp_loc = sexp.pexp_loc;
        exp_type = instance (Predef.type_unit);
        exp_env = env;
      } 
  | Pexp_par (se1, se2) ->
      check_process ctx sexp ;
      let e1 = do_type_exp P env se1
      and e2 = do_type_exp P env se2 in
      {
        exp_desc = Texp_par (e1, e2);
        exp_loc = sexp.pexp_loc;
        exp_type = e2.exp_type; (* necessarily process *)
        exp_env = env;
      } 
  | Pexp_null ->
      check_process ctx sexp ;
      {
        exp_desc = Texp_null;
        exp_loc = sexp.pexp_loc;
        exp_type =  instance Predef.type_process;
        exp_env = env;
      } 
  | Pexp_reply (sres, jid) ->
      check_process ctx sexp ;
      let lid = Longident.parse jid.pjident_desc in
      let path,ty =
        try
          let path,desc = Env.lookup_continuation lid env in
          desc.continuation_kind <- true ;
          path, desc.continuation_type
        with Not_found ->
          raise(Error(jid.pjident_loc, Unbound_value lid)) in
      let res = type_expect env sres ty in
      {
        exp_desc = Texp_reply (res, path);
        exp_loc  = sexp.pexp_loc;
        exp_type = instance Predef.type_process;
        exp_env  = env;
      }
  | Pexp_def (sautos, sbody) ->
      let (autos, new_env) = type_def env sautos in
      let body = do_type_exp ctx new_env sbody in
      {
        exp_desc = Texp_def (autos, body);
        exp_loc  = sexp.pexp_loc;
        exp_type = body.exp_type;
        exp_env  = env
      } 
  | Pexp_loc (sdefs, sbody) ->
      let (defs, new_env) = type_loc env sdefs in
      let body = do_type_exp ctx new_env sbody in
      {
        exp_desc = Texp_loc (defs, body);
        exp_loc  = sexp.pexp_loc;
        exp_type = body.exp_type;
        exp_env  = env
      } 
(*< JOCAML *)

and type_argument env sarg ty_expected =
  let rec no_labels ty =
    let ty = expand_head env ty in
    match ty.desc with
      Tvar -> false
    | Tarrow ("",_, ty,_) when not !Clflags.classic -> no_labels ty
    | Tarrow _ -> false
    | _ -> true
  in
  match expand_head env ty_expected, sarg with
  | _, {pexp_desc = Pexp_function(l,_,_)} when not (is_optional l) ->
      type_expect env sarg ty_expected
  | {desc = Tarrow("",ty_arg,ty_res,_)}, _ ->
      (* apply optional arguments when expected type is "" *)
      (* we must be very careful about not breaking the semantics *)
      let texp = do_type_exp E env sarg in
      let rec make_args args ty_fun =
        match (expand_head env ty_fun).desc with
        | Tarrow (l,ty_arg,ty_fun,_) when is_optional l ->
            make_args
              ((Some(option_none ty_arg sarg.pexp_loc), Optional) :: args)
              ty_fun
        | Tarrow (l,_,ty_res',_) when l = "" || !Clflags.classic ->
            args, ty_fun, no_labels ty_res'
        | Tvar ->  args, ty_fun, false
        |  _ -> [], texp.exp_type, false
      in
      let args, ty_fun, simple_res = make_args [] texp.exp_type in
      if not (simple_res || no_labels ty_res) then
        type_expect env sarg ty_expected
      else begin
      unify_exp env {texp with exp_type = ty_fun} ty_expected;
      if args = [] then texp else
      (* eta-expand to avoid side effects *)
      let var_pair name ty =
        let id = Ident.create name in
        {pat_desc = Tpat_var id; pat_type = ty_arg;
         pat_loc = Location.none; pat_env = env},
        {exp_type = ty_arg; exp_loc = Location.none; exp_env = env; exp_desc =
         Texp_ident(Path.Pident id,{val_type = ty_arg; val_kind = Val_reg})}
      in
      let eta_pat, eta_var = var_pair "eta" ty_arg in
      let func texp =
        { texp with exp_type = ty_fun; exp_desc =
          Texp_function([eta_pat, {texp with exp_type = ty_res; exp_desc =
                                   Texp_apply (texp, args@
                                               [Some eta_var, Required])}],
                        Total) } in
      if is_nonexpansive texp then func texp else
      (* let-expand to have side effects *)
      let let_pat, let_var = var_pair "let" texp.exp_type in
      { texp with exp_type = ty_fun; exp_desc =
        Texp_let (Nonrecursive, [let_pat, texp], func let_var) }
      end
  | _ ->
      type_expect env sarg ty_expected

and type_application env funct sargs =
  let result_type omitted ty_fun =
    List.fold_left
      (fun ty_fun (l,ty,lv) -> newty2 lv (Tarrow(l,ty,ty_fun,Cok)))
      ty_fun omitted
  in
  let rec has_label l ty_fun =
    match (expand_head env ty_fun).desc with
    | Tarrow (l', _, ty_res, _) ->
        (l = l' || has_label l ty_res)
    | Tvar -> true
    | _ -> false
  in
  let ignored = ref [] in
  let rec type_unknown_args args omitted ty_fun = function
      [] ->
        (List.rev_map
           (function None, x -> None, x | Some f, x -> Some (f ()), x)
           args,
         result_type omitted ty_fun)
    | (l1, sarg1) :: sargl ->
        let (ty1, ty2) =
          match (expand_head env ty_fun).desc with
            Tvar ->
              let t1 = newvar () and t2 = newvar () in
              unify env ty_fun (newty (Tarrow(l1,t1,t2,Clink(ref Cunknown))));
              (t1, t2)
          | Tarrow (l,t1,t2,_) when l = l1
            || !Clflags.classic && l1 = "" && not (is_optional l) ->
              (t1, t2)
          | td ->
              let ty_fun =
                match td with Tarrow _ -> newty td | _ -> ty_fun in
              let ty_res = result_type (omitted @ !ignored) ty_fun in
              match ty_res.desc with
                Tarrow _ ->
                  if (!Clflags.classic || not (has_label l1 ty_fun)) then
                    raise(Error(sarg1.pexp_loc, Apply_wrong_label(l1, ty_res)))
                  else
                    raise(Error(funct.exp_loc, Incoherent_label_order))
              | _ ->
                  raise(Error(funct.exp_loc,
                              Apply_non_function funct.exp_type))
        in
        let optional = if is_optional l1 then Optional else Required in
        let arg1 () =
          let arg1 = type_expect env sarg1 ty1 in
          if optional = Optional then
            unify_exp env arg1 (type_option(newvar()));
          arg1
        in
        type_unknown_args ((Some arg1, optional) :: args) omitted ty2 sargl
  in
  let rec nonopt_labels ls ty_fun =
    match (expand_head env ty_fun).desc with
    | Tarrow (l, _, ty_res, _) ->
        if is_optional l then nonopt_labels ls ty_res
        else nonopt_labels (l::ls) ty_res
    | Tvar -> None
    | _    -> Some ls
  in
  let ignore_labels =
    !Clflags.classic ||
    match nonopt_labels [] funct.exp_type with
    | Some labels ->
        List.length labels = List.length sargs &&
        List.for_all (fun (l,_) -> l = "") sargs &&
        List.exists (fun l -> l <> "") labels &&
        begin
          Location.prerr_warning funct.exp_loc Warnings.Labels_omitted;
          true
        end
    | None -> false
  in
  let rec type_args args omitted ty_fun ty_old sargs more_sargs =
    match expand_head env ty_fun with
      {desc=Tarrow (l, ty, ty_fun, com); level=lv} as ty_fun'
      when (sargs <> [] || more_sargs <> []) && commu_repr com = Cok ->
        let name = label_name l
        and optional = if is_optional l then Optional else Required in
        let sargs, more_sargs, arg =
          if ignore_labels && not (is_optional l) then begin
            (* In classic mode, omitted = [] *)
            match sargs, more_sargs with
              (l', sarg0) :: _, _ ->
                raise(Error(sarg0.pexp_loc, Apply_wrong_label(l', ty_old)))
            | _, (l', sarg0) :: more_sargs ->
                if l <> l' && l' <> "" then
                  raise(Error(sarg0.pexp_loc, Apply_wrong_label(l', ty_fun')))
                else
                  ([], more_sargs, Some (fun () -> type_argument env sarg0 ty))
            | _ ->
                assert false
          end else try
            let (l', sarg0, sargs, more_sargs) =
              try
                let (l', sarg0, sargs1, sargs2) = extract_label name sargs
                in (l', sarg0, sargs1 @ sargs2, more_sargs)
              with Not_found ->
                let (l', sarg0, sargs1, sargs2) = extract_label name more_sargs
                in (l', sarg0, sargs @ sargs1, sargs2)
            in
            sargs, more_sargs,
            if optional = Required || is_optional l' then
              Some (fun () -> type_argument env sarg0 ty)
            else
              Some (fun () -> option_some (type_argument env sarg0 
                                             (extract_option_type env ty)))
          with Not_found ->
            sargs, more_sargs,
            if optional = Optional &&
              (List.mem_assoc "" sargs || List.mem_assoc "" more_sargs)
            then begin
              ignored := (l,ty,lv) :: !ignored;
              Some (fun () -> option_none ty Location.none)
            end else None
        in
        let omitted = if arg = None then (l,ty,lv) :: omitted else omitted in
        let ty_old = if sargs = [] then ty_fun else ty_old in
        type_args ((arg,optional)::args) omitted ty_fun ty_old sargs more_sargs
    | _ ->
        match sargs with
          (l, sarg0) :: _ when ignore_labels ->
            raise(Error(sarg0.pexp_loc, Apply_wrong_label(l, ty_old)));
        | _ ->
            type_unknown_args args omitted ty_fun (sargs @ more_sargs)
  in
  match funct.exp_desc, sargs with
    (* Special case for ignore: avoid discarding warning *)
    Texp_ident (_, {val_kind=Val_prim{Primitive.prim_name="%ignore"}}),
    ["", sarg] ->
      let ty_arg, ty_res = filter_arrow env funct.exp_type "" in
      let exp = type_expect env sarg ty_arg in
      begin match expand_head env exp.exp_type with
      | {desc = Tarrow _} ->
          Location.prerr_warning exp.exp_loc Warnings.Partial_application
      | _ -> ()
      end;
      ([Some exp, Required], ty_res)
  | _ ->
      let ty = funct.exp_type in
      if ignore_labels then
        type_args [] [] ty ty [] sargs
      else
        type_args [] [] ty ty sargs []

and type_construct env loc lid sarg explicit_arity ty_expected =
  let constr =
    try
      Env.lookup_constructor lid env
    with Not_found ->
      raise(Error(loc, Unbound_constructor lid)) in
  let sargs =
    match sarg with
      None -> []
    | Some {pexp_desc = Pexp_tuple sel} when explicit_arity -> sel
    | Some {pexp_desc = Pexp_tuple sel} when constr.cstr_arity > 1 -> sel
    | Some se -> [se] in
  if List.length sargs <> constr.cstr_arity then
    raise(Error(loc, Constructor_arity_mismatch
                  (lid, constr.cstr_arity, List.length sargs)));
  let (ty_args, ty_res) = instance_constructor constr in
  let texp =
    { exp_desc = Texp_construct(constr, []);
      exp_loc = loc;
      exp_type = ty_res;
      exp_env = env } in
  unify_exp env texp ty_expected;
  let args = List.map2 (type_expect env) sargs ty_args in
  { texp with exp_desc = Texp_construct(constr, args) }

(* Typing of an expression with an expected type.
   Some constructs are treated specially to provide better error messages. *)

and type_expect env sexp ty_expected =
  match sexp.pexp_desc with
    Pexp_constant(Const_string s as cst) ->
      let exp =
        { exp_desc = Texp_constant cst;
          exp_loc = sexp.pexp_loc;
          exp_type =
            (* Terrible hack for format strings *)
            begin match (repr ty_expected).desc with
              Tconstr(path, _, _) when Path.same path Predef.path_format ->
                type_format sexp.pexp_loc s
            | _ -> instance Predef.type_string
            end;
          exp_env = env } in
      unify_exp env exp ty_expected;
      exp
  | Pexp_construct(lid, sarg, explicit_arity) ->
      type_construct env sexp.pexp_loc lid sarg explicit_arity ty_expected
  | Pexp_let(rec_flag, spat_sexp_list, sbody) ->
      let (pat_exp_list, new_env) = type_let env rec_flag spat_sexp_list in
      let body = type_expect new_env sbody ty_expected in
      { exp_desc = Texp_let(rec_flag, pat_exp_list, body);
        exp_loc = sexp.pexp_loc;
        exp_type = body.exp_type;
        exp_env = env }
  | Pexp_sequence(sexp1, sexp2) ->
      let exp1 = type_statement env sexp1 in
      let exp2 = type_expect env sexp2 ty_expected in
      { exp_desc = Texp_sequence(exp1, exp2);
        exp_loc = sexp.pexp_loc;
        exp_type = exp2.exp_type;
        exp_env = env }
  | Pexp_function (l, Some default, [spat, sbody]) ->
      let loc = default.pexp_loc in
      let scases =
        [{ppat_loc = loc; ppat_desc =
          Ppat_construct(Longident.Lident"Some",
                         Some{ppat_loc = loc; ppat_desc = Ppat_var"*sth*"},
                         false)},
         {pexp_loc = loc; pexp_desc = Pexp_ident(Longident.Lident"*sth*")};
         {ppat_loc = loc; ppat_desc =
          Ppat_construct(Longident.Lident"None", None, false)},
         default] in
      let smatch =
        {pexp_loc = loc; pexp_desc =
         Pexp_match({pexp_loc = loc; pexp_desc =
                     Pexp_ident(Longident.Lident"*opt*")},
                    scases)} in
      let sfun =
        {pexp_loc = sexp.pexp_loc; pexp_desc =
         Pexp_function(l, None,[{ppat_loc = loc; ppat_desc = Ppat_var"*opt*"},
                                {pexp_loc = sexp.pexp_loc; pexp_desc =
                                 Pexp_let(Default, [spat, smatch], sbody)}])}
      in
      type_expect env sfun ty_expected
  | Pexp_function (l, _, caselist) ->
      let (ty_arg, ty_res) =
        try filter_arrow env ty_expected l
        with Unify _ ->
          match expand_head env ty_expected with
            {desc = Tarrow _} as ty ->
              raise(Error(sexp.pexp_loc, Abstract_wrong_label(l, ty)))
          | _ ->
              raise(Error(sexp.pexp_loc, Too_many_arguments))
      in
      if is_optional l then begin
        try unify env ty_arg (type_option(newvar()))
        with Unify _ -> assert false
      end;
(*> JOCAML *)
      let env_noconts = Env.remove_continuations env in
(*< JOCAML *)      
      let cases, partial =
        type_cases E env_noconts ty_arg ty_res (Some sexp.pexp_loc) caselist in
      let rec all_labeled ty =
        match (repr ty).desc with
          Tarrow ("", _, _, _) | Tvar -> false
        | Tarrow (l, _, ty, _) -> l.[0] <> '?' && all_labeled ty
        | _ -> true
      in
      if is_optional l && all_labeled ty_res then
        Location.prerr_warning (fst (List.hd cases)).pat_loc
          (Warnings.Other "This optional argument cannot be erased");
      { exp_desc = Texp_function(cases, partial);
        exp_loc = sexp.pexp_loc;
        exp_type = newty (Tarrow(l, ty_arg, ty_res, Cok));
        exp_env = env }
  | _ ->
      let exp = do_type_exp E env sexp in
      unify_exp env exp ty_expected;
      exp

(* Typing of statements (expressions whose values are discarded) *)

and type_statement env sexp =
    let exp = do_type_exp E env sexp in
    match (expand_head env exp.exp_type).desc with
    | Tarrow _ ->
        Location.prerr_warning sexp.pexp_loc Warnings.Partial_application;
        exp
    | Tconstr (p, _, _) when Path.same p Predef.path_unit -> exp
    | Tvar -> exp
    | _ ->
        Location.prerr_warning sexp.pexp_loc Warnings.Statement_type;
        exp

(* Typing of match cases *)
(* Argument ty_res is unused when ctx is P *)
and type_cases ctx env ty_arg ty_res partial_loc caselist =
  let ty_arg' = newvar () in
  let pat_env_list =
    List.map
      (fun (spat, _) ->
        let (pat, ext_env) = type_pattern env spat in
        unify_pat env pat ty_arg';
        (pat, ext_env))
      caselist in
  (* Check partial matches here (required for polymorphic variants) *)
  let partial =
    match partial_loc with None -> Partial
    | Some loc ->
        let cases = List.map2
            (fun (pat, _) (_, act) ->
              let dummy = { exp_desc = Texp_tuple [];
                            exp_type = newty (Ttuple[]);
                            exp_env = env; exp_loc = act.pexp_loc } in
              match act.pexp_desc with
                Pexp_when _ ->
                  pat, {dummy with exp_desc = Texp_when(dummy, dummy)}
              | _           -> pat, dummy)
            pat_env_list caselist in
        Parmatch.check_partial env loc cases in
  (* `Contaminating' unifications start here *)
  begin match pat_env_list with [] -> ()
  | (pat, _) :: _ -> unify_pat env pat ty_arg
  end;
  let cases = match ctx with
  | E ->    
    List.map2
      (fun (pat, ext_env) (_, sexp) ->        
        let exp = type_expect ext_env sexp ty_res in
        (pat, exp))
      pat_env_list caselist
  | P ->
      List.map2
        (fun (pat, ext_env) (_, sexp) ->        
          let exp = do_type_exp P ext_env sexp in
          (pat, exp))
        pat_env_list caselist in
  (* Check for impossible variant constructors, and normalize variant types *)
  List.iter (fun (pat, _) -> iter_pattern check_unused_variant pat) cases;
  Parmatch.check_unused env cases;
  cases, partial

(* Typing of let bindings *)

and type_let env rec_flag spat_sexp_list =
  begin_def();
  let (pat_list, new_env) =
    type_pattern_list env (List.map (fun (spat, sexp) -> spat) spat_sexp_list)
  in
  if rec_flag = Recursive then
    List.iter2
      (fun pat (_, sexp) -> unify_pat env pat (type_approx env sexp))
      pat_list spat_sexp_list;
  let exp_env =
    match rec_flag with Nonrecursive | Default -> env | Recursive -> new_env in
  let exp_list =
    List.map2
      (fun (spat, sexp) pat -> type_expect exp_env sexp pat.pat_type)
      spat_sexp_list pat_list in
  List.iter2
    (fun pat exp -> ignore(Parmatch.check_partial env pat.pat_loc [pat, exp]))
    pat_list exp_list;
  end_def();
  List.iter2
    (fun pat exp ->
       if not (is_nonexpansive exp) then
         iter_pattern (fun pat -> make_nongen pat.pat_type) pat)
    pat_list exp_list;
  List.iter
    (fun pat -> iter_pattern (fun pat -> generalize pat.pat_type) pat)
    pat_list;
  (List.combine pat_list exp_list, new_env)

(*> JOCAML *)
(* Typing of join definitions *)
and type_clause env names jpats scl =
  let conts = ref [] in
  let extend_env jpat env =
    let chan,args = jpat.jpat_desc in
    let kid = chan.jident_desc
    and kdesc =
      {continuation_type = newvar();
       continuation_kind = false;} in
    conts := kdesc :: !conts;
    List.fold_left
      (fun env jarg -> match jarg.jarg_desc with
      | Some id ->
          Env.add_value
            id
            {val_kind = Val_reg ;
            val_type = jarg.jarg_type}
            env
      | None -> env)
      (Env.add_continuation kid kdesc env) args in
  let new_env = List.fold_right extend_env jpats env
  and _,sexp = scl.pjclause_desc in
  let exp = do_type_exp P new_env sexp in

  (* Now type defined names *)
  List.iter2
    (fun jpat kdesc ->
      let chan, args = jpat.jpat_desc in
      let tchan =
        try
          List.assoc chan.jident_desc names
        with Not_found -> assert false in
      let targs = match args with
      | [] -> instance (Predef.type_unit)
      | [jarg] -> jarg.jarg_type
      | _ ->
          newty
            (Ttuple (List.map (fun jarg -> jarg.jarg_type) args)) in
      let otchan =
        match kdesc with
        | {continuation_kind=false} ->
            Ctype.make_channel targs
        | {continuation_type=tres} ->
            newty (Tarrow ("", targs, tres, Cok)) in
      try
        unify env otchan tchan
      with Unify trace ->
        raise(Error(jpat.jpat_loc, Join_pattern_type_clash(trace))))
    jpats !conts ;

  { jclause_loc = scl.pjclause_loc;
    jclause_desc = (jpats, exp);}
  

and type_auto env (def_names, auto_lhs) sauto =
  let cls =
    List.map2 (type_clause env def_names) auto_lhs sauto.pjauto_desc in
  let def_names =
    List.map
      (fun (chan, ty) -> match (expand_head env ty).desc with
      | Tarrow (_, _, _, _) ->
          chan, {jchannel_sync=true; jchannel_type=ty}
      | Tconstr (p, _, _) when Path.same p Predef.path_channel ->
          chan, {jchannel_sync=false; jchannel_type=ty}
      | _ -> assert false)
      def_names in
  {jauto_desc = cls;
   jauto_names = def_names;
   jauto_loc = sauto.pjauto_loc}

and generalize_auto auto =
      List.iter
        (fun cl ->
          let jpats,_ = cl.jclause_desc in
          let tys = ref [] in
          List.iter
            (fun jpat ->
              let chan,_ = jpat.jpat_desc in
              let newtys = ref [] in
              let rec f ty =
                if List.memq ty !tys then
                  make_nongen ty
                else if not (List.memq ty !newtys) then begin
                  newtys := ty :: !newtys ;
                  iter_type_expr f ty
                end in
              iter_type_expr f chan.jident_type ;
              tys := !newtys @ !tys)
            jpats)
        auto.jauto_desc;
      List.iter
        (fun (id,chan) -> generalize chan.jchannel_type)
        auto.jauto_names

and add_auto_names env names =
   List.fold_left
     (fun env (id,ty) ->
         Env.add_value id {val_type = ty; val_kind = Val_reg} env)
      env names

and type_def env sautos =
  begin_def ();
  let names_lhs_list = type_autos_lhs env sautos in
  let new_env =
    List.fold_left
      (fun env (names,_) -> add_auto_names env names)
      env names_lhs_list in
  let autos =
    List.map2 (type_auto new_env) names_lhs_list sautos in
  end_def () ;

(* Generalization *)
  List.iter generalize_auto autos ;

  autos, new_env

and type_loc env sdefs =
  begin_def ();
  let names_lhs_list = type_locs_lhs env sdefs in
  let new_env =
    List.fold_left
      (fun env (jid_loc, autos_lhs) ->
       List.fold_left
          (fun env (names,_) -> add_auto_names env names)
          (Env.add_value
             jid_loc.jident_desc
             {val_type = jid_loc.jident_type; val_kind = Val_reg}
             env)
          autos_lhs)
       env  names_lhs_list in
  let defs =
    List.map2
      (fun (location, autos_lhs) loc_def ->
        let (_, sautos,sexp) = loc_def.pjloc_desc in
        let autos =
          List.map2 (type_auto new_env) autos_lhs sautos in
        let exp = do_type_exp P new_env sexp in
        {jloc_desc= (location, autos, exp);
         jloc_loc = loc_def.pjloc_loc})
      names_lhs_list sdefs in
  end_def ();

(* Generalization *)
  List.iter
    (fun loc_def ->
      let _,autos,_ = loc_def.jloc_desc in
      List.iter generalize_auto autos)
    defs;
  defs, new_env

(*< JOCAML *)

(* Exported typer for expressions *)
let type_exp  env sexp = do_type_exp E env sexp 

(* Typing of toplevel bindings *)

let type_binding env rec_flag spat_sexp_list =
  Typetexp.reset_type_variables();
  type_let env rec_flag spat_sexp_list

(* Typing of toplevel expressions *)

let type_expression env sexp =
  Typetexp.reset_type_variables();
  begin_def();
  let exp = do_type_exp E env sexp in
  end_def();
  if is_nonexpansive exp then generalize exp.exp_type
  else make_nongen exp.exp_type;
  exp

(*> JOCAML *)
(* Typing of toplevel join-definition *)
let type_joindefinition env d =
  Typetexp.reset_type_variables();
  type_def env d

let type_joinlocation env d =
  Typetexp.reset_type_variables();
  type_loc env d

(*< JOCAML *)
(* Error report *)

open Format
open Printtyp

let report_error ppf = function
  | Unbound_value lid ->
      fprintf ppf "Unbound value %a" longident lid
  | Unbound_constructor lid ->
      fprintf ppf "Unbound constructor %a" longident lid
  | Unbound_label lid ->
      fprintf ppf "Unbound record field label %a" longident lid
  | Constructor_arity_mismatch(lid, expected, provided) ->
      fprintf ppf
       "@[The constructor %a@ expects %i argument(s),@ \
        but is here applied to %i argument(s)@]"
       longident lid expected provided
  | Label_mismatch(lid, trace) ->
      report_unification_error ppf trace
        (function ppf ->
           fprintf ppf "The record field label %a@ belongs to the type"
                   longident lid)
        (function ppf ->
           fprintf ppf "but is here mixed with labels of type")
  | Pattern_type_clash trace ->
      report_unification_error ppf trace
        (function ppf ->
           fprintf ppf "This pattern matches values of type")
        (function ppf ->
           fprintf ppf "but is here used to match values of type")
  | Multiply_bound_variable ->
      fprintf ppf "This variable is bound several times in this matching"
  | Orpat_vars id ->
      fprintf ppf "Variable %s must occur on both sides of this | pattern"
        (Ident.name id)
  | Expr_type_clash trace ->
      report_unification_error ppf trace
        (function ppf ->
           fprintf ppf "This expression has type")
        (function ppf ->
           fprintf ppf "but is here used with type")
  | Apply_non_function typ ->
      begin match (repr typ).desc with
        Tarrow _ ->
          fprintf ppf "This function is applied to too many arguments"
      | _ ->
          fprintf ppf
            "This expression is not a function, it cannot be applied"
      end
  | Apply_wrong_label (l, ty) ->
      let print_label ppf = function
        | "" -> fprintf ppf "without label"
        | l -> fprintf ppf "with label ~%s" l in
      reset_and_mark_loops ty;
      fprintf ppf
        "@[<v>@[<2>Expecting function has type@ %a@]@,\
          This argument cannot be applied %a@]"
        type_expr ty print_label l
  | Label_multiply_defined lid ->
      fprintf ppf "The record field label %a is defined several times"
              longident lid
  | Label_missing labels ->
      let print_labels ppf = List.iter (fun lbl -> fprintf ppf "@ %s" lbl) in
      fprintf ppf "@[<hov>Some record field labels are undefined:%a@]"
        print_labels labels
  | Label_not_mutable lid ->
      fprintf ppf "The record field label %a is not mutable" longident lid
  | Bad_format s ->
      fprintf ppf "Bad format `%s'" s
  | Undefined_method (ty, me) ->
      reset_and_mark_loops ty;
      fprintf ppf
        "@[<v>@[This expression has type@;<1 2>%a@]@,\
         It has no method %s@]" type_expr ty me
  | Undefined_inherited_method me ->
      fprintf ppf "This expression has no method %s" me
  | Unbound_class cl ->
      fprintf ppf "Unbound class %a" longident cl
  | Virtual_class cl ->
      fprintf ppf "One cannot create instances of the virtual class %a"
      longident cl
  | Unbound_instance_variable v ->
      fprintf ppf "Unbound instance variable %s" v
  | Instance_variable_not_mutable v ->
      fprintf ppf "The instance variable %s is not mutable" v
  | Not_subtype(tr1, tr2) ->
      report_subtyping_error ppf tr1 "is not a subtype of type" tr2
  | Outside_class ->
      fprintf ppf "This object duplication occurs outside a method definition"
  | Value_multiply_overridden v ->
      fprintf ppf "The instance variable %s is overridden several times" v
  | Coercion_failure (ty, ty', trace) ->
      report_unification_error ppf trace
        (function ppf ->
           let ty, ty' = prepare_expansion (ty, ty') in
           fprintf ppf
             "This expression cannot be coerced to type@;<1 2>%a;@ it has type"
           (type_expansion ty) ty')
        (function ppf ->
           fprintf ppf "but is here used with type")
  | Too_many_arguments ->
      fprintf ppf "This function expects too many arguments"
  | Abstract_wrong_label (l, ty) ->
      let label_mark = function
        | "" -> "but its first argument is not labeled"
        |  l -> sprintf "but its first argument is labeled ~%s" l in
      reset_and_mark_loops ty;
      fprintf ppf "@[<v>@[<2>This function should have type@ %a@]@,%s@]"
      type_expr ty (label_mark l)
  | Scoping_let_module(id, ty) ->
      reset_and_mark_loops ty;
      fprintf ppf
       "This `let module' expression has type@ %a@ " type_expr ty;
      fprintf ppf
       "In this type, the locally bound module name %s escapes its scope" id
  | Masked_instance_variable lid ->
      fprintf ppf
        "The instance variable %a@ \
         cannot be accessed from the definition of another instance variable"
        longident lid
  | Not_a_variant_type lid ->
      fprintf ppf "The type %a@ is not a variant type" longident lid
  | Incoherent_label_order ->
      fprintf ppf "This function is applied to arguments@ ";
      fprintf ppf "in an order different from other calls.@ ";
      fprintf ppf "This is only allowed when the real type is known."
(*> JOCAML *)
  | Expr_as_proc ->
      fprintf ppf "This expression is used in process context"
  | Proc_as_expr ->
      fprintf ppf "This process is used in expression context"
  | Garrigue_illegal msg ->
      fprintf ppf "Illegal label in jocaml: %s" msg
  | Vouillon_illegal msg ->
      fprintf ppf "Illegal object in jocaml: %s" msg
  | Send_non_channel typ ->
      fprintf ppf "This expression is not a channel"
  | Join_pattern_type_clash trace ->
      report_unification_error ppf trace
        (function ppf ->
           fprintf ppf "This join-pattern defines a channel of type")
        (function ppf ->
           fprintf ppf "but the channel is used with type")
(*< JOCAML *)      
