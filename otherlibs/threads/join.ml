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

open Printf

(*DEBUG*)let verbose =
(*DEBUG*)  try int_of_string (Sys.getenv "VERBOSE") with | _ -> 0
(*DEBUG*)
(*DEBUG*)let debug_mutex = Mutex.create ()
(*DEBUG*)
(*DEBUG*)let debug lvl source msg =
(*DEBUG*)  if verbose >= lvl then begin
(*DEBUG*)   Mutex.lock debug_mutex ;
(*DEBUG*)    eprintf "%s[%i]: %s\n" source (Thread.id (Thread.self ())) msg ;
(*DEBUG*)    flush stderr ;
(*DEBUG*)    Mutex.unlock debug_mutex
(*DEBUG*)  end
(*DEBUG*)
(*DEBUG*)let debug1 = debug 1
(*DEBUG*)and debug2 = debug 2
(*DEBUG*)and debug3 = debug 3


(*
   Active tasks.
     A task is active when :
      * running compiled code
      * or in lib code, doomed to become inactive and not to create
        other tasks.

     A task is inactive when :
      * suspended, awaiting synchronous reply
      * simply finished (ie exit_thread is performed)
*)

let active_mutex = Mutex.create ()
and active_condition = Condition.create ()
and active = ref 1
and in_pool = ref 0
and pool_konts = ref 0
(* Number of threads devoted to join *)
(*DEBUG*)and nthreads = ref 1
(*DEBUG*)and suspended = ref 0
(*DEBUG*)and nthreads_mutex = Mutex.create()

let incr_locked r =
  Mutex.lock nthreads_mutex ;
  incr r ;
  Mutex.unlock nthreads_mutex

and decr_locked r =
  Mutex.lock nthreads_mutex ;
  decr r ;
  Mutex.unlock nthreads_mutex


let check_active () =
(*DEBUG*)debug2 "CHECK"
(*DEBUG*) (sprintf "active=%i, nthreads=%i, suspended=%i[%i,%i]"
(*DEBUG*)   !active !nthreads !suspended !in_pool !pool_konts) ;
  if !active <= 0 then Condition.signal active_condition

let become_inactive () =
  Mutex.lock active_mutex ;
  decr active ;
  Mutex.unlock active_mutex ;
 (* if active reaches 0, this cannot change, so we unlock now *)
  check_active () ;

(* incr_active is performed by task creator or awaker *)
and incr_active () =
  Mutex.lock active_mutex ;
  incr active ;
  Mutex.unlock active_mutex

(*************************************)
(* Real threads creation/destruction *)
(*************************************)

external thread_new : (unit -> unit) -> Thread.t = "caml_thread_new"
external thread_uncaught_exception : exn -> unit = "caml_thread_uncaught_exception"


let pool_size =
  try
    int_of_string (Sys.getenv "POOLSIZE")
  with
  | _ -> 10
and runmax =
   try
    Some (int_of_string (Sys.getenv "RUNMAX"))
  with
  | _ -> None
(*DEBUG*)let tasks_status () =
(*DEBUG*)sprintf "active=%i, nthread=%i suspended=%i[%i, %i]"
(*DEBUG*) !active !nthreads !suspended !in_pool
(*DEBUG*) (!pool_konts)


let really_exit_thread () =
  decr_locked nthreads ;
(*DEBUG*)debug1 "REAL EXIT" (sprintf "nthreads=%i" !nthreads);
  Thread.exit ()

(* Note: really_create_process
   uses thread_new, to short-circuit handling of exceptions by Thread *)  

exception MaxRun

let really_create_process f =
  incr_locked nthreads ;
  try
    begin match runmax with
    | Some k when !nthreads - !suspended > k -> raise MaxRun
    | _ -> ()
    end ;
    let t = Thread.id (thread_new f) in
(*DEBUG*)debug1 "REAL FORK"
(*DEBUG*) (sprintf "%i nthread=%i suspended=%i[%i]"
(*DEBUG*)   t !nthreads !suspended !in_pool) ;
    ignore(t) ;
    true
  with
  | e ->
(*DEBUG*)debug2 "REAL FORK FAILED"
(*DEBUG*)  (sprintf "%s, %s" (tasks_status ()) (Printexc.to_string e)) ;
      decr_locked nthreads ;
      false
      


(****************)
(* Thread cache *)
(****************)

let pool_condition = Condition.create ()
and pool_mutex = Mutex.create ()
and pool_kont = ref [] 

let rec do_pool () =
  incr in_pool ;
(*DEBUG*)incr_locked suspended ;
(*DEBUG*)debug2 "POOL SLEEP" (tasks_status ()) ;
  Condition.wait pool_condition pool_mutex ;
