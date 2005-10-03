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

open Join_types
open Printf
(*DEBUG*)open Join_debug

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

let nthreads_mutex = Mutex.create()

let incr_locked m r =
  Mutex.lock m ;
  incr r ;
  Mutex.unlock m

and decr_locked m r =
  Mutex.lock m ;
  decr r ;
  Mutex.unlock m

(*DEBUG*)let tasks_status () =
(*DEBUG*)sprintf "active=%i, nthread=%i suspended=%i[%i, %i]"
(*DEBUG*) !active !nthreads !suspended !in_pool !pool_konts

let become_inactive () =
  decr_locked nthreads_mutex active ;
 (* if active reaches 0, this cannot change, so we unlock now *)
(*DEBUG*)debug2 "CHECK" (tasks_status ()) ;
  if !active <= 0 then begin
    Mutex.lock active_mutex ;
    Condition.signal active_condition ;
    Mutex.unlock active_mutex
  end

(* incr_active is performed by task creator or awaker *)
and incr_active () = incr_locked  nthreads_mutex active


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


let really_exit_thread () =
  decr_locked nthreads_mutex nthreads ;
(*DEBUG*)debug1 "REAL EXIT" (sprintf "nthreads=%i" !nthreads);
  Thread.exit ()

(* Note: really_create_process
   uses thread_new, to short-circuit handling of exceptions by Thread *)  

exception MaxRun

let really_create_process f =
  incr_locked nthreads_mutex nthreads ;
  try
    begin match runmax with
    | Some k when !nthreads > k -> raise MaxRun
    | _ -> ()
    end ;
    let t = thread_new f in
(*DEBUG*)debug1 "REAL FORK" (sprintf "%i %s" (Thread.id t) (tasks_status ())) ;
    Some t
  with
  | e ->
(*DEBUG*)debug1 "REAL FORK FAILED"
(*DEBUG*)  (sprintf "%s, %s" (tasks_status ()) (Printexc.to_string e)) ;
      decr_locked nthreads_mutex nthreads ;
      None
      


(****************)
(* Thread cache *)
(****************)

let pool_condition = Condition.create ()
and pool_mutex = Mutex.create ()
and pool_kont = ref [] 

let rec do_pool () =
  incr in_pool ;
(*DEBUG*)incr_locked nthreads_mutex suspended ;
(*DEBUG*)debug2 "POOL SLEEP" (tasks_status ()) ;
  Condition.wait pool_condition pool_mutex ;
(*DEBUG*)decr_locked nthreads_mutex suspended ;
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
      if really_create_process f = None then begin
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
    with
    | Join_misc.JoinExit ->
(* technique to silentely suicide join-managed threads *)
      flush stdout; flush stderr
    | e ->
      flush stdout; flush stderr;
      thread_uncaught_exception e
    end ;
    exit_thread () in

  if !in_pool <= 2 then begin
    match really_create_process g with
    | None -> put_pool g 
    | Some _ -> ()
  end else begin
    put_pool g
  end

let rec hard_create_real_process f =
  match really_create_process f with
  | None ->
      Thread.delay 0.1 ;
      hard_create_real_process f
  | Some t -> t
  
let create_real_process f =
(*DEBUG*)debug2 "CREATE_REAL_PROCESS" (tasks_status ()) ;
  incr_active () ;
(* Wapper around f, to be sure to call my exit_thread *)  
  let g () = 
    begin try f ()
    with e ->
      flush stdout; flush stderr;
      thread_uncaught_exception e
    end ;
    exit_thread () in
  hard_create_real_process g

  
let inform_suspend () =
(*DEBUG*)incr_locked nthreads_mutex suspended ;
  become_inactive () ;
  if !active = !pool_konts then grab_from_pool 0.1

and inform_unsuspend () =
(*DEBUG*)decr_locked nthreads_mutex suspended


(* Important: k.kmutex is locked ! *)
let suspend_for_reply k =
(*DEBUG*)debug3 "SUSPEND_FOR_REPLY"
(*DEBUG*)  (tasks_status ()) ;  
  match k.kval with
  | Start ->
      begin
        inform_suspend () ;
        Condition.wait k.kcondition k.kmutex ;
        inform_unsuspend () ;
        Mutex.unlock k.kmutex ;
        match k.kval with
        | Ret v ->
(*DEBUG*)debug3 "REPLIED" (tasks_status ()) ;
            (Obj.obj v)
        | Exn e ->
(*DEBUG*)debug3 "REPLIED EXN" (tasks_status ()) ;
            raise e
        | Start|Go _ -> assert false
      end
  | Go _ -> assert false
  | Ret v ->
      Mutex.unlock k.kmutex ;
(*DEBUG*)debug3 "REPLIED IMMEDIATE" (tasks_status ()) ;
      (Obj.obj v)
  | Exn e ->
      Mutex.unlock k.kmutex ;
(*DEBUG*)debug3 "REPLIED EXN IMMEDIATE" (tasks_status ()) ;
      raise e

let reply_to v k = 
(*DEBUG*)debug3 "REPLY" (sprintf "%i" (Obj.magic v)) ;
  Mutex.lock k.kmutex ;
  assert (k.kval = Start) ;
  k.kval <- Ret (Obj.repr v) ;
  incr_active () ; (* The awaken task becomes active *)
  Condition.signal k.kcondition ;
  Mutex.unlock k.kmutex 

let reply_to_exn e k = 
(*DEBUG*)debug3 "REPLY EXN"
(*DEBUG*) (sprintf "%s" (Join_misc.exn_to_string e)) ;
  Mutex.lock k.kmutex ;
  assert (k.kval = Start) ;
  k.kval <- Exn e ;
  incr_active () ; (* The awaken task becomes active *)
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
(*DEBUG*)debug1 "HOOK" (if b <> None then "PROCESS CREATED" else "FAILED");
    if b=None then begin
      prerr_endline "Threads are exhausted, good bye !"
    end

  end

let rec exit_hook () =
(*DEBUG*)debug1 "HOOK" "enter" ;
(*DEBUG*)decr_locked nthreads_mutex nthreads ;
  Mutex.lock active_mutex ;
  decr active ;
  begin if !active > 0 then begin
    if !pool_konts = !active then begin
      Mutex.unlock active_mutex ;
      from_pool ()
    end ;
(*DEBUG*)debug1 "HOOK" (sprintf "suspend %s" (tasks_status ())) ;
    Condition.wait active_condition active_mutex
  end else
    Mutex.unlock active_mutex
  end ;
(*DEBUG*)debug1 "HOOK" "over" ;
  ()