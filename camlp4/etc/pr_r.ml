(* camlp4r q_MLast.cmo ./pa_extfun.cmo *)
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

(* $Id$ *)

open Pcaml;
open Spretty;

value not_impl name x =
  let desc =
    if Obj.is_block (Obj.repr x) then
      "tag = " ^ string_of_int (Obj.tag (Obj.repr x))
    else "int_val = " ^ string_of_int (Obj.magic x)
  in
  HVbox [: `S NO ("<pr_r: not impl: " ^ name ^ "; " ^ desc ^ ">") :]
;

value gen_where = ref True;
value old_sequences = ref False;
value input_file_ic = ref None;

external is_printable : char -> bool = "is_printable";

value char_escaped =
  fun
  [ '\\' -> "\\\\"
  | '\b' -> "\\b"
  | '\n' -> "\\n"
  | '\r' -> "\\r"
  | '\t' -> "\\t"
  | c ->
      if is_printable c then String.make 1 c
      else do {
        let n = Char.code c in
        let s = String.create 4 in
        String.unsafe_set s 0 '\\';
        String.unsafe_set s 1 (Char.unsafe_chr (48 + n / 100));
        String.unsafe_set s 2 (Char.unsafe_chr (48 + n / 10 mod 10));
        String.unsafe_set s 3 (Char.unsafe_chr (48 + n mod 10));
        s
      } ]
;

value apply_it l f =
  apply_it_f l where rec apply_it_f =
    fun
    [ [] -> f
    | [a :: l] -> a (apply_it_f l) ]
;

value rec list elem el k =
  match el with
  [ [] -> k
  | [x] -> [: `elem x k :]
  | [x :: l] -> [: `elem x [: :]; list elem l k :] ]
;

value rec listws elem sep el k =
  match el with
  [ [] -> k
  | [x] -> [: `elem x k :]
  | [x :: l] -> [: `elem x [: `sep :]; listws elem sep l k :] ]
;

value rec listwbws elem b sep el k =
  match el with
  [ [] -> [: b; k :]
  | [x] -> [: `elem b x k :]
  | [x :: l] -> [: `elem b x [: :]; listwbws elem [: `sep :] sep l k :] ]
;

value level box elem next e k =
  let rec curr e k = elem curr next e k in
  box e (curr e k)
;

value is_infix =
  let infixes = Hashtbl.create 73 in
  do {
    List.iter (fun s -> Hashtbl.add infixes s True)
      ["=="; "!="; "+"; "+."; "-"; "-."; "*"; "*."; "/"; "/."; "**"; "**.";
       "="; "=."; "<>"; "<>."; "<"; "<."; ">"; ">."; "<="; "<=."; ">="; ">=.";
       "^"; "@"; "asr"; "land"; "lor"; "lsl"; "lsr"; "lxor"; "mod"; "or";
       "quo"; "&&"; "||"; "~-"; "~-."];
    fun s -> try Hashtbl.find infixes s with [ Not_found -> False ]
  }
;

value is_keyword =
  let keywords = Hashtbl.create 301 in
  do {
    List.iter (fun s -> Hashtbl.add keywords s True)
      ["<>"; "<="; "struct"; "asr"; ":]"; "[:"; ":="; "type"; "::"; "return";
       "for"; "to"; "and"; "rec"; "||"; "of"; "with"; "while"; "module";
       "when"; "exception"; "lsr"; "lsl"; "done"; "/."; ".."; "->"; "in";
       "-."; "if"; "value"; "lor"; "external"; "sig"; "+."; "then"; "where";
       "*."; "**"; "match"; "parser"; "try"; "do"; "land"; "else"; "as";
       "open"; "}"; "|"; "end"; "{"; "lxor"; "`"; "_"; "^"; "]"; "["; "let";
       "!="; "@"; "?"; ">"; "="; "<"; ";"; ":"; "mutable"; "/"; "[|"; ".";
       "-"; ","; "+"; "downto"; "*"; ")"; "|]"; "("; "'"; "&&"; "functor";
       ">="; "#"; "~-."; "~-"; "fun"; "mod"; "=="; "declare"];
    fun s -> try Hashtbl.find keywords s with [ Not_found -> False ]
  }
;

value has_special_chars v =
  match v.[0] with
  [ 'a'..'z' | 'A'..'Z' | '_' -> False
  | _ ->
      if String.length v >= 2 && v.[0] == '<' &&
         (v.[1] == '<' || v.[1] == ':')
      then
        False
      else True ]
;

value var_escaped v =
  if has_special_chars v || is_keyword v then " \\" ^ v else v
;

value flag n f = if f then [: `S LR n :] else [: :];

(* default global loc *)

value loc = (0, 0);

(* extensible printers *)

value sig_item x k = pr_sig_item.pr_fun "top" x "" [: `S RO ";"; k :];
value str_item x k = pr_str_item.pr_fun "top" x "" [: `S RO ";"; k :];
value expr x k = pr_expr.pr_fun "top" x "" k;
value patt x k = pr_patt.pr_fun "top" x "" k;
value expr_fun_args ge = Extfun.apply pr_expr_fun_args.val ge;

(* type core *)

value ctyp_f = ref (fun []);
value ctyp t k = ctyp_f.val t k;

value input_from_source bp ep =
  match input_file_ic.val with
  [ Some ic when ep > bp ->
      do {
        seek_in ic bp;
        let len = ep - bp in
        let buff = Buffer.create 20 in
        loop 0 where rec loop i =
          if i < len then do {
            let c = input_char ic in
            Buffer.add_char buff c;
            loop (i + 1)
          }
          else Buffer.contents buff
      }
  | _ -> "" ]
;

value rec labels loc b vl k =
  match vl with
  [ [] -> [: b; k :]
  | [v] -> [: `label True (snd loc) b v k :]
  | [v :: ([(nloc, _, _, _) :: _] as l)] ->
      [: `label False (fst nloc) b v [: :]; labels loc [: :] l k :] ]
and label is_last bp_next b (loc, f, m, t) k =
  let m = flag "mutable" m in
  let txt =
    let s = input_from_source (snd loc) bp_next in
    let s =
      try
        let i = String.index s ';' in
        String.sub s (i + 1) (String.length s - i - 1)
      with
      [ Not_found -> "" ]
    in
    try
      let i = String.rindex s '\n' in
      String.sub s 0 i
    with
    [ Not_found -> s ]
  in
  let k = [: if is_last then [: :] else [: `S RO ";" :]; `S RO txt; k :] in
  Hbox
    [: `HVbox
         [: `HVbox [: b; `S LR f; `S LR ":" :];
            `HVbox [: m; `ctyp t [: :] :] :];
       k :]
;

value rec ctyp_list tel k = listws ctyp (S LR "and") tel k;

value include_comment_of_last_constructor ep =
  match input_file_ic.val with
  [ Some ic ->
     do {
       seek_in ic ep;
       loop ep where rec loop ep =
         let c = input_char ic in
         if c = '\n' then ep + 1
         else loop (ep + 1)
     }
  | None -> ep ]
;

value rec variants loc b vl k =
  let ep = include_comment_of_last_constructor (snd loc) in
  variants_loop (fst loc, ep) b vl k
and variants_loop loc b vl k =
  match vl with
  [ [] -> [: b; k :]
  | [v] -> [: `variant (snd loc) b v k :]
  | [v :: ([(nloc, _, _) :: _] as l)] ->
      [: `variant (fst nloc) b v [: :];
         variants_loop loc [: `S LR "|" :] l k :] ]
and variant bp_next b (loc, c, tl) k =
  let txt =
    let s = input_from_source (snd loc) bp_next in
    try
      let i = String.rindex s '\n' in
      String.sub s 0 i
    with
    [ Not_found -> "" ]
  in
  let k = [: `S RO txt; k :] in
  match tl with
  [ [] -> HVbox [: b; `HOVbox [: `S LR c; k :] :]
  | _ ->
      HVbox
        [: b; `HOVbox [: `S LR c; `S LR "of"; ctyp_list tl [: :]; k :] :] ]
;

value rec row_fields b rfl k = listwbws row_field b (S LR "|") rfl k
and row_field b rf k =
  match rf with
  [ MLast.RfTag c ao tl ->
      let c = "`" ^ c in
      match tl with
      [ [] -> HVbox [: b; `HOVbox [: `S LR c; k :] :]
      | _ ->
          let ao = if ao then [: `S LR "&" :] else [: :] in
          HVbox
            [: b; `HOVbox [: `S LR c; `S LR "of"; ao; ctyp_list tl k :] :] ]
  | MLast.RfInh t ->
      HVbox [: b; `ctyp t k :] ]
;

(* *)

value rec class_longident sl k =
  match sl with
  [ [i] -> HVbox [: `S LR i; k :]
  | [m :: sl] -> HVbox [: `S LR m; `S NO "."; `class_longident sl k :]
  | _ -> HVbox [: `not_impl "class_longident" sl; k :] ]
;

