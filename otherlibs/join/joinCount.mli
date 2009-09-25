(***********************************************************************)
(*                                                                     *)
(*                           JoCaml                                    *)
(*                                                                     *)
(*            Luc Maranget, projet Moscova, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 2008 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(** Counting {i n} asynchronous events

  The following submodules are successive refinements of
  the {e count {i n} events} programming idiom.
  Here an event is a message sent on an asynchronous channel.

    - {!Down} just counts {i n} messages sent on a [tick] channel.
    - {!Collector} additionnaly computes a resut from the messages
      sent on a [collect] channel.
    - {!Dynamic} is a refinement of [Collector] where {i n} is not
      known in advance.
*)

(** Simple countdowns. *)
module Down :
  sig
    type ('a, 'b) t = { tick : unit Join.chan; wait : unit -> unit; }

    val create : int -> ('a, 'b) t
    (** [create n] returns a countdown [c] for [n] events.
        That is, after [n] messages on [c.tick], the call
	[c.wait()] will return.
        Observe that at most one call [c.wait()] returns.*)
  end


(** Collecting countdowns, or {e collectors}. *)
module Collector :
  sig
    type ('a, 'b) t = { collect : 'a Join.chan; wait : unit -> 'b; }
    (** Type of collectors.

     Collectors are refinements of countdowns, which collect and
     combine [n] partial results (type ['a]) into a final result
     (type ['b]). Given a collector [c] for [n] events, with
     combining function [comb] and initial result [y0]:
       - The [n] events, [x1],...,[xn], are sent as [n] messages
         on [c.collect]. Notice that the notation [xi] does
         not imply any kind of ordering.
       - Then [c.wait()] returns the
          value [comb x1 (comb x2 (... (comb xn y0)))].
          Again, at most one call  [c.wait()] returns.
    *)

    val create : ('a -> 'b -> 'b) -> 'b -> int -> ('a, 'b) t
    (** [create comb y0 n] returns a collector of [n]
	events of type ['a],  with combining function [comb] and initial
        result [y0]. *)  
  end


(** Dynamic collectors *)
module Dynamic :
  sig
    type ('a, 'b) t = {
      enter : unit -> unit;
      leave : 'a Join.chan;
      wait : unit -> 'b;
      finished : unit Join.chan;
    }
   (** Dynamic collectors are refinement of simple collectors,
       for which the number of events to collect need not be given in
       advance.

      Given a dynamic collector [c], defined as [create comb y0]:
        - [c] is informed of the future occurence of an event [xi],
          by sending an unit message on [c.enter()].
        - [c] is informed of the occurence of event [xi] by sending
          a message [c.leave(xi)].
        - [c] is informed that no more event will occur by sending
          a message [c.finished()].

     Then the call [c.wait()] will return the combined result
          [comb x1 (comb x2 (... (comb xn y0)))], once all the announced
          events have occured. Observe that at most one such call is allowed.
    *)

    val create : ('a -> 'b -> 'b) -> 'b -> ('a, 'b) t
  (** [create comb y0] returns a dynamic  collector
	of events of type ['a],  with combining function [comb] and initial
        result [y0]. *)  
  end
