(* camlp4r *)
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

(** Lexers for Camlp4 grammars.

   This module defines the Camlp4 lexer type to be used in extensible
   grammars (see module [Grammar]). It also provides some useful functions
   to create lexers (this module should be renamed [Glexer] one day). *)

type pattern = (string * string);
    (** Token patterns come from the EXTEND statement.
-       The first string is the constructor name (must start with
        an uppercase character). When it is empty, the second string
        is supposed to be a keyword.
-       The second string is the constructor parameter. Empty if it
        has no parameter.
-       The way tokens patterns are interpreted to parse tokens is
        done by the lexer, function [tok_match] below. *)

exception Error of string;
    (** An lexing error exception to be used by lexers. *)

(** {6 Lexer type} *)

type location = (int * int);
type location_function = int -> location;
  (** The type for a function associating a number of a token in a stream
      (starting from 0) to its source location. *)
type lexer_func 'te = Stream.t char -> (Stream.t 'te * location_function);
  (** The type for a lexer function. The character stream is the input
      stream to be lexed. The result is a pair of a token stream and
      a location function for this tokens stream. *)

type glexer 'te =
  { tok_func : lexer_func 'te;
    tok_using : pattern -> unit;
    tok_removing : pattern -> unit;
    tok_match : pattern -> 'te -> string;
    tok_text : pattern -> string;
    tok_comm : mutable option (list location) }
;
   (** The type for a lexer used by Camlp4 grammars.
-      The field [tok_func] is the main lexer function. See [lexer_func]
       type above. This function may be created from a [char stream parser]
       or for an [ocamllex] function using the functions below.
-      The field [tok_using] is a function telling the lexer that the grammar
       uses this token (pattern). The lexer can check that its constructor
       is correct, and interpret some kind of tokens as keywords (to record
       them in its tables). Called by [EXTEND] statements.
-      The field [tok_removing] is a function telling the lexer that the
       grammar does not uses the given token (pattern) any more. If the
       lexer has a notion of "keywords", it can release it from its tables.
       Called by [DELETE_RULE] statements.
-      The field [tok_match] is a function taking a pattern and returning
       a function matching a token against the pattern. Warning: for
       efficency, write it as a function returning functions according
       to the values of the pattern, not a function with two parameters.
-      The field [tok_text] returns the name of some token pattern,
       used in error messages.
-      The field [tok_comm] if not None asks the lexer to record the
       locations of the comments.  *)

value lexer_text : pattern -> string;
   (** A simple [tok_text] function for lexers *)

value default_match : pattern -> (string * string) -> string;
   (** A simple [tok_match] function for lexers, appling to token type
       [(string * string)] *)

(** {6 Lexers from char stream parsers or ocamllex function}

   The functions below create lexer functions either from a [char stream]
   parser or for an [ocamllex] function. With the returned function [f],
   the simplest [Token.lexer] can be written:
   {[
          { Token.tok_func = f;
            Token.tok_using = (fun _ -> ());
            Token.tok_removing = (fun _ -> ());
            Token.tok_match = Token.default_match;
            Token.tok_text = Token.lexer_text }
   ]}
   Note that a better [tok_using] function should check the used tokens
   and raise [Token.Error] for incorrect ones. The other functions
   [tok_removing], [tok_match] and [tok_text] may have other implementations
   as well. *)

value lexer_func_of_parser :
  (Stream.t char -> ('te * location)) -> lexer_func 'te;
   (** A lexer function from a lexer written as a char stream parser
       returning the next token and its location. *)
value lexer_func_of_ocamllex : (Lexing.lexbuf -> 'te) -> lexer_func 'te;
   (** A lexer function from a lexer created by [ocamllex] *)

value make_stream_and_location :
  (unit -> ('te * location)) -> (Stream.t 'te * location_function);
   (** General function *)

(** {6 Useful functions} *)

value eval_char : string -> char;
   (** Convert a char token, where the escape sequences (backslashes)
       remain to be interpreted; raise [Failure] if an
       incorrect backslash sequence is found; [Token.eval_char (Char.escaped c)]
       returns [c] *)

value eval_string : location -> string -> string;
   (** Convert a string token, where the escape sequences (backslashes)
       remain to be interpreted; issue a warning if an incorrect
       backslash sequence is found;
       [Token.eval_string loc (String.escaped s)] returns [s] *)

(**/**)

(* deprecated since version 3.05; use rather type glexer *)
type t = (string * string);
type lexer =
  { func : lexer_func t;
    using : pattern -> unit;
    removing : pattern -> unit;
    tparse : pattern -> option (Stream.t t -> string);
    text : pattern -> string }
;
