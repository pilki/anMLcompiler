(* camlp4r pa_extend.cmo *)
(***********************************************************************)
(*                                                                     *)
(*                             Camlp4                                  *)
(*                                                                     *)
(*        Daniel de Rauglaudre, projet Cristal, INRIA Rocquencourt     *)
(*                                                                     *)
(*  Copyright 2002 Institut National de Recherche en Informatique et   *)
(*  Automatique.  Distributed only by permission.                      *)
(*                                                                     *)
(***********************************************************************)

(* This file has been generated by program: do not edit! *)

let version = Sys.ocaml_version;;

let syntax_name = ref "";;

let gram =
  Grammar.gcreate
    {Token.tok_func = (fun _ -> failwith "no loaded parsing module");
     Token.tok_using = (fun _ -> ()); Token.tok_removing = (fun _ -> ());
     Token.tok_match = (fun _ -> raise (Match_failure ("", 23, 23)));
     Token.tok_text = (fun _ -> ""); Token.tok_comm = None}
;;

let interf = Grammar.Entry.create gram "interf";;
let implem = Grammar.Entry.create gram "implem";;
let top_phrase = Grammar.Entry.create gram "top_phrase";;
let use_file = Grammar.Entry.create gram "use_file";;
let sig_item = Grammar.Entry.create gram "sig_item";;
let str_item = Grammar.Entry.create gram "str_item";;
let module_type = Grammar.Entry.create gram "module_type";;
let module_expr = Grammar.Entry.create gram "module_expr";;
let expr = Grammar.Entry.create gram "expr";;
let patt = Grammar.Entry.create gram "patt";;
let ctyp = Grammar.Entry.create gram "type";;
let let_binding = Grammar.Entry.create gram "let_binding";;
let type_declaration = Grammar.Entry.create gram "type_declaration";;

let class_sig_item = Grammar.Entry.create gram "class_sig_item";;
let class_str_item = Grammar.Entry.create gram "class_str_item";;
let class_type = Grammar.Entry.create gram "class_type";;
let class_expr = Grammar.Entry.create gram "class_expr";;

let parse_interf = ref (Grammar.Entry.parse interf);;
let parse_implem = ref (Grammar.Entry.parse implem);;

let rec skip_to_eol cs =
  match Stream.peek cs with
    Some '\n' -> ()
  | Some c -> Stream.junk cs; skip_to_eol cs
  | _ -> ()
;;
let sync = ref skip_to_eol;;

let input_file = ref "";;
let output_file = ref None;;

let warning_default_function (bp, ep) txt =
  let c1 = bp.Lexing.pos_cnum - bp.Lexing.pos_bol in
  let c2 = ep.Lexing.pos_cnum - bp.Lexing.pos_bol in
  Printf.eprintf "<W> File \"%s\", line %d, chars %d-%d: %s\n"
    bp.Lexing.pos_fname bp.Lexing.pos_lnum c1 c2 txt;
  flush stderr
;;

let warning = ref warning_default_function;;

let apply_with_var v x f =
  let vx = !v in
  try v := x; let r = f () in v := vx; r with
    e -> v := vx; raise e
;;

List.iter (fun (n, f) -> Quotation.add n f)
  ["id", Quotation.ExStr (fun _ s -> "$0:" ^ s ^ "$");
   "string", Quotation.ExStr (fun _ s -> "\"" ^ String.escaped s ^ "\"")];;

let quotation_dump_file = ref (None : string option);;

type err_ctx =
    Finding
  | Expanding
  | ParsingResult of MLast.loc * string
  | Locating
;;
exception Qerror of string * err_ctx * exn;;

let expand_quotation loc expander shift name str =
  let new_warning =
    let warn = !warning in
    fun (bp, ep) txt -> warn (Reloc.adjust_loc shift (bp, ep)) txt
  in
  apply_with_var warning new_warning
    (fun () ->
       try expander str with
         Stdpp.Exc_located (loc, exc) ->
           let exc1 = Qerror (name, Expanding, exc) in
           raise
             (Stdpp.Exc_located
                (Reloc.adjust_loc shift (Reloc.linearize loc), exc1))
       | exc ->
           let exc1 = Qerror (name, Expanding, exc) in
           raise (Stdpp.Exc_located (loc, exc1)))
;;

let parse_quotation_result entry loc shift name str =
  let cs = Stream.of_string str in
  try Grammar.Entry.parse entry cs with
    Stdpp.Exc_located (iloc, (Qerror (_, Locating, _) as exc)) ->
      raise (Stdpp.Exc_located (Reloc.adjust_loc shift iloc, exc))
  | Stdpp.Exc_located (iloc, Qerror (_, Expanding, exc)) ->
      let ctx = ParsingResult (iloc, str) in
      let exc1 = Qerror (name, ctx, exc) in
      raise (Stdpp.Exc_located (loc, exc1))
  | Stdpp.Exc_located (_, (Qerror (_, _, _) as exc)) ->
      raise (Stdpp.Exc_located (loc, exc))
  | Stdpp.Exc_located (iloc, exc) ->
      let ctx = ParsingResult (iloc, str) in
      let exc1 = Qerror (name, ctx, exc) in
      raise (Stdpp.Exc_located (loc, exc1))
