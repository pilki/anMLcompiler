(***********************************************************************)
(*                                                                     *)
(*                           Objective Caml                            *)
(*                                                                     *)
(*         Jerome Vouillon, projet Cristal, INRIA Rocquencourt         *)
(*                                                                     *)
(*  Copyright 2002 Institut National de Recherche en Informatique et   *)
(*  en Automatique.  All rights reserved.  This file is distributed    *)
(*  under the terms of the GNU Library General Public License, with    *)
(*  the special exception on linking described in file ../LICENSE.     *)
(*                                                                     *)
(***********************************************************************)

(* $Id$ *)

open Obj

(**** Object representation ****)

let last_id = ref 0
let new_id () =
  let id = !last_id in incr last_id; id

let set_id o id =
  let id0 = !id in
  Array.unsafe_set (Obj.magic o : int array) 1 id0;
  id := id0 + 1

(**** Object copy ****)

let copy o =
  let o = (Obj.obj (Obj.dup (Obj.repr o))) in
  set_id o last_id;
  o

(**** Compression options ****)
(* Parameters *)
type params = {
    mutable compact_table : bool;
    mutable copy_parent : bool;
    mutable clean_when_copying : bool;
    mutable retry_count : int;
    mutable bucket_small_size : int
  } 

let params = {
  compact_table = true;
  copy_parent = true;
  clean_when_copying = true;
  retry_count = 3;
  bucket_small_size = 16
} 

(**** Parameters ****)

let step = Sys.word_size / 16
let first_bucket = 0
let bucket_size = 32                    (* Must be 256 or less *)
let initial_object_size = 2

(**** Items ****)

type item

let dummy_item = (magic () : item)

(**** Types ****)

