(* camlp4r *)
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

open Stdpp;;
open Token;;

let no_quotations = ref false;;

(* The string buffering machinery *)

let buff = ref (String.create 80);;
let store len x =
  if len >= String.length !buff then
    buff := !buff ^ String.create (String.length !buff);
  !buff.[len] <- x;
  succ len
;;
let mstore len s =
  let rec add_rec len i =
    if i == String.length s then len else add_rec (store len s.[i]) (succ i)
  in
  add_rec len 0
;;
let get_buff len = String.sub !buff 0 len;;

(* The lexer *)

let stream_peek_nth n strm =
  let rec loop n =
    function
      [] -> None
    | [x] -> if n == 1 then Some x else None
    | _ :: l -> loop (n - 1) l
  in
  loop n (Stream.npeek n strm)
;;

let rec ident len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some
      ('A'..'Z' | 'a'..'z' | '\192'..'\214' | '\216'..'\246' |
       '\248'..'\255' | '0'..'9' | '_' | '\'' as c) ->
      Stream.junk strm__; ident (store len c) strm__
  | _ -> len
and ident2 len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some
      ('!' | '?' | '~' | '=' | '@' | '^' | '&' | '+' | '-' | '*' | '/' | '%' |
       '.' | ':' | '<' | '>' | '|' | '$' as c) ->
      Stream.junk strm__; ident2 (store len c) strm__
  | _ -> len
and ident3 len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some
      ('0'..'9' | 'A'..'Z' | 'a'..'z' | '\192'..'\214' | '\216'..'\246' |
       '\248'..'\255' | '_' | '!' | '%' | '&' | '*' | '+' | '-' | '.' | '/' |
       ':' | '<' | '=' | '>' | '?' | '@' | '^' | '|' | '~' | '\'' | '$' as c
         ) ->
      Stream.junk strm__; ident3 (store len c) strm__
  | _ -> len
and base_number len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('o' | 'O') ->
      Stream.junk strm__; digits octal (store len 'o') strm__
  | Some ('x' | 'X') -> Stream.junk strm__; digits hexa (store len 'x') strm__
  | Some ('b' | 'B') ->
      Stream.junk strm__; digits binary (store len 'b') strm__
  | _ -> number len strm__
and digits kind len (strm__ : _ Stream.t) =
  let d =
    try kind strm__ with
      Stream.Failure -> raise (Stream.Error "ill-formed integer constant")
  in
  digits_under kind (store len d) strm__
and digits_under kind len (strm__ : _ Stream.t) =
  match
    try Some (kind strm__) with
      Stream.Failure -> None
  with
    Some d -> digits_under kind (store len d) strm__
  | _ ->
      match Stream.peek strm__ with
        Some '_' -> Stream.junk strm__; digits_under kind len strm__
      | Some 'l' -> Stream.junk strm__; "INT32", get_buff len
      | Some 'L' -> Stream.junk strm__; "INT64", get_buff len
      | Some 'n' -> Stream.junk strm__; "NATIVEINT", get_buff len
      | _ -> "INT", get_buff len