;;

let ghostify (bp, ep) =
  let ghost p = {p with Lexing.pos_cnum = 0} in ghost bp, ghost ep
;;

let handle_quotation loc proj in_expr entry reloc (name, str) =
  let shift =
    match name with
      "" -> String.length "<<"
    | _ -> String.length "<:" + String.length name + String.length "<"
  in
  let shift = Reloc.shift_pos shift (fst loc) in
  let expander =
    try Quotation.find name with
      exc ->
        let exc1 = Qerror (name, Finding, exc) in
        raise (Stdpp.Exc_located ((fst loc, shift), exc1))
  in
  let ast =
    match expander with
      Quotation.ExStr f ->
        let new_str = expand_quotation loc (f in_expr) shift name str in
        parse_quotation_result entry loc shift name new_str
    | Quotation.ExAst fe_fp ->
        expand_quotation loc (proj fe_fp) shift name str
  in
  reloc
    (let zero = ref None in
     fun _ ->
       match !zero with
         None -> zero := Some (ghostify loc); loc
       | Some x -> x)
    shift ast
;;

let parse_locate entry shift str =
  let cs = Stream.of_string str in
  try Grammar.Entry.parse entry cs with
    Stdpp.Exc_located ((p1, p2), exc) ->
      let ctx = Locating in
      let exc1 = Qerror (Grammar.Entry.name entry, ctx, exc) in
      raise (Stdpp.Exc_located (Reloc.adjust_loc shift (p1, p2), exc1))
;;

let handle_locate loc entry ast_f (pos, str) =
  let s = str in
  let loc = pos, Reloc.shift_pos (String.length s) pos in
  let x = parse_locate entry (fst loc) s in ast_f loc x
;;

