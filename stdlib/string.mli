(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License.         *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(** String operations. *)

(** Return the length (number of characters) of the given string. *)
external length : string -> int = "%string_length"

(** [String.get s n] returns character number [n] in string [s].
   The first character is character number 0.
   The last character is character number [String.length s - 1].
   Raise [Invalid_argument] if [n] is outside the range
   0 to [(String.length s - 1)].
   You can also write [s.[n]] instead of [String.get s n]. *)
external get : string -> int -> char = "%string_safe_get"

(** [String.set s n c] modifies string [s] in place,
   replacing the character number [n] by [c].
   Raise [Invalid_argument] if [n] is outside the range
   0 to [(String.length s - 1)].
   You can also write [s.[n] <- c] instead of [String.set s n c]. *)
external set : string -> int -> char -> unit = "%string_safe_set"

(** [String.create n] returns a fresh string of length [n].
   The string initially contains arbitrary characters.
   Raise [Invalid_argument] if [n < 0] or [n > Sys.max_string_length].
*)
external create : int -> string = "create_string"

(** [String.make n c] returns a fresh string of length [n],
   filled with the character [c].
   Raise [Invalid_argument] if [n < 0] or [n > ]{!Sys.max_string_length}.*)
val make : int -> char -> string

(** Return a copy of the given string. *)
val copy : string -> string

(** [String.sub s start len] returns a fresh string of length [len],
   containing the characters number [start] to [start + len - 1]
   of string [s].
   Raise [Invalid_argument] if [start] and [len] do not
   designate a valid substring of [s]; that is, if [start < 0],
   or [len < 0], or [start + len > ]{!String.length}[ s]. *)
val sub : string -> int -> int -> string

(** [String.fill s start len c] modifies string [s] in place,
   replacing the characters number [start] to [start + len - 1]
   by [c].
   Raise [Invalid_argument] if [start] and [len] do not
   designate a valid substring of [s]. *)
val fill : string -> int -> int -> char -> unit

(** [String.blit src srcoff dst dstoff len] copies [len] characters
   from string [src], starting at character number [srcoff], to
   string [dst], starting at character number [dstoff]. It works
   correctly even if [src] and [dst] are the same string,
   and the source and destination chunks overlap.
   Raise [Invalid_argument] if [srcoff] and [len] do not
   designate a valid substring of [src], or if [dstoff] and [len]
   do not designate a valid substring of [dst]. *)
val blit : string -> int -> string -> int -> int -> unit

(** [String.concat sep sl] catenates the list of strings [sl],
   inserting the separator string [sep] between each. *)
val concat : string -> string list -> string

(** [String.iter f s] applies function [f] in turn to all
   the characters of [s].  It is equivalent to
   [f s.(0); f s.(1); ...; f s.(String.length s - 1); ()]. *)
val iter : (char -> unit) -> string -> unit

(** Return a copy of the argument, with special characters
   represented by escape sequences, following the lexical
   conventions of Objective Caml.  If there is no special
   character in the argument, return the original string itself,
   not a copy. *)
val escaped: string -> string

(** [String.index s c] returns the position of the leftmost
   occurrence of character [c] in string [s].
   Raise [Not_found] if [c] does not occur in [s]. *)
val index: string -> char -> int

(** [String.rindex s c] returns the position of the rightmost
   occurrence of character [c] in string [s].
   Raise [Not_found] if [c] does not occur in [s]. *)
val rindex: string -> char -> int

(** Same as {!String.index}, but start
   searching at the character position given as second argument.
   [String.index s c] is equivalent to [String.index_from s 0 c].*)
val index_from: string -> int -> char -> int

(** Same as {!String.rindex}, but start
   searching at the character position given as second argument.
   [String.rindex s c] is equivalent to
   [String.rindex_from s (String.length s - 1) c]. *)
val rindex_from: string -> int -> char -> int


(** [String.contains s c] tests if character [c]
   appears in the string [s]. *)
val contains : string -> char -> bool

(** [String.contains_from s start c] tests if character [c]
   appears in the substring of [s] starting from [start] to the end
   of [s].
   Raise [Invalid_argument] if [start] is not a valid index of [s]. *)
val contains_from : string -> int -> char -> bool

(** [String.rcontains_from s stop c] tests if character [c]
   appears in the substring of [s] starting from the beginning
   of [s] to index [stop].
   Raise [Invalid_argument] if [stop] is not a valid index of [s]. *)
val rcontains_from : string -> int -> char -> bool

(** Return a copy of the argument, with all lowercase letters
   translated to uppercase, including accented letters of the ISO
   Latin-1 (8859-1) character set. *)
val uppercase: string -> string

(** Return a copy of the argument, with all uppercase letters
   translated to lowercase, including accented letters of the ISO
   Latin-1 (8859-1) character set. *)
val lowercase: string -> string

(** Return a copy of the argument, with the first letter set to uppercase. *)
val capitalize: string -> string

(** Return a copy of the argument, with the first letter set to lowercase. *)
val uncapitalize: string -> string


(**/**)

external unsafe_get : string -> int -> char = "%string_unsafe_get"
external unsafe_set : string -> int -> char -> unit = "%string_unsafe_set"
external unsafe_blit : string -> int -> string -> int -> int -> unit
        = "blit_string" "noalloc"
external unsafe_fill : string -> int -> int -> char -> unit
        = "fill_string" "noalloc"