value rec clty_longident sl k =
  match sl with
  [ [i] -> HVbox [: `S LR i; k :]
  | [m :: sl] -> HVbox [: `S LR m; `S NO "."; `clty_longident sl k :]
  | _ -> HVbox [: `not_impl "clty_longident" sl; k :] ]
;

value rec meth_list (ml, v) k =
  match (ml, v) with
  [ ([f], False) -> [: `field f k :]
  | ([], _) -> [: `S LR ".."; k :]
  | ([f :: ml], v) -> [: `field f [: `S RO ";" :]; meth_list (ml, v) k :] ]
and field (lab, t) k = HVbox [: `S LR lab; `S LR ":"; `ctyp t k :];

ctyp_f.val :=
  apply_it
    [level (fun _ x -> HOVbox x)
       (fun curr next t k ->
          match t with
          [ <:ctyp< $t1$ == $t2$ >> ->
              [: curr t1 [: `S LR "==" :]; `next t2 k :]
          | t -> [: `next t k :] ]);
     level (fun _ x -> HOVbox x)
       (fun curr next t k ->
          match t with
          [ <:ctyp< $x$ as $y$ >> -> [: curr x [: `S LR "as" :]; `next y k :]
          | t -> [: `next t k :] ]);
     level (fun _ x -> HOVbox x)
       (fun curr next t k ->
          match t with
          [ <:ctyp< $x$ -> $y$ >> -> [: `next x [: `S LR "->" :]; curr y k :]
          | t -> [: `next t k :] ]);
     level (fun _ x -> HOVbox x)
       (fun curr next t k ->
          match t with
          [ <:ctyp< $t1$ $t2$ >> -> [: curr t1 [: :]; `next t2 k :]
          | t -> [: `next t k :] ]);
     level (fun _ x -> HOVbox x)
       (fun curr next t k ->
          match t with
          [ <:ctyp< ? $lab$ : $t$ >> ->
              [: `S LO "?"; `S LR lab; `S RO ":"; `next t k :]
          | <:ctyp< ~ $lab$ : $t$ >> ->
              [: `S LO ("~" ^ lab ^ ":"); `next t k :]
          | t -> [: `next t k :] ]);
     level (fun _ x -> HOVbox x)
       (fun curr next t k ->
          match t with
          [ <:ctyp< $t1$ . $t2$ >> ->
              [: curr t1 [: :]; `S NO "."; `next t2 k :]
          | t -> [: `next t k :] ]);
     level (fun _ x -> HOVbox x)
       (fun curr next t k ->
          match t with
          [ <:ctyp< ($list:tl$) >> ->
              [: `S LO "("; listws ctyp (S LR "*") tl [: `S RO ")"; k :] :]
          | <:ctyp< '$s$ >> -> [: `S LO "'"; `S LR (var_escaped s); k :]
          | <:ctyp< $lid:s$ >> -> [: `S LR (var_escaped s); k :]
          | <:ctyp< $uid:s$ >> -> [: `S LR s; k :]
          | <:ctyp< _ >> -> [: `S LR "_"; k :]
          | <:ctyp< { $list: ftl$ } >> ->
              let loc = MLast.loc_of_ctyp t in
              [: `HVbox
                   [: labels loc [: `S LR "{" :] ftl [: `S LR "}" :]; k :] :]
          | <:ctyp< [ $list:ctl$ ] >> ->
              let loc = MLast.loc_of_ctyp t in
              [: `Vbox
                    [: `HVbox [: :];
                       variants loc
                          [: `S LR "[" :] ctl [: `S LR "]" :]; k :] :]
          | <:ctyp< [| $list:rfl$ |] >> ->
              [: `HVbox
                    [: `HVbox [: :];
                       row_fields [: `S LR "[|" :] rfl [: `S LR "|]" :];
                       k :] :]
          | <:ctyp< [| > $list:rfl$ |] >> ->
              [: `HVbox
                    [: `HVbox [: :];
                       row_fields [: `S LR "[|"; `S LR ">" :] rfl
                         [: `S LR "|]" :];
                       k :] :]
          | <:ctyp< [| < $list:rfl$ > $list:sl$ |] >> ->
              let k1 = [: `S LR "|]" :] in
              let k1 =
                match sl with
                [ [] -> k1
                | l ->
                    [: `S LR ">";
                       list (fun x k -> HVbox [: `S LR x; k :]) l k1 :] ]
              in
              [: `HVbox
                    [: `HVbox [: :];
                       row_fields [: `S LR "[|"; `S LR "<" :] rfl k1; k :] :]
          | <:ctyp< $_$ -> $_$ >> | <:ctyp< $_$ $_$ >> |
            <:ctyp< $_$ == $_$ >> | <:ctyp< $_$ . $_$ >> |
            <:ctyp< $_$ as $_$ >> | <:ctyp< ? $_$ : $_$ >> |
            <:ctyp< ~ $_$ : $_$ >> ->
              [: `S LO "("; `ctyp t [: `HVbox [: `S RO ")"; k :] :] :]
          | MLast.TyCls _ id -> [: `S LO "#"; `class_longident id k :]
          | MLast.TyObj _ [] False -> [: `S LR "<>"; k :]
          | MLast.TyObj _ ml v ->
              [: `S LR "<"; meth_list (ml, v) [: `S LR ">"; k :] :] ])]
    (fun t k -> not_impl "ctyp" t);

(* patterns *)

value rec is_irrefut_patt =
  fun
  [ <:patt< $lid:_$ >> -> True
  | <:patt< () >> -> True
  | <:patt< _ >> -> True
  | <:patt< ($x$ as $_$) >> -> is_irrefut_patt x
  | <:patt< { $list:fpl$ } >> ->
      List.for_all (fun (_, p) -> is_irrefut_patt p) fpl
  | <:patt< ($p$ : $_$) >> -> is_irrefut_patt p
  | <:patt< ($list:pl$) >> -> List.for_all is_irrefut_patt pl
  | <:patt< ? $_$ : ( $p$ ) >> -> is_irrefut_patt p
  | <:patt< ? $_$ : ($p$ = $_$) >> -> is_irrefut_patt p
  | <:patt< ~ $_$ : $p$ >> -> is_irrefut_patt p
  | _ -> False ]
;

value rec get_defined_ident =
  fun
  [ <:patt< $_$ . $_$ >> -> []
  | <:patt< _ >> -> []
  | <:patt< $lid:x$ >> -> [x]
  | <:patt< ($p1$ as $p2$) >> -> get_defined_ident p1 @ get_defined_ident p2
  | <:patt< $int:_$ >> -> []
  | <:patt< $flo:_$ >> -> []
  | <:patt< $str:_$ >> -> []
  | <:patt< $chr:_$ >> -> []
  | <:patt< [| $list:pl$ |] >> -> List.flatten (List.map get_defined_ident pl)
  | <:patt< ($list:pl$) >> -> List.flatten (List.map get_defined_ident pl)
  | <:patt< $uid:_$ >> -> []
  | <:patt< ` $_$ >> -> []
  | <:patt< # $list:_$ >> -> []
  | <:patt< $p1$ $p2$ >> -> get_defined_ident p1 @ get_defined_ident p2
  | <:patt< { $list:lpl$ } >> ->
      List.flatten (List.map (fun (lab, p) -> get_defined_ident p) lpl)
  | <:patt< $p1$ | $p2$ >> -> get_defined_ident p1 @ get_defined_ident p2
  | <:patt< $p1$ .. $p2$ >> -> get_defined_ident p1 @ get_defined_ident p2
  | <:patt< ($p$ : $_$) >> -> get_defined_ident p
  | <:patt< ~ $_$ : $p$ >> -> get_defined_ident p
  | <:patt< ? $_$ : ($p$) >> -> get_defined_ident p
  | <:patt< ? $_$ : ($p$ = $e$) >> -> get_defined_ident p
  | MLast.PaAnt _ p -> get_defined_ident p ]
;

value un_irrefut_patt p =
  match get_defined_ident p with
  [ [] -> (<:patt< _ >>, <:expr< () >>)
  | [i] -> (<:patt< $lid:i$ >>, <:expr< $lid:i$ >>)
  | il ->
      let (upl, uel) =
        List.fold_right
          (fun i (upl, uel) ->
             ([<:patt< $lid:i$ >> :: upl], [<:expr< $lid:i$ >> :: uel]))
          il ([], [])
      in
      (<:patt< ($list:upl$) >>, <:expr< ($list:uel$) >>) ]
;            

(* expressions *)

pr_expr_fun_args.val :=
  extfun Extfun.empty with
  [ <:expr< fun [$p$ -> $e$] >> as ge ->
      if is_irrefut_patt p then
        let (pl, e) = expr_fun_args e in
        ([p :: pl], e)
      else ([], ge)
  | ge -> ([], ge) ];

value rec bind_list b pel k =
  match pel with
  [ [pe] -> let_binding b pe k
  | pel ->
      Vbox [: `HVbox [: :]; listwbws let_binding b (S LR "and") pel k :] ]
and let_binding b (p, e) k =
  let (p, e) =
    if is_irrefut_patt p then (p, e)
    else
      let (up, ue) = un_irrefut_patt p in
      (up, <:expr< match $e$ with [ $p$ -> $ue$ ] >>)
  in
  BEbox [: let_binding0 [: b; `patt p [: :] :] e [: :]; k :]
and let_binding0 b e k =
  let (pl, e) = expr_fun_args e in
  match e with
  [ <:expr< let $rec:r$ $lid:f$ = fun [ $list:pel$ ] in $e$ >>
    when
      let rec call_f =
        fun
        [ <:expr< $lid:f'$ >> -> f = f'
        | <:expr< $e$ $_$ >> -> call_f e
        | _ -> False ]
      in
      gen_where.val && call_f e ->
      let (pl1, e1) = expr_fun_args <:expr< fun [ $list:pel$ ] >> in
      [: `HVbox [: `HVbox b; `HOVbox (list patt pl [: `S LR "=" :]) :];
         `HVbox
            [: `HOVbox
                  [: `expr e [: :]; `S LR "where"; flag "rec" r; `S LR f;
                     `HVbox (list patt pl1 [: `S LR "=" :]) :];
               `expr e1 k :] :]
  | <:expr< ($e$ : $t$) >> ->
      [: `HVbox
            [: `HVbox b; `HOVbox (list patt pl [: `S LR ":" :]);
               `ctyp t [: `S LR "=" :] :];
         `expr e k :]
  | _ ->
      [: `HVbox [: `HVbox b; `HOVbox (list patt pl [: `S LR "=" :]) :];
         `expr e k :] ]
and match_assoc_list pwel k =
  match pwel with
  [ [pwe] -> match_assoc [: `S LR "[" :] pwe [: `S LR "]"; k :]
  | pel ->
      Vbox
        [: `HVbox [: :];
           listwbws match_assoc [: `S LR "[" :] (S LR "|") pel
             [: `S LR "]"; k :] :] ]
and match_assoc b (p, w, e) k =
  let s =
    let (p, k) =
      match p with
      [ <:patt< ($p$ as $p2$) >> -> (p, [: `S LR "as"; `patt p2 [: :] :])
      | _ -> (p, [: :]) ]
    in
    match w with
    [ Some e1 ->
        [: `HVbox
              [: `HVbox [: :]; `patt p k;
                 `HVbox [: `S LR "when"; `expr e1 [: `S LR "->" :] :] :] :]
    | _ -> [: `patt p [: k; `S LR "->" :] :] ]
  in
  HVbox [: b; `HVbox [: `HVbox s; `expr e k :] :]
;

value label lab = S LR (var_escaped lab);

value field_expr (lab, e) k = HVbox [: `label lab; `S LR "="; `expr e k :];

value rec sequence_loop =
  fun
  [ [<:expr< let $rec:r$ $list:pel$ in $e$ >>] ->
      let el =
        match e with
        [ <:expr< do { $list:el$ } >> -> el
        | _ -> [e] ]
      in
      let r = flag "rec" r in
      [: listwbws (fun b (p, e) k -> let_binding b (p, e) k)
           [: `S LR "let"; r :] (S LR "and") pel [: `S RO ";" :];
         sequence_loop el :]
  | [(<:expr< let $rec:_$ $list:_$ in $_$ >> as e) :: el] ->
      [: `HVbox [: `S LO "("; `expr e [: `S RO ")"; `S RO ";" :] :];
         sequence_loop el :]
  | [e] -> [: `expr e [: :] :]
  | [e :: el] -> [: `expr e [: `S RO ";" :]; sequence_loop el :]
  | [] -> [: :] ]
;

value sequence b1 b2 b3 el k =
  BEbox
    [: `BEbox [: b1; b2; `HVbox [: b3; `S LR "do {" :] :];
       `HVbox [: `HVbox [: :]; sequence_loop el :];
       `HVbox [: `S LR "}"; k :] :]
;

value rec let_sequence e =
  match e with
  [ <:expr< do { $list:el$ } >> -> Some el
  | <:expr< let $rec:_$ $list:_$ in $e1$ >> ->
      match let_sequence e1 with
      [ Some _ -> Some [e]
      | None -> None ]
  | _ -> None ]
;

value ifbox b1 b2 b3 e k =
  if old_sequences.val then HVbox [: `HOVbox [: b1; b2; b3 :]; `expr e k :]
  else
    match let_sequence e with
    [ Some el -> sequence b1 b2 b3 el k
    | None -> HVbox [: `BEbox [: b1; b2; b3 :]; `expr e k :] ]
;

value rec type_params sl k =
  let sl = List.map fst sl in
  list (fun s k -> HVbox [: `S LO "'"; `S LR s; k :]) sl k
;

value constrain (t1, t2) k =
  HVbox [: `S LR "constraint"; `ctyp t1 [: `S LR "=" :]; `ctyp t2 k :]
;

value type_list b tdl k =
  HVbox
    [: `HVbox [: :];
       listwbws
         (fun b ((_, tn), tp, te, cl) k ->
            let tn = var_escaped tn in
            HVbox
              [: `HVbox [: b; `S LR tn; type_params tp [: `S LR "=" :] :];
                 `ctyp te [: :]; list constrain cl k :])
         b (S LR "and") tdl [: :];
       k :]
;

value external_def s t pl k =
  let ls = list (fun s k -> HVbox [: `S LR ("\"" ^ s ^ "\""); k :]) pl k in
  HVbox
    [: `HVbox [: `S LR "external"; `S LR (var_escaped s); `S LR ":" :];
       `ctyp t [: `S LR "="; ls :] :]
;

value value_description s t k =
  HVbox
    [: `HVbox [: `S LR "value"; `S LR (var_escaped s); `S LR ":" :];
       `ctyp t k :]
;

value rec mod_ident sl k =
  match sl with
  [ [] -> k
  | [s] -> [: `S LR (var_escaped s); k :]
  | [s :: sl] -> [: `S LR s; `S NO "."; mod_ident sl k :] ]
;

value rec module_type mt k =
  let next = module_type1 in
  match mt with
  [ <:module_type< functor ( $s$ : $mt1$ ) -> $mt2$ >> ->
      let head =
        HVbox
          [: `S LR "functor"; `S LO "("; `S LR s; `S LR ":";
             `module_type mt1 [: `S RO ")" :]; `S LR "->" :]
      in
      HVbox [: `head; `module_type mt2 k :]
  | _ -> next mt k ]
and module_type1 mt k =
  let curr = module_type1 in
  let next = module_type2 in
  match mt with
  [ <:module_type< $mt$ with $list:icl$ >> ->
      HVbox [: `curr mt [: :]; `with_constraints [: `S LR "with" :] icl k :]
  | _ -> next mt k ]
and module_type2 mt k =
  let curr = module_type2 in
  let next = module_type3 in
  match mt with
  [ <:module_type< sig $list:s$ end >> ->
      BEbox
        [: `S LR "sig"; `HVbox [: `HVbox [: :]; list sig_item s [: :] :];
           `HVbox [: `S LR "end"; k :] :]
  | _ -> next mt k ]
and module_type3 mt k =
  let curr = module_type3 in
  let next = module_type4 in
  match mt with
  [ <:module_type< $mt1$ $mt2$ >> -> HVbox [: `curr mt1 [: :]; `next mt2 k :]
  | _ -> next mt k ]
and module_type4 mt k =
  let curr = module_type4 in
  let next = module_type5 in
  match mt with
  [ <:module_type< $mt1$ . $mt2$ >> ->
      HVbox [: `curr mt1 [: `S NO "." :]; `next mt2 k :]
  | _ -> next mt k ]
and module_type5 mt k =
  match mt with
  [ <:module_type< $lid:s$ >> -> HVbox [: `S LR s; k :]
  | <:module_type< $uid:s$ >> -> HVbox [: `S LR s; k :]
  | _ -> HVbox [: `S LO "("; `module_type mt [: `S RO ")"; k :] :] ]
and module_declaration b mt k =
  match mt with
  [ <:module_type< functor ( $i$ : $t$ ) -> $mt$ >> ->
      module_declaration
        [: b; `S LO "("; `S LR i; `S LR ":"; `module_type t [: `S RO ")" :] :]
        mt k
  | _ ->
      HVbox
        [: `HVbox [: :];
           `HVbox [: `HVbox [: b; `S LR ":" :]; `module_type mt [: :] :];
           k :] ]
and modtype_declaration s mt k =
  HVbox
    [: `HVbox [: :];
       `HVbox
          [: `HVbox [: `S LR "module"; `S LR "type"; `S LR s; `S LR "=" :];
             `module_type mt [: :] :];
       k :]
and with_constraints b icl k =
  HVbox [: `HVbox [: :]; listwbws with_constraint b (S LR "and") icl k :]
and with_constraint b wc k =
  match wc with
  [ MLast.WcTyp _ p al e ->
      let params =
        match al with
        [ [] -> [: :]
        | [s] -> [: `S LO "'"; `S LR (fst s) :]
        | sl -> [: `S LO "("; type_params sl [: `S RO ")" :] :] ]
      in
      HVbox
        [: `HVbox
              [: `HVbox b; `S LR "type"; params;
                 mod_ident p [: `S LR "=" :] :];
           `ctyp e k :]
  | MLast.WcMod _ sl mt ->
      HVbox
        [: b; `S LR "module"; mod_ident sl [: `S LR "=" :];
           `module_type mt k :] ]
and module_expr me k =
  match me with
  [ <:module_expr< struct $list:s$ end >> ->
      let s = HVbox [: `S LR "struct"; list str_item s [: :] :] in
      HVbox [: `HVbox [: :]; `s; `HVbox [: `S LR "end"; k :] :]
  | <:module_expr< functor ($s$ : $mt$) -> $me$ >> ->
      let head =
        HVbox
          [: `S LR "functor"; `S LO "("; `S LR s; `S LR ":";
             `module_type mt [: `S RO ")" :]; `S LR "->" :]
      in
      HVbox [: `head; `module_expr me k :]
  | _ -> module_expr1 me k ]
and module_expr1 me k =
  let curr = module_expr1 in
  let next = module_expr2 in
  match me with
  [ <:module_expr< $me1$ $me2$ >> -> HVbox [: `curr me1 [: :]; `next me2 k :]
  | _ -> next me k ]
and module_expr2 me k =
  let curr = module_expr2 in
  let next = module_expr3 in
  match me with
  [ <:module_expr< $me1$ . $me2$ >> ->
      HVbox [: `curr me1 [: `S NO "." :]; `next me2 k :]
  | _ -> next me k ]
and module_expr3 me k =
  let curr = module_expr3 in
  match me with
  [ <:module_expr< $uid:s$ >> -> HVbox [: `S LR s; k :]
  | <:module_expr< ( $me$ : $mt$ ) >> ->
      HVbox
        [: `S LO "("; `module_expr me [: `S LR ":" :];
           `module_type mt [: `S RO ")"; k :] :]
  | <:module_expr< struct $list:_$ end >> ->
      HVbox [: `S LO "("; `module_expr me [: `S RO ")"; k :] :]
  | x -> not_impl "module_expr3" x ]
and module_binding b me k =
  match me with
  [ <:module_expr< functor ($s$ : $mt$) -> $mb$ >> ->
      module_binding
        [: `HVbox
              [: b; `S LO "("; `S LR s; `S LR ":";
                 `module_type mt [: `S RO ")" :] :] :]
        mb k
  | <:module_expr< ( $me$ : $mt$ ) >> ->
      HVbox
        [: `HVbox [: :];
           `HVbox
              [: `HVbox
                    [: `HVbox [: b; `S LR ":" :];
                       `module_type mt [: `S LR "=" :] :];
                 `module_expr me [: :] :];
           k :]
  | _ ->
      HVbox
        [: `HVbox [: :];
           `HVbox [: `HVbox [: b; `S LR "=" :]; `module_expr me [: :] :];
           k :] ]
and class_declaration b ci k =
  class_fun_binding
    [: b; flag "virtual" ci.MLast.ciVir; `S LR ci.MLast.ciNam;
       class_type_parameters ci.MLast.ciPrm :]
    ci.MLast.ciExp k
and class_fun_binding b ce k =
  match ce with
  [ MLast.CeFun _ p cfb -> class_fun_binding [: b; `patt p [: :] :] cfb k
  | ce -> HVbox [: `HVbox [: b; `S LR "=" :]; `class_expr ce k :] ]
and class_type_parameters (loc, tpl) =
  match tpl with
  [ [] -> [: :]
  | tpl ->
      [: `S LO "["; listws type_parameter (S RO ",") tpl [: `S RO "]" :] :] ]
and type_parameter tp k = HVbox [: `S LO "'"; `S LR (fst tp); k :]
and class_expr ce k =
  match ce with
  [ MLast.CeFun _ p ce ->
      HVbox
        [: `S LR "fun"; `simple_patt p [: `S LR "->" :]; `class_expr ce k :]
  | MLast.CeLet _ rf lb ce ->
      HVbox
        [: `HVbox [: :];
           `bind_list [: `S LR "let"; flag "rec" rf :] lb [: `S LR "in" :];
           `class_expr ce k :]
  | ce -> class_expr1 ce k ]
and class_expr1 ce k =
  match ce with
  [ MLast.CeApp _ ce e ->
      HVbox [: `class_expr1 ce [: :]; `simple_expr e k :]
  | ce -> class_expr2 ce k ]
and class_expr2 ce k =
  match ce with
  [ MLast.CeCon _ ci [] -> class_longident ci k
  | MLast.CeCon _ ci ctcl ->
      HVbox
        [: `class_longident ci [: :]; `S LO "[";
           listws ctyp (S RO ",") ctcl [: `S RO "]"; k :] :]
  | MLast.CeStr _ csp cf ->
      class_structure [: `S LR "object"; `class_self_patt_opt csp :] cf
        [: `S LR "end"; k :]
  | MLast.CeTyc _ ce ct ->
      HVbox
        [: `S LO "("; `class_expr ce [: `S LR ":" :];
           `class_type ct [: `S RO ")"; k :] :]
  | MLast.CeFun _ _ _ ->
      HVbox [: `S LO "("; `class_expr ce [: `S RO ")"; k :] :]
  | _ -> HVbox [: `not_impl "class_expr" ce; k :] ]
and simple_expr e k =
  match e with
  [ <:expr< $lid:_$ >> -> expr e k
  | _ -> HVbox [: `S LO "("; `expr e [: `S RO ")"; k :] :] ]
and class_structure b cf k =
  BEbox
    [: `HVbox b; `HVbox [: `HVbox [: :]; list class_str_item cf [: :] :];
       `HVbox k :]
and class_self_patt_opt csp =
  match csp with
  [ Some p -> HVbox [: `S LO "("; `patt p [: `S RO ")" :] :]
  | None -> HVbox [: :] ]
and class_str_item cf k =
  let k = [: `S RO ";"; k :] in
  match cf with
  [ MLast.CrDcl _ s ->
      HVbox [: `HVbox [: :]; list class_str_item s [: :] :]
  | MLast.CrInh _ ce pb ->
      HVbox
        [: `S LR "inherit"; `class_expr ce [: :];
           match pb with
           [ Some i -> [: `S LR "as"; `S LR i :]
           | _ -> [: :] ];
           k :]
  | MLast.CrVal _ lab mf e ->
      HVbox [: `S LR "value"; `cvalue (lab, mf, e) k :]
  | MLast.CrVir _ lab pf t ->
      HVbox
        [: `S LR "method"; `S LR "virtual"; flag "private" pf; `label lab;
           `S LR ":"; `ctyp t k :]
  | MLast.CrMth _ lab pf fb ->
      fun_binding [: `S LR "method"; flag "private" pf; `label lab :] fb k
  | MLast.CrCtr _ t1 t2 ->
      HVbox
        [: `HVbox [: `S LR "type"; `ctyp t1 [: `S LR "=" :] :]; `ctyp t2 k :]
  | MLast.CrIni _ se -> HVbox [: `S LR "initializer"; `expr se k :] ]
and label lab = S LR (var_escaped lab)
and cvalue (lab, mf, e) k =
  HVbox [: flag "mutable" mf; `label lab; `S LR "="; `expr e k :]
and fun_binding b fb k =
  match fb with
  [ <:expr< fun $p$ -> $e$ >> -> fun_binding [: b; `simple_patt p [: :] :] e k
  | e -> HVbox [: `HVbox [: b; `S LR "=" :]; `expr e k :] ]
and simple_patt p k =
  match p with
  [ <:patt< $lid:_$ >> | <:patt< ~ $_$ : $_$ >> | <:patt< ~ $_$ >> -> patt p k
  | _ -> HVbox [: `S LO "("; `patt p [: `S RO ")"; k :] :] ]
and class_type ct k =
  match ct with
  [ MLast.CtFun _ t ct ->
      HVbox
        [: `S LR "["; `ctyp t [: `S LR "]"; `S LR "->" :]; `class_type ct k :]
  | _ -> class_signature ct k ]
and class_signature cs k =
  match cs with
  [ MLast.CtCon _ id [] -> clty_longident id k
  | MLast.CtCon _ id tl ->
      HVbox
        [: `clty_longident id [: :]; `S LO "[";
           listws ctyp (S RO ",") tl [: `S RO "]"; k :] :]
  | MLast.CtSig _ cst csf ->
      class_self_type [: `S LR "object" :] cst
        [: `HVbox [: `HVbox [: :]; list class_sig_item csf [: :] :];
           `HVbox [: `S LR "end"; k :] :]
  | _ -> HVbox [: `not_impl "class_signature" cs; k :] ]
and class_self_type b cst k =
  BEbox
    [: `HVbox
          [: b;
             match cst with
             [ None -> [: :]
             | Some t -> [: `S LO "("; `ctyp t [: `S RO ")" :] :] ] :];
       k :]