let expr_anti loc e = MLast.ExAnt (loc, e);;
let patt_anti loc p = MLast.PaAnt (loc, p);;
let expr_eoi = Grammar.Entry.create gram "expression";;
let patt_eoi = Grammar.Entry.create gram "pattern";;
Grammar.extend
  [Grammar.Entry.obj (expr_eoi : 'expr_eoi Grammar.Entry.e), None,
   [None, None,
    [[Gramext.Snterm (Grammar.Entry.obj (expr : 'expr Grammar.Entry.e));
      Gramext.Stoken ("EOI", "")],
     Gramext.action
       (fun _ (x : 'expr) (_loc : Lexing.position * Lexing.position) ->
          (x : 'expr_eoi))]];
   Grammar.Entry.obj (patt_eoi : 'patt_eoi Grammar.Entry.e), None,
   [None, None,
    [[Gramext.Snterm (Grammar.Entry.obj (patt : 'patt Grammar.Entry.e));
      Gramext.Stoken ("EOI", "")],
     Gramext.action
       (fun _ (x : 'patt) (_loc : Lexing.position * Lexing.position) ->
          (x : 'patt_eoi))]]];;

let handle_expr_quotation loc x =
  handle_quotation loc fst true expr_eoi Reloc.expr x
;;

let handle_expr_locate loc x = handle_locate loc expr_eoi expr_anti x;;

let handle_patt_quotation loc x =
  handle_quotation loc snd false patt_eoi Reloc.patt x
;;

let handle_patt_locate loc x = handle_locate loc patt_eoi patt_anti x;;

let expr_reloc = Reloc.expr;;
let patt_reloc = Reloc.patt;;

let ctyp_reloc = Reloc.ctyp;;
let row_field_reloc = Reloc.row_field;;
let class_infos_reloc = Reloc.class_infos;;
let module_type_reloc = Reloc.module_type;;
let sig_item_reloc = Reloc.sig_item;;
let with_constr_reloc = Reloc.with_constr;;
let module_expr_reloc = Reloc.module_expr;;
let str_item_reloc = Reloc.str_item;;
let class_type_reloc = Reloc.class_type;;
let class_sig_item_reloc = Reloc.class_sig_item;;
let class_expr_reloc = Reloc.class_expr;;
let class_str_item_reloc = Reloc.class_str_item;;

let rename_id = ref (fun x -> x);;

let find_line (bp, ep) str =
  bp.Lexing.pos_lnum, bp.Lexing.pos_cnum - bp.Lexing.pos_bol,
  ep.Lexing.pos_cnum - bp.Lexing.pos_bol
;;

let loc_fmt =
  match Sys.os_type with
    "MacOS" ->
      format_of_string "File \"%s\"; line %d; characters %d to %d\n### "
  | _ -> format_of_string "File \"%s\", line %d, characters %d-%d:\n"
;;

let report_quotation_error name ctx =
  let name = if name = "" then !(Quotation.default) else name in
  Format.print_flush ();
  Format.open_hovbox 2;
  Printf.eprintf "While %s \"%s\":"
    (match ctx with
       Finding -> "finding quotation"
     | Expanding -> "expanding quotation"
     | ParsingResult (_, _) -> "parsing result of quotation"
     | Locating -> "parsing")
    name;
  match ctx with
    ParsingResult ((bp, ep), str) ->
      begin match !quotation_dump_file with
        Some dump_file ->
          Printf.eprintf " dumping result...\n";
          flush stderr;
          begin try
            let (line, c1, c2) = find_line (bp, ep) str in
            let oc = open_out_bin dump_file in
            output_string oc str;
            output_string oc "\n";
            flush oc;
            close_out oc;
            Printf.eprintf loc_fmt dump_file line c1 c2;
            flush stderr
          with
            _ ->
              Printf.eprintf "Error while dumping result in file \"%s\""
                dump_file;
              Printf.eprintf "; dump aborted.\n";
              flush stderr
          end
      | None ->
          if !input_file = "" then
            Printf.eprintf
              "\n(consider setting variable Pcaml.quotation_dump_file)\n"
          else Printf.eprintf " (consider using option -QD)\n";
          flush stderr
      end
  | _ -> Printf.eprintf "\n"; flush stderr
;;

let print_format str =
  let rec flush ini cnt =
    if cnt > ini then Format.print_string (String.sub str ini (cnt - ini))
  in
  let rec loop ini cnt =
    if cnt == String.length str then flush ini cnt
    else
      match str.[cnt] with
        '\n' ->
          flush ini cnt;
          Format.close_box ();
          Format.force_newline ();
          Format.open_box 2;
          loop (cnt + 1) (cnt + 1)
      | ' ' -> flush ini cnt; Format.print_space (); loop (cnt + 1) (cnt + 1)
      | _ -> loop ini (cnt + 1)
  in
  Format.open_box 2; loop 0 0; Format.close_box ()
;;

let print_file_failed file line char =
  Format.print_string ", file \"";
  Format.print_string file;
  Format.print_string "\", line ";
  Format.print_int line;
  Format.print_string ", char ";
  Format.print_int char
;;

let print_exn =
  function
    Out_of_memory -> Format.print_string "Out of memory\n"
  | Assert_failure (file, line, char) ->
      Format.print_string "Assertion failed"; print_file_failed file line char
  | Match_failure (file, line, char) ->
      Format.print_string "Pattern matching failed";
      print_file_failed file line char
  | Stream.Error str -> print_format ("Parse error: " ^ str)
  | Stream.Failure -> Format.print_string "Parse failure"
  | Token.Error str ->
      Format.print_string "Lexing error: "; Format.print_string str
  | Failure str -> Format.print_string "Failure: "; Format.print_string str
  | Invalid_argument str ->
      Format.print_string "Invalid argument: "; Format.print_string str
  | Sys_error msg ->
      Format.print_string "I/O error: "; Format.print_string msg
  | x ->
      Format.print_string "Uncaught exception: ";
      Format.print_string
        (Obj.magic (Obj.field (Obj.field (Obj.repr x) 0) 0));
      if Obj.size (Obj.repr x) > 1 then
        begin
          Format.print_string " (";
          for i = 1 to Obj.size (Obj.repr x) - 1 do
            if i > 1 then Format.print_string ", ";
            let arg = Obj.field (Obj.repr x) i in
            if not (Obj.is_block arg) then
              Format.print_int (Obj.magic arg : int)
            else if Obj.tag arg = Obj.tag (Obj.repr "a") then
              begin
                Format.print_char '\"';
                Format.print_string (Obj.magic arg : string);
                Format.print_char '\"'
              end
            else Format.print_char '_'
          done;
          Format.print_char ')'
        end
;;

let report_error exn =
  match exn with
    Qerror (name, Finding, Not_found) ->
      let name = if name = "" then !(Quotation.default) else name in
      Format.print_flush ();
      Format.open_hovbox 2;
      Format.printf "Unbound quotation: \"%s\"" name;
      Format.close_box ()
  | Qerror (name, ctx, exn) -> report_quotation_error name ctx; print_exn exn
  | e -> print_exn exn
;;

let no_constructors_arity = ref false;;

let arg_spec_list_ref = ref [];;
let arg_spec_list () = !arg_spec_list_ref;;
let add_option name spec descr =
  arg_spec_list_ref := !arg_spec_list_ref @ [name, spec, descr]
;;

(* Printers *)

open Spretty;;

type 'a printer_t =
  { mutable pr_fun : string -> 'a -> string -> kont -> pretty;
    mutable pr_levels : 'a pr_level list }
and 'a pr_level =
  { pr_label : string;
    pr_box : 'a -> pretty Stream.t -> pretty;
    mutable pr_rules : 'a pr_rule }
and 'a pr_rule =
  ('a, ('a curr -> 'a next -> string -> kont -> pretty Stream.t)) Extfun.t
and 'a curr = 'a -> string -> kont -> pretty Stream.t
and 'a next = 'a -> string -> kont -> pretty
and kont = pretty Stream.t
;;

let pr_str_item =
  {pr_fun = (fun _ -> raise (Match_failure ("", 409, 30))); pr_levels = []}
;;
let pr_sig_item =
  {pr_fun = (fun _ -> raise (Match_failure ("", 410, 30))); pr_levels = []}
;;
let pr_module_type =
  {pr_fun = (fun _ -> raise (Match_failure ("", 411, 33))); pr_levels = []}
;;
let pr_module_expr =
  {pr_fun = (fun _ -> raise (Match_failure ("", 412, 33))); pr_levels = []}
;;
let pr_expr =
  {pr_fun = (fun _ -> raise (Match_failure ("", 413, 26))); pr_levels = []}
;;
let pr_patt =
  {pr_fun = (fun _ -> raise (Match_failure ("", 414, 26))); pr_levels = []}
;;
let pr_ctyp =
  {pr_fun = (fun _ -> raise (Match_failure ("", 415, 26))); pr_levels = []}
;;
let pr_class_sig_item =
  {pr_fun = (fun _ -> raise (Match_failure ("", 416, 36))); pr_levels = []}
;;
let pr_class_str_item =
  {pr_fun = (fun _ -> raise (Match_failure ("", 417, 36))); pr_levels = []}
;;
let pr_class_type =
  {pr_fun = (fun _ -> raise (Match_failure ("", 418, 32))); pr_levels = []}
;;
let pr_class_expr =
  {pr_fun = (fun _ -> raise (Match_failure ("", 419, 32))); pr_levels = []}
;;
let pr_expr_fun_args = ref Extfun.empty;;

let pr_fun name pr lab =
  let rec loop app =
    function
      [] -> (fun x dg k -> failwith ("unable to print " ^ name))
    | lev :: levl ->
        if app || lev.pr_label = lab then
          let next = loop true levl in
          let rec curr x dg k = Extfun.apply lev.pr_rules x curr next dg k in
          fun x dg k -> lev.pr_box x (curr x dg k)
        else loop app levl
  in
  loop false pr.pr_levels
;;

pr_str_item.pr_fun <- pr_fun "str_item" pr_str_item;;
pr_sig_item.pr_fun <- pr_fun "sig_item" pr_sig_item;;
pr_module_type.pr_fun <- pr_fun "module_type" pr_module_type;;
pr_module_expr.pr_fun <- pr_fun "module_expr" pr_module_expr;;
pr_expr.pr_fun <- pr_fun "expr" pr_expr;;
pr_patt.pr_fun <- pr_fun "patt" pr_patt;;
pr_ctyp.pr_fun <- pr_fun "ctyp" pr_ctyp;;
pr_class_sig_item.pr_fun <- pr_fun "class_sig_item" pr_class_sig_item;;
pr_class_str_item.pr_fun <- pr_fun "class_str_item" pr_class_str_item;;
pr_class_type.pr_fun <- pr_fun "class_type" pr_class_type;;
pr_class_expr.pr_fun <- pr_fun "class_expr" pr_class_expr;;

let rec find_pr_level lab =
  function
    [] -> failwith ("level " ^ lab ^ " not found")
  | lev :: levl -> if lev.pr_label = lab then lev else find_pr_level lab levl
;;

let undef x = ref (fun _ -> failwith x);;
let print_interf = undef "no printer";;
let print_implem = undef "no printer";;

let top_printer pr x =
  Format.force_newline ();
  Spretty.print_pretty Format.print_char Format.print_string
    Format.print_newline "<< " "   " 78 (fun _ _ -> "", 0, 0, 0) 0
    (pr.pr_fun "top" x "" Stream.sempty);
  Format.print_string " >>"
;;

let buff = Buffer.create 73;;
let buffer_char = Buffer.add_char buff;;
let buffer_string = Buffer.add_string buff;;
let buffer_newline () = Buffer.add_char buff '\n';;

let string_of pr x =
  Buffer.clear buff;
  Spretty.print_pretty buffer_char buffer_string buffer_newline "" "" 78
    (fun _ _ -> "", 0, 0, 0) 0 (pr.pr_fun "top" x "" Stream.sempty);
  Buffer.contents buff
;;

let inter_phrases = ref None;;