and octal (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('0'..'7' as d) -> Stream.junk strm__; d
  | _ -> raise Stream.Failure
and hexa (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('0'..'9' | 'a'..'f' | 'A'..'F' as d) -> Stream.junk strm__; d
  | _ -> raise Stream.Failure
and binary (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('0'..'1' as d) -> Stream.junk strm__; d
  | _ -> raise Stream.Failure
and number len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('0'..'9' as c) -> Stream.junk strm__; number (store len c) strm__
  | Some '_' -> Stream.junk strm__; number len strm__
  | Some '.' -> Stream.junk strm__; decimal_part (store len '.') strm__
  | Some ('e' | 'E') ->
      Stream.junk strm__; exponent_part (store len 'E') strm__
  | Some 'l' -> Stream.junk strm__; "INT32", get_buff len
  | Some 'L' -> Stream.junk strm__; "INT64", get_buff len
  | Some 'n' -> Stream.junk strm__; "NATIVEINT", get_buff len
  | _ -> "INT", get_buff len
and decimal_part len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('0'..'9' as c) ->
      Stream.junk strm__; decimal_part (store len c) strm__
  | Some '_' -> Stream.junk strm__; decimal_part len strm__
  | Some ('e' | 'E') ->
      Stream.junk strm__; exponent_part (store len 'E') strm__
  | _ -> "FLOAT", get_buff len
and exponent_part len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('+' | '-' as c) ->
      Stream.junk strm__; end_exponent_part (store len c) strm__
  | _ -> end_exponent_part len strm__
and end_exponent_part len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('0'..'9' as c) ->
      Stream.junk strm__; end_exponent_part_under (store len c) strm__
  | _ -> raise (Stream.Error "ill-formed floating-point constant")
and end_exponent_part_under len (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some ('0'..'9' as c) ->
      Stream.junk strm__; end_exponent_part_under (store len c) strm__
  | Some '_' -> Stream.junk strm__; end_exponent_part_under len strm__
  | _ -> "FLOAT", get_buff len
;;

let error_on_unknown_keywords = ref false;;
let err loc msg = raise_with_loc loc (Token.Error msg);;

(* Debugging positions and locations *)
let eprint_pos msg p =
  Printf.eprintf "%s: fname=%s; lnum=%d; bol=%d; cnum=%d\n%!" msg
    p.Lexing.pos_fname p.Lexing.pos_lnum p.Lexing.pos_bol p.Lexing.pos_cnum
;;

let eprint_loc (bp, ep) = eprint_pos "P1" bp; eprint_pos "P2" ep;;
   
let check_location msg (bp, ep as loc) =
  let ok =
    if bp.Lexing.pos_lnum > ep.Lexing.pos_lnum ||
       bp.Lexing.pos_bol > ep.Lexing.pos_bol ||
       bp.Lexing.pos_cnum > ep.Lexing.pos_cnum || bp.Lexing.pos_lnum < 0 ||
       ep.Lexing.pos_lnum < 0 || bp.Lexing.pos_bol < 0 ||
       ep.Lexing.pos_bol < 0 || bp.Lexing.pos_cnum < 0 ||
       ep.Lexing.pos_cnum < 0
    then
      begin
        Printf.eprintf "*** Warning: (%s) strange positions ***\n" msg;
        eprint_loc loc;
        false
      end
    else true
  in
  ok, loc
;;

let next_token_fun dfa ssd find_kwd fname lnum bolpos glexr =
  let make_pos p =
    {Lexing.pos_fname = !fname; Lexing.pos_lnum = !lnum;
     Lexing.pos_bol = !bolpos; Lexing.pos_cnum = p}
  in
  let mkloc (bp, ep) = make_pos bp, make_pos ep in
  let keyword_or_error (bp, ep) s =
    let loc = mkloc (bp, ep) in
    try ("", find_kwd s), loc with
      Not_found ->
        if !error_on_unknown_keywords then err loc ("illegal token: " ^ s)
        else ("", s), loc
  in
  let error_if_keyword ((_, id as a), bep) =
    let loc = mkloc bep in
    try
      ignore (find_kwd id);
      err loc ("illegal use of a keyword as a label: " ^ id)
    with
      Not_found -> a, loc
  in
  let rec next_token after_space (strm__ : _ Stream.t) =
    let bp = Stream.count strm__ in
    match Stream.peek strm__ with
      Some '\010' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in
        bolpos := ep; incr lnum; next_token true s
    | Some '\013' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in
        let ep =
          match Stream.peek s with
            Some '\010' -> Stream.junk s; ep + 1
          | _ -> ep
        in
        bolpos := ep; incr lnum; next_token true s
    | Some (' ' | '\t' | '\026' | '\012') ->
        Stream.junk strm__; next_token true strm__
    | Some '#' when bp = !bolpos ->
        Stream.junk strm__;
        let s = strm__ in
        if linedir 1 s then begin line_directive s; next_token true s end
        else keyword_or_error (bp, bp + 1) "#"
    | Some '(' -> Stream.junk strm__; left_paren bp strm__
    | Some ('A'..'Z' | '\192'..'\214' | '\216'..'\222' as c) ->
        Stream.junk strm__;
        let s = strm__ in
        let id = get_buff (ident (store 0 c) s) in
        let loc = mkloc (bp, Stream.count s) in
        (try "", find_kwd id with
           Not_found -> "UIDENT", id),
        loc
    | Some ('a'..'z' | '\223'..'\246' | '\248'..'\255' | '_' as c) ->
        Stream.junk strm__;
        let s = strm__ in
        let id = get_buff (ident (store 0 c) s) in
        let loc = mkloc (bp, Stream.count s) in
        (try "", find_kwd id with
           Not_found -> "LIDENT", id),
        loc
    | Some ('1'..'9' as c) ->
        Stream.junk strm__;
        let tok = number (store 0 c) strm__ in
        let loc = mkloc (bp, Stream.count strm__) in tok, loc
    | Some '0' ->
        Stream.junk strm__;
        let tok = base_number (store 0 '0') strm__ in
        let loc = mkloc (bp, Stream.count strm__) in tok, loc
    | Some '\'' ->
        Stream.junk strm__;
        let s = strm__ in
        begin match Stream.npeek 2 s with
          [_; '\''] | ['\\'; _] ->
            let tok = "CHAR", get_buff (char bp 0 s) in
            let loc = mkloc (bp, Stream.count s) in tok, loc
        | _ -> keyword_or_error (bp, Stream.count s) "'"
        end
    | Some '\"' ->
        Stream.junk strm__;
        let tok = "STRING", get_buff (string bp 0 strm__) in
        let loc = mkloc (bp, Stream.count strm__) in tok, loc
    | Some '$' ->
        Stream.junk strm__;
        let tok = dollar bp 0 strm__ in
        let loc = mkloc (bp, Stream.count strm__) in tok, loc
    | Some ('!' | '=' | '@' | '^' | '&' | '+' | '-' | '*' | '/' | '%' as c) ->
        Stream.junk strm__;
        let id = get_buff (ident2 (store 0 c) strm__) in
        keyword_or_error (bp, Stream.count strm__) id
    | Some ('~' as c) ->
        Stream.junk strm__;
        begin try
          match Stream.peek strm__ with
            Some ('a'..'z' as c) ->
              Stream.junk strm__;
              let len =
                try ident (store 0 c) strm__ with
                  Stream.Failure -> raise (Stream.Error "")
              in
              let s = strm__ in
              let ep = Stream.count strm__ in
              let id = get_buff len in
              let (strm__ : _ Stream.t) = s in
              begin match Stream.peek strm__ with
                Some ':' ->
                  Stream.junk strm__;
                  let eb = Stream.count strm__ in
                  error_if_keyword (("LABEL", id), (bp, ep))
              | _ -> error_if_keyword (("TILDEIDENT", id), (bp, ep))
              end
          | _ ->
              let id = get_buff (ident2 (store 0 c) strm__) in
              keyword_or_error (bp, Stream.count strm__) id
        with
          Stream.Failure -> raise (Stream.Error "")
        end
    | Some ('?' as c) ->
        Stream.junk strm__;
        begin try
          match Stream.peek strm__ with
            Some ('a'..'z' as c) ->
              Stream.junk strm__;
              let len =
                try ident (store 0 c) strm__ with
                  Stream.Failure -> raise (Stream.Error "")
              in
              let s = strm__ in
              let ep = Stream.count strm__ in
              let id = get_buff len in
              let (strm__ : _ Stream.t) = s in
              begin match Stream.peek strm__ with
                Some ':' ->
                  Stream.junk strm__;
                  let eb = Stream.count strm__ in
                  error_if_keyword (("OPTLABEL", id), (bp, ep))
              | _ -> error_if_keyword (("QUESTIONIDENT", id), (bp, ep))
              end
          | _ ->
              let id = get_buff (ident2 (store 0 c) strm__) in
              keyword_or_error (bp, Stream.count strm__) id
        with
          Stream.Failure -> raise (Stream.Error "")
        end
    | Some '<' -> Stream.junk strm__; less bp strm__
    | Some (':' as c1) ->
        Stream.junk strm__;
        let len =
          try
            match Stream.peek strm__ with
              Some (']' | ':' | '=' | '>' as c2) ->
                Stream.junk strm__; store (store 0 c1) c2
            | _ -> store 0 c1
          with
            Stream.Failure -> raise (Stream.Error "")
        in
        let ep = Stream.count strm__ in
        let id = get_buff len in keyword_or_error (bp, ep) id
    | Some ('>' | '|' as c1) ->
        Stream.junk strm__;
        let len =
          try
            match Stream.peek strm__ with
              Some (']' | '}' as c2) ->
                Stream.junk strm__; store (store 0 c1) c2
            | _ -> ident2 (store 0 c1) strm__
          with
            Stream.Failure -> raise (Stream.Error "")
        in
        let ep = Stream.count strm__ in
        let id = get_buff len in keyword_or_error (bp, ep) id
    | Some ('[' | '{' as c1) ->
        Stream.junk strm__;
        let s = strm__ in
        let len =
          match Stream.npeek 2 s with
            ['<'; '<' | ':'] -> store 0 c1
          | _ ->
              let (strm__ : _ Stream.t) = s in
              match Stream.peek strm__ with
                Some ('|' | '<' | ':' as c2) ->
                  Stream.junk strm__; store (store 0 c1) c2
              | _ -> store 0 c1
        in
        let ep = Stream.count s in
        let id = get_buff len in keyword_or_error (bp, ep) id
    | Some '.' ->
        Stream.junk strm__;
        let id =
          try
            match Stream.peek strm__ with
              Some '.' -> Stream.junk strm__; ".."
            | _ -> if ssd && after_space then " ." else "."
          with
            Stream.Failure -> raise (Stream.Error "")
        in
        let ep = Stream.count strm__ in keyword_or_error (bp, ep) id
    | Some ';' ->
        Stream.junk strm__;
        let id =
          try
            match Stream.peek strm__ with
              Some ';' -> Stream.junk strm__; ";;"
            | _ -> ";"
          with
            Stream.Failure -> raise (Stream.Error "")
        in
        let ep = Stream.count strm__ in keyword_or_error (bp, ep) id
    | Some '\\' ->
        Stream.junk strm__;
        let ep = Stream.count strm__ in
        ("LIDENT", get_buff (ident3 0 strm__)), mkloc (bp, ep)
    | Some c ->
        Stream.junk strm__;
        let ep = Stream.count strm__ in
        keyword_or_error (bp, ep) (String.make 1 c)
    | _ -> let _ = Stream.empty strm__ in ("EOI", ""), mkloc (bp, succ bp)
  and less bp strm =
    if !no_quotations then
      let (strm__ : _ Stream.t) = strm in
      let len = ident2 (store 0 '<') strm__ in
      let ep = Stream.count strm__ in
      let id = get_buff len in keyword_or_error (bp, ep) id
    else
      let (strm__ : _ Stream.t) = strm in
      match Stream.peek strm__ with
        Some '<' ->
          Stream.junk strm__;
          let len =
            try quotation bp 0 strm__ with
              Stream.Failure -> raise (Stream.Error "")
          in
          let ep = Stream.count strm__ in
          ("QUOTATION", ":" ^ get_buff len), mkloc (bp, ep)
      | Some ':' ->
          Stream.junk strm__;
          let i =
            try let len = ident 0 strm__ in get_buff len with
              Stream.Failure -> raise (Stream.Error "")
          in
          begin match Stream.peek strm__ with
            Some '<' ->
              Stream.junk strm__;
              let len =
                try quotation bp 0 strm__ with
                  Stream.Failure -> raise (Stream.Error "")
              in
              let ep = Stream.count strm__ in
              ("QUOTATION", i ^ ":" ^ get_buff len), mkloc (bp, ep)
          | _ -> raise (Stream.Error "character '<' expected")
          end
      | _ ->
          let len = ident2 (store 0 '<') strm__ in
          let ep = Stream.count strm__ in
          let id = get_buff len in keyword_or_error (bp, ep) id
  and string bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '\"' -> Stream.junk strm__; len
    | Some '\\' ->
        Stream.junk strm__;
        begin match Stream.peek strm__ with
          Some c ->
            Stream.junk strm__;
            let ep = Stream.count strm__ in
            string bp (store (store len '\\') c) strm__
        | _ -> raise (Stream.Error "")
        end
    | Some '\010' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in
        bolpos := ep; incr lnum; string bp len s
    | Some '\013' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in
        let (len, ep) =
          match Stream.peek s with
            Some '\010' ->
              Stream.junk s; store (store len '\013') '\010', ep + 1
          | _ -> store len '\013', ep
        in
        bolpos := ep; incr lnum; string bp len s
    | Some c -> Stream.junk strm__; string bp (store len c) strm__
    | _ ->
        let ep = Stream.count strm__ in
        err (mkloc (bp, ep)) "string not terminated"
  and char bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '\'' ->
        Stream.junk strm__;
        let s = strm__ in if len = 0 then char bp (store len '\'') s else len
    | Some '\\' ->
        Stream.junk strm__;
        begin match Stream.peek strm__ with
          Some c ->
            Stream.junk strm__; char bp (store (store len '\\') c) strm__
        | _ -> raise (Stream.Error "")
        end
    | Some '\010' ->
        Stream.junk strm__;
        let s = strm__ in
        bolpos := bp + 1; incr lnum; char bp (store len '\010') s
    | Some '\013' ->
        Stream.junk strm__;
        let s = strm__ in
        let bol =
          match Stream.peek s with
            Some '\010' -> Stream.junk s; bp + 2
          | _ -> bp + 1
        in
        bolpos := bol; incr lnum; char bp (store len '\013') s
    | Some c -> Stream.junk strm__; char bp (store len c) strm__
    | _ ->
        let ep = Stream.count strm__ in
        err (mkloc (bp, ep)) "char not terminated"
  and dollar bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '$' -> Stream.junk strm__; "ANTIQUOT", ":" ^ get_buff len
    | Some ('a'..'z' | 'A'..'Z' as c) ->
        Stream.junk strm__; antiquot bp (store len c) strm__
    | Some ('0'..'9' as c) ->
        Stream.junk strm__; maybe_locate bp (store len c) strm__
    | Some ':' ->
        Stream.junk strm__;
        let k = get_buff len in
        "ANTIQUOT", k ^ ":" ^ locate_or_antiquot_rest bp 0 strm__
    | Some '\\' ->
        Stream.junk strm__;
        begin match Stream.peek strm__ with
          Some c ->
            Stream.junk strm__;
            "ANTIQUOT", ":" ^ locate_or_antiquot_rest bp (store len c) strm__
        | _ -> raise (Stream.Error "")
        end
    | _ ->
        let s = strm__ in
        if dfa then
          let (strm__ : _ Stream.t) = s in
          match Stream.peek strm__ with
            Some c ->
              Stream.junk strm__;
              "ANTIQUOT", ":" ^ locate_or_antiquot_rest bp (store len c) s
          | _ ->
              let ep = Stream.count strm__ in
              err (mkloc (bp, ep)) "antiquotation not terminated"
        else "", get_buff (ident2 (store 0 '$') s)
  and maybe_locate bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '$' -> Stream.junk strm__; "ANTIQUOT", ":" ^ get_buff len
    | Some ('0'..'9' as c) ->
        Stream.junk strm__; maybe_locate bp (store len c) strm__
    | Some ':' ->
        Stream.junk strm__;
        "LOCATE", get_buff len ^ ":" ^ locate_or_antiquot_rest bp 0 strm__
    | Some '\\' ->
        Stream.junk strm__;
        begin match Stream.peek strm__ with
          Some c ->
            Stream.junk strm__;
            "ANTIQUOT", ":" ^ locate_or_antiquot_rest bp (store len c) strm__
        | _ -> raise (Stream.Error "")
        end
    | Some c ->
        Stream.junk strm__;
        "ANTIQUOT", ":" ^ locate_or_antiquot_rest bp (store len c) strm__
    | _ ->
        let ep = Stream.count strm__ in
        err (mkloc (bp, ep)) "antiquotation not terminated"
  and antiquot bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '$' -> Stream.junk strm__; "ANTIQUOT", ":" ^ get_buff len
    | Some ('a'..'z' | 'A'..'Z' | '0'..'9' as c) ->
        Stream.junk strm__; antiquot bp (store len c) strm__
    | Some ':' ->
        Stream.junk strm__;
        let k = get_buff len in
        "ANTIQUOT", k ^ ":" ^ locate_or_antiquot_rest bp 0 strm__
    | Some '\\' ->
        Stream.junk strm__;
        begin match Stream.peek strm__ with
          Some c ->
            Stream.junk strm__;
            "ANTIQUOT", ":" ^ locate_or_antiquot_rest bp (store len c) strm__
        | _ -> raise (Stream.Error "")
        end
    | Some c ->
        Stream.junk strm__;
        "ANTIQUOT", ":" ^ locate_or_antiquot_rest bp (store len c) strm__
    | _ ->
        let ep = Stream.count strm__ in
        err (mkloc (bp, ep)) "antiquotation not terminated"
  and locate_or_antiquot_rest bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '$' -> Stream.junk strm__; get_buff len
    | Some '\\' ->
        Stream.junk strm__;
        begin match Stream.peek strm__ with
          Some c ->
            Stream.junk strm__;
            locate_or_antiquot_rest bp (store len c) strm__
        | _ -> raise (Stream.Error "")
        end
    | Some c ->
        Stream.junk strm__; locate_or_antiquot_rest bp (store len c) strm__
    | _ ->
        let ep = Stream.count strm__ in
        err (mkloc (bp, ep)) "antiquotation not terminated"
  and quotation bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '>' -> Stream.junk strm__; maybe_end_quotation bp len strm__
    | Some '<' ->
        Stream.junk strm__;
        quotation bp (maybe_nested_quotation bp (store len '<') strm__) strm__
    | Some '\\' ->
        Stream.junk strm__;
        let len =
          try
            match Stream.peek strm__ with
              Some ('>' | '<' | '\\' as c) -> Stream.junk strm__; store len c
            | _ -> store len '\\'
          with
            Stream.Failure -> raise (Stream.Error "")
        in
        quotation bp len strm__
    | Some '\010' ->
        Stream.junk strm__;
        let s = strm__ in
        bolpos := bp + 1; incr lnum; quotation bp (store len '\010') s
    | Some '\013' ->
        Stream.junk strm__;
        let s = strm__ in
        let bol =
          match Stream.peek s with
            Some '\010' -> Stream.junk s; bp + 2
          | _ -> bp + 1
        in
        bolpos := bol; incr lnum; quotation bp (store len '\013') s
    | Some c -> Stream.junk strm__; quotation bp (store len c) strm__
    | _ ->
        let ep = Stream.count strm__ in
        err (mkloc (bp, ep)) "quotation not terminated"
  and maybe_nested_quotation bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '<' ->
        Stream.junk strm__; mstore (quotation bp (store len '<') strm__) ">>"
    | Some ':' ->
        Stream.junk strm__;
        let len =
          try ident (store len ':') strm__ with
            Stream.Failure -> raise (Stream.Error "")
        in
        begin try
          match Stream.peek strm__ with
            Some '<' ->
              Stream.junk strm__;
              mstore (quotation bp (store len '<') strm__) ">>"
          | _ -> len
        with
          Stream.Failure -> raise (Stream.Error "")
        end
    | _ -> len
  and maybe_end_quotation bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '>' -> Stream.junk strm__; len
    | _ -> quotation bp (store len '>') strm__
  and left_paren bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '*' ->
        Stream.junk strm__;
        let _ =
          try comment bp strm__ with
            Stream.Failure -> raise (Stream.Error "")
        in
        begin try next_token true strm__ with
          Stream.Failure -> raise (Stream.Error "")
        end
    | _ -> let ep = Stream.count strm__ in keyword_or_error (bp, ep) "("
  and comment bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '(' -> Stream.junk strm__; left_paren_in_comment bp strm__
    | Some '*' -> Stream.junk strm__; star_in_comment bp strm__
    | Some '\"' ->
        Stream.junk strm__;
        let _ =
          try string bp 0 strm__ with
            Stream.Failure -> raise (Stream.Error "")
        in
        comment bp strm__
    | Some '\'' -> Stream.junk strm__; quote_in_comment bp strm__
    | Some '\010' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in bolpos := ep; incr lnum; comment bp s
    | Some '\013' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in
        let ep =
          match Stream.peek s with
            Some '\010' -> Stream.junk s; ep + 1
          | _ -> ep
        in
        bolpos := ep; incr lnum; comment bp s
    | Some c -> Stream.junk strm__; comment bp strm__
    | _ ->
        let ep = Stream.count strm__ in
        err (mkloc (bp, ep)) "comment not terminated"
  and quote_in_comment bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '\'' -> Stream.junk strm__; comment bp strm__
    | Some '\\' -> Stream.junk strm__; quote_antislash_in_comment bp 0 strm__
    | _ ->
        let s = strm__ in
        begin match Stream.npeek 2 s with
          ['\013' | '\010'; '\''] ->
            bolpos := bp + 1; incr lnum; Stream.junk s; Stream.junk s
        | ['\013'; '\010'] ->
            begin match Stream.npeek 3 s with
              [_; _; '\''] ->
                bolpos := bp + 2;
                incr lnum;
                Stream.junk s;
                Stream.junk s;
                Stream.junk s
            | _ -> ()
            end
        | [_; '\''] -> Stream.junk s; Stream.junk s
        | _ -> ()
        end;
        comment bp s
  and quote_any_in_comment bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '\'' -> Stream.junk strm__; comment bp strm__
    | _ -> comment bp strm__
  and quote_antislash_in_comment bp len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '\'' -> Stream.junk strm__; comment bp strm__
    | Some ('\\' | '\"' | 'n' | 't' | 'b' | 'r') ->
        Stream.junk strm__; quote_any_in_comment bp strm__
    | Some ('0'..'9') ->
        Stream.junk strm__; quote_antislash_digit_in_comment bp strm__
    | _ -> comment bp strm__
  and quote_antislash_digit_in_comment bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some ('0'..'9') ->
        Stream.junk strm__; quote_antislash_digit2_in_comment bp strm__
    | _ -> comment bp strm__
  and quote_antislash_digit2_in_comment bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some ('0'..'9') -> Stream.junk strm__; quote_any_in_comment bp strm__
    | _ -> comment bp strm__
  and left_paren_in_comment bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '*' ->
        Stream.junk strm__; let s = strm__ in comment bp s; comment bp s
    | _ -> comment bp strm__
  and star_in_comment bp (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some ')' -> Stream.junk strm__; ()
    | _ -> comment bp strm__
  and linedir n s =
    match stream_peek_nth n s with
      Some (' ' | '\t') -> linedir (n + 1) s
    | Some ('0'..'9') -> true
    | _ -> false
  and any_to_nl (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '\010' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in bolpos := ep; incr lnum
    | Some '\013' ->
        Stream.junk strm__;
        let s = strm__ in
        let ep = Stream.count strm__ in
        let ep =
          match Stream.peek s with
            Some '\010' -> Stream.junk s; ep + 1
          | _ -> ep
        in
        bolpos := ep; incr lnum
    | Some _ -> Stream.junk strm__; any_to_nl strm__
    | _ -> ()
  and line_directive (strm__ : _ Stream.t) =
    let _ = skip_spaces strm__ in
    let n =
      try line_directive_number 0 strm__ with
        Stream.Failure -> raise (Stream.Error "")
    in
    let _ =
      try skip_spaces strm__ with
        Stream.Failure -> raise (Stream.Error "")
    in
    let _ =
      try line_directive_string strm__ with
        Stream.Failure -> raise (Stream.Error "")
    in
    let _ =
      try any_to_nl strm__ with
        Stream.Failure -> raise (Stream.Error "")
    in
    let ep = Stream.count strm__ in bolpos := ep; lnum := n
  and skip_spaces (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some (' ' | '\t') -> Stream.junk strm__; skip_spaces strm__
    | _ -> ()
  and line_directive_number n (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some ('0'..'9' as c) ->
        Stream.junk strm__;
        line_directive_number (10 * n + (Char.code c - Char.code '0')) strm__
    | _ -> n
  and line_directive_string (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some '\"' ->
        Stream.junk strm__;
        let _ =
          try line_directive_string_contents 0 strm__ with
            Stream.Failure -> raise (Stream.Error "")
        in
        ()
    | _ -> ()
  and line_directive_string_contents len (strm__ : _ Stream.t) =
    match Stream.peek strm__ with
      Some ('\010' | '\013') -> Stream.junk strm__; ()
    | Some '\"' -> Stream.junk strm__; fname := get_buff len
    | Some c ->
        Stream.junk strm__;
        line_directive_string_contents (store len c) strm__
    | _ -> raise Stream.Failure
  in
  fun cstrm ->
    try
      let glex = !glexr in
      let comm_bp = Stream.count cstrm in
      let r = next_token false cstrm in
      begin match glex.tok_comm with
        Some list ->
          let next_bp = (fst (snd r)).Lexing.pos_cnum in
          if next_bp > comm_bp then
            let comm_loc = mkloc (comm_bp, next_bp) in
            glex.tok_comm <- Some (comm_loc :: list)
      | None -> ()
      end;
      r
    with
      Stream.Error str ->
        err (mkloc (Stream.count cstrm, Stream.count cstrm + 1)) str
;;


let dollar_for_antiquotation = ref true;;
let specific_space_dot = ref false;;

let func kwd_table glexr =
  let bolpos = ref 0 in
  let lnum = ref 1 in
  let fname = ref "" in
  let find = Hashtbl.find kwd_table in
  let dfa = !dollar_for_antiquotation in
  let ssd = !specific_space_dot in
  Token.lexer_func_of_parser
    (next_token_fun dfa ssd find fname lnum bolpos glexr)
;;

let rec check_keyword_stream (strm__ : _ Stream.t) =
  let _ = check strm__ in
  let _ =
    try Stream.empty strm__ with
      Stream.Failure -> raise (Stream.Error "")
  in
  true
and check (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some
      ('A'..'Z' | 'a'..'z' | '\192'..'\214' | '\216'..'\246' |
       '\248'..'\255') ->
      Stream.junk strm__; check_ident strm__
  | Some
      ('!' | '?' | '~' | '=' | '@' | '^' | '&' | '+' | '-' | '*' | '/' | '%' |
       '.') ->
      Stream.junk strm__; check_ident2 strm__
  | Some '<' ->
      Stream.junk strm__;
      let s = strm__ in
      begin match Stream.npeek 1 s with
        [':' | '<'] -> ()
      | _ -> check_ident2 s
      end
  | Some ':' ->
      Stream.junk strm__;
      let _ =
        try
          match Stream.peek strm__ with
            Some (']' | ':' | '=' | '>') -> Stream.junk strm__; ()
          | _ -> ()
        with
          Stream.Failure -> raise (Stream.Error "")
      in
      let ep = Stream.count strm__ in ()
  | Some ('>' | '|') ->
      Stream.junk strm__;
      let _ =
        try
          match Stream.peek strm__ with
            Some (']' | '}') -> Stream.junk strm__; ()
          | _ -> check_ident2 strm__
        with
          Stream.Failure -> raise (Stream.Error "")
      in
      ()
  | Some ('[' | '{') ->
      Stream.junk strm__;
      let s = strm__ in
      begin match Stream.npeek 2 s with
        ['<'; '<' | ':'] -> ()
      | _ ->
          let (strm__ : _ Stream.t) = s in
          match Stream.peek strm__ with
            Some ('|' | '<' | ':') -> Stream.junk strm__; ()
          | _ -> ()
      end
  | Some ';' ->
      Stream.junk strm__;
      let _ =
        try
          match Stream.peek strm__ with
            Some ';' -> Stream.junk strm__; ()
          | _ -> ()
        with
          Stream.Failure -> raise (Stream.Error "")
      in
      ()
  | Some _ -> Stream.junk strm__; ()
  | _ -> raise Stream.Failure
and check_ident (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some
      ('A'..'Z' | 'a'..'z' | '\192'..'\214' | '\216'..'\246' |
       '\248'..'\255' | '0'..'9' | '_' | '\'') ->
      Stream.junk strm__; check_ident strm__
  | _ -> ()
and check_ident2 (strm__ : _ Stream.t) =
  match Stream.peek strm__ with
    Some
      ('!' | '?' | '~' | '=' | '@' | '^' | '&' | '+' | '-' | '*' | '/' | '%' |
       '.' | ':' | '<' | '>' | '|') ->
      Stream.junk strm__; check_ident2 strm__
  | _ -> ()
;;

let check_keyword s =
  try check_keyword_stream (Stream.of_string s) with
    _ -> false
;;

let error_no_respect_rules p_con p_prm =
  raise
    (Token.Error
       ("the token " ^
          (if p_con = "" then "\"" ^ p_prm ^ "\""
           else if p_prm = "" then p_con
           else p_con ^ " \"" ^ p_prm ^ "\"") ^
          " does not respect Plexer rules"))
;;

let error_ident_and_keyword p_con p_prm =
  raise
    (Token.Error
       ("the token \"" ^ p_prm ^ "\" is used as " ^ p_con ^
          " and as keyword"))
;;

let using_token kwd_table ident_table (p_con, p_prm) =
  match p_con with
    "" ->
      if not (Hashtbl.mem kwd_table p_prm) then
        if check_keyword p_prm then
          if Hashtbl.mem ident_table p_prm then
            error_ident_and_keyword (Hashtbl.find ident_table p_prm) p_prm
          else Hashtbl.add kwd_table p_prm p_prm
        else error_no_respect_rules p_con p_prm
  | "LIDENT" ->
      if p_prm = "" then ()
      else
        begin match p_prm.[0] with
          'A'..'Z' -> error_no_respect_rules p_con p_prm
        | _ ->
            if Hashtbl.mem kwd_table p_prm then
              error_ident_and_keyword p_con p_prm
            else Hashtbl.add ident_table p_prm p_con
        end
  | "UIDENT" ->
      if p_prm = "" then ()
      else
        begin match p_prm.[0] with
          'a'..'z' -> error_no_respect_rules p_con p_prm
        | _ ->
            if Hashtbl.mem kwd_table p_prm then
              error_ident_and_keyword p_con p_prm
            else Hashtbl.add ident_table p_prm p_con
        end
  | "INT" | "INT32" | "INT64" | "NATIVEINT" | "FLOAT" | "CHAR" | "STRING" |
    "TILDEIDENT" | "QUESTIONIDENT" | "LABEL" | "OPTLABEL" | "QUOTATION" |
    "ANTIQUOT" | "LOCATE" | "EOI" ->
      ()
  | _ ->
      raise
        (Token.Error
           ("the constructor \"" ^ p_con ^ "\" is not recognized by Plexer"))
;;

let removing_token kwd_table ident_table (p_con, p_prm) =
  match p_con with
    "" -> Hashtbl.remove kwd_table p_prm
  | "LIDENT" | "UIDENT" ->
      if p_prm <> "" then Hashtbl.remove ident_table p_prm
  | _ -> ()
;;

let text =
  function
    "", t -> "'" ^ t ^ "'"
  | "LIDENT", "" -> "lowercase identifier"
  | "LIDENT", t -> "'" ^ t ^ "'"
  | "UIDENT", "" -> "uppercase identifier"
  | "UIDENT", t -> "'" ^ t ^ "'"
  | "INT", "" -> "integer"
  | "INT32", "" -> "32 bits integer"
  | "INT64", "" -> "64 bits integer"
  | "NATIVEINT", "" -> "native integer"
  | ("INT" | "INT32" | "NATIVEINT"), s -> "'" ^ s ^ "'"
  | "FLOAT", "" -> "float"
  | "STRING", "" -> "string"
  | "CHAR", "" -> "char"
  | "QUOTATION", "" -> "quotation"
  | "ANTIQUOT", k -> "antiquot \"" ^ k ^ "\""
  | "LOCATE", "" -> "locate"
  | "EOI", "" -> "end of input"
  | con, "" -> con
  | con, prm -> con ^ " \"" ^ prm ^ "\""
;;

let eq_before_colon p e =
  let rec loop i =
    if i == String.length e then
      failwith "Internal error in Plexer: incorrect ANTIQUOT"
    else if i == String.length p then e.[i] == ':'
    else if p.[i] == e.[i] then loop (i + 1)
    else false
  in
  loop 0
;;

let after_colon e =
  try
    let i = String.index e ':' in
    String.sub e (i + 1) (String.length e - i - 1)
  with
    Not_found -> ""
;;

let tok_match =
  function
    "ANTIQUOT", p_prm ->
      begin function
        "ANTIQUOT", prm when eq_before_colon p_prm prm -> after_colon prm
      | _ -> raise Stream.Failure
      end
  | tok -> Token.default_match tok
;;

let gmake () =
  let kwd_table = Hashtbl.create 301 in
  let id_table = Hashtbl.create 301 in
  let glexr =
    ref
      {tok_func = (fun _ -> raise (Match_failure ("", 748, 17)));
       tok_using = (fun _ -> raise (Match_failure ("", 748, 37)));
       tok_removing = (fun _ -> raise (Match_failure ("", 748, 60)));
       tok_match = (fun _ -> raise (Match_failure ("", 749, 18)));
       tok_text = (fun _ -> raise (Match_failure ("", 749, 37)));
       tok_comm = None}
  in
  let glex =
    {tok_func = func kwd_table glexr;
     tok_using = using_token kwd_table id_table;
     tok_removing = removing_token kwd_table id_table; tok_match = tok_match;
     tok_text = text; tok_comm = None}
  in
  glexr := glex; glex
;;

let tparse =
  function
    "ANTIQUOT", p_prm ->
      let p (strm__ : _ Stream.t) =
        match Stream.peek strm__ with
          Some ("ANTIQUOT", prm) when eq_before_colon p_prm prm ->
            Stream.junk strm__; after_colon prm
        | _ -> raise Stream.Failure
      in
      Some p
  | _ -> None
;;

let make () =
  let kwd_table = Hashtbl.create 301 in
  let id_table = Hashtbl.create 301 in
  let glexr =
    ref
      {tok_func = (fun _ -> raise (Match_failure ("", 777, 17)));
       tok_using = (fun _ -> raise (Match_failure ("", 777, 37)));
       tok_removing = (fun _ -> raise (Match_failure ("", 777, 60)));
       tok_match = (fun _ -> raise (Match_failure ("", 778, 18)));
       tok_text = (fun _ -> raise (Match_failure ("", 778, 37)));
       tok_comm = None}
  in
  {func = func kwd_table glexr; using = using_token kwd_table id_table;
   removing = removing_token kwd_table id_table; tparse = tparse; text = text}
;;
