(* camlp4r *)
(* $Id$ *)

(*
Added statements:

  At toplevel (structure item):

     DEFINE <uident>
     DEFINE <uident> = <expression>
     DEFINE <uident> (<parameters>) = <expression>
     IFDEF <uident> THEN <structure_items> (END | ENDIF)
     IFDEF <uident> THEN <structure_items> ELSE <structure_items> (END | ENDIF)
     IFNDEF <uident> THEN <structure_items> (END | ENDIF)
     IFNDEF <uident> THEN <structure_items> ELSE <structure_items> (END | ENDIF)

  In expressions:

     IFDEF <uident> THEN <expression> ELSE <expression> (END | ENDIF)
     IFNDEF <uident> THEN <expression> ELSE <expression> (END | ENDIF)
     __FILE__
     __LOCATION__

  In patterns:

     IFDEF <uident> THEN <pattern> ELSE <pattern> (END | ENDIF)
     IFNDEF <uident> THEN <pattern> ELSE <pattern> (END | ENDIF)

  As Camlp4 options:

     -D<uident>
     -U<uident>

  After having used a DEFINE <uident> followed by "= <expression>", you
  can use it in expressions *and* in patterns. If the expression defining
  the macro cannot be used as a pattern, there is an error message if
  it is used in a pattern.

  The expression __FILE__ returns the current compiled file name.
  The expression __LOCATION__ returns the current location of itself.

*)

#load "pa_extend.cmo";
#load "q_MLast.cmo";

open Pcaml;

type item_or_def 'a =
  [ SdStr of 'a
  | SdDef of string and option (list string * MLast.expr)
  | SdUnd of string
  | SdITE of string and list (item_or_def 'a) and list (item_or_def 'a) ]
;

value rec list_remove x =
  fun
  [ [(y, _) :: l] when y = x -> l
  | [d :: l] -> [d :: list_remove x l]
  | [] -> [] ]
;

value defined = ref [];

value is_defined i = List.mem_assoc i defined.val;

value loc =
    let nowhere =
      { (Lexing.dummy_pos) with Lexing.pos_lnum = 1; Lexing.pos_cnum = 0 } in
    (nowhere, nowhere);

value subst mloc env =
  loop where rec loop =
    fun
    [ <:expr< let $opt:rf$ $list:pel$ in $e$ >> ->
        let pel = List.map (fun (p, e) -> (p, loop e)) pel in
        <:expr< let $opt:rf$ $list:pel$ in $loop e$ >>
    | <:expr< if $e1$ then $e2$ else $e3$ >> ->
         <:expr< if $loop e1$ then $loop e2$ else $loop e3$ >>
    | <:expr< $e1$ $e2$ >> -> <:expr< $loop e1$ $loop e2$ >>
    | <:expr< $lid:x$ >> | <:expr< $uid:x$ >> as e ->
        try <:expr< $anti:List.assoc x env$ >> with
        [ Not_found -> e ]
    | <:expr< ($list:x$) >> -> <:expr< ($list:List.map loop x$) >>
    | <:expr< { $list:pel$ } >> ->
        let pel = List.map (fun (p, e) -> (p, loop e)) pel in
        <:expr< { $list:pel$ } >>
    | e -> e ]
;

value substp mloc env =
  loop where rec loop =
    fun
    [ <:expr< $e1$ $e2$ >> -> <:patt< $loop e1$ $loop e2$ >>
    | <:expr< $lid:x$ >> ->
        try <:patt< $anti:List.assoc x env$ >> with
        [ Not_found -> <:patt< $lid:x$ >> ]
    | <:expr< $uid:x$ >> ->
        try <:patt< $anti:List.assoc x env$ >> with
        [ Not_found -> <:patt< $uid:x$ >> ]
    | <:expr< $int:x$ >> -> <:patt< $int:x$ >>
    | <:expr< $str:s$ >> -> <:patt< $str:s$ >>
    | <:expr< ($list:x$) >> -> <:patt< ($list:List.map loop x$) >>
    | <:expr< { $list:pel$ } >> ->
        let ppl = List.map (fun (p, e) -> (p, loop e)) pel in
        <:patt< { $list:ppl$ } >>
    | x ->
        Stdpp.raise_with_loc mloc
          (Failure
             "this macro cannot be used in a pattern (see its definition)") ]
;

value incorrect_number loc l1 l2 =
  Stdpp.raise_with_loc loc
    (Failure
       (Printf.sprintf "expected %d parameters; found %d"
          (List.length l2) (List.length l1)))
;