and class_sig_item csf k =
  let k = [: `S RO ";"; k :] in
  match csf with
  [ MLast.CgCtr _ t1 t2 ->
      HVbox [: `S LR "type"; `ctyp t1 [: `S LR "=" :]; `ctyp t2 k :]
  | MLast.CgDcl _ s ->
      HVbox [: `HVbox [: :]; list class_sig_item s k :]
  | MLast.CgMth _ lab pf t ->
      HVbox
        [: `S LR "method"; flag "private" pf; `label lab; `S LR ":";
           `ctyp t k :]
  | MLast.CgVal _ lab mf t ->
      HVbox
        [: `S LR "value"; flag "mutable" mf; `label lab; `S LR ":";
           `ctyp t k :]
  | _ -> HVbox [: `not_impl "class_sig_item" csf; k :] ]
and class_description b ci k =
  HVbox
    [: `HVbox
          [: b; flag "virtual" ci.MLast.ciVir; `S LR ci.MLast.ciNam;
             class_type_parameters ci.MLast.ciPrm; `S LR ":" :];
       `class_type ci.MLast.ciExp k :]
and class_type_declaration b ci k =
  HVbox
    [: `HVbox
          [: b; flag "virtual" ci.MLast.ciVir; `S LR ci.MLast.ciNam;
             class_type_parameters ci.MLast.ciPrm; `S LR "=" :];
       `class_signature ci.MLast.ciExp k :]
;

pr_sig_item.pr_levels :=
  [{pr_label = "top";
    pr_box s x = LocInfo (MLast.loc_of_sig_item s) (HVbox x);
    pr_rules =
      extfun Extfun.empty with
      [ <:sig_item< type $list:stl$ >> ->
          fun curr next _ k -> [: `type_list [: `S LR "type" :] stl k :]
      | <:sig_item< declare $list:s$ end >> ->
          fun curr next _ k ->
            [: `BEbox
                  [: `S LR "declare";
                     `HVbox [: `HVbox [: :]; list sig_item s [: :] :];
                     `HVbox [: `S LR "end"; k :] :] :]
      | MLast.SgDir _ _ _ as si ->
          fun curr next _ k -> [: `not_impl "sig_item1" si :]
      | <:sig_item< exception $c$ of $list:tl$ >> ->
          fun curr next _ k ->
            [: `variant 0 [: `S LR "exception" :] (loc, c, tl) k :]
      | <:sig_item< value $s$ : $t$ >> ->
          fun curr next _ k -> [: `value_description s t k :]
      | <:sig_item< include $mt$ >> ->
          fun curr next _ k -> [: `S LR "include"; `module_type mt k :]
      | <:sig_item< external $s$ : $t$ = $list:pl$ >> ->
          fun curr next _ k -> [: `external_def s t pl k :]
      | <:sig_item< module $s$ : $mt$ >> ->
          fun curr next _ k ->
            [: `module_declaration [: `S LR "module"; `S LR s :] mt k :]
      | <:sig_item< module type $s$ = $mt$ >> ->
          fun curr next _ k -> [: `modtype_declaration s mt k :]
      | <:sig_item< open $sl$ >> ->
          fun curr next _ k -> [: `S LR "open"; mod_ident sl k :]
      | MLast.SgCls _ cd ->
          fun curr next _ k ->
            [: `HVbox [: :];
               listwbws class_description [: `S LR "class" :] (S LR "and") cd
                 k :]
      | MLast.SgClt _ cd ->
          fun curr next _ k ->
            [: `HVbox [: :];
               listwbws class_type_declaration
                 [: `S LR "class"; `S LR "type" :] (S LR "and") cd k :] ]}];

pr_str_item.pr_levels :=
  [{pr_label = "top";
    pr_box s x = LocInfo (MLast.loc_of_str_item s) (HVbox x);
    pr_rules =
      extfun Extfun.empty with
      [ <:str_item< open $i$ >> ->
          fun curr next _ k -> [: `S LR "open"; mod_ident i k :]
      | <:str_item< $exp:e$ >> ->
          fun curr next _ k -> [: `HVbox [: :]; `expr e k :]
      | <:str_item< declare $list:s$ end >> ->
          fun curr next _ k ->
            [: `BEbox
                  [: `S LR "declare";
                     `HVbox [: `HVbox [: :]; list str_item s [: :] :];
                     `HVbox [: `S LR "end"; k :] :] :]
      | <:str_item< # $s$ $opt:x$ >> ->
          fun curr next _ k ->
            let s =
              "(* #" ^ s ^ " " ^
                (match x with
                 [ Some <:expr< $str:s$ >> -> "\"" ^ s ^ "\""
                 | _ -> "?" ]) ^
                " *)"
            in
            [: `S LR s :]
      | <:str_item< exception $c$ of $list:tl$ = $b$ >> ->
          fun curr next _ k ->
            match b with
            [ [] -> [: `variant 0 [: `S LR "exception" :] (loc, c, tl) k :]
            | _ ->
                [: `variant 0 [: `S LR "exception" :] (loc, c, tl)
                     [: `S LR "=" :];
                   mod_ident b k :] ]
      | <:str_item< include $me$ >> ->
          fun curr next _ k -> [: `S LR "include"; `module_expr me k :]
      | <:str_item< type $list:tdl$ >> ->
          fun curr next _ k -> [: `type_list [: `S LR "type" :] tdl k :]
      | <:str_item< value $rec:rf$ $list:pel$ >> ->
          fun curr next _ k ->
            [: `bind_list [: `S LR "value"; flag "rec" rf :] pel k :]
      | <:str_item< external $s$ : $t$ = $list:pl$ >> ->
          fun curr next _ k -> [: `external_def s t pl k :]
      | <:str_item< module $s$ = $me$ >> ->
          fun curr next _ k ->
            [: `module_binding [: `S LR "module"; `S LR s :] me k :]
      | <:str_item< module type $s$ = $mt$ >> ->
          fun curr next _ k ->
            [: `HVbox [: :];
               `HVbox
                  [: `HVbox
                        [: `S LR "module"; `S LR "type"; `S LR s;
                           `S LR "=" :];
                     `module_type mt [: :] :];
               k :]
      | MLast.StCls _ cd ->
          fun curr next _ k ->
            [: `HVbox [: :];
               listwbws class_declaration [: `S LR "class" :] (S LR "and") cd
                 k :]
      | MLast.StClt _ cd ->
          fun curr next _ k ->
            [: `HVbox [: :];
               listwbws class_type_declaration
                 [: `S LR "class"; `S LR "type" :] (S LR "and") cd k :] ]}];

(*
EXTEND_PRINTER
  pr_expr:
    [ "top" (fun e x -> LocInfo (MLast.loc_of_expr e) (HOVbox x))
      [ <:expr< let $rec:r$ $p1$ = $e1$ in $e$ >> ->
          let r = flag "rec" r in
          [: `Vbox
                [: `HVbox [: :];
                   `let_binding [: `S LR "let"; r :] (p1, e1)
                      [: `S LR "in" :];
                   `expr e k :] :]
      | <:expr< let $rec:r$ $list:pel$ in $e$ >> ->
          let r = flag "rec" r in
          [: `Vbox
                [: `HVbox [: :];
                   listwbws (fun b (p, e) k -> let_binding b (p, e) k)
                     [: `S LR "let"; r :] (S LR "and") pel [: `S LR "in" :];
                   `expr e k :] :] ] ]
  ;
END;
*)

pr_expr.pr_levels :=
  [{pr_label = "top"; pr_box e x = LocInfo (MLast.loc_of_expr e) (HOVbox x);
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< let $rec:r$ $p1$ = $e1$ in $e$ >> ->
          fun curr next _ k ->
            let r = flag "rec" r in
            [: `Vbox
                  [: `HVbox [: :];
                     `let_binding [: `S LR "let"; r :] (p1, e1)
                        [: `S LR "in" :];
                     `expr e k :] :]
      | <:expr< let $rec:r$ $list:pel$ in $e$ >> ->
          fun curr next _ k ->
            let r = flag "rec" r in
            [: `Vbox
                  [: `HVbox [: :];
                     listwbws (fun b (p, e) k -> let_binding b (p, e) k)
                       [: `S LR "let"; r :] (S LR "and") pel [: `S LR "in" :];
                     `expr e k :] :]
      | <:expr< let module $m$ = $mb$ in $e$ >> ->
          fun curr next _ k ->
            [: `HVbox
                  [: `HVbox [: :];
                     `module_binding
                        [: `S LR "let"; `S LR "module"; `S LR m :] mb
                        [: `S LR "in" :];
                     `expr e k :] :]
      | <:expr< fun [ $list:pel$ ] >> ->
          fun curr next _ k ->
            match pel with
            [ [] -> [: `S LR "fun"; `S LR "[]"; k :]
            | [(p, None, e)] ->
                if is_irrefut_patt p then
                  let (pl, e) = expr_fun_args e in
                  [: `BEbox
                        [: `HOVbox
                              [: `S LR "fun";
                                 list patt [p :: pl] [: `S LR "->" :] :];
                           `expr e k :] :]
                else
                  [: `HVbox [: `S LR "fun ["; `patt p [: `S LR "->" :] :];
                     `expr e [: `S LR "]"; k :] :]
            | _ ->
                [: `Vbox
                      [: `HVbox [: :]; `S LR "fun";
                         listwbws match_assoc [: `S LR "[" :] (S LR "|") pel
                           [: `S LR "]"; k :] :] :] ]
      | <:expr< match $e$ with $p1$ -> $e1$ >> when is_irrefut_patt p1 ->
          fun curr next _ k ->
            [: `BEbox
                  [: `S LR "match"; `expr e [: :];
                     `HVbox [: `S LR "with"; `patt p1 [: `S LR "->" :] :] :];
               `expr e1 k :]
      | <:expr< match $e$ with [ ] >> ->
          fun curr next _ k ->
            [: `HVbox [: :];
               `BEbox
                  [: `S LR "match"; `expr e [: :]; `S LR "with"; `S LR "[]";
                     k :] :]
      | <:expr< match $e$ with [ $list:pel$ ] >> ->
          fun curr next _ k ->
            [: `HVbox [: :];
               `BEbox [: `S LR "match"; `expr e [: :]; `S LR "with" :];
               `match_assoc_list pel k :]
      | <:expr< try $e$ with [ ] >> ->
          fun curr next _ k ->
            [: `HVbox [: :];
               `BEbox
                  [: `S LR "try"; `expr e [: :]; `S LR "with"; `S LR "[]";
                     k :] :]
      | <:expr< try $e$ with $p1$ -> $e1$ >> when is_irrefut_patt p1 ->
          fun curr next _ k ->
            [: `BEbox
                  [: `S LR "try"; `expr e [: :];
                     `HVbox [: `S LR "with"; `patt p1 [: `S LR "->" :] :] :];
               `expr e1 k :]
      | <:expr< try $e$ with [ $list:pel$ ] >> ->
          fun curr next _ k ->
            [: `HVbox [: :];
               `BEbox [: `S LR "try"; `expr e [: :]; `S LR "with" :];
               `match_assoc_list pel k :]
      | <:expr< if $_$ then () else raise (Assert_failure $_$) >> as e ->
          fun curr next _ k -> [: `next e "" k :]
      | <:expr< if $e1$ then $e2$ else $e3$ >> ->
          fun curr next _ k ->
            let (eel, e) =
              elseif e3 where rec elseif e =
                match e with
                [ <:expr< if $e1$ then $e2$ else $e3$ >> ->
                    let (eel, e) = elseif e3 in
                    ([(e1, e2) :: eel], e)
                | _ -> ([], e) ]
            in
            [: `HVbox
                  [: `HVbox [: :];
                     `ifbox [: `S LR "if" :] [: `expr e1 [: :] :]
                        [: `S LR "then" :] e2 [: :];
                     list
                       (fun (e1, e2) k ->
                          ifbox [: `HVbox [: `S LR "else"; `S LR "if" :] :]
                            [: `expr e1 [: :] :] [: `S LR "then" :] e2 k)
                       eel [: :];
                     `ifbox [: `S LR "else" :] [: :] [: :] e k :] :]
      | <:expr< do { $list:el$ } >> when old_sequences.val ->
          fun curr next _ k ->
            let (el, e) =
              match List.rev el with
              [ [e :: el] -> (List.rev el, e)
              | [] -> ([], <:expr< () >>) ]
            in
            [: `HOVCbox
                  [: `HVbox [: :];
                     `BEbox
                        [: `S LR "do";
                           `HVbox
                              [: `HVbox [: :];
                                 list (fun e k -> expr e [: `S RO ";"; k :])
                                   el [: :] :];
                           `S LR "return" :];
                     `expr e k :] :]
      | <:expr< do { $list:el$ } >> ->
          fun curr next _ k -> [: `sequence [: :] [: :] [: :] el k :]
      | <:expr< for $i$ = $e1$ $to:d$ $e2$ do { $list:el$ } >>
        when old_sequences.val ->
          fun curr next _ k ->
            let d = if d then "to" else "downto" in
            [: `BEbox
                  [: `HOVbox
                        [: `S LR "for"; `S LR i; `S LR "=";
                           `expr e1 [: `S LR d :];
                           `expr e2 [: `S LR "do" :] :];
                     `HVbox
                        [: `HVbox [: :];
                           list (fun e k -> expr e [: `S RO ";"; k :]) el
                             [: :] :];
                     `HVbox [: `S LR "done"; k :] :] :]
      | <:expr< for $i$ = $e1$ $to:d$ $e2$ do { $list:el$ } >> ->
          fun curr next _ k ->
            let d = if d then "to" else "downto" in
            [: `sequence
                  [: `HOVbox
                        [: `S LR "for"; `S LR i; `S LR "=";
                           `expr e1 [: `S LR d :]; `expr e2 [: :] :] :]
                  [: :] [: :] el k :]
      | <:expr< while $e1$ do { $list:el$ } >> when old_sequences.val ->
          fun curr next _ k ->
            [: `BEbox
                  [: `BEbox [: `S LR "while"; `expr e1 [: :]; `S LR "do" :];
                     `HVbox
                        [: `HVbox [: :];
                           list (fun e k -> expr e [: `S RO ";"; k :]) el
                             [: :] :];
                     `HVbox [: `S LR "done"; k :] :] :]
      | <:expr< while $e1$ do { $list:el$ } >> ->
          fun curr next _ k ->
            [: `sequence [: `S LR "while"; `expr e1 [: :] :] [: :] [: :] el
                  k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $x$ := $y$ >> ->
          fun curr next _ k -> [: `next x "" [: `S LR ":=" :]; `expr y k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox [: `HVbox [: :]; x :];
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:"||"$ $x$ $y$ >> ->
          fun curr next _ k -> [: `next x "" [: `S LR "||" :]; curr y "" k :]
      | <:expr< $lid:"or"$ $x$ $y$ >> ->
          fun curr next _ k -> [: `next x "" [: `S LR "||" :]; curr y "" k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox [: `HVbox [: :]; x :];
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:"&&"$ $x$ $y$ >> ->
          fun curr next _ k -> [: `next x "" [: `S LR "&&" :]; curr y "" k :]
      | <:expr< $lid:"&"$ $x$ $y$ >> ->
          fun curr next _ k -> [: `next x "" [: `S LR "&&" :]; curr y "" k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:op$ $x$ $y$ >> as e ->
          fun curr next _ k ->
            match op with
            [ "<" | ">" | "<=" | ">=" | "=" | "<>" | "==" | "!=" ->
                [: curr x "" [: `S LR op :]; `next y "" k :]
            | _ -> [: `next e "" k :] ]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:op$ $x$ $y$ >> as e ->
          fun curr next _ k ->
            match op with
            [ "^" | "@" -> [: `next x "" [: `S LR op :]; curr y "" k :]
            | _ -> [: `next e "" k :] ]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:op$ $x$ $y$ >> as e ->
          fun curr next _ k ->
            match op with
            [ "+" | "+." | "-" | "-." ->
                [: curr x "" [: `S LR op :]; `next y "" k :]
            | _ -> [: `next e "" k :] ]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:op$ $x$ $y$ >> as e ->
          fun curr next _ k ->
            match op with
            [ "*" | "/" | "*." | "/." | "land" | "lor" | "lxor" | "mod" ->
                [: curr x "" [: `S LR op :]; `next y "" k :]
            | _ -> [: `next e "" k :] ]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:op$ $x$ $y$ >> as e ->
          fun curr next _ k ->
            match op with
            [ "**" | "asr" | "lsl" | "lsr" ->
                [: `next x "" [: `S LR op :]; curr y "" k :]
            | _ -> [: `next e "" k :] ]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $lid:"~-"$ $x$ >> ->
          fun curr next _ k -> [: `S LR "-"; curr x "" k :]
      | <:expr< $lid:"~-."$ $x$ >> ->
          fun curr next _ k -> [: `S LR "-."; curr x "" k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $int:x$ >> -> fun curr next _ k -> [: `S LR x; k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = "apply"; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< [$_$ :: $_$] >> as e ->
          fun curr next _ k -> [: `next e "" k :]
      | <:expr< Pervasives.ref (Lazy.Delayed (fun () -> $x$)) >> ->
          fun curr next _ k -> [: `S LR "lazy"; `next x "" k :]
      | <:expr< if $e$ then () else raise (Assert_failure $_$) >> ->
          fun curr next _ k -> [: `S LR "assert"; `next e "" k :]
      | <:expr< raise (Assert_failure $_$) >> ->
          fun curr next _ k -> [: `S LR "assert"; `S LR "False"; k :]
      | <:expr< $lid:n$ $x$ $y$ >> as e ->
          fun curr next _ k ->
            if is_infix n then [: `next e "" k :]
            else [: curr <:expr< $lid:n$ $x$ >> "" [: :]; `next y "" k :]
      | <:expr< $x$ $y$ >> ->
          fun curr next _ k -> [: curr x "" [: :]; `next y "" k :]
      | MLast.ExNew _ sl ->
          fun curr next _ k -> [: `S LR "new"; `class_longident sl k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = "dot"; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $x$ . ( $y$ ) >> ->
          fun curr next _ k ->
            [: curr x "" [: :]; `S NO ".("; `expr y [: `S RO ")"; k :] :]
      | <:expr< $x$ . [ $y$ ] >> ->
          fun curr next _ k ->
            [: curr x "" [: :]; `S NO ".["; `expr y [: `S RO "]"; k :] :]
      | <:expr< $e1$ . $e2$ >> ->
          fun curr next _ k -> [: curr e1 "" [: :]; `S NO "."; curr e2 "" k :]
      | <:expr< $e$ # $lab$ >> ->
          fun curr next _ k -> [: curr e "" [: :]; `S NO "#"; `label lab; k :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]};
   {pr_label = "simple";
    pr_box e x = LocInfo (MLast.loc_of_expr e) (HOVbox x);
    pr_rules =
      extfun Extfun.empty with
      [ <:expr< $int:x$ >> ->
          fun curr next _ k ->
            if x.[0] = '-' then [: `S LO "("; `S LR x; `S RO ")"; k :]
            else [: `S LR x; k :]
      | <:expr< $flo:x$ >> ->
          fun curr next _ k ->
            if x.[0] = '-' then [: `S LO "("; `S LR x; `S RO ")"; k :]
            else [: `S LR x; k :]
      | <:expr< $str:s$ >> ->
          fun curr next _ k -> [: `S LR ("\"" ^ s ^ "\""); k :]
      | <:expr< $chr:c$ >> ->
          fun curr next _ k -> [: `S LR ("'" ^ c ^ "'"); k :]
      | <:expr< $uid:s$ >> -> fun curr next _ k -> [: `S LR s; k :]
      | <:expr< $lid:s$ >> ->
          fun curr next _ k -> [: `S LR (var_escaped s); k :]
      | <:expr< ` $i$ >> -> fun curr next _ k -> [: `S LR ("`" ^ i); k :]
      | <:expr< ~ $i$ : $lid:j$ >> when i = j ->
          fun curr next _ k -> [: `S LR ("~" ^ i); k :]
      | <:expr< ~ $i$ : $e$ >> ->
          fun curr next _ k -> [: `S LO ("~" ^ i ^ ":"); curr e "" k :]
      | <:expr< ? $i$ : $lid:j$ >> when i = j ->
          fun curr next _ k -> [: `S LR ("?" ^ i); k :]
      | <:expr< ? $i$ : $e$ >> ->
          fun curr next _ k -> [: `S LO ("?" ^ i ^ ":"); curr e "" k :]
      | <:expr< [$_$ :: $_$] >> as e ->
          fun curr next _ k ->
            let (el, c) =
              make_list e where rec make_list e =
                match e with
                [ <:expr< [$e$ :: $y$] >> ->
                    let (el, c) = make_list y in
                    ([e :: el], c)
                | <:expr< [] >> -> ([], None)
                | x -> ([], Some e) ]
            in
            match c with
            [ None ->
                [: `S LO "["; listws expr (S RO ";") el [: `S RO "]"; k :] :]
            | Some x ->
                [: `S LO "["; listws expr (S RO ";") el [: `S LR "::" :];
                   `expr x [: `S RO "]"; k :] :] ]
      | <:expr< [| $list:el$ |] >> ->
          fun curr next _ k ->
            [: `S LR "[|"; listws expr (S RO ";") el [: `S LR "|]"; k :] :]
      | <:expr< { $list:fel$ } >> ->
          fun curr next _ k ->
            [: `S LO "{";
               listws
                 (fun (lab, e) k ->
                    HVbox [: let_binding0 [: `patt lab [: :] :] e k :])
                 (S RO ";") fel [: `S RO "}"; k :] :]
      | <:expr< { ($e$) with $list:fel$ } >> ->
          fun curr next _ k ->
            [: `HVbox
                  [: `S LO "{"; `S LO "(";
                     `expr e [: `S RO ")"; `S LR "with" :] :];
               listws
                 (fun (lab, e) k ->
                    HVbox [: `patt lab [: `S LR "=" :]; `expr e k :])
                 (S RO ";") fel [: `S RO "}"; k :] :]
      | <:expr< ($e$ : $t$) >> ->
          fun curr next _ k ->
            [: `S LO "("; `expr e [: `S LR ":" :];
               `ctyp t [: `S RO ")"; k :] :]
      | <:expr< ($e$ : $t1$ :> $t2$) >> ->
          fun curr next _ k ->
            [: `S LO "("; `expr e [: `S LR ":" :];
               `ctyp t1 [: `S LR ":>" :]; `ctyp t2 [: `S RO ")"; k :] :]
      | <:expr< ($e$ :> $t2$) >> ->
          fun curr next _ k ->
            [: `S LO "("; `expr e [: `S LR ":>" :];
               `ctyp t2 [: `S RO ")"; k :] :]
      | MLast.ExOvr _ [] -> fun curr next _ k -> [: `S LR "{< >}"; k :]
      | MLast.ExOvr _ fel ->
          fun curr next _ k ->
            [: `S LR "{<";
               listws field_expr (S RO ";") fel [: `S LR ">}"; k :] :]
      | <:expr< ($list:el$) >> ->
          fun curr next _ k ->
            [: `S LO "("; listws expr (S RO ",") el [: `S RO ")"; k :] :]
      | <:expr< $_$ $_$ >> | <:expr< $uid:_$ $_$ $_$ >> |
        <:expr< $_$ . $_$ >> | <:expr< $_$ # $_$ >> |
        <:expr< fun [ $list:_$ ] >> | <:expr< match $_$ with [ $list:_$ ] >> |
        <:expr< try $_$ with [ $list:_$ ] >> |
        <:expr< if $_$ then $_$ else $_$ >> | <:expr< do { $list:_$ } >> |
        <:expr< for $_$ = $_$ $to:_$ $_$ do { $list:_$ } >> |
        <:expr< while $_$ do { $list:_$ } >> |
        <:expr< let $rec:_$ $list:_$ in $_$ >> | MLast.ExNew _ _ as e ->
          fun curr next _ k ->
            [: `S LO "("; `expr e [: `HVbox [: `S RO ")"; k :] :] :]
      | e -> fun curr next _ k -> [: `next e "" k :] ]}];

pr_patt.pr_levels :=
  [{pr_label = "top"; pr_box _ x = HOVbox [: `HVbox [: :]; x :];
    pr_rules =
      extfun Extfun.empty with
      [ <:patt< $x$ | $y$ >> ->
          fun curr next _ k -> [: curr x "" [: `S LR "|" :]; `next y "" k :]
      | p -> fun curr next _ k -> [: `next p "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox [: `HVbox [: :]; x :];
    pr_rules =
      extfun Extfun.empty with
      [ <:patt< $x$ .. $y$ >> ->
          fun curr next _ k -> [: curr x "" [: `S NO ".." :]; `next y "" k :]
      | p -> fun curr next _ k -> [: `next p "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:patt< [$_$ :: $_$] >> as p ->
          fun curr next _ k -> [: `next p "" k :]
      | <:patt< $x$ $y$ >> ->
          fun curr next _ k -> [: curr x "" [: :]; `next y "" k :]
      | p -> fun curr next _ k -> [: `next p "" k :] ]};
   {pr_label = ""; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:patt< $x$ . $y$ >> ->
          fun curr next _ k -> [: curr x "" [: `S NO "." :]; `next y "" k :]
      | p -> fun curr next _ k -> [: `next p "" k :] ]};
   {pr_label = "simple"; pr_box _ x = HOVbox x;
    pr_rules =
      extfun Extfun.empty with
      [ <:patt< [$_$ :: $_$] >> as p ->
          fun curr next _ k ->
            let (pl, c) =
              make_list p where rec make_list p =
                match p with
                [ <:patt< [$p$ :: $y$] >> ->
                    let (pl, c) = make_list y in
                    ([p :: pl], c)
                | <:patt< [] >> -> ([], None)
                | x -> ([], Some p) ]
            in
            [: `HOVCbox
                  [: `S LO "[";
                     let rec glop pl k =
                       match pl with
                       [ [] -> failwith "simple_patt"
                       | [p] ->
                           match c with
                           [ None -> [: `patt p k :]
                           | Some x ->
                               [: `patt p [: `S LR "::" :]; `patt x k :] ]
                       | [p :: pl] ->
                           [: `patt p [: `S RO ";" :]; glop pl k :] ]
                     in
                     glop pl [: `S RO "]"; k :] :] :]
      | <:patt< [| $list:pl$ |] >> ->
          fun curr next _ k ->
            [: `S LR "[|"; listws patt (S RO ";") pl [: `S LR "|]"; k :] :]
      | <:patt< { $list:fpl$ } >> ->
          fun curr next _ k ->
            [: `HVbox
                  [: `S LO "{";
                     listws
                       (fun (lab, p) k ->
                          HVbox [: `patt lab [: `S LR "=" :]; `patt p k :])
                       (S RO ";") fpl [: `S RO "}"; k :] :] :]
      | <:patt< ($list:[p::pl]$) >> ->
          fun curr next _ k ->
            [: `HOVCbox
                  [: `S LO "(";
                     listws patt (S RO ",") [p :: pl] [: `S RO ")"; k :] :] :]
      | <:patt< ($p$ : $ct$) >> ->
          fun curr next _ k ->
            [: `S LO "("; `patt p [: `S LR ":" :];
               `ctyp ct [: `S RO ")"; k :] :]
      | <:patt< ($x$ as $y$) >> ->
          fun curr next _ k ->
            [: `S LO "("; `patt x [: `S LR "as" :];
               `patt y [: `S RO ")"; k :] :]
      | <:patt< $int:s$ >> -> fun curr next _ k -> [: `S LR s; k :]
      | <:patt< $flo:s$ >> -> fun curr next _ k -> [: `S LR s; k :]
      | <:patt< $str:s$ >> ->
          fun curr next _ k -> [: `S LR ("\"" ^ s ^ "\""); k :]
      | <:patt< $chr:c$ >> ->
          fun curr next _ k -> [: `S LR ("'" ^ c ^ "'"); k :]
      | <:patt< $lid:s$ >> ->
          fun curr next _ k -> [: `S LR (var_escaped s); k :]
      | <:patt< $uid:s$ >> -> fun curr next _ k -> [: `S LR s; k :]
      | <:patt< ` $i$ >> -> fun curr next _ k -> [: `S LR ("`" ^ i); k :]
      | <:patt< # $list:sl$ >> ->
          fun curr next _ k -> [: `S LO "#"; mod_ident sl k :]
      | <:patt< ~ $i$ : $p$ >> ->
          fun curr next _ k -> [: `S LO ("~" ^ i ^ ":"); curr p "" k :]
      | <:patt< ? $i$ : ($p$ : $t$) >> ->
          fun curr next _ k ->
            [: `S LO ("?"^ i ^ ":"); `S LO "("; `patt p [: `S LR ":" :];
               `ctyp t [: `S RO ")"; k :] :]
      | <:patt< ? $i$ : ($p$) >> ->
          fun curr next _ k ->
            match p with
            [ <:patt< $lid:x$ >> when i = x -> [: `S LR ("?" ^ i); k :]
            | _ ->
                [: `S LO ("?"^ i ^ ":"); `S LO "("; `patt p [: `S RO ")";
                   k :] :] ]
      | <:patt< ? $i$ : ($p$ : $t$ = $e$) >> ->
          fun curr next _ k ->
            match p with
            [ <:patt< $lid:x$ >> when i = x ->
                [: `S LO "?"; `S LO "("; `patt p [: `S LR ":" :];
                   `ctyp t [: `S LR "=" :]; `expr e [: `S RO ")"; k :] :]
            | _ ->
                [: `S LO ("?" ^ i ^ ":"); `S LO "("; `patt p [: `S LR ":" :];
                   `ctyp t [: `S LR "=" :]; `expr e [: `S RO ")"; k :] :] ]
      | <:patt< ? $i$ : ($p$ = $e$) >> ->
          fun curr next _ k ->
            match p with
            [ <:patt< $lid:x$ >> when i = x ->
                [: `S LO "?"; `S LO "("; `patt p [: `S LR "=" :];
                   `expr e [: `S RO ")"; k :] :]
            | _ ->
                [: `S LO ("?" ^ i ^ ":"); `S LO "("; `patt p [: `S LR "=" :];
                   `expr e [: `S RO ")"; k :] :] ]
      | <:patt< _ >> -> fun curr next _ k -> [: `S LR "_"; k :]
      | <:patt< $_$ $_$ >> | <:patt< $_$ .. $_$ >>
      | <:patt< $_$ | $_$ >> as p ->
          fun curr next _ k ->
            [: `S LO "("; `patt p [: `HVbox [: `S RO ")"; k :] :] :]
      | p -> fun curr next _ k -> [: `next p "" k :] ]}];

value output_string_eval oc s =
  loop 0 where rec loop i =
    if i == String.length s then ()
    else if i == String.length s - 1 then output_char oc s.[i]
    else
      match (s.[i], s.[i + 1]) with
      [ ('\\', 'n') -> do { output_char oc '\n'; loop (i + 2) }
      | (c, _) -> do { output_char oc c; loop (i + 1) } ]
;

value maxl = ref 78;
value sep = ref None;
value ncip = ref False;
value comm_after = ref False;
value type_comm = ref False;
value delayed_comm = ref "";

value copy_after oc s =
  let s =
    try
      let i = String.index s '\n' in
      do {
        output_string oc (String.sub s 0 i);
        String.sub s i (String.length s - i)
      }
    with
    [ Not_found -> s ]
  in
  do {
    output_string oc delayed_comm.val;
    let len = String.length s in
    let i =
      if len > 4 && String.sub s (len - 3) 3 = "*)\n"
      then
        loop (len - 6) where rec loop i =
          if i >= 0 then
            if String.sub s i 5 = "\n(** " then i + 1 else loop (i - 1)
          else len
      else len
    in
    output_string oc (String.sub s 0 i);
    delayed_comm.val :=
      if i < len then "\n" ^ String.sub s i (len - i - 1)
      else String.sub s i (len - i)
  }
;

value input_from_next_bol ic bol len =
  let buff = Buffer.create 20 in
  loop bol 0 where rec loop bol_found i =
    if i = len then Buffer.contents buff
    else
      let c = input_char ic in
      let bol_found = bol_found || c = '\n' in
      do {
        if bol_found then Buffer.add_char buff c else ();
        loop bol_found (i + 1)
      }
;

value copy_source ic oc first bp ep =
  match sep.val with
  [ Some str ->
      if first then ()
      else if ep == in_channel_length ic then output_string oc "\n"
      else output_string_eval oc str
  | None ->
      do {
        seek_in ic bp;
        let s = input_from_next_bol ic first (ep - bp) in
        if not comm_after.val then output_string oc s
        else copy_after oc s
      } ]
;

value copy_to_end ic oc first bp =
  let ilen = in_channel_length ic in
  if bp < ilen then copy_source ic oc first bp ilen
  else output_string oc "\n"
;

module Buff =
  struct
    value buff = ref (String.create 80);
    value store len x =
      do {
        if len >= String.length buff.val then
          buff.val := buff.val ^ String.create (String.length buff.val)
        else ();
        buff.val.[len] := x;
        succ len
      }
    ;
    value mstore len s =
      add_rec len 0 where rec add_rec len i =
        if i == String.length s then len
        else add_rec (store len s.[i]) (succ i)
    ;
    value get len = String.sub buff.val 0 len;
  end
;

value extract_comment strm =
  let rec find_comm sp_cnt =
    parser
    [ [: `'('; a = find_star sp_cnt :] -> a
    | [: `' '; s :] -> find_comm (sp_cnt + 1) s
    | [: `_; s :] -> find_comm 0 s
    | [: :] -> "" ]
  and find_star sp_cnt =
    parser
    [ [: `'*';
         a = insert (Buff.mstore 0 (String.make sp_cnt ' ' ^ "(*")) :] -> a
    | [: a = find_comm 0 :] -> a ]
  and insert len =
    parser
    [ [: `'*'; a = rparen (Buff.store len '*') :] -> a
    | [: `x; s :] -> insert (Buff.store len x) s
    | [: :] -> "" ]
  and rparen len =
    parser
    [ [: `')'; s :] -> if_newline (Buff.store len ')') s
    | [: a = insert len :] -> a ]
  and if_newline len =
    parser
    [ [: `'\n'; a = while_space (Buff.store len '\n') :] -> a
    | [: :] -> " " ^ Buff.get len ]
  and while_space len =
    parser
    [ [: `(' ' as c); a = while_space (Buff.store len c) :] -> a
    | [: `'\n'; a = while_space len :] -> a
    | [: :] -> Buff.get len ]
  in
  find_comm 0 strm
;

value print_comment ic oc last_ep (bp, ep) =
  if bp > last_ep.val then do {
    seek_in ic last_ep.val;
    let strm =
      Stream.from
        (fun i -> if i = bp - last_ep.val then None else Some (input_char ic))
    in
    match extract_comment strm with
    [ "" -> ()
    | s -> output_string oc s ];
    last_ep.val := last_ep.val + Stream.count strm
  }
  else ()
;

value apply_printer printer ast =
  let oc =
    match Pcaml.output_file.val with
    [ Some f -> open_out_bin f
    | None -> stdout ]
  in
  let cleanup () =
    match Pcaml.output_file.val with
    [ Some _ -> close_out oc
    | None -> () ]
  in
  let pr_ch = output_char oc in
  let pr_str = output_string oc in
  let pr_nl () = output_char oc '\n' in
  if Pcaml.input_file.val <> "-" && Pcaml.input_file.val <> "" then do {
    let ic = open_in_bin Pcaml.input_file.val in
    let last_ep = ref 0 in
    let prcom =
      if not ncip.val && sep.val = None then print_comment ic oc last_ep
      else fun _ -> ()
    in
    try
      do {
        input_file_ic.val := if type_comm.val then Some ic else None;
        let (first, last_pos) =
          List.fold_left
            (fun (first, last_pos) (si, (bp, ep)) ->
               do {
                 copy_source ic oc first last_pos bp;
                 flush oc;
                 last_ep.val := bp;
                 print_pretty pr_ch pr_str pr_nl "" "" maxl.val prcom
                   (printer si [: :]);
                 flush oc;
                 (False, ep)
               })
            (True, 0) ast
        in
        copy_to_end ic oc first last_pos;
        flush oc
      }
    with x ->
      do { close_in ic; input_file_ic.val := None; cleanup (); raise x };
    close_in ic;
    input_file_ic.val := None;
    cleanup ()
  }
  else do {
    List.iter
      (fun (si, _) ->
         do {
           print_pretty pr_ch pr_str pr_nl "" "" maxl.val (fun _ -> ())
             (printer si [: :]);
           match sep.val with
           [ Some str -> output_string_eval oc str
           | None -> output_char oc '\n' ];
           flush oc
         })
      ast;
    cleanup ()
  }
;

Pcaml.print_interf.val := apply_printer sig_item;
Pcaml.print_implem.val := apply_printer str_item;

Pcaml.add_option "-l" (Arg.Int (fun x -> maxl.val := x))
  "<length>   Maximum line length for pretty printing.";

Pcaml.add_option "-sep" (Arg.String (fun x -> sep.val := Some x))
  "<string> Use this string between phrases instead of reading source.";

Pcaml.add_option "-ncip" (Arg.Set ncip) "        No comments in phrases.";

Pcaml.add_option "-old_seq" (Arg.Set old_sequences)
  "     Pretty print with old syntax for sequences.";

Pcaml.add_option "-ca" (Arg.Set comm_after)
  "          Put the ocamldoc comments after declarations.";

Pcaml.add_option "-tc" (Arg.Set type_comm)
  "          Add the comments inside sum and record types.";
