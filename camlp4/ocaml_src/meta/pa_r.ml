(* camlp4r pa_extend.cmo q_MLast.cmo *)
(***********************************************************************)
(*                                                                     *)
(*                             Camlp4                                  *)
(*                                                                     *)
(*        Daniel de Rauglaudre, projet Cristal, INRIA Rocquencourt     *)
(*                                                                     *)
(*  Copyright 2001 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* Id *)

open Stdpp;;
open Pcaml;;

Pcaml.no_constructors_arity := false;;

let help_sequences () =
  Printf.eprintf "\
New syntax:
     do {e1; e2; ... ; en}
     while e do {e1; e2; ... ; en}
     for v = v1 to/downto v2 do {e1; e2; ... ; en}
Old (discouraged) syntax:
     do e1; e2; ... ; en-1; return en
     while e do e1; e2; ... ; en; done
     for v = v1 to/downto v2 do e1; e2; ... ; en; done
To avoid compilation warning use the new syntax.
";
  flush stderr;
  exit 1
;;
Pcaml.add_option "-help_seq" (Arg.Unit help_sequences)
  "    Print explanations about new sequences and exit.";;

let odfa = !(Plexer.dollar_for_antiquotation) in
Plexer.dollar_for_antiquotation := false;
Grammar.Unsafe.reinit_gram gram (Plexer.make ());
Plexer.dollar_for_antiquotation := odfa;
Grammar.Unsafe.clear_entry interf;
Grammar.Unsafe.clear_entry implem;
Grammar.Unsafe.clear_entry top_phrase;
Grammar.Unsafe.clear_entry use_file;
Grammar.Unsafe.clear_entry module_type;
Grammar.Unsafe.clear_entry module_expr;
Grammar.Unsafe.clear_entry sig_item;
Grammar.Unsafe.clear_entry str_item;
Grammar.Unsafe.clear_entry expr;
Grammar.Unsafe.clear_entry patt;
Grammar.Unsafe.clear_entry ctyp;
Grammar.Unsafe.clear_entry let_binding;
Grammar.Unsafe.clear_entry class_type;
Grammar.Unsafe.clear_entry class_expr;
Grammar.Unsafe.clear_entry class_sig_item;
Grammar.Unsafe.clear_entry class_str_item;;

let o2b =
  function
    Some _ -> true
  | None -> false
;;

let mkumin loc f arg =
  match arg with
    MLast.ExInt (_, n) when int_of_string n > 0 ->
      let n = "-" ^ n in MLast.ExInt (loc, n)
  | MLast.ExFlo (_, n) when float_of_string n > 0.0 ->
      let n = "-" ^ n in MLast.ExFlo (loc, n)
  | _ -> let f = "~" ^ f in MLast.ExApp (loc, MLast.ExLid (loc, f), arg)
;;

let mklistexp loc last =
  let rec loop top =
    function
      [] ->
        begin match last with
          Some e -> e
        | None -> MLast.ExUid (loc, "[]")
        end
    | e1 :: el ->
        let loc = if top then loc else fst (MLast.loc_of_expr e1), snd loc in
        MLast.ExApp
          (loc, MLast.ExApp (loc, MLast.ExUid (loc, "::"), e1), loop false el)
  in
  loop true
;;

let mklistpat loc last =
  let rec loop top =
    function
      [] ->
        begin match last with
          Some p -> p
        | None -> MLast.PaUid (loc, "[]")
        end
    | p1 :: pl ->
        let loc = if top then loc else fst (MLast.loc_of_patt p1), snd loc in
        MLast.PaApp
          (loc, MLast.PaApp (loc, MLast.PaUid (loc, "::"), p1), loop false pl)
  in
  loop true
;;

(* ...suppose to flush the input in case of syntax error to avoid multiple
   errors in case of cut-and-paste in the xterm, but work bad: for example
   the input "for x = 1;" waits for another line before displaying the
   error...
value rec sync cs =
  match cs with parser
  [ [: `';' :] -> sync_semi cs
  | [: `_ :] -> sync cs ]
and sync_semi cs =
  match Stream.peek cs with 
  [ Some ('\010' | '\013') -> ()
  | _ -> sync cs ]
;
Pcaml.sync.val := sync;
*)

let type_parameter = Grammar.Entry.create gram "type_parameter";;
let fun_binding = Grammar.Entry.create gram "fun_binding";;
let ipatt = Grammar.Entry.create gram "ipatt";;
let direction_flag = Grammar.Entry.create gram "direction_flag";;
let mod_ident = Grammar.Entry.create gram "mod_ident";;