type label = int
type closure = item
type obj = t array
external ret : (obj -> 'a) -> closure = "%identity"

(**** Labels ****)

let public_method_label s =
  let accu = ref 0 in
  for i = 0 to String.length s - 1 do
    accu := 223 * !accu + Char.code s.[i]
  done;
  (* reduce to 31 bits *)
  accu := !accu land (1 lsl 31 - 1);
  (* make it signed for 64 bits architectures *)
  if !accu > 0x3FFFFFFF then !accu - (1 lsl 31) else !accu

(**** Sparse array ****)

module Vars = Map.Make(struct type t = string let compare = compare end)
type vars = int Vars.t

module Meths = Map.Make(struct type t = string let compare = compare end)
type meths = label Meths.t
module Labs = Map.Make(struct type t = label let compare = compare end)
type labs = bool Labs.t

(* The compiler assumes that the first field of this structure is [size]. *)
type table =
 { mutable size: int;
   mutable methods: closure array;
   mutable methods_by_name: meths;
   mutable methods_by_label: labs;
   mutable previous_states:
     (meths * labs * (label * item) list * vars *
      label list * string list) list;
   mutable hidden_meths: (label * item) list;
   mutable vars: vars;
   mutable initializers: (obj -> unit) list }

let dummy_table =
  { methods = [| |];
    methods_by_name = Meths.empty;
    methods_by_label = Labs.empty;
    previous_states = [];
    hidden_meths = [];
    vars = Vars.empty;
    initializers = [];
    size = 0 }

let table_count = ref 0

let new_table public =
  incr table_count;
  { methods = [| public |];
    methods_by_name = Meths.empty;
    methods_by_label = Labs.empty;
    previous_states = [];
    hidden_meths = [];
    vars = Vars.empty;
    initializers = [];
    size = initial_object_size }

let resize array new_size =
  let old_size = Array.length array.methods in
  if new_size > old_size then begin
    let new_buck = Array.create new_size dummy_item in
    Array.blit array.methods 0 new_buck 0 old_size;
    array.methods <- new_buck
 end

let put array label element =
  resize array (label + 1);
  array.methods.(label) <- element

(**** Classes ****)

let method_count = ref 0
let inst_var_count = ref 0

type t
type meth = item

let new_method table =
  let index = Array.length table.methods in
  resize table (index + 1);
  index

let get_method_label table name =
  try
    Meths.find name table.methods_by_name
  with Not_found ->
    let label = new_method table in
    table.methods_by_name <- Meths.add name label table.methods_by_name;
    table.methods_by_label <- Labs.add label true table.methods_by_label;
    label

let set_method table label element =
  incr method_count;
  if Labs.find label table.methods_by_label then
    put table label element
  else
    table.hidden_meths <- (label, element) :: table.hidden_meths

let get_method table label =
  try List.assoc label table.hidden_meths
  with Not_found -> table.methods.(label)

let to_list arr =
  if arr == magic 0 then [] else Array.to_list arr

let narrow table vars virt_meths concr_meths =
  let vars = to_list vars
  and virt_meths = to_list virt_meths
  and concr_meths = to_list concr_meths in
  let virt_meth_labs = List.map (get_method_label table) virt_meths in
  let concr_meth_labs = List.map (get_method_label table) concr_meths in
  table.previous_states <-
     (table.methods_by_name, table.methods_by_label, table.hidden_meths,
      table.vars, virt_meth_labs, vars)
     :: table.previous_states;
  table.vars <- Vars.empty;
  let by_name = ref Meths.empty in
  let by_label = ref Labs.empty in
  List.iter2
    (fun met label ->
       by_name := Meths.add met label !by_name;
       by_label :=
          Labs.add label
            (try Labs.find label table.methods_by_label with Not_found -> true)
            !by_label)
    concr_meths concr_meth_labs;
  List.iter2
    (fun met label ->
       by_name := Meths.add met label !by_name;
       by_label := Labs.add label false !by_label)
    virt_meths virt_meth_labs;
  table.methods_by_name <- !by_name;
  table.methods_by_label <- !by_label;
  table.hidden_meths <-
     List.fold_right
       (fun ((lab, _) as met) hm ->
          if List.mem lab virt_meth_labs then hm else met::hm)
       table.hidden_meths
       []

let widen table =
  let (by_name, by_label, saved_hidden_meths, saved_vars, virt_meths, vars) =
    List.hd table.previous_states
  in
  table.previous_states <- List.tl table.previous_states;
  table.vars <-
     List.fold_left
       (fun s v -> Vars.add v (Vars.find v table.vars) s)
       saved_vars vars;
  table.methods_by_name <- by_name;
  table.methods_by_label <- by_label;
  table.hidden_meths <-
     List.fold_right
       (fun ((lab, _) as met) hm ->
          if List.mem lab virt_meths then hm else met::hm)
       table.hidden_meths
       saved_hidden_meths

let new_slot table =
  let index = table.size in
  table.size <- index + 1;
  index

let new_variable table name =
  let index = new_slot table in
  table.vars <- Vars.add name index table.vars;
  index

let new_variables table names =
  let index = new_variable table names.(0) in
  for i = 1 to Array.length names - 1 do
    ignore (new_variable table names.(i))
  done;
  index

let get_variable table name =
  Vars.find name table.vars

let add_initializer table f =
  table.initializers <- f::table.initializers

let create_table public_map public_methods =
  let table = new_table public_map in
  if public_methods != magic 0 then
    Array.iter
      (function met ->
        let lab = new_method table in
        table.methods_by_name  <- Meths.add met lab table.methods_by_name;
        table.methods_by_label <- Labs.add lab true table.methods_by_label)
      public_methods;
  table

let init_class table =
  inst_var_count := !inst_var_count + table.size - 1;
  table.initializers <- List.rev table.initializers

let inherits cla vals virt_meths concr_meths (_, super, _, env) top =
  narrow cla vals virt_meths concr_meths;
  let init =
    if top then super cla env else Obj.repr (super cla) in
  widen cla;
  init

let make_class pub_map pub_meths class_init =
  let table = create_table pub_map pub_meths in
  let env_init = class_init table in
  init_class table;
  (env_init (Obj.repr 0), class_init, env_init, Obj.repr 0)

type init_table = { mutable env_init: t; mutable class_init: table -> t }

let make_class_store pub_map pub_meths class_init init_table =
  let table = create_table pub_map pub_meths in
  let env_init = class_init table in
  init_class table;
  init_table.class_init <- class_init;
  init_table.env_init <- env_init

(**** Objects ****)

let create_object table =
  (* XXX Appel de [obj_block] *)
  let obj = Obj.new_block Obj.object_tag table.size in
  (* XXX Appel de [modify] *)
  Obj.set_field obj 0 (Obj.repr table.methods);
  set_id obj last_id;
  (Obj.obj obj)

let create_object_opt obj_0 table =
  if (Obj.magic obj_0 : bool) then obj_0 else begin
    (* XXX Appel de [obj_block] *)
    let obj = Obj.new_block Obj.object_tag table.size in
    (* XXX Appel de [modify] *)
    Obj.set_field obj 0 (Obj.repr table.methods);
    set_id obj last_id;
    (Obj.obj obj)
  end

let rec iter_f obj =
  function
    []   -> ()
  | f::l -> f obj; iter_f obj l

let run_initializers obj table =
  let inits = table.initializers in
  if inits <> [] then
    iter_f obj inits

let run_initializers_opt obj_0 obj table =
  if (Obj.magic obj_0 : bool) then obj else begin
    let inits = table.initializers in
    if inits <> [] then iter_f obj inits;
    obj
  end

let create_object_and_run_initializers obj_0 table =
  if (Obj.magic obj_0 : bool) then obj_0 else begin
    let obj = create_object table in
    run_initializers obj table;
    obj
  end

(* Equivalent primitive below
let send obj lab =
  let (buck, elem) = decode lab in
  (magic obj : (obj -> t) array array array).(0).(buck).(elem) obj
*)
external send : obj -> label -> 'a = "%send"

(**** table collection access ****)

type tables = Empty | Cons of table * tables * tables
type mut_tables =
    {key: table; mutable data: tables; mutable next: tables}
external mut : tables -> mut_tables = "%identity"

let build_path n keys tables =
  let res = Cons (Obj.magic 0, Empty, Empty) in
  let r = ref res in
  for i = 0 to n do
    r := Cons (keys.(i), !r, Empty)
  done;
  tables.data <- !r;
  res

let rec lookup_keys i keys tables =
  if i < 0 then tables else
  let key = keys.(i) in
  let rec lookup_key tables =
    if tables.key == key then lookup_keys (i-1) keys tables.data else
    if tables.next <> Empty then lookup_key (mut tables.next) else
    let next = Cons (key, Empty, Empty) in
    tables.next <- next;
    build_path (i-1) keys (mut next)
  in
  lookup_key (mut tables)

let lookup_tables root keys =
  let root = mut root in
  if root.data <> Empty then
    lookup_keys (Array.length keys - 1) keys root.data
  else
    build_path (Array.length keys - 1) keys root

(**** builtin methods ****)

let get_const x = ret (fun obj -> x)
let get_var n   = ret (fun obj -> Array.unsafe_get obj n)
let get_env e n = ret (fun obj -> Obj.field (Array.unsafe_get obj e) n)
let get_meth n  = ret (fun obj -> send obj n)
let set_var n   = ret (fun obj x -> Array.unsafe_set obj n x)
let app_const f x = ret (fun obj -> f x)
let app_var f n   = ret (fun obj -> f (Array.unsafe_get obj n))
let app_env f e n = ret (fun obj -> f (Obj.field (Array.unsafe_get obj e) n))
let app_meth f n  = ret (fun obj -> f (send obj n))
let app_const_const f x y = ret (fun obj -> f x y)
let app_const_var f x n   = ret (fun obj -> f x (Array.unsafe_get obj n))
let app_const_meth f x n = ret (fun obj -> f x (send obj n))
let app_var_const f n x = ret (fun obj -> f (Array.unsafe_get obj n) x)
let app_meth_const f n x = ret (fun obj -> f (send obj n) x)
let app_const_env f x e n =
  ret (fun obj -> f x (Obj.field (Array.unsafe_get obj e) n))
let app_env_const f e n x =
  ret (fun obj -> f (Obj.field (Array.unsafe_get obj e) n) x)
let meth_app_const n x = ret (fun obj -> (send obj n) x)
let meth_app_var n m =
  ret (fun obj -> (send obj n) (Array.unsafe_get obj m))
let meth_app_env n e m =
  ret (fun obj -> (send obj n) (Obj.field (Array.unsafe_get obj e) m))
let meth_app_meth n m =
  ret (fun obj -> (send obj n) (send obj m))

type impl =
    GetConst
  | GetVar
  | GetEnv
  | GetMeth
  | SetVar
  | AppConst
  | AppVar
  | AppEnv
  | AppMeth
  | AppConstConst
  | AppConstVar
  | AppConstEnv
  | AppConstMeth
  | AppVarConst
  | AppEnvConst
  | AppMethConst
  | MethAppConst
  | MethAppVar
  | MethAppEnv
  | MethAppMeth
  | Closure of Obj.t

let method_impl i arr =
  let next () = incr i; magic arr.(!i) in
  match next() with
    GetConst -> let x : t = next() in ret (fun obj -> x)
  | GetVar   -> let n = next() in get_var n
  | GetEnv   -> let e = next() and n = next() in get_env e n
  | GetMeth  -> let n = next() in get_meth n
  | SetVar   -> let n = next() in set_var n
  | AppConst -> let f = next() and x = next() in ret (fun obj -> f x)
  | AppVar   -> let f = next() and n = next () in app_var f n
  | AppEnv   ->
      let f = next() and e = next() and n = next() in app_env f e n
  | AppMeth  -> let f = next() and n = next () in app_meth f n
  | AppConstConst ->
      let f = next() and x = next() and y = next() in ret (fun obj -> f x y)
  | AppConstVar ->
      let f = next() and x = next() and n = next() in app_const_var f x n
  | AppConstEnv ->
      let f = next() and x = next() and e = next () and n = next() in
      app_const_env f x e n
  | AppConstMeth ->
      let f = next() and x = next() and n = next() in app_const_meth f x n
  | AppVarConst ->
      let f = next() and n = next() and x = next() in app_var_const f n x
  | AppEnvConst ->
      let f = next() and e = next () and n = next() and x = next() in
      app_env_const f e n x
  | AppMethConst ->
      let f = next() and n = next() and x = next() in app_meth_const f n x
  | MethAppConst ->
      let n = next() and x = next() in meth_app_const n x
  | MethAppVar ->
      let n = next() and m = next() in meth_app_var n m
  | MethAppEnv ->
      let n = next() and e = next() and m = next() in meth_app_env n e m
  | MethAppMeth ->
      let n = next() and m = next() in meth_app_meth n m
  | Closure _ as clo -> magic clo

let set_methods table methods =
  let len = Array.length methods and i = ref 0 in
  while !i < len do
    let label = methods.(!i) and clo = method_impl i methods in
    set_method table label clo;
    incr i
  done

(**** Statistics ****)

type stats =
  { classes: int; methods: int; inst_vars: int; }

let stats () =
  { classes = !table_count;
    methods = !method_count; inst_vars = !inst_var_count; }