(*DEBUG*)decr_locked suspended ;
(*DEBUG*)debug2 "POOL AWAKE" (tasks_status ()) ;
  decr in_pool ;
  match !pool_kont with
  | f::rem ->
      pool_kont := rem ; decr pool_konts ;
(*DEBUG*)debug2 "POOL RUN" (sprintf "%i" (Thread.id (Thread.self()))) ;
      Mutex.unlock pool_mutex ;
      f ()
  | [] ->
      do_pool ()

(* Get a chance to avoid suspending *)
let pool_enter () =
  Mutex.lock pool_mutex ;
  match !pool_kont with
  | f::rem ->
      pool_kont := rem ; decr pool_konts ;
      Mutex.unlock pool_mutex ;
(*DEBUG*)debug2 "POOL FIRST RUN" (sprintf "%i" (Thread.id (Thread.self()))) ;
      f ()
  | [] ->
      do_pool ()

let rec grab_from_pool delay =
  Mutex.lock pool_mutex ;
  if !in_pool > 0 then begin
    Condition.signal pool_condition ;
    Mutex.unlock pool_mutex
  end else match !pool_kont with
  | f::rem ->
      pool_kont := rem ; decr pool_konts ;
      Mutex.unlock pool_mutex ;
      if not (really_create_process f) then begin
        Mutex.lock pool_mutex ;
        pool_kont := f :: !pool_kont ; incr pool_konts ;
        Mutex.unlock pool_mutex ;
        prerr_endline "Threads exhausted" ;
        Thread.delay delay ;
        grab_from_pool (1.0 +. delay)
      end
  | [] ->
      Mutex.unlock pool_mutex

let exit_thread () =
(*DEBUG*)debug2 "EXIT THREAD" (tasks_status ()) ;
  become_inactive () ;
  if !in_pool >= pool_size && !active > !pool_konts then
    really_exit_thread ()
  else 
    pool_enter ()

let put_pool f =
  Mutex.lock pool_mutex ;
  pool_kont := f :: !pool_kont ; incr pool_konts ;
  Condition.signal pool_condition ;
(*DEBUG*)debug2 "PUT POOL" (tasks_status ()) ;
  Mutex.unlock pool_mutex

let create_process f =
(*DEBUG*)debug2 "CREATE_PROCESS" (tasks_status ()) ;
  incr_active () ;
(* Wapper around f, to be sure to call my exit_thread *)  
  let g () = 
    begin try f ()
    with e ->
      flush stdout; flush stderr;
      thread_uncaught_exception e
    end ;
    exit_thread () in

  if !in_pool = 0 then begin
    if not (really_create_process g) then put_pool g 
  end else begin
    put_pool g
  end

type queue = Obj.t list

type status = int

type automaton = {
  mutable status : status ;
  mutex : Mutex.t ;
  queues : queue array ;
  mutable matches : (reaction) array ;
  names : Obj.t ;
} 

and reaction = status * int * (Obj.t -> Obj.t)

let put_queue auto idx a = auto.queues.(idx) <- a :: auto.queues.(idx)

let get_queue auto idx = match auto.queues.(idx) with
| [] -> assert false
| a::rem ->
    auto.queues.(idx) <- rem ;
    begin match rem with
    | [] -> auto.status <- auto.status land (lnot (1 lsl idx))
    | _  -> ()
    end ;
    a

let create_automaton nchans =
  {
    status = 0 ;
    mutex = Mutex.create () ;
    queues = Array.create nchans [] ;
    matches = [| |] ;
    names = Obj.magic 0 ;
  } 

let create_automaton_debug nchans names =
  {
    status = 0 ;
    mutex = Mutex.create () ;
    queues = Array.create nchans [] ;
    matches = [| |] ;
    names = names ;
  } 

let get_name auto idx = Obj.magic (Obj.field auto.names idx)

let patch_table auto t = auto.matches <- t

type kval = Start | Go of (unit -> Obj.t) | Ret of Obj.t

type continuation =
  { kmutex : Mutex.t ;
    kcondition : Condition.t ;
    mutable kval : kval }


(* Continuation mutex is automaton mutex *)
let kont_create auto =
  {kmutex = auto.mutex ;
   kcondition = Condition.create () ;
   kval = Start}

(**********************)
(* Asynchronous sends *)
(**********************)

type async =
    Async of (automaton) * int
  | Alone of (automaton) * int


let create_async auto i = Async (auto, i)
and create_async_alone auto g = Alone (auto, g)


(* Callbacks from compiled code *)

(* Transfert control to frozen principal thread *)
let kont_go k f =
  incr_active () ;