Grammar.extend
  (let _ = (interf : 'interf Grammar.Entry.e)
   and _ = (implem : 'implem Grammar.Entry.e)
   and _ = (top_phrase : 'top_phrase Grammar.Entry.e)
   and _ = (use_file : 'use_file Grammar.Entry.e)
   and _ = (sig_item : 'sig_item Grammar.Entry.e)
   and _ = (str_item : 'str_item Grammar.Entry.e)
   and _ = (ctyp : 'ctyp Grammar.Entry.e)
   and _ = (patt : 'patt Grammar.Entry.e)
   and _ = (expr : 'expr Grammar.Entry.e)
   and _ = (module_type : 'module_type Grammar.Entry.e)
   and _ = (module_expr : 'module_expr Grammar.Entry.e)
   and _ = (let_binding : 'let_binding Grammar.Entry.e)
   and _ = (type_parameter : 'type_parameter Grammar.Entry.e)
   and _ = (fun_binding : 'fun_binding Grammar.Entry.e)
   and _ = (ipatt : 'ipatt Grammar.Entry.e)
   and _ = (direction_flag : 'direction_flag Grammar.Entry.e)
   and _ = (mod_ident : 'mod_ident Grammar.Entry.e) in
   let grammar_entry_create s =
     Grammar.Entry.create (Grammar.of_entry interf) s
   in
   let sig_item_semi : 'sig_item_semi Grammar.Entry.e =
     grammar_entry_create "sig_item_semi"
   and str_item_semi : 'str_item_semi Grammar.Entry.e =
     grammar_entry_create "str_item_semi"
   and phrase : 'phrase Grammar.Entry.e = grammar_entry_create "phrase"
   and rebind_exn : 'rebind_exn Grammar.Entry.e =
     grammar_entry_create "rebind_exn"
   and module_binding : 'module_binding Grammar.Entry.e =
     grammar_entry_create "module_binding"
   and module_declaration : 'module_declaration Grammar.Entry.e =
     grammar_entry_create "module_declaration"
   and with_constr : 'with_constr Grammar.Entry.e =
     grammar_entry_create "with_constr"
   and dummy : 'dummy Grammar.Entry.e = grammar_entry_create "dummy"
   and sequence : 'sequence Grammar.Entry.e = grammar_entry_create "sequence"
   and match_case : 'match_case Grammar.Entry.e =
     grammar_entry_create "match_case"
   and label_expr : 'label_expr Grammar.Entry.e =
     grammar_entry_create "label_expr"
   and expr_ident : 'expr_ident Grammar.Entry.e =
     grammar_entry_create "expr_ident"
   and fun_def : 'fun_def Grammar.Entry.e = grammar_entry_create "fun_def"
   and label_patt : 'label_patt Grammar.Entry.e =
     grammar_entry_create "label_patt"
   and patt_label_ident : 'patt_label_ident Grammar.Entry.e =
     grammar_entry_create "patt_label_ident"
   and label_ipatt : 'label_ipatt Grammar.Entry.e =
     grammar_entry_create "label_ipatt"
   and type_declaration : 'type_declaration Grammar.Entry.e =
     grammar_entry_create "type_declaration"
   and type_patt : 'type_patt Grammar.Entry.e =
     grammar_entry_create "type_patt"
   and constrain : 'constrain Grammar.Entry.e =
     grammar_entry_create "constrain"
   and constructor_declaration : 'constructor_declaration Grammar.Entry.e =
     grammar_entry_create "constructor_declaration"
   and label_declaration : 'label_declaration Grammar.Entry.e =
     grammar_entry_create "label_declaration"
   and ident : 'ident Grammar.Entry.e = grammar_entry_create "ident" in
   [Grammar.Entry.obj (interf : 'interf Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("EOI", "")],
      Gramext.action (fun _ (loc : int * int) -> ([], false : 'interf));
      [Gramext.Stoken ("", "#"); Gramext.Stoken ("LIDENT", "");
       Gramext.Sopt
         (Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e)));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (dp : 'expr option) (n : string) _ (loc : int * int) ->
           ([MLast.SgDir (loc, n, dp), loc], true : 'interf));
      [Gramext.Snterm
         (Grammar.Entry.obj (sig_item_semi : 'sig_item_semi Grammar.Entry.e));
       Gramext.Sself],
      Gramext.action
        (fun (sil, stopped : 'interf) (si : 'sig_item_semi)
           (loc : int * int) ->
           (si :: sil, stopped : 'interf))]];
    Grammar.Entry.obj (sig_item_semi : 'sig_item_semi Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm
         (Grammar.Entry.obj (sig_item : 'sig_item Grammar.Entry.e));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (si : 'sig_item) (loc : int * int) ->
           (si, loc : 'sig_item_semi))]];
    Grammar.Entry.obj (implem : 'implem Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("EOI", "")],
      Gramext.action (fun _ (loc : int * int) -> ([], false : 'implem));
      [Gramext.Stoken ("", "#"); Gramext.Stoken ("LIDENT", "");
       Gramext.Sopt
         (Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e)));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (dp : 'expr option) (n : string) _ (loc : int * int) ->
           ([MLast.StDir (loc, n, dp), loc], true : 'implem));
      [Gramext.Snterm
         (Grammar.Entry.obj (str_item_semi : 'str_item_semi Grammar.Entry.e));
       Gramext.Sself],
      Gramext.action
        (fun (sil, stopped : 'implem) (si : 'str_item_semi)
           (loc : int * int) ->
           (si :: sil, stopped : 'implem))]];
    Grammar.Entry.obj (str_item_semi : 'str_item_semi Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm
         (Grammar.Entry.obj (str_item : 'str_item Grammar.Entry.e));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (si : 'str_item) (loc : int * int) ->
           (si, loc : 'str_item_semi))]];
    Grammar.Entry.obj (top_phrase : 'top_phrase Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("EOI", "")],
      Gramext.action (fun _ (loc : int * int) -> (None : 'top_phrase));
      [Gramext.Snterm (Grammar.Entry.obj (phrase : 'phrase Grammar.Entry.e))],
      Gramext.action
        (fun (ph : 'phrase) (loc : int * int) -> (Some ph : 'top_phrase))]];
    Grammar.Entry.obj (use_file : 'use_file Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("EOI", "")],
      Gramext.action (fun _ (loc : int * int) -> ([], false : 'use_file));
      [Gramext.Stoken ("", "#"); Gramext.Stoken ("LIDENT", "");
       Gramext.Sopt
         (Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e)));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (dp : 'expr option) (n : string) _ (loc : int * int) ->
           ([MLast.StDir (loc, n, dp)], true : 'use_file));
      [Gramext.Snterm
         (Grammar.Entry.obj (str_item : 'str_item Grammar.Entry.e));
       Gramext.Stoken ("", ";"); Gramext.Sself],
      Gramext.action
        (fun (sil, stopped : 'use_file) _ (si : 'str_item)
           (loc : int * int) ->
           (si :: sil, stopped : 'use_file))]];
    Grammar.Entry.obj (phrase : 'phrase Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "#"); Gramext.Stoken ("LIDENT", "");
       Gramext.Sopt
         (Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e)));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (dp : 'expr option) (n : string) _ (loc : int * int) ->
           (MLast.StDir (loc, n, dp) : 'phrase));
      [Gramext.Snterm
         (Grammar.Entry.obj (str_item : 'str_item Grammar.Entry.e));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (sti : 'str_item) (loc : int * int) -> (sti : 'phrase))]];
    Grammar.Entry.obj (module_expr : 'module_expr Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "struct");
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj (str_item : 'str_item Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (s : 'str_item) (loc : int * int) -> (s : 'e__1))]);
       Gramext.Stoken ("", "end")],
      Gramext.action
        (fun _ (st : 'e__1 list) _ (loc : int * int) ->
           (MLast.MeStr (loc, st) : 'module_expr));
      [Gramext.Stoken ("", "functor"); Gramext.Stoken ("", "(");
       Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e));
       Gramext.Stoken ("", ")"); Gramext.Stoken ("", "->"); Gramext.Sself],
      Gramext.action
        (fun (me : 'module_expr) _ _ (t : 'module_type) _ (i : string) _ _
           (loc : int * int) ->
           (MLast.MeFun (loc, i, t, me) : 'module_expr))];
     None, None,
     [[Gramext.Sself; Gramext.Sself],
      Gramext.action
        (fun (me2 : 'module_expr) (me1 : 'module_expr) (loc : int * int) ->
           (MLast.MeApp (loc, me1, me2) : 'module_expr))];
     None, None,
     [[Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Sself],
      Gramext.action
        (fun (me2 : 'module_expr) _ (me1 : 'module_expr) (loc : int * int) ->
           (MLast.MeAcc (loc, me1, me2) : 'module_expr))];
     None, None,
     [[Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (me : 'module_expr) _ (loc : int * int) ->
           (me : 'module_expr));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (mt : 'module_type) _ (me : 'module_expr) _
           (loc : int * int) ->
           (MLast.MeTyc (loc, me, mt) : 'module_expr));
      [Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.MeUid (loc, i) : 'module_expr))]];
    Grammar.Entry.obj (str_item : 'str_item Grammar.Entry.e), None,
    [Some "top", None,
     [[Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) (loc : int * int) ->
           (MLast.StExp (loc, e) : 'str_item));
      [Gramext.Stoken ("", "value");
       Gramext.Sopt (Gramext.Stoken ("", "rec"));
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (let_binding : 'let_binding Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (l : 'let_binding list) (r : string option) _
           (loc : int * int) ->
           (MLast.StVal (loc, o2b r, l) : 'str_item));
      [Gramext.Stoken ("", "type");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (type_declaration : 'type_declaration Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (tdl : 'type_declaration list) _ (loc : int * int) ->
           (MLast.StTyp (loc, tdl) : 'str_item));
      [Gramext.Stoken ("", "open");
       Gramext.Snterm
         (Grammar.Entry.obj (mod_ident : 'mod_ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'mod_ident) _ (loc : int * int) ->
           (MLast.StOpn (loc, i) : 'str_item));
      [Gramext.Stoken ("", "module"); Gramext.Stoken ("", "type");
       Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e))],
      Gramext.action
        (fun (mt : 'module_type) _ (i : string) _ _ (loc : int * int) ->
           (MLast.StMty (loc, i, mt) : 'str_item));
      [Gramext.Stoken ("", "module"); Gramext.Stoken ("UIDENT", "");
       Gramext.Snterm
         (Grammar.Entry.obj
            (module_binding : 'module_binding Grammar.Entry.e))],
      Gramext.action
        (fun (mb : 'module_binding) (i : string) _ (loc : int * int) ->
           (MLast.StMod (loc, i, mb) : 'str_item));
      [Gramext.Stoken ("", "include");
       Gramext.Snterm
         (Grammar.Entry.obj (module_expr : 'module_expr Grammar.Entry.e))],
      Gramext.action
        (fun (me : 'module_expr) _ (loc : int * int) ->
           (MLast.StInc (loc, me) : 'str_item));
      [Gramext.Stoken ("", "external"); Gramext.Stoken ("LIDENT", "");
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Slist1 (Gramext.Stoken ("STRING", ""))],
      Gramext.action
        (fun (pd : string list) _ (t : 'ctyp) _ (i : string) _
           (loc : int * int) ->
           (MLast.StExt (loc, i, t, pd) : 'str_item));
      [Gramext.Stoken ("", "exception");
       Gramext.Snterm
         (Grammar.Entry.obj
            (constructor_declaration :
             'constructor_declaration Grammar.Entry.e));
       Gramext.Snterm
         (Grammar.Entry.obj (rebind_exn : 'rebind_exn Grammar.Entry.e))],
      Gramext.action
        (fun (b : 'rebind_exn) (_, c, tl : 'constructor_declaration) _
           (loc : int * int) ->
           (MLast.StExc (loc, c, tl, b) : 'str_item));
      [Gramext.Stoken ("", "declare");
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj (str_item : 'str_item Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (s : 'str_item) (loc : int * int) -> (s : 'e__2))]);
       Gramext.Stoken ("", "end")],
      Gramext.action
        (fun _ (st : 'e__2 list) _ (loc : int * int) ->
           (MLast.StDcl (loc, st) : 'str_item))]];
    Grammar.Entry.obj (rebind_exn : 'rebind_exn Grammar.Entry.e), None,
    [None, None,
     [[], Gramext.action (fun (loc : int * int) -> ([] : 'rebind_exn));
      [Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (mod_ident : 'mod_ident Grammar.Entry.e))],
      Gramext.action
        (fun (sl : 'mod_ident) _ (loc : int * int) -> (sl : 'rebind_exn))]];
    Grammar.Entry.obj (module_binding : 'module_binding Grammar.Entry.e),
    None,
    [None, Some Gramext.RightA,
     [[Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (module_expr : 'module_expr Grammar.Entry.e))],
      Gramext.action
        (fun (me : 'module_expr) _ (loc : int * int) ->
           (me : 'module_binding));
      [Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (module_expr : 'module_expr Grammar.Entry.e))],
      Gramext.action
        (fun (me : 'module_expr) _ (mt : 'module_type) _ (loc : int * int) ->
           (MLast.MeTyc (loc, me, mt) : 'module_binding));
      [Gramext.Stoken ("", "("); Gramext.Stoken ("UIDENT", "");
       Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e));
       Gramext.Stoken ("", ")"); Gramext.Sself],
      Gramext.action
        (fun (mb : 'module_binding) _ (mt : 'module_type) _ (m : string) _
           (loc : int * int) ->
           (MLast.MeFun (loc, m, mt, mb) : 'module_binding))]];
    Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "functor"); Gramext.Stoken ("", "(");
       Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", ":"); Gramext.Sself;
       Gramext.Stoken ("", ")"); Gramext.Stoken ("", "->"); Gramext.Sself],
      Gramext.action
        (fun (mt : 'module_type) _ _ (t : 'module_type) _ (i : string) _ _
           (loc : int * int) ->
           (MLast.MtFun (loc, i, t, mt) : 'module_type))];
     None, None,
     [[Gramext.Sself; Gramext.Stoken ("", "with");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (with_constr : 'with_constr Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (wcl : 'with_constr list) _ (mt : 'module_type)
           (loc : int * int) ->
           (MLast.MtWit (loc, mt, wcl) : 'module_type))];
     None, None,
     [[Gramext.Stoken ("", "sig");
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj (sig_item : 'sig_item Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (s : 'sig_item) (loc : int * int) -> (s : 'e__3))]);
       Gramext.Stoken ("", "end")],
      Gramext.action
        (fun _ (sg : 'e__3 list) _ (loc : int * int) ->
           (MLast.MtSig (loc, sg) : 'module_type))];
     None, None,
     [[Gramext.Sself; Gramext.Sself],
      Gramext.action
        (fun (m2 : 'module_type) (m1 : 'module_type) (loc : int * int) ->
           (MLast.MtApp (loc, m1, m2) : 'module_type))];
     None, None,
     [[Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Sself],
      Gramext.action
        (fun (m2 : 'module_type) _ (m1 : 'module_type) (loc : int * int) ->
           (MLast.MtAcc (loc, m1, m2) : 'module_type))];
     None, None,
     [[Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (mt : 'module_type) _ (loc : int * int) ->
           (mt : 'module_type));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.MtLid (loc, i) : 'module_type));
      [Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.MtUid (loc, i) : 'module_type))]];
    Grammar.Entry.obj (sig_item : 'sig_item Grammar.Entry.e), None,
    [Some "top", None,
     [[Gramext.Stoken ("", "value"); Gramext.Stoken ("LIDENT", "");
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (i : string) _ (loc : int * int) ->
           (MLast.SgVal (loc, i, t) : 'sig_item));
      [Gramext.Stoken ("", "type");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (type_declaration : 'type_declaration Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (tdl : 'type_declaration list) _ (loc : int * int) ->
           (MLast.SgTyp (loc, tdl) : 'sig_item));
      [Gramext.Stoken ("", "open");
       Gramext.Snterm
         (Grammar.Entry.obj (mod_ident : 'mod_ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'mod_ident) _ (loc : int * int) ->
           (MLast.SgOpn (loc, i) : 'sig_item));
      [Gramext.Stoken ("", "module"); Gramext.Stoken ("", "type");
       Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e))],
      Gramext.action
        (fun (mt : 'module_type) _ (i : string) _ _ (loc : int * int) ->
           (MLast.SgMty (loc, i, mt) : 'sig_item));
      [Gramext.Stoken ("", "module"); Gramext.Stoken ("UIDENT", "");
       Gramext.Snterm
         (Grammar.Entry.obj
            (module_declaration : 'module_declaration Grammar.Entry.e))],
      Gramext.action
        (fun (mt : 'module_declaration) (i : string) _ (loc : int * int) ->
           (MLast.SgMod (loc, i, mt) : 'sig_item));
      [Gramext.Stoken ("", "include");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e))],
      Gramext.action
        (fun (mt : 'module_type) _ (loc : int * int) ->
           (MLast.SgInc (loc, mt) : 'sig_item));
      [Gramext.Stoken ("", "external"); Gramext.Stoken ("LIDENT", "");
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Slist1 (Gramext.Stoken ("STRING", ""))],
      Gramext.action
        (fun (pd : string list) _ (t : 'ctyp) _ (i : string) _
           (loc : int * int) ->
           (MLast.SgExt (loc, i, t, pd) : 'sig_item));
      [Gramext.Stoken ("", "exception");
       Gramext.Snterm
         (Grammar.Entry.obj
            (constructor_declaration :
             'constructor_declaration Grammar.Entry.e))],
      Gramext.action
        (fun (_, c, tl : 'constructor_declaration) _ (loc : int * int) ->
           (MLast.SgExc (loc, c, tl) : 'sig_item));
      [Gramext.Stoken ("", "declare");
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj (sig_item : 'sig_item Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (s : 'sig_item) (loc : int * int) -> (s : 'e__4))]);
       Gramext.Stoken ("", "end")],
      Gramext.action
        (fun _ (st : 'e__4 list) _ (loc : int * int) ->
           (MLast.SgDcl (loc, st) : 'sig_item))]];
    Grammar.Entry.obj
      (module_declaration : 'module_declaration Grammar.Entry.e),
    None,
    [None, Some Gramext.RightA,
     [[Gramext.Stoken ("", "("); Gramext.Stoken ("UIDENT", "");
       Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e));
       Gramext.Stoken ("", ")"); Gramext.Sself],
      Gramext.action
        (fun (mt : 'module_declaration) _ (t : 'module_type) _ (i : string) _
           (loc : int * int) ->
           (MLast.MtFun (loc, i, t, mt) : 'module_declaration));
      [Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e))],
      Gramext.action
        (fun (mt : 'module_type) _ (loc : int * int) ->
           (mt : 'module_declaration))]];
    Grammar.Entry.obj (with_constr : 'with_constr Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "module");
       Gramext.Snterm
         (Grammar.Entry.obj (mod_ident : 'mod_ident Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (module_type : 'module_type Grammar.Entry.e))],
      Gramext.action
        (fun (mt : 'module_type) _ (i : 'mod_ident) _ (loc : int * int) ->
           (MLast.WcMod (loc, i, mt) : 'with_constr));
      [Gramext.Stoken ("", "type");
       Gramext.Snterm
         (Grammar.Entry.obj (mod_ident : 'mod_ident Grammar.Entry.e));
       Gramext.Slist0
         (Gramext.Snterm
            (Grammar.Entry.obj
               (type_parameter : 'type_parameter Grammar.Entry.e)));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (tpl : 'type_parameter list) (i : 'mod_ident) _
           (loc : int * int) ->
           (MLast.WcTyp (loc, i, tpl, t) : 'with_constr))]];
    Grammar.Entry.obj (expr : 'expr Grammar.Entry.e), None,
    [Some "top", Some Gramext.RightA,
     [[Gramext.Stoken ("", "while"); Gramext.Sself; Gramext.Stoken ("", "do");
       Gramext.Stoken ("", "{");
       Gramext.Snterm
         (Grammar.Entry.obj (sequence : 'sequence Grammar.Entry.e));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (el : 'sequence) _ _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExWhi (loc, e, el) : 'expr));
      [Gramext.Stoken ("", "for"); Gramext.Stoken ("LIDENT", "");
       Gramext.Stoken ("", "="); Gramext.Sself;
       Gramext.Snterm
         (Grammar.Entry.obj
            (direction_flag : 'direction_flag Grammar.Entry.e));
       Gramext.Sself; Gramext.Stoken ("", "do"); Gramext.Stoken ("", "{");
       Gramext.Snterm
         (Grammar.Entry.obj (sequence : 'sequence Grammar.Entry.e));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (el : 'sequence) _ _ (e2 : 'expr) (df : 'direction_flag)
           (e1 : 'expr) _ (i : string) _ (loc : int * int) ->
           (MLast.ExFor (loc, i, e1, e2, df, el) : 'expr));
      [Gramext.Stoken ("", "do"); Gramext.Stoken ("", "{");
       Gramext.Snterm
         (Grammar.Entry.obj (sequence : 'sequence Grammar.Entry.e));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (seq : 'sequence) _ _ (loc : int * int) ->
           (match seq with
              [e] -> e
            | _ -> MLast.ExSeq (loc, seq) :
            'expr));
      [Gramext.Stoken ("", "if"); Gramext.Sself; Gramext.Stoken ("", "then");
       Gramext.Sself; Gramext.Stoken ("", "else"); Gramext.Sself],
      Gramext.action
        (fun (e3 : 'expr) _ (e2 : 'expr) _ (e1 : 'expr) _ (loc : int * int) ->
           (MLast.ExIfe (loc, e1, e2, e3) : 'expr));
      [Gramext.Stoken ("", "try"); Gramext.Sself; Gramext.Stoken ("", "with");
       Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e));
       Gramext.Stoken ("", "->"); Gramext.Sself],
      Gramext.action
        (fun (e1 : 'expr) _ (p1 : 'ipatt) _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExTry (loc, e, [p1, None, e1]) : 'expr));
      [Gramext.Stoken ("", "try"); Gramext.Sself; Gramext.Stoken ("", "with");
       Gramext.Stoken ("", "[");
       Gramext.Slist0sep
         (Gramext.Snterm
            (Grammar.Entry.obj (match_case : 'match_case Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (l : 'match_case list) _ _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExTry (loc, e, l) : 'expr));
      [Gramext.Stoken ("", "match"); Gramext.Sself;
       Gramext.Stoken ("", "with");
       Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e));
       Gramext.Stoken ("", "->"); Gramext.Sself],
      Gramext.action
        (fun (e1 : 'expr) _ (p1 : 'ipatt) _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExMat (loc, e, [p1, None, e1]) : 'expr));
      [Gramext.Stoken ("", "match"); Gramext.Sself;
       Gramext.Stoken ("", "with"); Gramext.Stoken ("", "[");
       Gramext.Slist0sep
         (Gramext.Snterm
            (Grammar.Entry.obj (match_case : 'match_case Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (l : 'match_case list) _ _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExMat (loc, e, l) : 'expr));
      [Gramext.Stoken ("", "fun");
       Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e));
       Gramext.Snterm
         (Grammar.Entry.obj (fun_def : 'fun_def Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'fun_def) (p : 'ipatt) _ (loc : int * int) ->
           (MLast.ExFun (loc, [p, None, e]) : 'expr));
      [Gramext.Stoken ("", "fun"); Gramext.Stoken ("", "[");
       Gramext.Slist0sep
         (Gramext.Snterm
            (Grammar.Entry.obj (match_case : 'match_case Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (l : 'match_case list) _ _ (loc : int * int) ->
           (MLast.ExFun (loc, l) : 'expr));
      [Gramext.Stoken ("", "let"); Gramext.Stoken ("", "module");
       Gramext.Stoken ("UIDENT", "");
       Gramext.Snterm
         (Grammar.Entry.obj
            (module_binding : 'module_binding Grammar.Entry.e));
       Gramext.Stoken ("", "in"); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) _ (mb : 'module_binding) (m : string) _ _
           (loc : int * int) ->
           (MLast.ExLmd (loc, m, mb, e) : 'expr));
      [Gramext.Stoken ("", "let"); Gramext.Sopt (Gramext.Stoken ("", "rec"));
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (let_binding : 'let_binding Grammar.Entry.e)),
          Gramext.Stoken ("", "and"));
       Gramext.Stoken ("", "in"); Gramext.Sself],
      Gramext.action
        (fun (x : 'expr) _ (l : 'let_binding list) (o : string option) _
           (loc : int * int) ->
           (MLast.ExLet (loc, o2b o, l, x) : 'expr))];
     Some "where", None,
     [[Gramext.Sself; Gramext.Stoken ("", "where");
       Gramext.Sopt (Gramext.Stoken ("", "rec"));
       Gramext.Snterm
         (Grammar.Entry.obj (let_binding : 'let_binding Grammar.Entry.e))],
      Gramext.action
        (fun (lb : 'let_binding) (rf : string option) _ (e : 'expr)
           (loc : int * int) ->
           (MLast.ExLet (loc, o2b rf, [lb], e) : 'expr))];
     Some ":=", Some Gramext.NonA,
     [[Gramext.Sself; Gramext.Stoken ("", ":="); Gramext.Sself;
       Gramext.Snterm (Grammar.Entry.obj (dummy : 'dummy Grammar.Entry.e))],
      Gramext.action
        (fun _ (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExAss (loc, e1, e2) : 'expr))];
     Some "||", Some Gramext.RightA,
     [[Gramext.Sself; Gramext.Stoken ("", "||"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) (f : string) (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, f), e1), e2) :
            'expr))];
     Some "&&", Some Gramext.RightA,
     [[Gramext.Sself; Gramext.Stoken ("", "&&"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) (f : string) (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, f), e1), e2) :
            'expr))];
     Some "<", Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "!="); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "!="), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "=="); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "=="), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "<>"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "<>"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "="); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "="), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", ">="); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, ">="), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "<="); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "<="), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", ">"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, ">"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "<"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "<"), e1), e2) :
            'expr))];
     Some "^", Some Gramext.RightA,
     [[Gramext.Sself; Gramext.Stoken ("", "@"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "@"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "^"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "^"), e1), e2) :
            'expr))];
     Some "+", Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "-."); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "-."), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "+."); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "+."), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "-"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "-"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "+"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "+"), e1), e2) :
            'expr))];
     Some "*", Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "mod"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "mod"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "lxor"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "lxor"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "lor"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "lor"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "land"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "land"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "/."); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "/."), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "*."); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "*."), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "/"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "/"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "*"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "*"), e1), e2) :
            'expr))];
     Some "**", Some Gramext.RightA,
     [[Gramext.Sself; Gramext.Stoken ("", "lsr"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "lsr"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "lsl"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "lsl"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "asr"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "asr"), e1), e2) :
            'expr));
      [Gramext.Sself; Gramext.Stoken ("", "**"); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp
              (loc, MLast.ExApp (loc, MLast.ExLid (loc, "**"), e1), e2) :
            'expr))];
     Some "unary minus", Some Gramext.NonA,
     [[Gramext.Stoken ("", "-."); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) _ (loc : int * int) -> (mkumin loc "-." e : 'expr));
      [Gramext.Stoken ("", "-"); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) _ (loc : int * int) -> (mkumin loc "-" e : 'expr))];
     Some "apply", Some Gramext.LeftA,
     [[Gramext.Stoken ("", "lazy"); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) _ (loc : int * int) ->
           (MLast.ExApp
              (loc,
               MLast.ExAcc
                 (loc, MLast.ExUid (loc, "Pervasives"),
                  MLast.ExLid (loc, "ref")),
               MLast.ExApp
                 (loc,
                  MLast.ExAcc
                    (loc, MLast.ExUid (loc, "Lazy"),
                     MLast.ExUid (loc, "Delayed")),
                  MLast.ExFun (loc, [MLast.PaUid (loc, "()"), None, e]))) :
            'expr));
      [Gramext.Stoken ("", "assert"); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) _ (loc : int * int) ->
           (let f = MLast.ExStr (loc, !input_file) in
            let bp = MLast.ExInt (loc, string_of_int (fst loc)) in
            let ep = MLast.ExInt (loc, string_of_int (snd loc)) in
            let raiser =
              MLast.ExApp
                (loc, MLast.ExLid (loc, "raise"),
                 MLast.ExApp
                   (loc, MLast.ExUid (loc, "Assert_failure"),
                    MLast.ExTup (loc, [f; bp; ep])))
            in
            match e with
              MLast.ExUid (_, "False") -> raiser
            | _ ->
                if !no_assert then MLast.ExUid (loc, "()")
                else MLast.ExIfe (loc, e, MLast.ExUid (loc, "()"), raiser) :
            'expr));
      [Gramext.Sself; Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) (e1 : 'expr) (loc : int * int) ->
           (MLast.ExApp (loc, e1, e2) : 'expr))];
     Some ".", Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Sself],
      Gramext.action
        (fun (e2 : 'expr) _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExAcc (loc, e1, e2) : 'expr));
      [Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Stoken ("", "[");
       Gramext.Sself; Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (e2 : 'expr) _ _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExSte (loc, e1, e2) : 'expr));
      [Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (e2 : 'expr) _ _ (e1 : 'expr) (loc : int * int) ->
           (MLast.ExAre (loc, e1, e2) : 'expr))];
     Some "~-", Some Gramext.NonA,
     [[Gramext.srules
         [[Gramext.Stoken ("", "~-.")],
          Gramext.action (fun (x : string) (loc : int * int) -> (x : 'e__5));
          [Gramext.Stoken ("", "~-")],
          Gramext.action (fun (x : string) (loc : int * int) -> (x : 'e__5))];
       Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) (f : 'e__5) (loc : int * int) ->
           (MLast.ExApp (loc, MLast.ExLid (loc, f), e) : 'expr))];
     Some "simple", None,
     [[Gramext.Stoken ("QUOTATION", "")],
      Gramext.action
        (fun (x : string) (loc : int * int) ->
           (let x =
              try
                let i = String.index x ':' in
                String.sub x 0 i,
                String.sub x (i + 1) (String.length x - i - 1)
              with
                Not_found -> "", x
            in
            Pcaml.handle_expr_quotation loc x :
            'expr));
      [Gramext.Stoken ("LOCATE", "")],
      Gramext.action
        (fun (x : string) (loc : int * int) ->
           (let x =
              try
                let i = String.index x ':' in
                int_of_string (String.sub x 0 i),
                String.sub x (i + 1) (String.length x - i - 1)
              with
                Not_found | Failure _ -> 0, x
            in
            Pcaml.handle_expr_locate loc x :
            'expr));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action (fun _ (e : 'expr) _ (loc : int * int) -> (e : 'expr));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ",");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e)),
          Gramext.Stoken ("", ","));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (el : 'expr list) _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExTup (loc, (e :: el)) : 'expr));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExTyc (loc, e, t) : 'expr));
      [Gramext.Stoken ("", "("); Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ _ (loc : int * int) -> (MLast.ExUid (loc, "()") : 'expr));
      [Gramext.Stoken ("", "{"); Gramext.Stoken ("", "("); Gramext.Sself;
       Gramext.Stoken ("", ")"); Gramext.Stoken ("", "with");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (label_expr : 'label_expr Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (lel : 'label_expr list) _ _ (e : 'expr) _ _
           (loc : int * int) ->
           (MLast.ExRec (loc, lel, Some e) : 'expr));
      [Gramext.Stoken ("", "{");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (label_expr : 'label_expr Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (lel : 'label_expr list) _ (loc : int * int) ->
           (MLast.ExRec (loc, lel, None) : 'expr));
      [Gramext.Stoken ("", "[|");
       Gramext.Slist0sep
         (Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Stoken ("", "|]")],
      Gramext.action
        (fun _ (el : 'expr list) _ (loc : int * int) ->
           (MLast.ExArr (loc, el) : 'expr));
      [Gramext.Stoken ("", "[");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Sopt
         (Gramext.srules
            [[Gramext.Stoken ("", "::");
              Gramext.Snterm
                (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
             Gramext.action
               (fun (e : 'expr) _ (loc : int * int) -> (e : 'e__6))]);
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (last : 'e__6 option) (el : 'expr list) _ (loc : int * int) ->
           (mklistexp loc last el : 'expr));
      [Gramext.Stoken ("", "["); Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ _ (loc : int * int) -> (MLast.ExUid (loc, "[]") : 'expr));
      [Gramext.Snterm
         (Grammar.Entry.obj (expr_ident : 'expr_ident Grammar.Entry.e))],
      Gramext.action (fun (i : 'expr_ident) (loc : int * int) -> (i : 'expr));
      [Gramext.Stoken ("CHAR", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.ExChr (loc, s) : 'expr));
      [Gramext.Stoken ("STRING", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.ExStr (loc, s) : 'expr));
      [Gramext.Stoken ("FLOAT", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.ExFlo (loc, s) : 'expr));
      [Gramext.Stoken ("INT", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.ExInt (loc, s) : 'expr))]];
    Grammar.Entry.obj (dummy : 'dummy Grammar.Entry.e), None,
    [None, None,
     [[], Gramext.action (fun (loc : int * int) -> (() : 'dummy))]];
    Grammar.Entry.obj (sequence : 'sequence Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action (fun (e : 'expr) (loc : int * int) -> ([e] : 'sequence));
      [Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (e : 'expr) (loc : int * int) -> ([e] : 'sequence));
      [Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ";"); Gramext.Sself],
      Gramext.action
        (fun (el : 'sequence) _ (e : 'expr) (loc : int * int) ->
           (e :: el : 'sequence));
      [Gramext.Stoken ("", "let"); Gramext.Sopt (Gramext.Stoken ("", "rec"));
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (let_binding : 'let_binding Grammar.Entry.e)),
          Gramext.Stoken ("", "and"));
       Gramext.Stoken ("", "in"); Gramext.Sself],
      Gramext.action
        (fun (el : 'sequence) _ (l : 'let_binding list) (o : string option) _
           (loc : int * int) ->
           (let e =
              match el with
                [e] -> e
              | _ -> MLast.ExSeq (loc, el)
            in
            [MLast.ExLet (loc, o2b o, l, e)] :
            'sequence))]];
    Grammar.Entry.obj (let_binding : 'let_binding Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e));
       Gramext.Snterm
         (Grammar.Entry.obj (fun_binding : 'fun_binding Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'fun_binding) (p : 'ipatt) (loc : int * int) ->
           (p, e : 'let_binding))]];
    Grammar.Entry.obj (fun_binding : 'fun_binding Grammar.Entry.e), None,
    [None, Some Gramext.RightA,
     [[Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (t : 'ctyp) _ (loc : int * int) ->
           (MLast.ExTyc (loc, e, t) : 'fun_binding));
      [Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (loc : int * int) -> (e : 'fun_binding));
      [Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e));
       Gramext.Sself],
      Gramext.action
        (fun (e : 'fun_binding) (p : 'ipatt) (loc : int * int) ->
           (MLast.ExFun (loc, [p, None, e]) : 'fun_binding))]];
    Grammar.Entry.obj (match_case : 'match_case Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e));
       Gramext.Sopt
         (Gramext.srules
            [[Gramext.Stoken ("", "as");
              Gramext.Snterm
                (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e))],
             Gramext.action
               (fun (p : 'patt) _ (loc : int * int) -> (p : 'e__7))]);
       Gramext.Sopt
         (Gramext.srules
            [[Gramext.Stoken ("", "when");
              Gramext.Snterm
                (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
             Gramext.action
               (fun (e : 'expr) _ (loc : int * int) -> (e : 'e__8))]);
       Gramext.Stoken ("", "->");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (w : 'e__8 option) (aso : 'e__7 option) (p : 'patt)
           (loc : int * int) ->
           (let p =
              match aso with
                Some p2 -> MLast.PaAli (loc, p, p2)
              | _ -> p
            in
            p, w, e :
            'match_case))]];
    Grammar.Entry.obj (label_expr : 'label_expr Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm
         (Grammar.Entry.obj
            (patt_label_ident : 'patt_label_ident Grammar.Entry.e));
       Gramext.Snterm
         (Grammar.Entry.obj (fun_binding : 'fun_binding Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'fun_binding) (i : 'patt_label_ident) (loc : int * int) ->
           (i, e : 'label_expr))]];
    Grammar.Entry.obj (expr_ident : 'expr_ident Grammar.Entry.e), None,
    [None, Some Gramext.RightA,
     [[Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", ".");
       Gramext.Sself],
      Gramext.action
        (fun (j : 'expr_ident) _ (i : string) (loc : int * int) ->
           (let rec loop m =
              function
                MLast.ExAcc (_, x, y) -> loop (MLast.ExAcc (loc, m, x)) y
              | e -> MLast.ExAcc (loc, m, e)
            in
            loop (MLast.ExUid (loc, i)) j :
            'expr_ident));
      [Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.ExUid (loc, i) : 'expr_ident));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.ExLid (loc, i) : 'expr_ident))]];
    Grammar.Entry.obj (fun_def : 'fun_def Grammar.Entry.e), None,
    [None, Some Gramext.RightA,
     [[Gramext.Stoken ("", "->");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action (fun (e : 'expr) _ (loc : int * int) -> (e : 'fun_def));
      [Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e));
       Gramext.Sself],
      Gramext.action
        (fun (e : 'fun_def) (p : 'ipatt) (loc : int * int) ->
           (MLast.ExFun (loc, [p, None, e]) : 'fun_def))]];
    Grammar.Entry.obj (patt : 'patt Grammar.Entry.e), None,
    [None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "|"); Gramext.Sself],
      Gramext.action
        (fun (p2 : 'patt) _ (p1 : 'patt) (loc : int * int) ->
           (MLast.PaOrp (loc, p1, p2) : 'patt))];
     None, Some Gramext.NonA,
     [[Gramext.Sself; Gramext.Stoken ("", ".."); Gramext.Sself],
      Gramext.action
        (fun (p2 : 'patt) _ (p1 : 'patt) (loc : int * int) ->
           (MLast.PaRng (loc, p1, p2) : 'patt))];
     None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Sself],
      Gramext.action
        (fun (p2 : 'patt) (p1 : 'patt) (loc : int * int) ->
           (MLast.PaApp (loc, p1, p2) : 'patt))];
     None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Sself],
      Gramext.action
        (fun (p2 : 'patt) _ (p1 : 'patt) (loc : int * int) ->
           (MLast.PaAcc (loc, p1, p2) : 'patt))];
     Some "simple", None,
     [[Gramext.Stoken ("QUOTATION", "")],
      Gramext.action
        (fun (x : string) (loc : int * int) ->
           (let x =
              try
                let i = String.index x ':' in
                String.sub x 0 i,
                String.sub x (i + 1) (String.length x - i - 1)
              with
                Not_found -> "", x
            in
            Pcaml.handle_patt_quotation loc x :
            'patt));
      [Gramext.Stoken ("LOCATE", "")],
      Gramext.action
        (fun (x : string) (loc : int * int) ->
           (let x =
              try
                let i = String.index x ':' in
                int_of_string (String.sub x 0 i),
                String.sub x (i + 1) (String.length x - i - 1)
              with
                Not_found | Failure _ -> 0, x
            in
            Pcaml.handle_patt_locate loc x :
            'patt));
      [Gramext.Stoken ("", "_")],
      Gramext.action (fun _ (loc : int * int) -> (MLast.PaAny loc : 'patt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ",");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e)),
          Gramext.Stoken ("", ","));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (pl : 'patt list) _ (p : 'patt) _ (loc : int * int) ->
           (MLast.PaTup (loc, (p :: pl)) : 'patt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", "as");
       Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (p2 : 'patt) _ (p : 'patt) _ (loc : int * int) ->
           (MLast.PaAli (loc, p, p2) : 'patt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (p : 'patt) _ (loc : int * int) ->
           (MLast.PaTyc (loc, p, t) : 'patt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action (fun _ (p : 'patt) _ (loc : int * int) -> (p : 'patt));
      [Gramext.Stoken ("", "("); Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ _ (loc : int * int) -> (MLast.PaUid (loc, "()") : 'patt));
      [Gramext.Stoken ("", "{");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (label_patt : 'label_patt Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (lpl : 'label_patt list) _ (loc : int * int) ->
           (MLast.PaRec (loc, lpl) : 'patt));
      [Gramext.Stoken ("", "[|");
       Gramext.Slist0sep
         (Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Stoken ("", "|]")],
      Gramext.action
        (fun _ (pl : 'patt list) _ (loc : int * int) ->
           (MLast.PaArr (loc, pl) : 'patt));
      [Gramext.Stoken ("", "[");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Sopt
         (Gramext.srules
            [[Gramext.Stoken ("", "::");
              Gramext.Snterm
                (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e))],
             Gramext.action
               (fun (p : 'patt) _ (loc : int * int) -> (p : 'e__9))]);
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (last : 'e__9 option) (pl : 'patt list) _ (loc : int * int) ->
           (mklistpat loc last pl : 'patt));
      [Gramext.Stoken ("", "["); Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ _ (loc : int * int) -> (MLast.PaUid (loc, "[]") : 'patt));
      [Gramext.Stoken ("CHAR", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.PaChr (loc, s) : 'patt));
      [Gramext.Stoken ("STRING", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.PaStr (loc, s) : 'patt));
      [Gramext.Stoken ("FLOAT", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.PaFlo (loc, s) : 'patt));
      [Gramext.Stoken ("", "-"); Gramext.Stoken ("FLOAT", "")],
      Gramext.action
        (fun (s : string) _ (loc : int * int) ->
           (MLast.PaFlo (loc, ("-" ^ s)) : 'patt));
      [Gramext.Stoken ("", "-"); Gramext.Stoken ("INT", "")],
      Gramext.action
        (fun (s : string) _ (loc : int * int) ->
           (MLast.PaInt (loc, ("-" ^ s)) : 'patt));
      [Gramext.Stoken ("INT", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.PaInt (loc, s) : 'patt));
      [Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.PaUid (loc, s) : 'patt));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.PaLid (loc, s) : 'patt))]];
    Grammar.Entry.obj (label_patt : 'label_patt Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm
         (Grammar.Entry.obj
            (patt_label_ident : 'patt_label_ident Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e))],
      Gramext.action
        (fun (p : 'patt) _ (i : 'patt_label_ident) (loc : int * int) ->
           (i, p : 'label_patt))]];
    Grammar.Entry.obj (patt_label_ident : 'patt_label_ident Grammar.Entry.e),
    None,
    [None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Sself],
      Gramext.action
        (fun (p2 : 'patt_label_ident) _ (p1 : 'patt_label_ident)
           (loc : int * int) ->
           (MLast.PaAcc (loc, p1, p2) : 'patt_label_ident))];
     None, Some Gramext.RightA,
     [[Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.PaLid (loc, i) : 'patt_label_ident));
      [Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.PaUid (loc, i) : 'patt_label_ident))]];
    Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "_")],
      Gramext.action (fun _ (loc : int * int) -> (MLast.PaAny loc : 'ipatt));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (s : string) (loc : int * int) ->
           (MLast.PaLid (loc, s) : 'ipatt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ",");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e)),
          Gramext.Stoken ("", ","));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (pl : 'ipatt list) _ (p : 'ipatt) _ (loc : int * int) ->
           (MLast.PaTup (loc, (p :: pl)) : 'ipatt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", "as");
       Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (p2 : 'ipatt) _ (p : 'ipatt) _ (loc : int * int) ->
           (MLast.PaAli (loc, p, p2) : 'ipatt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (p : 'ipatt) _ (loc : int * int) ->
           (MLast.PaTyc (loc, p, t) : 'ipatt));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action (fun _ (p : 'ipatt) _ (loc : int * int) -> (p : 'ipatt));
      [Gramext.Stoken ("", "("); Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ _ (loc : int * int) -> (MLast.PaUid (loc, "()") : 'ipatt));
      [Gramext.Stoken ("", "{");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (label_ipatt : 'label_ipatt Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (lpl : 'label_ipatt list) _ (loc : int * int) ->
           (MLast.PaRec (loc, lpl) : 'ipatt))]];
    Grammar.Entry.obj (label_ipatt : 'label_ipatt Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm
         (Grammar.Entry.obj
            (patt_label_ident : 'patt_label_ident Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e))],
      Gramext.action
        (fun (p : 'ipatt) _ (i : 'patt_label_ident) (loc : int * int) ->
           (i, p : 'label_ipatt))]];
    Grammar.Entry.obj (type_declaration : 'type_declaration Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Snterm
         (Grammar.Entry.obj (type_patt : 'type_patt Grammar.Entry.e));
       Gramext.Slist0
         (Gramext.Snterm
            (Grammar.Entry.obj
               (type_parameter : 'type_parameter Grammar.Entry.e)));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Slist0
         (Gramext.Snterm
            (Grammar.Entry.obj (constrain : 'constrain Grammar.Entry.e)))],
      Gramext.action
        (fun (cl : 'constrain list) (tk : 'ctyp) _
           (tpl : 'type_parameter list) (n : 'type_patt) (loc : int * int) ->
           (n, tpl, tk, cl : 'type_declaration))]];
    Grammar.Entry.obj (type_patt : 'type_patt Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (n : string) (loc : int * int) -> (loc, n : 'type_patt))]];
    Grammar.Entry.obj (constrain : 'constrain Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "constraint");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t2 : 'ctyp) _ (t1 : 'ctyp) _ (loc : int * int) ->
           (t1, t2 : 'constrain))]];
    Grammar.Entry.obj (type_parameter : 'type_parameter Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("", "-"); Gramext.Stoken ("", "'");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'ident) _ _ (loc : int * int) ->
           (i, (false, true) : 'type_parameter));
      [Gramext.Stoken ("", "+"); Gramext.Stoken ("", "'");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'ident) _ _ (loc : int * int) ->
           (i, (true, false) : 'type_parameter));
      [Gramext.Stoken ("", "'");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'ident) _ (loc : int * int) ->
           (i, (false, false) : 'type_parameter))]];
    Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e), None,
    [None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "=="); Gramext.Sself],
      Gramext.action
        (fun (t2 : 'ctyp) _ (t1 : 'ctyp) (loc : int * int) ->
           (MLast.TyMan (loc, t1, t2) : 'ctyp))];
     None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "as"); Gramext.Sself],
      Gramext.action
        (fun (t2 : 'ctyp) _ (t1 : 'ctyp) (loc : int * int) ->
           (MLast.TyAli (loc, t1, t2) : 'ctyp))];
     Some "arrow", Some Gramext.RightA,
     [[Gramext.Sself; Gramext.Stoken ("", "->"); Gramext.Sself],
      Gramext.action
        (fun (t2 : 'ctyp) _ (t1 : 'ctyp) (loc : int * int) ->
           (MLast.TyArr (loc, t1, t2) : 'ctyp))];
     None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Sself],
      Gramext.action
        (fun (t2 : 'ctyp) (t1 : 'ctyp) (loc : int * int) ->
           (MLast.TyApp (loc, t1, t2) : 'ctyp))];
     None, Some Gramext.LeftA,
     [[Gramext.Sself; Gramext.Stoken ("", "."); Gramext.Sself],
      Gramext.action
        (fun (t2 : 'ctyp) _ (t1 : 'ctyp) (loc : int * int) ->
           (MLast.TyAcc (loc, t1, t2) : 'ctyp))];
     Some "simple", None,
     [[Gramext.Stoken ("", "{");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (label_declaration : 'label_declaration Grammar.Entry.e)),
          Gramext.Stoken ("", ";"));
       Gramext.Stoken ("", "}")],
      Gramext.action
        (fun _ (ldl : 'label_declaration list) _ (loc : int * int) ->
           (MLast.TyRec (loc, ldl) : 'ctyp));
      [Gramext.Stoken ("", "[");
       Gramext.Slist0sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (constructor_declaration :
                'constructor_declaration Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (cdl : 'constructor_declaration list) _ (loc : int * int) ->
           (MLast.TySum (loc, cdl) : 'ctyp));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action (fun _ (t : 'ctyp) _ (loc : int * int) -> (t : 'ctyp));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", "*");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e)),
          Gramext.Stoken ("", "*"));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (tl : 'ctyp list) _ (t : 'ctyp) _ (loc : int * int) ->
           (MLast.TyTup (loc, (t :: tl)) : 'ctyp));
      [Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.TyUid (loc, i) : 'ctyp));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.TyLid (loc, i) : 'ctyp));
      [Gramext.Stoken ("", "_")],
      Gramext.action (fun _ (loc : int * int) -> (MLast.TyAny loc : 'ctyp));
      [Gramext.Stoken ("", "'");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'ident) _ (loc : int * int) ->
           (MLast.TyQuo (loc, i) : 'ctyp))]];
    Grammar.Entry.obj
      (constructor_declaration : 'constructor_declaration Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (ci : string) (loc : int * int) ->
           (loc, ci, [] : 'constructor_declaration));
      [Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", "of");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (cal : 'ctyp list) _ (ci : string) (loc : int * int) ->
           (loc, ci, cal : 'constructor_declaration))]];
    Grammar.Entry.obj
      (label_declaration : 'label_declaration Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("LIDENT", ""); Gramext.Stoken ("", ":");
       Gramext.Sopt (Gramext.Stoken ("", "mutable"));
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) (mf : string option) _ (i : string)
           (loc : int * int) ->
           (loc, i, o2b mf, t : 'label_declaration))]];
    Grammar.Entry.obj (ident : 'ident Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("UIDENT", "")],
      Gramext.action (fun (i : string) (loc : int * int) -> (i : 'ident));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action (fun (i : string) (loc : int * int) -> (i : 'ident))]];
    Grammar.Entry.obj (mod_ident : 'mod_ident Grammar.Entry.e), None,
    [None, Some Gramext.RightA,
     [[Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", ".");
       Gramext.Sself],
      Gramext.action
        (fun (j : 'mod_ident) _ (i : string) (loc : int * int) ->
           (i :: j : 'mod_ident));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) -> ([i] : 'mod_ident));
      [Gramext.Stoken ("UIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) -> ([i] : 'mod_ident))]];
    Grammar.Entry.obj (direction_flag : 'direction_flag Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("", "downto")],
      Gramext.action (fun _ (loc : int * int) -> (false : 'direction_flag));
      [Gramext.Stoken ("", "to")],
      Gramext.action
        (fun _ (loc : int * int) -> (true : 'direction_flag))]]]);;

(* Objects and Classes *)

Grammar.extend
  (let _ = (str_item : 'str_item Grammar.Entry.e)
   and _ = (sig_item : 'sig_item Grammar.Entry.e)
   and _ = (expr : 'expr Grammar.Entry.e)
   and _ = (ctyp : 'ctyp Grammar.Entry.e)
   and _ = (class_sig_item : 'class_sig_item Grammar.Entry.e)
   and _ = (class_str_item : 'class_str_item Grammar.Entry.e)
   and _ = (class_type : 'class_type Grammar.Entry.e)
   and _ = (class_expr : 'class_expr Grammar.Entry.e) in
   let grammar_entry_create s =
     Grammar.Entry.create (Grammar.of_entry str_item) s
   in
   let class_declaration : 'class_declaration Grammar.Entry.e =
     grammar_entry_create "class_declaration"
   and class_fun_binding : 'class_fun_binding Grammar.Entry.e =
     grammar_entry_create "class_fun_binding"
   and class_type_parameters : 'class_type_parameters Grammar.Entry.e =
     grammar_entry_create "class_type_parameters"
   and class_fun_def : 'class_fun_def Grammar.Entry.e =
     grammar_entry_create "class_fun_def"
   and class_structure : 'class_structure Grammar.Entry.e =
     grammar_entry_create "class_structure"
   and class_self_patt : 'class_self_patt Grammar.Entry.e =
     grammar_entry_create "class_self_patt"
   and cvalue : 'cvalue Grammar.Entry.e = grammar_entry_create "cvalue"
   and label : 'label Grammar.Entry.e = grammar_entry_create "label"
   and class_self_type : 'class_self_type Grammar.Entry.e =
     grammar_entry_create "class_self_type"
   and class_description : 'class_description Grammar.Entry.e =
     grammar_entry_create "class_description"
   and class_type_declaration : 'class_type_declaration Grammar.Entry.e =
     grammar_entry_create "class_type_declaration"
   and field_expr_list : 'field_expr_list Grammar.Entry.e =
     grammar_entry_create "field_expr_list"
   and meth_list : 'meth_list Grammar.Entry.e =
     grammar_entry_create "meth_list"
   and field : 'field Grammar.Entry.e = grammar_entry_create "field"
   and clty_longident : 'clty_longident Grammar.Entry.e =
     grammar_entry_create "clty_longident"
   and class_longident : 'class_longident Grammar.Entry.e =
     grammar_entry_create "class_longident"
   in
   [Grammar.Entry.obj (str_item : 'str_item Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "class"); Gramext.Stoken ("", "type");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (class_type_declaration :
                'class_type_declaration Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (ctd : 'class_type_declaration list) _ _ (loc : int * int) ->
           (MLast.StClt (loc, ctd) : 'str_item));
      [Gramext.Stoken ("", "class");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (class_declaration : 'class_declaration Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (cd : 'class_declaration list) _ (loc : int * int) ->
           (MLast.StCls (loc, cd) : 'str_item))]];
    Grammar.Entry.obj (sig_item : 'sig_item Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "class"); Gramext.Stoken ("", "type");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (class_type_declaration :
                'class_type_declaration Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (ctd : 'class_type_declaration list) _ _ (loc : int * int) ->
           (MLast.SgClt (loc, ctd) : 'sig_item));
      [Gramext.Stoken ("", "class");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (class_description : 'class_description Grammar.Entry.e)),
          Gramext.Stoken ("", "and"))],
      Gramext.action
        (fun (cd : 'class_description list) _ (loc : int * int) ->
           (MLast.SgCls (loc, cd) : 'sig_item))]];
    Grammar.Entry.obj
      (class_declaration : 'class_declaration Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Sopt (Gramext.Stoken ("", "virtual"));
       Gramext.Stoken ("LIDENT", "");
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_type_parameters : 'class_type_parameters Grammar.Entry.e));
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_fun_binding : 'class_fun_binding Grammar.Entry.e))],
      Gramext.action
        (fun (cfb : 'class_fun_binding) (ctp : 'class_type_parameters)
           (i : string) (vf : string option) (loc : int * int) ->
           ({MLast.ciLoc = loc; MLast.ciVir = o2b vf; MLast.ciPrm = ctp;
             MLast.ciNam = i; MLast.ciExp = cfb} :
            'class_declaration))]];
    Grammar.Entry.obj
      (class_fun_binding : 'class_fun_binding Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Snterm (Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e));
       Gramext.Sself],
      Gramext.action
        (fun (cfb : 'class_fun_binding) (p : 'ipatt) (loc : int * int) ->
           (MLast.CeFun (loc, p, cfb) : 'class_fun_binding));
      [Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (class_type : 'class_type Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (class_expr : 'class_expr Grammar.Entry.e))],
      Gramext.action
        (fun (ce : 'class_expr) _ (ct : 'class_type) _ (loc : int * int) ->
           (MLast.CeTyc (loc, ce, ct) : 'class_fun_binding));
      [Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (class_expr : 'class_expr Grammar.Entry.e))],
      Gramext.action
        (fun (ce : 'class_expr) _ (loc : int * int) ->
           (ce : 'class_fun_binding))]];
    Grammar.Entry.obj
      (class_type_parameters : 'class_type_parameters Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("", "[");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj
               (type_parameter : 'type_parameter Grammar.Entry.e)),
          Gramext.Stoken ("", ","));
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (tpl : 'type_parameter list) _ (loc : int * int) ->
           (loc, tpl : 'class_type_parameters));
      [],
      Gramext.action
        (fun (loc : int * int) -> (loc, [] : 'class_type_parameters))]];
    Grammar.Entry.obj (class_fun_def : 'class_fun_def Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterml
         (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e), "simple");
       Gramext.Sself],
      Gramext.action
        (fun (cfd : 'class_fun_def) (p : 'patt) (loc : int * int) ->
           (MLast.CeFun (loc, p, cfd) : 'class_fun_def));
      [Gramext.Snterml
         (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e), "simple");
       Gramext.Stoken ("", "->");
       Gramext.Snterm
         (Grammar.Entry.obj (class_expr : 'class_expr Grammar.Entry.e))],
      Gramext.action
        (fun (ce : 'class_expr) _ (p : 'patt) (loc : int * int) ->
           (MLast.CeFun (loc, p, ce) : 'class_fun_def))]];
    Grammar.Entry.obj (class_expr : 'class_expr Grammar.Entry.e), None,
    [Some "top", None,
     [[Gramext.Stoken ("", "let"); Gramext.Sopt (Gramext.Stoken ("", "rec"));
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (let_binding : 'let_binding Grammar.Entry.e)),
          Gramext.Stoken ("", "and"));
       Gramext.Stoken ("", "in"); Gramext.Sself],
      Gramext.action
        (fun (ce : 'class_expr) _ (lb : 'let_binding list)
           (rf : string option) _ (loc : int * int) ->
           (MLast.CeLet (loc, o2b rf, lb, ce) : 'class_expr));
      [Gramext.Stoken ("", "fun");
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_fun_def : 'class_fun_def Grammar.Entry.e))],
      Gramext.action
        (fun (cfd : 'class_fun_def) _ (loc : int * int) ->
           (cfd : 'class_expr))];
     Some "apply", Some Gramext.NonA,
     [[Gramext.Sself;
       Gramext.Snterml
         (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e), "simple")],
      Gramext.action
        (fun (e : 'expr) (ce : 'class_expr) (loc : int * int) ->
           (MLast.CeApp (loc, ce, e) : 'class_expr))];
     Some "simple", None,
     [[Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (ce : 'class_expr) _ (loc : int * int) -> (ce : 'class_expr));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (class_type : 'class_type Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (ct : 'class_type) _ (ce : 'class_expr) _ (loc : int * int) ->
           (MLast.CeTyc (loc, ce, ct) : 'class_expr));
      [Gramext.Stoken ("", "object");
       Gramext.Sopt
         (Gramext.Snterm
            (Grammar.Entry.obj
               (class_self_patt : 'class_self_patt Grammar.Entry.e)));
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_structure : 'class_structure Grammar.Entry.e));
       Gramext.Stoken ("", "end")],
      Gramext.action
        (fun _ (cf : 'class_structure) (cspo : 'class_self_patt option) _
           (loc : int * int) ->
           (MLast.CeStr (loc, cspo, cf) : 'class_expr));
      [Gramext.Snterm
         (Grammar.Entry.obj
            (class_longident : 'class_longident Grammar.Entry.e))],
      Gramext.action
        (fun (ci : 'class_longident) (loc : int * int) ->
           (MLast.CeCon (loc, ci, []) : 'class_expr));
      [Gramext.Snterm
         (Grammar.Entry.obj
            (class_longident : 'class_longident Grammar.Entry.e));
       Gramext.Stoken ("", "[");
       Gramext.Slist0sep
         (Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e)),
          Gramext.Stoken ("", ","));
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (ctcl : 'ctyp list) _ (ci : 'class_longident)
           (loc : int * int) ->
           (MLast.CeCon (loc, ci, ctcl) : 'class_expr))]];
    Grammar.Entry.obj (class_structure : 'class_structure Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj
                   (class_str_item : 'class_str_item Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (cf : 'class_str_item) (loc : int * int) ->
                  (cf : 'e__10))])],
      Gramext.action
        (fun (cf : 'e__10 list) (loc : int * int) ->
           (cf : 'class_structure))]];
    Grammar.Entry.obj (class_self_patt : 'class_self_patt Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("", "(");
       Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (p : 'patt) _ (loc : int * int) ->
           (MLast.PaTyc (loc, p, t) : 'class_self_patt));
      [Gramext.Stoken ("", "(");
       Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (p : 'patt) _ (loc : int * int) -> (p : 'class_self_patt))]];
    Grammar.Entry.obj (class_str_item : 'class_str_item Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("", "initializer");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (se : 'expr) _ (loc : int * int) ->
           (MLast.CrIni (loc, se) : 'class_str_item));
      [Gramext.Stoken ("", "type");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t2 : 'ctyp) _ (t1 : 'ctyp) _ (loc : int * int) ->
           (MLast.CrCtr (loc, t1, t2) : 'class_str_item));
      [Gramext.Stoken ("", "method");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Snterm
         (Grammar.Entry.obj (fun_binding : 'fun_binding Grammar.Entry.e))],
      Gramext.action
        (fun (fb : 'fun_binding) (l : 'label) _ (loc : int * int) ->
           (MLast.CrMth (loc, l, false, fb) : 'class_str_item));
      [Gramext.Stoken ("", "method"); Gramext.Stoken ("", "private");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Snterm
         (Grammar.Entry.obj (fun_binding : 'fun_binding Grammar.Entry.e))],
      Gramext.action
        (fun (fb : 'fun_binding) (l : 'label) _ _ (loc : int * int) ->
           (MLast.CrMth (loc, l, true, fb) : 'class_str_item));
      [Gramext.Stoken ("", "method"); Gramext.Stoken ("", "virtual");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (l : 'label) _ _ (loc : int * int) ->
           (MLast.CrVir (loc, l, false, t) : 'class_str_item));
      [Gramext.Stoken ("", "method"); Gramext.Stoken ("", "virtual");
       Gramext.Stoken ("", "private");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (l : 'label) _ _ _ (loc : int * int) ->
           (MLast.CrVir (loc, l, true, t) : 'class_str_item));
      [Gramext.Stoken ("", "value");
       Gramext.Snterm (Grammar.Entry.obj (cvalue : 'cvalue Grammar.Entry.e))],
      Gramext.action
        (fun (lab, mf, e : 'cvalue) _ (loc : int * int) ->
           (MLast.CrVal (loc, lab, mf, e) : 'class_str_item));
      [Gramext.Stoken ("", "inherit");
       Gramext.Snterm
         (Grammar.Entry.obj (class_expr : 'class_expr Grammar.Entry.e));
       Gramext.Sopt
         (Gramext.srules
            [[Gramext.Stoken ("", "as"); Gramext.Stoken ("LIDENT", "")],
             Gramext.action
               (fun (i : string) _ (loc : int * int) -> (i : 'e__11))])],
      Gramext.action
        (fun (pb : 'e__11 option) (ce : 'class_expr) _ (loc : int * int) ->
           (MLast.CrInh (loc, ce, pb) : 'class_str_item))]];
    Grammar.Entry.obj (cvalue : 'cvalue Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Sopt (Gramext.Stoken ("", "mutable"));
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":>");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (t : 'ctyp) _ (l : 'label) (mf : string option)
           (loc : int * int) ->
           (l, o2b mf, MLast.ExCoe (loc, e, None, t) : 'cvalue));
      [Gramext.Sopt (Gramext.Stoken ("", "mutable"));
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ":>");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (t2 : 'ctyp) _ (t : 'ctyp) _ (l : 'label)
           (mf : string option) (loc : int * int) ->
           (l, o2b mf, MLast.ExCoe (loc, e, Some t, t2) : 'cvalue));
      [Gramext.Sopt (Gramext.Stoken ("", "mutable"));
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (t : 'ctyp) _ (l : 'label) (mf : string option)
           (loc : int * int) ->
           (l, o2b mf, MLast.ExTyc (loc, e, t) : 'cvalue));
      [Gramext.Sopt (Gramext.Stoken ("", "mutable"));
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (l : 'label) (mf : string option)
           (loc : int * int) ->
           (l, o2b mf, e : 'cvalue))]];
    Grammar.Entry.obj (label : 'label Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("LIDENT", "")],
      Gramext.action (fun (i : string) (loc : int * int) -> (i : 'label))]];
    Grammar.Entry.obj (class_type : 'class_type Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "object");
       Gramext.Sopt
         (Gramext.Snterm
            (Grammar.Entry.obj
               (class_self_type : 'class_self_type Grammar.Entry.e)));
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj
                   (class_sig_item : 'class_sig_item Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (csf : 'class_sig_item) (loc : int * int) ->
                  (csf : 'e__12))]);
       Gramext.Stoken ("", "end")],
      Gramext.action
        (fun _ (csf : 'e__12 list) (cst : 'class_self_type option) _
           (loc : int * int) ->
           (MLast.CtSig (loc, cst, csf) : 'class_type));
      [Gramext.Snterm
         (Grammar.Entry.obj
            (clty_longident : 'clty_longident Grammar.Entry.e))],
      Gramext.action
        (fun (id : 'clty_longident) (loc : int * int) ->
           (MLast.CtCon (loc, id, []) : 'class_type));
      [Gramext.Snterm
         (Grammar.Entry.obj
            (clty_longident : 'clty_longident Grammar.Entry.e));
       Gramext.Stoken ("", "[");
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e)),
          Gramext.Stoken ("", ","));
       Gramext.Stoken ("", "]")],
      Gramext.action
        (fun _ (tl : 'ctyp list) _ (id : 'clty_longident) (loc : int * int) ->
           (MLast.CtCon (loc, id, tl) : 'class_type));
      [Gramext.Stoken ("", "[");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "]"); Gramext.Stoken ("", "->"); Gramext.Sself],
      Gramext.action
        (fun (ct : 'class_type) _ _ (t : 'ctyp) _ (loc : int * int) ->
           (MLast.CtFun (loc, t, ct) : 'class_type))]];
    Grammar.Entry.obj (class_self_type : 'class_self_type Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("", "(");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (loc : int * int) -> (t : 'class_self_type))]];
    Grammar.Entry.obj (class_sig_item : 'class_sig_item Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("", "type");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t2 : 'ctyp) _ (t1 : 'ctyp) _ (loc : int * int) ->
           (MLast.CgCtr (loc, t1, t2) : 'class_sig_item));
      [Gramext.Stoken ("", "method");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (l : 'label) _ (loc : int * int) ->
           (MLast.CgMth (loc, l, false, t) : 'class_sig_item));
      [Gramext.Stoken ("", "method"); Gramext.Stoken ("", "private");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (l : 'label) _ _ (loc : int * int) ->
           (MLast.CgMth (loc, l, true, t) : 'class_sig_item));
      [Gramext.Stoken ("", "method"); Gramext.Stoken ("", "virtual");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (l : 'label) _ _ (loc : int * int) ->
           (MLast.CgVir (loc, l, false, t) : 'class_sig_item));
      [Gramext.Stoken ("", "method"); Gramext.Stoken ("", "virtual");
       Gramext.Stoken ("", "private");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (l : 'label) _ _ _ (loc : int * int) ->
           (MLast.CgVir (loc, l, true, t) : 'class_sig_item));
      [Gramext.Stoken ("", "value");
       Gramext.Sopt (Gramext.Stoken ("", "mutable"));
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (l : 'label) (mf : string option) _
           (loc : int * int) ->
           (MLast.CgVal (loc, l, o2b mf, t) : 'class_sig_item));
      [Gramext.Stoken ("", "inherit");
       Gramext.Snterm
         (Grammar.Entry.obj (class_type : 'class_type Grammar.Entry.e))],
      Gramext.action
        (fun (cs : 'class_type) _ (loc : int * int) ->
           (MLast.CgInh (loc, cs) : 'class_sig_item))]];
    Grammar.Entry.obj
      (class_description : 'class_description Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Sopt (Gramext.Stoken ("", "virtual"));
       Gramext.Stoken ("LIDENT", "");
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_type_parameters : 'class_type_parameters Grammar.Entry.e));
       Gramext.Stoken ("", ":");
       Gramext.Snterm
         (Grammar.Entry.obj (class_type : 'class_type Grammar.Entry.e))],
      Gramext.action
        (fun (ct : 'class_type) _ (ctp : 'class_type_parameters) (n : string)
           (vf : string option) (loc : int * int) ->
           ({MLast.ciLoc = loc; MLast.ciVir = o2b vf; MLast.ciPrm = ctp;
             MLast.ciNam = n; MLast.ciExp = ct} :
            'class_description))]];
    Grammar.Entry.obj
      (class_type_declaration : 'class_type_declaration Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Sopt (Gramext.Stoken ("", "virtual"));
       Gramext.Stoken ("LIDENT", "");
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_type_parameters : 'class_type_parameters Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm
         (Grammar.Entry.obj (class_type : 'class_type Grammar.Entry.e))],
      Gramext.action
        (fun (cs : 'class_type) _ (ctp : 'class_type_parameters) (n : string)
           (vf : string option) (loc : int * int) ->
           ({MLast.ciLoc = loc; MLast.ciVir = o2b vf; MLast.ciPrm = ctp;
             MLast.ciNam = n; MLast.ciExp = cs} :
            'class_type_declaration))]];
    Grammar.Entry.obj (expr : 'expr Grammar.Entry.e),
    Some (Gramext.Level "apply"),
    [None, Some Gramext.LeftA,
     [[Gramext.Stoken ("", "new");
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_longident : 'class_longident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'class_longident) _ (loc : int * int) ->
           (MLast.ExNew (loc, i) : 'expr))]];
    Grammar.Entry.obj (expr : 'expr Grammar.Entry.e),
    Some (Gramext.Level "."),
    [None, None,
     [[Gramext.Sself; Gramext.Stoken ("", "#");
       Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e))],
      Gramext.action
        (fun (lab : 'label) _ (e : 'expr) (loc : int * int) ->
           (MLast.ExSnd (loc, e, lab) : 'expr))]];
    Grammar.Entry.obj (expr : 'expr Grammar.Entry.e),
    Some (Gramext.Level "simple"),
    [None, None,
     [[Gramext.Stoken ("", "{<");
       Gramext.Snterm
         (Grammar.Entry.obj
            (field_expr_list : 'field_expr_list Grammar.Entry.e));
       Gramext.Stoken ("", ">}")],
      Gramext.action
        (fun _ (fel : 'field_expr_list) _ (loc : int * int) ->
           (MLast.ExOvr (loc, fel) : 'expr));
      [Gramext.Stoken ("", "{<"); Gramext.Stoken ("", ">}")],
      Gramext.action
        (fun _ _ (loc : int * int) -> (MLast.ExOvr (loc, []) : 'expr));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ":>");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExCoe (loc, e, None, t) : 'expr));
      [Gramext.Stoken ("", "("); Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ":>");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t2 : 'ctyp) _ (t : 'ctyp) _ (e : 'expr) _ (loc : int * int) ->
           (MLast.ExCoe (loc, e, Some t, t2) : 'expr))]];
    Grammar.Entry.obj (field_expr_list : 'field_expr_list Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e))],
      Gramext.action
        (fun (e : 'expr) _ (l : 'label) (loc : int * int) ->
           ([l, e] : 'field_expr_list));
      [Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (e : 'expr) _ (l : 'label) (loc : int * int) ->
           ([l, e] : 'field_expr_list));
      [Gramext.Snterm (Grammar.Entry.obj (label : 'label Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ";"); Gramext.Sself],
      Gramext.action
        (fun (fel : 'field_expr_list) _ (e : 'expr) _ (l : 'label)
           (loc : int * int) ->
           ((l, e) :: fel : 'field_expr_list))]];
    Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e),
    Some (Gramext.Level "simple"),
    [None, None,
     [[Gramext.Stoken ("", "<"); Gramext.Stoken ("", ">")],
      Gramext.action
        (fun _ _ (loc : int * int) -> (MLast.TyObj (loc, [], false) : 'ctyp));
      [Gramext.Stoken ("", "<");
       Gramext.Snterm
         (Grammar.Entry.obj (meth_list : 'meth_list Grammar.Entry.e));
       Gramext.Stoken ("", ">")],
      Gramext.action
        (fun _ (ml, v : 'meth_list) _ (loc : int * int) ->
           (MLast.TyObj (loc, ml, v) : 'ctyp));
      [Gramext.Stoken ("", "#");
       Gramext.Snterm
         (Grammar.Entry.obj
            (class_longident : 'class_longident Grammar.Entry.e))],
      Gramext.action
        (fun (id : 'class_longident) _ (loc : int * int) ->
           (MLast.TyCls (loc, id) : 'ctyp))]];
    Grammar.Entry.obj (meth_list : 'meth_list Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "..")],
      Gramext.action (fun _ (loc : int * int) -> ([], true : 'meth_list));
      [Gramext.Snterm (Grammar.Entry.obj (field : 'field Grammar.Entry.e))],
      Gramext.action
        (fun (f : 'field) (loc : int * int) -> ([f], false : 'meth_list));
      [Gramext.Snterm (Grammar.Entry.obj (field : 'field Grammar.Entry.e));
       Gramext.Stoken ("", ";")],
      Gramext.action
        (fun _ (f : 'field) (loc : int * int) -> ([f], false : 'meth_list));
      [Gramext.Snterm (Grammar.Entry.obj (field : 'field Grammar.Entry.e));
       Gramext.Stoken ("", ";"); Gramext.Sself],
      Gramext.action
        (fun (ml, v : 'meth_list) _ (f : 'field) (loc : int * int) ->
           (f :: ml, v : 'meth_list))]];
    Grammar.Entry.obj (field : 'field Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("LIDENT", ""); Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) _ (lab : string) (loc : int * int) ->
           (lab, t : 'field))]];
    Grammar.Entry.obj (clty_longident : 'clty_longident Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) -> ([i] : 'clty_longident));
      [Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", ".");
       Gramext.Sself],
      Gramext.action
        (fun (l : 'clty_longident) _ (m : string) (loc : int * int) ->
           (m :: l : 'clty_longident))]];
    Grammar.Entry.obj (class_longident : 'class_longident Grammar.Entry.e),
    None,
    [None, None,
     [[Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) -> ([i] : 'class_longident));
      [Gramext.Stoken ("UIDENT", ""); Gramext.Stoken ("", ".");
       Gramext.Sself],
      Gramext.action
        (fun (l : 'class_longident) _ (m : string) (loc : int * int) ->
           (m :: l : 'class_longident))]]]);;

(* Labels *)

Grammar.extend
  (let _ = (ctyp : 'ctyp Grammar.Entry.e)
   and _ = (ipatt : 'ipatt Grammar.Entry.e)
   and _ = (patt : 'patt Grammar.Entry.e)
   and _ = (expr : 'expr Grammar.Entry.e)
   and _ = (mod_ident : 'mod_ident Grammar.Entry.e) in
   let grammar_entry_create s =
     Grammar.Entry.create (Grammar.of_entry ctyp) s
   in
   let row_field : 'row_field Grammar.Entry.e =
     grammar_entry_create "row_field"
   and name_tag : 'name_tag Grammar.Entry.e = grammar_entry_create "name_tag"
   and ident : 'ident Grammar.Entry.e = grammar_entry_create "ident" in
   [Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e),
    Some (Gramext.After "arrow"),
    [None, Some Gramext.NonA,
     [[Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Sself],
      Gramext.action
        (fun (t : 'ctyp) (i : string) (loc : int * int) ->
           (MLast.TyOlb (loc, i, t) : 'ctyp));
      [Gramext.Stoken ("TILDEIDENTCOLON", ""); Gramext.Sself],
      Gramext.action
        (fun (t : 'ctyp) (i : string) (loc : int * int) ->
           (MLast.TyLab (loc, i, t) : 'ctyp))]];
    Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e),
    Some (Gramext.Level "simple"),
    [None, None,
     [[Gramext.Stoken ("", "[|"); Gramext.Stoken ("", "<");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (row_field : 'row_field Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", ">");
       Gramext.Slist1
         (Gramext.Snterm
            (Grammar.Entry.obj (name_tag : 'name_tag Grammar.Entry.e)));
       Gramext.Stoken ("", "|]")],
      Gramext.action
        (fun _ (ntl : 'name_tag list) _ (rfl : 'row_field list) _ _
           (loc : int * int) ->
           (MLast.TyVrn (loc, rfl, Some (Some ntl)) : 'ctyp));
      [Gramext.Stoken ("", "[|"); Gramext.Stoken ("", "<");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (row_field : 'row_field Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", "|]")],
      Gramext.action
        (fun _ (rfl : 'row_field list) _ _ (loc : int * int) ->
           (MLast.TyVrn (loc, rfl, Some (Some [])) : 'ctyp));
      [Gramext.Stoken ("", "[|"); Gramext.Stoken ("", ">");
       Gramext.Slist1sep
         (Gramext.Snterm
            (Grammar.Entry.obj (row_field : 'row_field Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", "|]")],
      Gramext.action
        (fun _ (rfl : 'row_field list) _ _ (loc : int * int) ->
           (MLast.TyVrn (loc, rfl, Some None) : 'ctyp));
      [Gramext.Stoken ("", "[|");
       Gramext.Slist0sep
         (Gramext.Snterm
            (Grammar.Entry.obj (row_field : 'row_field Grammar.Entry.e)),
          Gramext.Stoken ("", "|"));
       Gramext.Stoken ("", "|]")],
      Gramext.action
        (fun _ (rfl : 'row_field list) _ (loc : int * int) ->
           (MLast.TyVrn (loc, rfl, None) : 'ctyp))]];
    Grammar.Entry.obj (row_field : 'row_field Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e))],
      Gramext.action
        (fun (t : 'ctyp) (loc : int * int) -> (MLast.RfInh t : 'row_field));
      [Gramext.Stoken ("", "`");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e));
       Gramext.Stoken ("", "of"); Gramext.Sopt (Gramext.Stoken ("", "&"));
       Gramext.Slist1sep
         (Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e)),
          Gramext.Stoken ("", "&"))],
      Gramext.action
        (fun (l : 'ctyp list) (ao : string option) _ (i : 'ident) _
           (loc : int * int) ->
           (MLast.RfTag (i, o2b ao, l) : 'row_field));
      [Gramext.Stoken ("", "`");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'ident) _ (loc : int * int) ->
           (MLast.RfTag (i, true, []) : 'row_field))]];
    Grammar.Entry.obj (name_tag : 'name_tag Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("", "`");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (i : 'ident) _ (loc : int * int) -> (i : 'name_tag))]];
    Grammar.Entry.obj (patt : 'patt Grammar.Entry.e),
    Some (Gramext.Level "simple"),
    [None, None,
     [[Gramext.Stoken ("QUESTIONIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, MLast.PaLid (loc, i), None) : 'patt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (e : 'expr) _ (t : 'ctyp) _ (p : 'patt) _ (i : string)
           (loc : int * int) ->
           (MLast.PaOlb (loc, i, MLast.PaTyc (loc, p, t), Some e) : 'patt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (p : 'patt) _ (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, MLast.PaTyc (loc, p, t), None) : 'patt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (e : 'expr) _ (p : 'patt) _ (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, p, Some e) : 'patt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (p : 'patt) _ (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, p, None) : 'patt));
      [Gramext.Stoken ("TILDEIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.PaLab (loc, i, MLast.PaLid (loc, i)) : 'patt));
      [Gramext.Stoken ("TILDEIDENTCOLON", ""); Gramext.Sself],
      Gramext.action
        (fun (p : 'patt) (i : string) (loc : int * int) ->
           (MLast.PaLab (loc, i, p) : 'patt));
      [Gramext.Stoken ("", "#");
       Gramext.Snterm
         (Grammar.Entry.obj (mod_ident : 'mod_ident Grammar.Entry.e))],
      Gramext.action
        (fun (sl : 'mod_ident) _ (loc : int * int) ->
           (MLast.PaTyp (loc, sl) : 'patt));
      [Gramext.Stoken ("", "`");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (s : 'ident) _ (loc : int * int) ->
           (MLast.PaVrn (loc, s) : 'patt))]];
    Grammar.Entry.obj (ipatt : 'ipatt Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("QUESTIONIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, MLast.PaLid (loc, i), None) : 'ipatt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (e : 'expr) _ (t : 'ctyp) _ (p : 'ipatt) _ (i : string)
           (loc : int * int) ->
           (MLast.PaOlb (loc, i, MLast.PaTyc (loc, p, t), Some e) : 'ipatt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", ":");
       Gramext.Snterm (Grammar.Entry.obj (ctyp : 'ctyp Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (t : 'ctyp) _ (p : 'ipatt) _ (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, MLast.PaTyc (loc, p, t), None) : 'ipatt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", "=");
       Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
       Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (e : 'expr) _ (p : 'ipatt) _ (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, p, Some e) : 'ipatt));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Stoken ("", "(");
       Gramext.Sself; Gramext.Stoken ("", ")")],
      Gramext.action
        (fun _ (p : 'ipatt) _ (i : string) (loc : int * int) ->
           (MLast.PaOlb (loc, i, p, None) : 'ipatt));
      [Gramext.Stoken ("TILDEIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.PaLab (loc, i, MLast.PaLid (loc, i)) : 'ipatt));
      [Gramext.Stoken ("TILDEIDENTCOLON", ""); Gramext.Sself],
      Gramext.action
        (fun (p : 'ipatt) (i : string) (loc : int * int) ->
           (MLast.PaLab (loc, i, p) : 'ipatt))]];
    Grammar.Entry.obj (expr : 'expr Grammar.Entry.e),
    Some (Gramext.After "apply"),
    [Some "label", None,
     [[Gramext.Stoken ("QUESTIONIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.ExOlb (loc, i, MLast.ExLid (loc, i)) : 'expr));
      [Gramext.Stoken ("QUESTIONIDENTCOLON", ""); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) (i : string) (loc : int * int) ->
           (MLast.ExOlb (loc, i, e) : 'expr));
      [Gramext.Stoken ("TILDEIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) ->
           (MLast.ExLab (loc, i, MLast.ExLid (loc, i)) : 'expr));
      [Gramext.Stoken ("TILDEIDENTCOLON", ""); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) (i : string) (loc : int * int) ->
           (MLast.ExLab (loc, i, e) : 'expr))]];
    Grammar.Entry.obj (expr : 'expr Grammar.Entry.e),
    Some (Gramext.Level "simple"),
    [None, None,
     [[Gramext.Stoken ("", "`");
       Gramext.Snterm (Grammar.Entry.obj (ident : 'ident Grammar.Entry.e))],
      Gramext.action
        (fun (s : 'ident) _ (loc : int * int) ->
           (MLast.ExVrn (loc, s) : 'expr))]];
    Grammar.Entry.obj (ident : 'ident Grammar.Entry.e), None,
    [None, None,
     [[Gramext.Stoken ("UIDENT", "")],
      Gramext.action (fun (i : string) (loc : int * int) -> (i : 'ident));
      [Gramext.Stoken ("LIDENT", "")],
      Gramext.action
        (fun (i : string) (loc : int * int) -> (i : 'ident))]]]);;

(* Old syntax for sequences *)

let not_yet_warned = ref true;;
let warning_seq () =
  if !not_yet_warned then
    begin
      not_yet_warned := false;
      Printf.eprintf "\
*** warning: use of old syntax
*** type \"camlp4r -help_seq\" in a shell for explanations
";
      flush stderr
    end
;;
Pcaml.add_option "-no_warn_seq" (Arg.Clear not_yet_warned)
  " No warning when using old syntax for sequences.";;

Grammar.extend
  (let _ = (expr : 'expr Grammar.Entry.e)
   and _ = (direction_flag : 'direction_flag Grammar.Entry.e) in
   [Grammar.Entry.obj (expr : 'expr Grammar.Entry.e),
    Some (Gramext.Level "top"),
    [None, None,
     [[Gramext.Stoken ("", "while"); Gramext.Sself; Gramext.Stoken ("", "do");
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (e : 'expr) (loc : int * int) -> (e : 'e__15))]);
       Gramext.Stoken ("", "done")],
      Gramext.action
        (fun _ (seq : 'e__15 list) _ (e : 'expr) _ (loc : int * int) ->
           (warning_seq (); MLast.ExWhi (loc, e, seq) : 'expr));
      [Gramext.Stoken ("", "for"); Gramext.Stoken ("LIDENT", "");
       Gramext.Stoken ("", "="); Gramext.Sself;
       Gramext.Snterm
         (Grammar.Entry.obj
            (direction_flag : 'direction_flag Grammar.Entry.e));
       Gramext.Sself; Gramext.Stoken ("", "do");
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (e : 'expr) (loc : int * int) -> (e : 'e__14))]);
       Gramext.Stoken ("", "done")],
      Gramext.action
        (fun _ (seq : 'e__14 list) _ (e2 : 'expr) (df : 'direction_flag)
           (e1 : 'expr) _ (i : string) _ (loc : int * int) ->
           (warning_seq (); MLast.ExFor (loc, i, e1, e2, df, seq) : 'expr));
      [Gramext.Stoken ("", "do");
       Gramext.Slist0
         (Gramext.srules
            [[Gramext.Snterm
                (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
              Gramext.Stoken ("", ";")],
             Gramext.action
               (fun _ (e : 'expr) (loc : int * int) -> (e : 'e__13))]);
       Gramext.Stoken ("", "return"); Gramext.Sself],
      Gramext.action
        (fun (e : 'expr) _ (seq : 'e__13 list) _ (loc : int * int) ->
           (warning_seq (); MLast.ExSeq (loc, (seq @ [e])) : 'expr))]]]);;
