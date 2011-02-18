(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Luc Maranget, projet Moscova, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 2004 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the Q Public License version 1.0.               *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

(** Map/reduce implementation based on pools.

    The algorithm can be sketched out as follows:
    - the server generates a list of input values;
    - clients register to perform computations from input values to
      (key, value) lists through a {i map} function;
    - the server dispatches input values to clients using a
      a pool structure ({i cf.} {!JoinPool.Simple.t}),
      and merges values for the same key using a {i combine} function;
    - when all input values have been generated by the server, and all
      associated results have been sent by the clients, the server computes
      the overall result through a {i reduce} function. *)


module type Problem = sig
  val identifier : string
  (** The identifier for the problem, used to enable multiple map/reduce
      problems on a single server. *)

  type init
  (** The type of data sent by server to clients at startup. *)

  type client_data
  (** The type of client data (that is value computed at startup). *)

  type input
  (** The type of input values passed to client agents. *)

  type key
  (** The type of keys returned by client agents. *)

  type value
  (** The type of values returned by client agents. *)

  type output
  (** The type of overall result. *)

  val init_client : init -> client_data
  (** Called at client startup with the data registered at server startup.
      The returned value will be passed at each [map] call. *)

  val compare_keys : key -> key -> int
  (** Ordering over keys. Should follow the contract of {Pervasives.compare}. *)

  val map : client_data -> input -> (key * value) list
  (** The computation actually done by client agents. *)

  val combine : value -> value -> value
  (** Used by the server to combine values associated with the same key,
      [compare_keys] being used for key equality. *)

  val reduce : key -> value -> output -> output
  (** Used by the server to fold all client results at the end of the computation. *)
end
(** Input signature of the functor {!JoinMapRed.Make}. *)

module type S = sig
  type init
  (** The type of data sent by server to clients at startup. *)

  type input
  (** The type of input values passed to agents. *)

  type output
  (** The type of overall result. *)

  val client : JoinHelper.configuration -> unit
  (** [client cfg] uses the [cfg] to connect to the server, and registers itself
      to receive computations ({i i.e.} executions of {!JoinMapRed.Problem.map}). *)

  val server :
      JoinHelper.configuration -> init ->
        ('a, input) JoinPool.Simple.enum -> output -> output
  (** [server cfg i e z] sets up a server using the passed configuration, and
      dispatches tasks to registered clients using a pool.

      The result is [reduce k1 v1 (reduce k2 v2 (... (reduce kn vn z)))]
      where:
      - [reduce] is a shorthand for {!JoinMapRed.Problem.reduce};
      - the [(ki, vi)] couples are the values returned by the client agents
        (outcomes of {!JoinMapRed.Problem.map} applications for [xi]),
        the [vi] being combined through {!JoinMapRed.Problem.combine}
        for equal keys;
      - the [xi] are the values successively returned by [e]. *)
end
(** Output signature of the functor {!JoinMapRed.Make}. *)

module Make : functor (P : Problem) -> S
  with type input = P.input and type output = P.output and type init = P.init
(** Functor building a map/reduce implementation for a given problem. *)