(*DEBUG*)debug2 "KONT_GO" "" ;
  k.kval <- Go f ;
  Condition.signal k.kcondition ;
  Mutex.unlock k.kmutex

(* Spawn new process *)
let fire_go auto f =
(*DEBUG*)debug3 "FIRE_GO" "" ;
  Mutex.unlock auto.mutex ;
  create_process f

(* Transfer control to current thread
   can be called when send triggers a match in the async case
   in thread-tail position *)
let just_go_async auto f =
(*DEBUG*)debug3 "JUST_GO_ASYNC" "" ;
  Mutex.unlock auto.mutex ;
  f ()

let rec attempt_match tail auto reactions idx i =
  if i >= Obj.size reactions then begin
(*DEBUG*)debug3 "ATTEMPT FAILED" (sprintf "%s %i" (get_name auto idx) auto.status) ;    
    Mutex.unlock auto.mutex
  end else begin
    let (ipat, iprim, f) = Obj.magic (Obj.field reactions i) in
    if ipat land auto.status = ipat then
      if iprim < 0 then begin
        f (if tail then just_go_async else fire_go) (* f will unlock auto's mutex *)
      end else begin
        f kont_go
      end
    else
      attempt_match tail auto reactions idx (i+1)
  end

let direct_send_async auto idx a =
(*DEBUG*)debug3 "SEND_ASYNC" (sprintf "channel=%s, status=%x"
(*DEBUG*)                      (get_name auto idx) auto.status ) ;
(* Acknowledge new message by altering queue and status *)
  Mutex.lock auto.mutex ;
  let old_status = auto.status in
  let new_status = old_status lor (1 lsl idx) in
  put_queue auto idx a ;
  auto.status <- new_status ;
  if old_status = new_status then begin
(*DEBUG*)debug3 "SEND_ASYNC" (sprintf "Return: %i" auto.status) ;
    Mutex.unlock auto.mutex
  end else begin
    attempt_match false auto (Obj.magic auto.matches) idx 0
  end

(* Optimize forwarders *)
and direct_send_async_alone auto g a =
(*DEBUG*)  debug3 "SEND_ASYNC_ALONE" (sprintf "match %i" g) ;
  let _,_,f = Obj.magic (Obj.field (Obj.magic auto.matches) g) in
  create_process (fun () -> f a)


let send_async chan a = match chan with
| Async (auto, idx) -> direct_send_async auto idx a
| Alone (auto, g)   -> direct_send_async_alone auto g a


let tail_direct_send_async auto idx a =
(*DEBUG*)debug3 "TAIL_ASYNC" (sprintf "channel %s, status=%i"
(*DEBUG*)       (get_name auto idx) auto.status) ;
(* Acknowledge new message by altering queue and status *)
  Mutex.lock auto.mutex ;
  let old_status = auto.status in
  let new_status = old_status lor (1 lsl idx) in
  put_queue auto idx a ;
  auto.status <- new_status ;
  if old_status = new_status then begin
(*DEBUG*)    debug3 "TAIL_ASYNC" (sprintf "Return: %i" auto.status) ;
    Mutex.unlock auto.mutex
  end else begin
    attempt_match true auto (Obj.magic auto.matches) idx 0
  end


(* Optimize forwarders *)

and tail_direct_send_async_alone auto g a =
(*DEBUG*)  debug3 "TAIL_ASYNC_ALONE" (sprintf "match %i" g) ;
  let _,_,f = Obj.magic (Obj.field (Obj.magic auto.matches) g) in
  f a

let tail_send_async chan a = match chan with
| Async (auto, idx) -> tail_direct_send_async auto idx a
| Alone (auto, g)   -> tail_direct_send_async_alone auto g a

(*********************)
(* Synchronous sends *)
(*********************)


(* No match was found *)
let kont_suspend k =
(*DEBUG*)debug3 "KONT_SUSPEND" (tasks_status ()) ;
(*DEBUG*)incr_locked suspended ;
  become_inactive () ;
  if !active = !pool_konts then grab_from_pool 0.1 ;      
  Condition.wait k.kcondition k.kmutex ;
(*DEBUG*)decr_locked suspended ;
  Mutex.unlock k.kmutex ;
  match k.kval with
  | Go f ->
(*DEBUG*)debug3 "REACTIVATED" (tasks_status ()) ;
      f ()
  | Ret v ->
(*DEBUG*)debug3 "REPLIED" (tasks_status ()) ;
      v
  | Start -> assert false

(* Suspend current thread when some match was found *)
let suspend_for_reply k =
(*DEBUG*)incr_locked suspended ;
  become_inactive () ;
  Condition.wait k.kcondition k.kmutex ;
(*DEBUG*)decr_locked suspended ;
  Mutex.unlock k.kmutex ;
  match k.kval with
  | Ret v ->
(*DEBUG*)debug3 "REPLIED" (tasks_status ()) ;
      v
  | Start|Go _ -> assert false


(* Transfert control to frozen principal thread and suspend current thread *)
let kont_go_suspend kme kpri f =
(*DEBUG*)debug2 "KONT_GO_SUSPEND" "" ;
(* awake principal *)
  incr_active () ;
  kpri.kval <- Go f ;
  Condition.signal kpri.kcondition ;
  suspend_for_reply kme

let just_go k f =
(*DEBUG*)debug3 "JUST_GO" "" ;
  Mutex.unlock k.kmutex ;
  f ()

(* Fire process and suspend : no principal name *)
let fire_suspend k _ f =
(*DEBUG*)  debug2 "FIRE_SUSPEND" "" ;
  create_process f ;
  suspend_for_reply k

let rec attempt_match_sync idx kont auto reactions i =
  if i >= Obj.size reactions then begin
(*DEBUG*)debug3 "SYNC ATTEMPT FAILED" (sprintf "%s %i" (get_name auto idx) auto.status) ;    
    kont_suspend kont
  end else begin
    let (ipat, ipri, f) = Obj.magic (Obj.field reactions i) in
    if ipat land auto.status = ipat then begin
      if ipri < 0 then
        f (fire_suspend kont)   (* will create other thread *)
      else if ipri = idx then begin
        f just_go               (* will continue evaluation *)
      end else begin
        f (kont_go_suspend kont) (* will awake principal thread *)
      end
    end else attempt_match_sync idx kont auto reactions (i+1)
  end

let send_sync auto idx a =
(*DEBUG*)  debug3 "SEND_SYNC" (sprintf "channel %s" (get_name auto idx)) ;
(* Acknowledge new message by altering queue and status *)
  Mutex.lock auto.mutex ;
  let old_status = auto.status in
  let new_status = old_status lor (1 lsl idx) in
  let kont = kont_create auto in
  put_queue auto idx (Obj.magic (kont,a)) ;
  auto.status <- new_status ;
  if old_status = new_status then begin
(*DEBUG*)    debug3 "SEND_SYNC" (sprintf "Return: %i" auto.status) ;
    kont_suspend kont
  end else begin
    attempt_match_sync idx kont auto (Obj.magic auto.matches) 0
  end

(* Optimize forwarders *)
and send_sync_alone auto g a =
(*DEBUG*)  debug3 "SEND_SYNC_ALONE" (sprintf "match %i" g) ;
  let _,ipri,f = Obj.magic (Obj.field (Obj.magic auto.matches) g) in
  if ipri >= 0 then begin
(*DEBUG*)    debug3 "SEND_SYNC_ALONE" "direct" ;
    f a    
  end else begin
(*DEBUG*)    debug3 "SEND_SYNC_ALONE" "fire" ;
    Mutex.lock auto.mutex ;
    let k = kont_create auto in
    fire_suspend k auto (fun () -> f (k,a))
  end


let reply_to v k =
(*DEBUG*)  debug3 "REPLY" (sprintf "%i" (Obj.magic v)) ;
  Mutex.lock k.kmutex ;
  k.kval <- Ret v ;
  Condition.signal k.kcondition ;
  Mutex.unlock k.kmutex 

(********************************)
(* Management of initial thread *)
(********************************)


(* Called when all active tasks are waiting in thread pool *)
let from_pool () =
  if !in_pool > 0 then begin
(*DEBUG*)debug1 "HOOK" "SHOULD PERPHAPS SIGNAL" ;    
(*    Condition.signal pool_condition  *) ()
  end else begin (* Create a new thread to enter pool *)
(*DEBUG*)debug1 "HOOK" "CREATE" ;    
    incr_active () ;
    let b = really_create_process exit_thread in
(*DEBUG*)debug1 "HOOK" (if b then "PROCESS CREATED" else "FAILED");
    if not b then begin
      prerr_endline "Threads are exhausted, good bye !"
    end

  end

let rec exit_hook () =
(*DEBUG*)debug1 "HOOK" "enter" ;
(*DEBUG*)decr_locked nthreads ;
  Mutex.lock active_mutex ;
  decr active ;
  begin if !active > 0 then begin
    if !pool_konts = !active then begin
      Mutex.unlock active_mutex ;
      from_pool ()
    end ;
(*DEBUG*)debug1 "HOOK" "suspend" ;
    Condition.wait active_condition active_mutex
  end else
    Mutex.unlock active_mutex
  end ;
(*DEBUG*)debug1 "HOOK" "over" ;
  ()


let _ = at_exit exit_hook