value define eo x =
  do {
    match eo with
    [ Some ([], e) ->
        EXTEND
          expr: LEVEL "simple"
            [ [ UIDENT $x$ -> Pcaml.expr_reloc (fun _ -> loc) (fst loc) e ] ]
          ;
          patt: LEVEL "simple"
            [ [ UIDENT $x$ ->
                  let p = substp loc [] e in
                  Pcaml.patt_reloc (fun _ -> loc) (fst loc) p ] ]
          ;
        END
    | Some (sl, e) ->
        EXTEND
          expr: LEVEL "apply"
            [ [ UIDENT $x$; param = SELF ->
                  let el =
                    match param with
                    [ <:expr< ($list:el$) >> -> el
                    | e -> [e] ]
                  in
                  if List.length el = List.length sl then
                    let env = List.combine sl el in
                    let e = subst loc env e in
                    Pcaml.expr_reloc (fun _ -> loc) (fst loc) e
                  else
                    incorrect_number loc el sl ] ]
          ;
          patt: LEVEL "simple"
            [ [ UIDENT $x$; param = SELF ->
                  let pl =
                    match param with
                    [ <:patt< ($list:pl$) >> -> pl
                    | p -> [p] ]
                  in
                  if List.length pl = List.length sl then
                    let env = List.combine sl pl in
                    let p = substp loc env e in
                    Pcaml.patt_reloc (fun _ -> loc) (fst loc) p
                  else
                    incorrect_number loc pl sl ] ]
          ;
        END
    | None -> () ];
    defined.val := [(x, eo) :: defined.val];
  }
;

value undef x =
  try
    do {
      let eo = List.assoc x defined.val in
      match eo with
      [ Some ([], _) ->
          do {
            DELETE_RULE expr: UIDENT $x$ END;
            DELETE_RULE patt: UIDENT $x$ END;
          }
      | Some (_, _) ->
          do {
            DELETE_RULE expr: UIDENT $x$; SELF END;
            DELETE_RULE patt: UIDENT $x$; SELF END;
          }
      | None -> () ];
      defined.val := list_remove x defined.val;
    }
  with
  [ Not_found -> () ]
;

value rec execute_macro = fun
[ SdStr i -> [i]
| SdDef x eo -> do { define eo x; [] }
| SdUnd x -> do { undef x; [] }
| SdITE i l1 l2 ->
   execute_macro_list (if is_defined i then l1 else l2) ]

and execute_macro_list = fun
[ [] -> []
| [hd::tl] -> (* The eveluation order is important here *)
  let il1 = execute_macro hd in
  let il2 = execute_macro_list tl in
    il1 @ il2 ]
; 

EXTEND
  GLOBAL: expr patt str_item sig_item;
  str_item: FIRST
    [ [ x = macro_def ->
          match execute_macro x with
          [ [si] -> si
          | sil -> <:str_item< declare $list:sil$ end >> ] ] ]
  ;
  macro_def:
    [ [ "DEFINE"; i = uident; def = opt_macro_value -> SdDef i def
      | "UNDEF"; i = uident -> SdUnd i
      | "IFDEF"; i = uident; "THEN"; dl = smlist; _ = endif ->
          SdITE i dl []
      | "IFDEF"; i = uident; "THEN"; dl1 = smlist; "ELSE";
        dl2 = smlist; _ = endif ->
          SdITE i dl1 dl2
      | "IFNDEF"; i = uident; "THEN"; dl = smlist; _ = endif ->
          SdITE i [] dl
      | "IFNDEF"; i = uident; "THEN"; dl1 = smlist; "ELSE";
        dl2 = smlist; _ = endif ->
          SdITE i dl2 dl1 ] ]
  ;
  smlist:
    [ [ sml = LIST1 str_item_or_macro -> sml ] ]
  ;
    endif:
      [ [ "END" -> ()
        | "ENDIF" -> () ] ]
    ;
  str_item_or_macro:
    [ [ d = macro_def -> d
      | si = str_item -> SdStr si ] ]
  ;
  opt_macro_value:
    [ [ "("; pl = LIST1 LIDENT SEP ","; ")"; "="; e = expr -> Some (pl, e)
      | "="; e = expr -> Some ([], e)
      | -> None ] ]
  ;
  expr: LEVEL "top"
    [ [ "IFDEF"; i = uident; "THEN"; e1 = expr; "ELSE"; e2 = expr; _ = endif ->
          if is_defined i then e1 else e2
      | "IFNDEF"; i = uident; "THEN"; e1 = expr; "ELSE"; e2 = expr; _ = endif ->
          if is_defined i then e2 else e1 ] ]
  ;
  expr: LEVEL "simple"
    [ [ LIDENT "__FILE__" -> <:expr< $str:Pcaml.input_file.val$ >>
      | LIDENT "__LOCATION__" ->
          let bp = string_of_int ((fst loc).Lexing.pos_cnum) in
          let ep = string_of_int ((snd loc).Lexing.pos_cnum) in
          <:expr< ($int:bp$, $int:ep$) >> ] ]
  ;
  patt:
    [ [ "IFDEF"; i = uident; "THEN"; p1 = patt; "ELSE"; p2 = patt; _ = endif ->
          if is_defined i then p1 else p2
      | "IFNDEF"; i = uident; "THEN"; p1 = patt; "ELSE"; p2 = patt; _ = endif ->
          if is_defined i then p2 else p1 ] ]
  ;
  uident:
    [ [ i = UIDENT -> i ] ]
  ;
END;

Pcaml.add_option "-D" (Arg.String (define None))
  "<string> Define for IFDEF instruction."
;
Pcaml.add_option "-U" (Arg.String undef)
  "<string> Undefine for IFDEF instruction."
;
