(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(* Compilation of pattern matching *)

open Misc
open Location
open Asttypes
open Primitive
open Types
open Typedtree
open Lambda

(*  See Peyton-Jones, ``The Implementation of functional programming
    languages'', chapter 5. *)

type pattern_matching =
  { mutable cases : (pattern list * lambda) list;
    args : (lambda * let_kind) list }

(* To group lines of patterns with identical keys *)

let add_line patl_action pm =
  pm.cases <- patl_action :: pm.cases; pm

let add make_matching_fun division key patl_action args =
  try
    let pm = List.assoc key division in
    pm.cases <- patl_action :: pm.cases;
    division
  with Not_found ->
    let pm = make_matching_fun args in
    pm.cases <- patl_action :: pm.cases;
    (key, pm) :: division

(* To find reasonable names for let-bound and lambda-bound idents *)

let rec name_pattern default = function
    (pat :: patl, action) :: rem ->
      begin match pat.pat_desc with
        Tpat_var id -> id
      | Tpat_alias(p, id) -> id
      | _ -> name_pattern default rem
      end
  | _ -> Ident.create default

(* To let-bind expressions to variables *)

let bind str var exp body =
  match exp with
    Lvar var' when Ident.same var var' -> body
  | _ -> Llet(str, var, exp, body)

(* To remove aliases and bind named components *)

let any_pat =
  { pat_desc = Tpat_any; pat_loc = Location.none;
    pat_type = Ctype.none; pat_env = Env.empty }

let simplify_matching m =
  match m.args with
    [] -> m
  | (arg, mut) :: argl ->
      let rec simplify = function
        (pat :: patl, action as patl_action) :: rem ->
          begin match pat.pat_desc with
            Tpat_var id ->
              (any_pat :: patl, bind Alias id arg action) ::
              simplify rem
          | Tpat_alias(p, id) ->
              simplify ((p :: patl, bind Alias id arg action) :: rem)
          | _ ->
              patl_action :: simplify rem
          end
      | cases -> cases in
    { args = m.args; cases = simplify m.cases }

(* Matching against a constant *)

let make_constant_matching = function
    [] -> fatal_error "Matching.make_constant_matching"
  | (arg :: argl) -> {cases = []; args = argl}

let divide_constant {cases = cl; args = al} =
  let rec divide = function
      ({pat_desc = Tpat_constant cst} :: patl, action) :: rem ->
        let (constants, others) = divide rem in
        (add make_constant_matching constants cst (patl, action) al, others)
    | cl ->
      ([], {cases = cl; args = al})
  in divide cl

(* Matching against a constructor *)

let make_field_args binding_kind arg first_pos last_pos argl =
  let rec make_args pos =
    if pos > last_pos
    then argl
    else (Lprim(Pfield pos, [arg]), binding_kind) :: make_args (pos + 1)
  in make_args first_pos

let make_constr_matching cstr = function
    [] -> fatal_error "Matching.make_constr_matching"
  | ((arg, mut) :: argl) ->
      let newargs =
        match cstr.cstr_tag with
          Cstr_constant _ | Cstr_block _ ->
            make_field_args Alias arg 0 (cstr.cstr_arity - 1) argl
        | Cstr_exception _ ->
            make_field_args Alias arg 1 cstr.cstr_arity argl in
      {cases = []; args = newargs}

let divide_constructor {cases = cl; args = al} =
  let rec divide = function
      ({pat_desc = Tpat_construct(cstr, args)} :: patl, action) :: rem ->
        let (constructs, others) = divide rem in
        (add (make_constr_matching cstr) constructs
             cstr.cstr_tag (args @ patl, action) al,
         others)
    | cl ->
      ([], {cases = cl; args = al})
  in divide cl

(* Making a constructor description from a variant pattern *)

let constr_of_variant row lab =
  let consts = ref 0 and nonconsts = ref 0 and cst = ref true in
  let row = Btype.row_repr row in
  if row.row_closed then
    List.iter
      (fun (lab', f) ->
	match Btype.row_field_repr f with
	  Rabsent -> ()
	| Reither([],_) | Rpresent None -> incr consts
	| Reither _ | Rpresent _ ->
	    nonconsts := 1; if lab = lab' then cst := false)
      row.row_fields
  else (consts := 100000; nonconsts := 1);
  { cstr_res = Ctype.newty (Tvariant row);
    cstr_args = [];
    cstr_arity = if !cst then 0 else 2;
    cstr_tag =
       if !cst then Cstr_constant (Btype.hash_variant lab) else Cstr_block 0;
    cstr_consts = !consts;
    cstr_nonconsts = !nonconsts }

let map_variant_matching pm =
  let pat_variant pat =
    match pat.pat_desc with Tpat_variant (lab, pato, row) ->
      let row = Btype.row_repr row in
      if Btype.row_field_repr (List.assoc lab row.row_fields) = Rabsent
      then raise Not_found;
      let patl =
        match pato with None -> []
        | Some pat ->
	    let consts = ref 0 in
	    if row.row_closed then
      	      List.iter
		(fun (lab,f) -> match Btype.row_field_repr f with
		| Reither(_::_,_) | Rpresent(Some _) -> incr consts
		| _ -> ())
      	       	row.row_fields
	    else consts := 100000;
            [{ pat with
	       pat_desc = Tpat_construct
                 ({cstr_res = Ctype.newty(Tvariant row);
      	       	   cstr_args = [];
		   cstr_arity = 0;
                   cstr_tag = Cstr_constant (Btype.hash_variant lab);
		   cstr_consts = !consts; cstr_nonconsts = 0},
		  []);
               pat_type = Predef.type_int };
             pat]
      in
      {pat with pat_desc = Tpat_construct (constr_of_variant row lab, patl)}
    | _ -> pat
  in
  { args = pm.args;
    cases =
      List.fold_right
        (fun (patl, lam) l ->
	  try (List.map pat_variant patl, lam) :: l with Not_found -> l)
        pm.cases [] }


(* Matching against a variable *)

let divide_var {cases = cl; args = al} =
  let rec divide = function
      ({pat_desc = Tpat_any} :: patl, action) :: rem ->
        let (vars, others) = divide rem in
        (add_line (patl, action) vars, others)
    | cl ->
        (make_constant_matching al, {cases = cl; args = al})
  in divide cl

(* Matching against a tuple pattern *)

let make_tuple_matching num_comps = function
    [] -> fatal_error "Matching.make_tuple_matching"
  | (arg, mut) :: argl ->
      let rec make_args pos =
        if pos >= num_comps
        then argl
        else (Lprim(Pfield pos, [arg]), Alias) :: make_args (pos + 1) in
      {cases = []; args = make_args 0}

let divide_tuple arity {cases = cl; args = al} =
  let rec divide = function
      ({pat_desc = Tpat_tuple args} :: patl, action) :: rem ->
        let (tuples, others) = divide rem in
        (add_line (args @ patl, action) tuples, others)
    | ({pat_desc = Tpat_any} :: patl, action) :: rem ->
        let (tuples, others) = divide rem in
        (add_line (replicate_list any_pat arity @ patl, action) tuples, others)
    | cl ->
        (make_tuple_matching arity al, {cases = cl; args = al})
  in divide cl

(* Matching against a record pattern *)

let make_record_matching all_labels = function
    [] -> fatal_error "Matching.make_tuple_matching"
  | ((arg, mut) :: argl) ->
      let rec make_args pos =
        if pos >= Array.length all_labels then argl else begin
          let lbl = all_labels.(pos) in
          let access =
            match lbl.lbl_repres with
              Record_regular -> Pfield lbl.lbl_pos
            | Record_float -> Pfloatfield lbl.lbl_pos in
          let str =
            match lbl.lbl_mut with
              Immutable -> Alias
            | Mutable -> StrictOpt in
          (Lprim(access, [arg]), str) :: make_args(pos + 1)
        end in
      {cases = []; args = make_args 0}

let divide_record all_labels {cases = cl; args = al} =
  let num_fields = Array.length all_labels in
  let record_matching_line lbl_pat_list =
    let patv = Array.create num_fields any_pat in
    List.iter (fun (lbl, pat) -> patv.(lbl.lbl_pos) <- pat) lbl_pat_list;
    Array.to_list patv in
  let rec divide = function
      ({pat_desc = Tpat_record lbl_pat_list} :: patl, action) :: rem ->
        let (records, others) = divide rem in
        (add_line (record_matching_line lbl_pat_list @ patl, action) records,
         others)
    | ({pat_desc = Tpat_any} :: patl, action) :: rem ->
        let (records, others) = divide rem in
        (add_line (record_matching_line [] @ patl, action) records, others)
    | cl ->
        (make_record_matching all_labels al, {cases = cl; args = al})
  in divide cl

(* Matching against an or pattern. *)

let rec flatten_orpat_match pat =
  match pat.pat_desc with
    Tpat_or(p1, p2) -> flatten_orpat_match p1 @ flatten_orpat_match p2
  | _ -> [[pat], lambda_unit]

let divide_orpat = function
    {cases = (orpat :: patl, act) :: casel; args = arg1 :: argl as args} ->
      ({cases = flatten_orpat_match orpat; args = [arg1]},
       {cases = [patl, act]; args = argl},
       {cases = casel; args = args})
  | _ ->
    fatal_error "Matching.divide_orpat"

(* Matching against an array pattern *)

let make_array_matching kind len = function
    [] -> fatal_error "Matching.make_array_matching"
  | ((arg, mut) :: argl) ->
      let rec make_args pos =
        if pos >= len
        then argl
        else (Lprim(Parrayrefu kind, [arg; Lconst(Const_base(Const_int pos))]),
              StrictOpt) :: make_args (pos + 1) in
      {cases = []; args = make_args 0}

let divide_array kind {cases = cl; args = al} =
  let rec divide = function
      ({pat_desc = Tpat_array(args)} :: patl, action) :: rem ->
        let len = List.length args in
        let (constructs, others) = divide rem in
        (add (make_array_matching kind len) constructs len
             (args @ patl, action) al,
         others)
    | cl ->
      ([], {cases = cl; args = al})
  in divide cl

(* To combine sub-matchings together *)

let combine_var (lambda1, total1) (lambda2, total2) =
  if total1 then (lambda1, true)
  else if lambda2 = Lstaticfail then (lambda1, total1)
  else (Lcatch(lambda1, lambda2), total2)

let rec cut n l =
    if n = 0 then [],l
    else match l with
      [] -> raise (Invalid_argument "cut")
    | a::l -> let l1,l2 = cut (n-1) l in a::l1, l2

let make_test_sequence check tst lt_tst arg const_lambda_list =
  let rec make_test_sequence const_lambda_list =
    if List.length const_lambda_list >= 4 & lt_tst <> Praise then
      split_sequence const_lambda_list
    else
      List.fold_right
      	(fun (c, act) rem ->
      	 if rem = Lstaticfail && not check then act else
      	 Lifthenelse(Lprim(tst, [arg; Lconst(Const_base c)]), act, rem))
      	const_lambda_list
        Lstaticfail
  and split_sequence const_lambda_list =
    let list1, list2 =
      	  cut (List.length const_lambda_list / 2) const_lambda_list in
    Lifthenelse(Lprim(lt_tst,[arg; Lconst(Const_base (fst(List.hd list2)))]),
      	       	make_test_sequence list1, make_test_sequence list2)
  in make_test_sequence
      (Sort.list (fun (c1,_) (c2,_) -> c1 < c2) const_lambda_list)

let make_switch_or_test_sequence check arg const_lambda_list int_lambda_list =
  if const_lambda_list = [] then
    if check then Lstaticfail else lambda_unit
  else
  let min_key =
    List.fold_right (fun (k, l) m -> min k m) int_lambda_list max_int in
  let max_key =
    List.fold_right (fun (k, l) m -> max k m) int_lambda_list min_int in
  (* min_key and max_key can be arbitrarily large, so watch out for
     overflow in the following comparison *)
  if List.length int_lambda_list <= 1 + max_key / 4 - min_key / 4 then
    (* Sparse matching -- use a sequence of tests
       (4 bytecode instructions per test)  *)
    make_test_sequence check (Pintcomp Ceq) (Pintcomp Clt)
       arg const_lambda_list
  else begin
    (* Dense matching -- use a jump table
       (2 bytecode instructions + 1 word per entry in the table) *)
    let numcases = max_key - min_key + 1 in
    let cases =
      List.map (fun (key, l) -> (key - min_key, l)) int_lambda_list in
    let offsetarg =
      if min_key = 0 then arg else Lprim(Poffsetint(-min_key), [arg]) in
    Lswitch(offsetarg,
            {sw_numconsts = numcases; sw_consts = cases;
             sw_numblocks = 0; sw_blocks = []; sw_checked = check})
  end

let make_bitvect_check arg int_lambda_list =
  let bv = String.make 32 '\000' in
  List.iter
    (fun (n, l) ->
      bv.[n lsr 3] <- Char.chr(Char.code bv.[n lsr 3] lor (1 lsl (n land 7))))
    int_lambda_list;
  Lifthenelse(Lprim(Pbittest, [Lconst(Const_base(Const_string bv)); arg]),
              lambda_unit, Lstaticfail)

let prim_string_equal =
  Pccall{prim_name = "string_equal";
         prim_arity = 2; prim_alloc = false;
         prim_native_name = ""; prim_native_float = false}

let combine_constant arg cst (const_lambda_list, total1) (lambda2, total2) =
  let lambda1 =
    match cst with
      Const_int _ ->
        let int_lambda_list =
          List.map (function Const_int n, l -> n,l | _ -> assert false)
                   const_lambda_list in
        make_switch_or_test_sequence true arg const_lambda_list int_lambda_list
    | Const_char _ ->
        let int_lambda_list =
          List.map (function Const_char c, l -> (Char.code c, l)
                           | _ -> assert false)
                   const_lambda_list in
        if List.for_all (fun (c, l) -> l = lambda_unit) const_lambda_list then
          make_bitvect_check arg int_lambda_list 
        else
          make_switch_or_test_sequence true arg
      	    const_lambda_list int_lambda_list
    | Const_string _ ->
        make_test_sequence true prim_string_equal Praise arg const_lambda_list
    | Const_float _ ->
        make_test_sequence true (Pfloatcomp Ceq) (Pfloatcomp Clt)
      	    arg const_lambda_list
  in (Lcatch(lambda1, lambda2), total2)

let combine_constructor arg cstr partial
	(tag_lambda_list, total1) (lambda2, total2) =
  if cstr.cstr_consts < 0 then begin
    (* Special cases for exceptions *)
    let lambda1 =
      List.fold_right
        (fun (ex, act) rem ->
           match ex with
           | Cstr_exception path ->
               Lifthenelse(Lprim(Pintcomp Ceq, 
                                 [Lprim(Pfield 0, [arg]); transl_path path]),
                           act, rem)
           | _ -> assert false)
        tag_lambda_list Lstaticfail
    in (Lcatch(lambda1, lambda2), total2)
  end else begin
    (* Regular concrete type *)
    let rec split_cases = function
      [] -> ([], [])
    | (cstr, act) :: rem ->
        let (consts, nonconsts) = split_cases rem in
        match cstr with
          Cstr_constant n -> ((n, act) :: consts, nonconsts)
        | Cstr_block n    -> (consts, (n, act) :: nonconsts)
        | _ -> assert false in
    let (consts, nonconsts) = split_cases tag_lambda_list
    and total = total1 &
      (partial = Total or
       List.length tag_lambda_list = cstr.cstr_consts + cstr.cstr_nonconsts) in
    let mkifthenelse arg act2 act1 = match cstr.cstr_res.desc with
      	Tconstr _ when cstr.cstr_consts = 1 ->  Lifthenelse(arg, act2, act1)
      | _ -> Lifthenelse
        (Lprim (Pandint, [arg; Lconst (Const_pointer 0)]), act2, act1) in
    let lambda1 =
      if total &
	List.for_all (fun (_, act) -> act = lambda_unit) tag_lambda_list
      then
	lambda_unit
      else
      match (cstr.cstr_consts, cstr.cstr_nonconsts, consts, nonconsts) with
        (1, 0, [0, act], []) -> act
      | (0, 1, [], [0, act]) -> act
      | (1, 1, [n, act1], [0, act2]) ->
          mkifthenelse arg act2 act1
      | (1, 1, [n, act1], []) ->
          mkifthenelse arg Lstaticfail act1
      | (n, 1, [], [0, act2]) ->
          mkifthenelse arg act2 Lstaticfail
      | (_, _, _, _) ->
      	  match cstr.cstr_res.desc with Tconstr _ ->
	    Lswitch(arg, {sw_numconsts = cstr.cstr_consts;
			  sw_consts = consts;
			  sw_numblocks = cstr.cstr_nonconsts;
			  sw_blocks = nonconsts;
			  sw_checked = false})
	  | _ ->
	  let cases = List.map (fun (n, act) -> Const_int n, act) consts in
	  match nonconsts with
      	    [] -> make_switch_or_test_sequence (not total) arg cases consts
      	  | [0, act] ->
	      mkifthenelse arg act
      	       	(make_switch_or_test_sequence (not total) arg cases consts)
	  | _ -> fatal_error "Matching.combine_constructor"
    in
    if total then (lambda1, true)
    else (Lcatch(lambda1, lambda2), total2)
  end

let combine_orpat (lambda1, total1) (lambda2, total2) (lambda3, total3) =
  (Lcatch(Lsequence(lambda1, lambda2), lambda3), total3)

let combine_array kind arg (len_lambda_list, total1) (lambda2, total2) =
  let lambda1 =
    match len_lambda_list with
      [] -> Lstaticfail (* does not happen? *)
    | [n, act] ->
        Lifthenelse(Lprim(Pintcomp Ceq,
                          [Lprim(Parraylength kind, [arg]);
                           Lconst(Const_base(Const_int n))]),
                    act, Lstaticfail)
    | _ ->
        let max_len =
          List.fold_left (fun m (n, act) -> max m n) 0 len_lambda_list in
        Lswitch(Lprim(Parraylength kind, [arg]),
                {sw_numblocks = 0; sw_blocks = []; sw_checked = true;
                 sw_numconsts = max_len + 1; sw_consts = len_lambda_list}) in
  (Lcatch(lambda1, lambda2), total2)

(* Insertion of debugging events *)

let rec event_branch repr lam =
  begin match lam, repr with
    (_, None) ->
      lam
  | (Levent(lam', ev), Some r) ->
      incr r;
      Levent(lam', {lev_loc = ev.lev_loc;
                    lev_kind = ev.lev_kind;
                    lev_repr = repr;
                    lev_env = ev.lev_env})
  | (Llet(str, id, lam, body), _) ->
      Llet(str, id, lam, event_branch repr body)
  | (_, Some r) ->
(*      incr r;
      Levent(lam, {lev_loc = -1;
                   lev_kind = Lev_before;
                   lev_repr = repr;
                   lev_env = Env.Env_empty})
*)      fatal_error "Matching.event_branch"
  end

(* The main compilation function.
   Input: a pattern matching.
   Output: a lambda term, a "total" flag (true if we're sure that the
     matching covers all cases; this is an approximation). *)

let rec compile_match repr partial m =

  let rec compile_list partial = function
    [] -> ([], true)
  | (key, pm) :: rem ->
      let (lambda1, total1) = compile_match repr partial pm in
      let (list2, total2) = compile_list partial rem in
      ((key, lambda1) :: list2, total1 & total2) in

  match m with
    { cases = [] } ->
      (Lstaticfail, false)
  | { cases = ([], action) :: rem; args = argl } ->
      if is_guarded action then begin
        let (lambda, total) =
	  compile_match None partial { cases = rem; args = argl } in
        (Lcatch(event_branch repr action, lambda), total)
      end else
        (event_branch repr action, true)
  | { args = (arg, str) :: argl } ->
      let v = name_pattern "match" m.cases in
      let newarg = Lvar v in
      let pm =
        simplify_matching
          { cases = m.cases; args = (newarg, Alias) :: argl } in
      let (lam, total) =
        match pm.cases with
          (pat :: patl, action) :: _ ->
            begin match pat.pat_desc with
              Tpat_any ->
                let (vars, others) = divide_var pm in
		let partial' =
		  if others.cases = [] then partial else Partial in
                combine_var (compile_match repr partial' vars)
			    (compile_match repr partial others)
            | Tpat_constant cst ->
                let (constants, others) = divide_constant pm in
		let partial' =
		  if others.cases = [] then partial else Partial in
                combine_constant newarg cst
                  (compile_list partial' constants)
		  (compile_match repr partial others)
            | Tpat_tuple patl ->
                let (tuples, others) = divide_tuple (List.length patl) pm in
		let partial' =
		  if others.cases = [] then partial else Partial in
                combine_var (compile_match repr partial' tuples)
			    (compile_match repr partial others)
            | Tpat_construct(cstr, patl) ->
                let (constrs, others) = divide_constructor pm in
		let partial' =
		  if others.cases = [] then partial else Partial in
                combine_constructor newarg cstr partial'
                  (compile_list partial' constrs)
		  (compile_match repr partial others)
            | Tpat_variant(lab, _, lvar) ->
	        let pm = map_variant_matching pm
		and cstr = constr_of_variant lvar lab in
                let (constrs, others) = divide_constructor pm in
		let partial' =
		  if others.cases = [] then partial else Partial in
                combine_constructor newarg cstr partial'
                  (compile_list partial' constrs)
		  (compile_match repr partial others)
            | Tpat_record((lbl, _) :: _) ->
                let (records, others) = divide_record lbl.lbl_all pm in
		let partial' =
		  if others.cases = [] then partial else Partial in
                combine_var (compile_match repr partial' records)
			    (compile_match repr partial others)
            | Tpat_array(patl) ->
                let kind = Typeopt.array_pattern_kind pat in
                let (arrays, others) = divide_array kind pm in
                combine_array kind newarg
                              (compile_list Partial arrays)
                              (compile_match repr partial others)
            | Tpat_or(pat1, pat2) ->
                (* Avoid duplicating the code of the action *)
                let (or_match, remainder_line, others) = divide_orpat pm in
		let partial' =
		  if others.cases = [] then partial else Partial in
		if partial' = Total then
		  or_match.cases <- [[{ pat_desc = Tpat_any;
					pat_loc = pat.pat_loc;
					pat_type = pat.pat_type;
					pat_env = pat.pat_env }],
				      lambda_unit];
                combine_orpat (compile_match None Partial or_match)
                              (compile_match repr partial' remainder_line)
                              (compile_match repr partial others)
            | _ ->
                fatal_error "Matching.compile_match1"
            end
        | _ -> fatal_error "Matching.compile_match2" in
      (bind str v arg lam, total)
  | _ -> assert false

(* The entry points *)

let compile_matching repr handler_fun arg pat_act_list partial =
  let pm =
    { cases = List.map (fun (pat, act) -> ([pat], act)) pat_act_list;
      args = [arg, Strict] } in
  let (lambda, total) = compile_match repr partial pm in
  if total then lambda else Lcatch(lambda, handler_fun())

let partial_function loc () =
  Lprim(Praise, [Lprim(Pmakeblock(0, Immutable),
          [transl_path Predef.path_match_failure;
           Lconst(Const_block(0,
              [Const_base(Const_string !Location.input_name);
               Const_base(Const_int loc.loc_start);
               Const_base(Const_int loc.loc_end)]))])])

let for_function loc repr param pat_act_list partial =
  compile_matching repr (partial_function loc) param pat_act_list partial

let for_trywith param pat_act_list =
  compile_matching None (fun () -> Lprim(Praise, [param]))
    param pat_act_list Partial

let for_let loc param pat body =
  compile_matching None (partial_function loc) param [pat, body] Partial

(* Handling of tupled functions and matches *)

exception Cannot_flatten

let flatten_pattern size p =
  match p.pat_desc with
    Tpat_tuple args -> args
  | Tpat_any -> replicate_list any_pat size
  | _ -> raise Cannot_flatten

let flatten_cases size cases =
  List.map (function (pat :: _, act) -> (flatten_pattern size pat, act)
                   | _ -> assert false)
           cases

let for_tupled_function loc paraml pats_act_list partial =
  let pm =
    { cases = pats_act_list;
      args = List.map (fun id -> (Lvar id, Strict)) paraml } in
  let (lambda, total) = compile_match None partial pm in
  if total then lambda else Lcatch(lambda, partial_function loc ())

let for_multiple_match loc paraml pat_act_list partial =
  let pm1 =
    { cases = List.map (fun (pat, act) -> ([pat], act)) pat_act_list;
      args = [Lprim(Pmakeblock(0, Immutable), paraml), Strict] } in
  let pm2 =
    simplify_matching pm1 in
  try
    let idl = List.map (fun _ -> Ident.create "match") paraml in
    let pm3 =
      { cases = flatten_cases (List.length paraml) pm2.cases;
        args = List.map (fun id -> (Lvar id, Alias)) idl } in
    let (lambda, total) = compile_match None partial pm3 in
    let lambda2 =
      if total then lambda else Lcatch(lambda, partial_function loc ()) in
    List.fold_right2 (bind Strict) idl paraml lambda2
  with Cannot_flatten ->
    let (lambda, total) = compile_match None partial pm2 in
    if total then lambda else Lcatch(lambda, partial_function loc ())
