(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 1996 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

type stype =
  | DT_tuple of stype list
  | DT_node of node * stype list
  | DT_var of int

and record_representation =
  | Record_regular
  | Record_float

and mutable_flag =
  | Mutable
  | Immutable

and node = {
    node_id: string;
    node_definition: node_definition;
   }

and node_definition =
  | DT_record of record_definition
  | DT_variant of variant_definition
  | DT_abstract
  | DT_builtin

and record_definition = {
    record_representation:  record_representation;
    record_fields: (string * mutable_flag * stype) list;
   }

and variant_definition = {
    variant_constructors: (string * stype list) list;
   }


type 'a ttype = stype

let stype_of_ttype (x : 'a ttype) : stype = x

module NodePairHash = Hashtbl.Make
    (struct
      type t = node * node
      let equal (n1, n2) (n1', n2') =
        n1 == n1' && n2 == n2'
      let hash (n1, n2) =
        Hashtbl.hash (n1.node_id, n2.node_id)
    end)

module TypEq : sig
  type ('a, 'b) t
  val refl: ('a, 'a) t
  val trans: ('a, 'b) t -> ('b, 'c) t -> ('a, 'c) t
  val sym: ('a, 'b) t -> ('b, 'a) t
  val app: ('a, 'b) t -> 'a -> 'b
  val unsafe: ('a, 'b) t
end = struct
  type ('a, 'b) t = unit
  let refl = ()
  let trans () () = ()
  let sym () = ()

  let app () x = Obj.magic x
  let unsafe = ()
end

let stype_equality t1 t2 =
  let checked = NodePairHash.create 8 in
  let list f l1 l2 =
    if List.length l1 <> List.length l2 then raise Exit;
    List.iter2 f l1 l2
  in
  let rec aux t1 t2 =
    if t1 == t2 then ()
    else
    match t1, t2 with
    | DT_tuple tyl1, DT_tuple tyl2 -> list aux tyl1 tyl2
    | DT_node (n1, tyl1), DT_node (n2, tyl2) -> node n1 n2; list aux tyl1 tyl2
    | DT_var i1, DT_var i2 when i1 = i2 -> ()
    | _ -> raise Exit
  and node n1 n2 =
    if n1 == n2 || NodePairHash.mem checked (n1, n2) then ()
    else begin
      NodePairHash.add checked (n1, n2) ();
      match n1.node_definition, n2.node_definition with
      | DT_record r1, DT_record r2 when r1.record_representation = r2.record_representation ->
          list field r1.record_fields r2.record_fields
      | DT_variant v1, DT_variant v2 ->
          list constructor v1.variant_constructors v2.variant_constructors
      | DT_builtin, DT_builtin when n1.node_id = n2.node_id ->
          ()
      | _ -> raise Exit
    end
  and constructor (c1, tl1) (c2, tl2) =
    if c1 <> c2 then raise Exit;
    list aux tl1 tl2
  and field (f1, mut1, t1) (f2, mut2, t2) =
    if f1 <> f2 || mut1 <> mut2 then raise Exit;
    aux t1 t2
  in
  try aux t1 t2; true
  with Exit -> false

let equal t1 t2 =
  if stype_equality t1 t2 then Some TypEq.unsafe else None

let node_equal n1 n2 =
  stype_equality (DT_node (n1, [])) (DT_node (n2, []))

module type DYN = sig
  type t
  val x: t
  val t: t ttype
end

type dyn = (module DYN)

let dyn (type s) t x =
  let module M = struct
    type t = s
    let x = x
    let t = t
  end
  in
  (module M : DYN)

type 'a head =
  | DV_tuple of 'a list
  | DV_record of (string * 'a) list
  | DV_constructor of string * 'a list

let subst s =
  if Array.length s = 0 then fun t -> t
  else let rec aux = function
    | DT_tuple tl -> DT_tuple (List.map aux tl)
    | DT_node (node, tl) -> DT_node (node, List.map aux tl)
    | DT_var i -> s.(i)
  in
  aux

exception AbstractValue of node

let inspect d =
  let module M = (val d : DYN) in
  match M.t with
  | DT_tuple tl -> DV_tuple (List.map2 dyn tl (Array.to_list (Obj.magic M.x)))
  | DT_node (node, tyl) ->
      let s = subst (Array.of_list tyl) in
      begin match node.node_definition with
      | DT_abstract | DT_builtin ->
          raise (AbstractValue node)
      | DT_record {record_fields = l} ->
          DV_record (List.map2 (fun (lab, _mut, t) x -> lab, dyn (s t) x) l (Array.to_list (Obj.magic M.x)))
      | DT_variant {variant_constructors = l} ->
          let x = Obj.repr M.x in
          let (cst, n) = if Obj.is_int x then true, Obj.magic x else false, Obj.tag x in
          let rec find n = function
            | ((_, tl) as c) :: rest ->
                let n = if cst = (tl == []) then n - 1 else n in
                if n < 0 then c else find n rest
            | [] ->
                assert false
          in
          let (c, tl) = find n l in
          let args =
            if cst then []
            else List.map2 (fun t x -> dyn (s t) x) tl (Array.to_list (Obj.magic M.x))
          in
          DV_constructor (c, args)
      end
  | DT_var _ -> assert false

let build : 'a ttype -> < toval: 'b. 'b ttype -> 'b > head -> 'a = fun t h ->
  let tuple tag tl vl =
    let n = List.length tl in
    let o = Obj.new_block tag n in
    let vl = Array.of_list vl and tl = Array.of_list tl in
    for i = 0 to n - 1 do
      let v : < toval: 'b. 'b ttype -> 'b > = vl.(i) in
      Obj.set_field o i (Obj.repr (v # toval tl.(i)))
    done;
    Obj.magic o
  in
  match t with
  | DT_tuple tl ->
      begin match h with DV_tuple vl ->
        if List.length tl <> List.length vl then failwith (Printf.sprintf "Wrong number of components %i (expecting %i)" (List.length vl) (List.length tl));
        tuple 0 tl vl
      | _ -> failwith "Tuple expected."
      end
  | DT_node (node, tyl) ->
      let s = subst (Array.of_list tyl) in
      begin match node.node_definition with
      | DT_record {record_fields = tl; record_representation = r} ->
          begin match h with
          | DV_record vl ->
              if List.length tl <> List.length vl then failwith (Printf.sprintf "Wrong number of fields %i (expecting %i)" (List.length vl) (List.length tl));
              let l =
                List.map2
                  (fun (tf, _, t) (vf, v) ->
                    if tf <> vf then failwith (Printf.sprintf "Wrong label %s (expecting %s)" vf tf);
                    s t, v) tl vl
              in
              let tl, vl = List.split l in
              let o = tuple 0 tl vl in
              let o = match r with
              | Record_float ->
                  Obj.repr (Array.init (Obj.size o) (fun i -> (Obj.magic (Obj.field o i) : float)))
              | Record_regular ->
                  o
              in
              Obj.magic o
          | _ -> failwith "Record expected."
          end
      | DT_variant {variant_constructors = constrs} ->
          begin match h with
          | DV_constructor (c, vl) ->
              let cst = vl == [] in
              let tag = ref (-1) in
              let (_, tl) =
                try List.find (fun (c0, tl) -> if cst = (tl == []) then incr tag; c = c0) constrs
                with Not_found -> failwith (Printf.sprintf "Unexpected constructor %S" c)
              in
              if List.length tl <> List.length vl then failwith (Printf.sprintf "Wrong arity %i (expecting %i)" (List.length vl) (List.length tl));
              if tl == [] then
                Obj.magic !tag
              else
                let tl = List.map s tl in
                tuple !tag tl vl
          | _ -> failwith "Constructor expected."
          end
      | _ -> assert false (* TODO *)
      end
  | DT_var _ -> assert false


let tuple l =
  let l = List.map (fun d -> let module M = (val d : DYN) in stype_of_ttype M.t, Obj.magic M.x) l in
  let tl, vl = List.split l in
  dyn (DT_tuple tl) (Array.of_list vl)

let make_abstract_node name = {node_id = name; node_definition = DT_abstract}
let make_builtin_node name = {node_id = name; node_definition = DT_builtin}

module type TYPE0 = sig
  type t
  val node: node
  val ttype: t ttype
  val inspect: dyn -> t option
end

module type TYPE1 = sig
  type 'a t
  module type T = sig
    type a
    type b
    val b: b ttype
    val eq: (a, b t) TypEq.t
  end

  val node: node
  val ttype: 'a ttype -> 'a t ttype
  val decompose: 'a t ttype -> 'a ttype

  val check: 'a ttype -> (module T with type a = 'a) option

  module type V = sig
    type b
    val b: b ttype
    val x: b t
  end
  val inspect: dyn -> (module V) option
end

module MkType0(X : sig val node: node type t end) = struct
  include X
  let ttype = DT_node (X.node, [])
  let inspect d =
    let module M = (val d : DYN) in
    match equal M.t ttype with
    | None -> None
    | Some eq -> Some (TypEq.app eq M.x)
end

module MkType1(X : sig val node: node type 'a t end) = struct
  include X

  module type T = sig
    type a
    type b
    val b: b ttype
    val eq: (a, b t) TypEq.t
  end

  let ttype t = DT_node (X.node, [t])

  let decompose = function
    | DT_node (n, [t]) when node_equal n X.node ->
        t
    | _ -> assert false

  let check (type a_) = function
    | DT_node (n, [b]) when node_equal n X.node ->
        let m = (module struct
          type a = a_
          type b
          let b = b
          let eq = TypEq.unsafe
        end : T with type a = a_) in
        Some m
    | _ ->
        None

  module type V = sig
    type b
    val b: b ttype
    val x: b t
  end

  let inspect d =
    let module M = (val d : DYN) in
    match check M.t with
    | None -> None
    | Some w ->
        let module W = (val w : T with type a = M.t) in
        let module N = struct
          type b = W.b
          let b = W.b
          let x = TypEq.app W.eq M.x
        end
        in
        let n = (module N : V) in
        Some n
end

module Abstract0(X : sig val name: string type t end) =
  MkType0(struct let node = make_abstract_node X.name type t = X.t end)

module Abstract1(X : sig val name: string type 'a t end) =
  MkType1(struct let node = make_abstract_node X.name type 'a t = 'a X.t end)

module Builtin0(X : sig val name: string type t end) =
  MkType0(struct let node = make_abstract_node X.name type t = X.t end)

module Builtin1(X : sig val name: string type 'a t end) =
  MkType1(struct let node = make_builtin_node X.name type 'a t = 'a X.t end)

module DInt = Builtin0(struct let name = "int" type t = int end)
module DString = Builtin0(struct let name = "string" type t = string end)
module DFloat = Builtin0(struct let name = "float" type t = float end)

module DList = MkType1(struct
  type 'a t = 'a list
  let rec node = {node_id = "list";
                  node_definition =
                  DT_variant {
                  variant_constructors = [
                  "[]", [];
                  "::", [DT_var 0;
                         DT_node (node, [DT_var 0])] ]}
                 }
  (* This must be synchronized with predef.ml.
     We could rely on the compiler to produce the node, but this would make
     this module depends on the new features and make bootstrap more complicated. *)
end)

module DOption = MkType1(struct
  type 'a t = 'a option
  let rec node = {node_id = "option";
                  node_definition =
                  DT_variant {variant_constructors = ["None", []; "Some", [DT_var 0]]}
                 }
end)

module DArray = Builtin1(struct let name = "array" type 'a t = 'a array end)

module DBool = MkType0(struct
  type t = bool
  let node = {node_id = "bool";
              node_definition =
              DT_variant {variant_constructors = ["false", []; "true", []]}
             }
end)