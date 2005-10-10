 (***********************************************************************)
 (*                                                                     *)
 (*                    ______________                                   *)
 (*                                                                     *)
 (*      Fabrice Le Fessant, projet SOR/PARA INRIA Rocquencourt         *)
 (*      Luc Maranget, projet Moscova                                   *)
 (*                                                                     *)
 (*  Copyright 1997 Institut National de Recherche en Informatique et   *)
 (*  Automatique.  Distributed only by permission.                      *)
 (*                                                                     *)
 (*                                                                     *)
 (***********************************************************************)

 (* $Id$ *)

 open Printf
 open Join_misc
 (*DEBUG*)open Join_debug

 let creation_time = Unix.gettimeofday ()

 (* Create site socket *)
 let local_port, local_socket = Join_misc.create_port 0
 ;;

 (* And compute global site identifier *)
 let local_id = local_addr, local_port, creation_time
 ;;

 let same_space (a1, p1, t1) (a2, p2, t2) =
   a1 = a2 && p1 = p2 && t1 = t2
 ;;

 (*********************)
 (* Global exceptions *)
 (*********************)

 (*
   Global exceptions look like they are common to all runtimes,
   This is achieved by a translation when processing ReplyExn messages
 *)

 let exn_table = Join_hash.create ()

 let get_exn_cstr exn = Obj.field exn 0
 and get_cstr_name cstr = (Obj.obj (Obj.field cstr 0) : string )

 let exn_global (file,line,_) exn_cstr =
   match Join_hash.add_once exn_table exn_cstr ((file, line), exn_cstr) with
   | None -> ()
   | Some ((old_file, old_line), _) ->
       failwith
	 (sprintf
	    "File \"%s\", line %i: global exception clash %s\n\
	    File  \"%s\", line %i: conflicting declaration\n"
	    file line (get_cstr_name exn_cstr)
	    old_file old_line)

 let localize_exn (exn : exn) =
   let cstr = get_exn_cstr (Obj.repr exn) in
   try
     let _,new_cstr = Join_hash.find exn_table cstr in
     let o = Obj.repr exn in
     let r =
       match Obj.size o with
       | 1|2 ->
	   let r = Obj.dup o in
	   Obj.set_field r 0 new_cstr ;
	   r
       | _ -> assert false in
 (*DEBUG*)debug2 "LOCALIZE"
 (*DEBUG*)  (sprintf "successful localization of %s" (get_cstr_name cstr)) ;
     Obj.obj r
   with
   | Not_found ->
 (*DEBUG*)debug2 "LOCALIZE"
 (*DEBUG*)  (sprintf "failed localization of %s" (get_cstr_name cstr)) ;    
       exn

 open Join_types

 (* Attempt to handle SIGPIPE *)
 let _ =
   Sys.set_signal
     Sys.sigpipe
     (Sys.Signal_handle
	(fun _ ->
 (*DEBUG*)debug1 "SIG HANDLER" "SIGPIPE" ;
	  ()))

 (* Describe site *)
 let local_space = {
   space_id = local_id ;
   space_status = SpaceUp ;
   uid_mutex = Mutex.create () ;
   next_uid =
     begin 
       let uid_counter = ref 0 in
       (fun () ->
	 Pervasives.incr uid_counter;
	 let r = !uid_counter in
	 r)
     end ;
   uid2local = Join_hash.create () ;
   remote_spaces =  Join_hash.create () ;
   space_listener = Deaf (local_socket, Mutex.create ())
 } 
 ;;

let space_to_string (addr, port, _) =
  sprintf "%s:%i" (Unix.string_of_inet_addr addr) port

 let get_remote_space space space_id =
   Join_hash.get space.remote_spaces
     (fun id ->
(*DEBUG*)debug2 "RSPACE CREATE" (space_to_string space_id) ;
       {
	rspace_id = id ;
	next_kid =
	begin
	  let kid_counter = ref 0
	  and kid_mutex = Mutex.create () in
	  (fun () ->
	    Mutex.lock kid_mutex ;
	    let r = !kid_counter in
	    Pervasives.incr kid_counter ;
	    Mutex.unlock kid_mutex ;
	    r)
	end ;
	replies_pending = counter_create () ;
	konts = Join_hash.create () ;
	link_in = NoHandler ;
	link_out = NoConnection (Mutex.create ()) ;
      })
     space_id

let find_local space uid =  
  try Join_hash.find space.uid2local uid
  with Not_found -> assert false

let find_automaton space uid =
  let r =
    try  Join_hash.find space.uid2local uid
    with Not_found -> assert false in
  (Obj.magic r : automaton)

type async_ref =
    { mutable async : 'a . automaton -> int -> 'a -> unit }
let send_async_ref = { async =  (fun _ _ _ -> assert false) }

type sync_ref =
    { mutable sync : 'a 'b . automaton -> int -> 'a -> 'b}
let send_sync_ref = { sync = (fun _ _ _ -> assert false) }

external do_globalize_message :
  'a -> Marshal.extern_flags list -> string * stub array
    = "caml_globalize_message" 

external do_localize_message :
  string -> (stub_tag * stub_val * int) array -> 'a
    = "caml_localize_message" 

let string_of_space = space_to_string 

let verbose_close caller fd =  
  (*DEBUG*)debug1 ("CLOSE from "^caller) (sprintf "%i" (Obj.magic fd)) ;
  try
    Unix.close fd
  with e ->
    (*DEBUG*)debug1 ("CLOSE from "^caller)
      (*DEBUG*) (Join_misc.exn_to_string e) ;
    ()

let close_link_in = function
  | NoHandler -> ()
  | Handler { in_channel = inc } ->
      Unix.shutdown inc Unix.SHUTDOWN_RECEIVE ;
      verbose_close "link_in" inc

let close_link_out = function
  | NoConnection _ | Connecting _ -> ()
  | Connected {out_channel = fd ; out_queue = queue } ->
      Join_queue.put queue GoodBye

and internal_close_link_out = function
  | NoConnection _ | Connecting _ -> ()
  | Connected {out_channel = fd ; out_queue = queue } ->
      Join_queue.put queue Killed


exception SawGoodBye
exception SawKilled

(* For efficiency, messages are transmitted as several
   marshalled values *)


(* Read the a sequence of chars that encodes a marshalled value
   ie, returned by extern from extern.c

   This code is inspired from input_value in pervasives.ml,
   it assumes non-blocking really_input *)
   
let header_size = Marshal.header_size  (* 20 ! *)

let read_marshalled_string ic =
  let header = String.create header_size in
  really_input ic header 0 header_size ;
  let data_size = Marshal.data_size header 0 in
  let total_size = data_size + header_size in
  let buff = String.create total_size in
  String.unsafe_blit header 0 buff 0 header_size ;
  really_input ic buff header_size data_size ;
  buff

and write_marshalled_string oc buff = output_string oc buff
  
(* read the argument part of a message,
   ie a pair, string * t_global array *)

let read_parameter ic =
  let s = read_marshalled_string ic in
  let t = (input_value ic : t_global array) in
  (s, t)

and write_parameter oc ((s, t):parameter) =
  write_marshalled_string oc s ;
  output_value oc t

type msg_prefix =
  | PasyncSend of chan_id
  | PsyncSend of chan_id * kont_id
  | PreplySend of kont_id
  | PreplyExn of (kont_id * exn)

let read_msg ic = match input_value ic with
| PasyncSend chan ->
   AsyncSend (chan, read_parameter ic)
| PsyncSend (chan,kont) ->
   SyncSend (chan, kont, read_parameter ic)
| PreplySend kont ->
   ReplySend (kont, read_parameter ic)
| PreplyExn (kont, e) ->
   ReplyExn (kont, e)

and write_message oc = function
  | AsyncSend (chan, arg) ->
      output_value oc (PasyncSend chan) ;
      write_parameter oc arg
  | SyncSend (chan, kont, arg) ->
      output_value oc (PsyncSend (chan, kont)) ;
      write_parameter oc arg
  | ReplySend (kont, arg) ->
      output_value oc (PreplySend kont) ;
      write_parameter oc arg
  | ReplyExn (kont, e) ->
      output_value oc (PreplyExn (kont, e))
  | Killed|GoodBye -> assert false

let rec start_listener space =
  begin match space.space_listener with
  | Deaf (sock,mtx) ->
      let rec do_rec () =
	Mutex.lock mtx ;
	begin match  space.space_listener with
	| Deaf (sock,mtx) ->
	    let listener () =
	      try
		while true do
		  (*DEBUG*)debug1 "LISTENER"
		    (*DEBUG*)  (sprintf "now accept on: %s" (space_to_string space.space_id)) ;
		  let s,_ = Join_misc.force_accept sock in
		  (*DEBUG*)debug1 "LISTENER" "someone coming" ;
		  Unix.shutdown s Unix.SHUTDOWN_SEND ;
		  let inc = Unix.in_channel_of_descr s in
		  let rspace_id = input_value inc in
		  (*DEBUG*)debug1 "LISTENER" ("his name: "^space_to_string rspace_id)  ;
		  let rspace =  get_remote_space space rspace_id in
		  begin match rspace.link_in with
		  | Handler _ -> assert false
		  | NoHandler ->
		      rspace.link_in <-
			Handler {in_channel = s ; }
		  end ;
		  Join_scheduler.create_process
		    (join_handler space rspace s inc)
		done
	      with
		(* 'normal' reaction to closing socket internally *)
	      | Unix.Unix_error((Unix.EBADF|Unix.EINVAL), "accept", _) ->
		  (*DEBUG*)debug1 "LISTENER" "saw shutdowned or closed socket" ;
		  ()
	      | e ->
		  (*DEBUG*)debug0 "LISTENER"
		    (*DEBUG*)  (sprintf "died of %s" (Join_misc.exn_to_string e)) ;
		  () in
	    Join_scheduler.create_process listener ;
	    space.space_listener <- Listen sock ;
	    Mutex.unlock mtx
	| Listen _ -> ()
	end in
      do_rec ()
  | Listen _ -> ()
  end

and join_handler space rspace s inc () =
  (*DEBUG*)debug1 "HANDLER"
    (*DEBUG*)  ("start receiving from "^string_of_space rspace.rspace_id) ;  try
      while true do
	let msg = read_msg inc in
	(*DEBUG*)debug2 "HANDLER" ("message from "^string_of_space rspace.rspace_id) ;
	match msg with
	| AsyncSend (chan, v) ->
	    let auto = find_automaton space chan.auto_id
	    and v = localize_rec space v in
	    send_async_ref.async auto chan.chan_id v
	| SyncSend (chan, kid, v) ->
	    let auto = find_automaton space chan.auto_id
	    and v = localize_rec space v
            and idx = chan.chan_id in
	    Join_scheduler.create_process
	      (fun () ->
		incr rspace.replies_pending ;
		begin try
		  let r = send_sync_ref.sync auto idx v in
		  do_remote_reply_to space rspace kid r
		with e -> do_remote_reply_to_exn space rspace kid e
		end ;
		(* At this point the reply is in queue *)
		decr rspace.replies_pending)
	| ReplySend (kid, v) ->
	    let kont =
	      try Join_hash.find_remove rspace.konts kid
	      with Not_found -> assert false
	    and v = localize_rec space v in
	    Join_scheduler.reply_to v kont
	| ReplyExn (kid, e) ->
	    let kont =
	      try Join_hash.find_remove rspace.konts kid
	      with Not_found -> assert false in
	    let e = localize_exn e in
	    Join_scheduler.reply_to_exn e kont              
	| GoodBye -> raise SawGoodBye
	| Killed -> assert false
      done
    with
    | SawGoodBye|End_of_file as e ->
	(* Distant site annouce it halts, or halts without annoucing it *)
	(*DEBUG*)debug1 "HANDLER"
	  (*DEBUG*)  (sprintf "site %s tells it halts with %s"
			(*DEBUG*)     (space_to_string rspace.rspace_id) (Printexc.to_string e)) ;
	verbose_close "handler self close" s ;
	internal_close_link_out rspace.link_out ;
	Join_hash.remove space.remote_spaces rspace.rspace_id ;
	(* For replies not made *)
	Join_hash.iter rspace.konts
	  (fun _ k -> Join_scheduler.reply_to_exn JoinExit k) ;
	(*DEBUG*)debug1 "HANDLER" "cleanup is over" ;
	()

    | Sys_error("Bad file descriptor") ->
	(*DEBUG*)debug1 "HANDLER" "Saw closed socket" ;
	()
    | e ->
	(*DEBUG*)debug0 "HANDLER"
	  (*DEBUG*)  (sprintf "died of %s" (Join_misc.exn_to_string e)) ;
	()


	  (* Get out queue for rspace,
	     in case no connection is here yet, create one *)

and get_out_queue space rspace =
  match rspace.link_out with
  | Connected {out_queue = queue ; } | Connecting queue -> queue
  | NoConnection mtx ->
      (* Outbound connection is set asynchronously,
	 hence check race condition, so as to create exactly
	 one queue and sender_work process *)
      let rec do_rec () =
	Mutex.lock mtx ;
	begin match rspace.link_out with
	| Connected  {out_queue = queue ; }
	| Connecting queue -> (* Other got it ! *)
	    Mutex.unlock mtx ;
	    queue
	| NoConnection _ -> (* Got it ! *)
	    let queue = Join_queue.create () in
	    rspace.link_out <- Connecting queue ;
	    Mutex.unlock mtx ;
	    (* The sender thread is join-scheduled *)
	    Join_scheduler.create_process
	      (start_sender_work space rspace queue) ;
	    queue end in
      do_rec ()

and close_link_out space rspace = 
  let queue = get_out_queue space rspace in
  Join_queue.put queue GoodBye

and do_remote_reply_to space rspace kid r =
  let queue = get_out_queue space rspace in
  Join_queue.put queue
    (ReplySend
       (kid, globalize_rec space r []))

and do_remote_reply_to_exn space rspace kid e =
  let queue = get_out_queue space rspace in
  Join_queue.put queue (ReplyExn (kid, e))

and sender_work rspace queue s outc =
  begin try while true do
    let msg = Join_queue.get queue in
    begin match msg with
    | Killed -> raise SawKilled
    | _ -> ()
    end ;
    (*DEBUG*)debug2 "SENDER" ("message for "^string_of_space rspace.rspace_id) ;
    write_message outc msg ; flush outc ;
    match msg with
    | GoodBye -> raise SawGoodBye
    | _ -> ()	
  done with
    (* Acknowledge various reasons for the sender to halt *)
  | SawGoodBye ->
      (*DEBUG*)debug1 "SENDER" "just sent goodbye" ;
      Unix.shutdown s Unix.SHUTDOWN_SEND ;
      verbose_close "self close from sender" s
	(* The distant site has halted, no need to shutdown *)
  | SawKilled ->
      (*DEBUG*)debug1 "SENDER" "just received Killed" ;
      verbose_close "self close from sender" s
  | e ->
      (*DEBUG*)debug0 "SENDER" ("died of "^Join_misc.exn_to_string e) ;
      ()
  end ;
  (* In any case, empty queue, flush_out_queue may be waiting *)
  Join_queue.clean queue

and start_sender_work space rspace queue () =
  (*DEBUG*)debug1 "SENDER"
    (*DEBUG*)    (sprintf "connect from %s to %s"
		    (*DEBUG*)       (string_of_space space.space_id)
		    (*DEBUG*)       (string_of_space rspace.rspace_id)) ;
  let addr,port,_ = rspace.rspace_id in
  let s = force_connect addr port in
  Unix.shutdown s Unix.SHUTDOWN_RECEIVE ;
  let outc = Unix.out_channel_of_descr s in
  rspace.link_out <-
    Connected
      { out_queue = queue ;
	out_channel = s ; } ;
  output_value outc space.space_id  ; flush outc ;
  (*DEBUG*)debug1 "SENDER"
    (*DEBUG*)  (sprintf "just sent my name %s" (string_of_space space.space_id)) ;
  sender_work rspace queue s outc

(* returns global identification for stub *)
and export_stub space stub = match stub.stub_tag with
|  Local ->
    let uid = stub.uid in
    if uid <> 0 then space.space_id, uid
    else begin
      (* race condition, since several threads can be exporting this stub *)
      Mutex.lock space.uid_mutex ;
      let uid = stub.uid in
      if uid <> 0 then begin (* lost *)
	Mutex.unlock space.uid_mutex  ;
	space.space_id, uid
      end else begin (* won, allocate new uid *)
	let uid = space.next_uid () in
	stub.uid <- uid ;
	Mutex.unlock space.uid_mutex ;	
	(* Listener is started  at first export *)
	if uid = 1 then start_listener space ;
	(* Remember binding uid -> local value *)
	Join_hash.add space.uid2local uid stub.stub_val ;
	(space.space_id, uid)
      end
    end
| Remote ->
    let rspace = (Obj.magic stub.stub_val : space_id ) in
    (rspace, stub.uid)

(* quasi-reverse of export stub, from global names to
   values, note that the stub is allocated by
   do_localize_message *)

and import_stub space (rspace_id, uid) =
  if same_space rspace_id space.space_id then
    Local, find_local space uid, uid
  else
    Remote, (Obj.magic rspace_id : stub_val), uid

and globalize_rec space v flags =
  let s,t =  do_globalize_message v flags in
  s, Array.map (export_stub space) t

and localize_rec space (s,t) =
  do_localize_message s (Array.map (import_stub space) t)
    

(* exported versions of globalize/localize, for tests *)
let globalize v flags = globalize_rec local_space v flags
and localize v = localize_rec local_space v


let do_remote_send_async space rspace_id uid idx a =
  let rspace = get_remote_space space rspace_id in
  let queue = get_out_queue space rspace in
  Join_queue.put queue
    (AsyncSend
       ({auto_id=uid; chan_id=idx;}, globalize_rec space a []))

let remote_send_async rspace uid idx a =
(*DEBUG*)debug3 "REMOTE" "SEND ASYNC" ;
  do_remote_send_async local_space rspace uid idx a
    
let remote_send_alone rspace uid a =
(*DEBUG*)debug3 "REMOTE" "SEND ALONE" ;
  assert false

let do_remote_send_sync space rspace_id uid idx kont a =
  let rspace = get_remote_space space rspace_id in
  let kid = rspace.next_kid ()
  and queue = get_out_queue space rspace in
  if kid = 0 then start_listener space ; (* first continuation exported *)
  Join_hash.add rspace.konts kid kont ;
  Join_queue.put queue
    (SyncSend
      ({auto_id=uid; chan_id=idx}, kid,
       globalize_rec space a [])) ;
  Mutex.lock kont.kmutex ;
  Join_scheduler.suspend_for_reply kont
    
let remote_send_sync rspace uid idx kont a =
(*DEBUG*)debug3 "REMOTE" "SEND SYNC" ;
  do_remote_send_sync local_space rspace uid idx kont a

let remote_send_sync_alone rspace uid kont a =
(*DEBUG*)debug3 "REMOTE" "SEND SYNC ALONE" ;
  assert false    


let kill_remote_space space rspace =
  close_link_in rspace.link_in ;
  close_link_out space rspace



let do_halt space = assert false
(*
  Mutex.lock space.space_mutex ; (* Against double halt, need more probably *)
  begin match space.space_status with
  | SpaceDown ->
      Mutex.unlock space.space_mutex
  | SpaceUp ->
      space.space_status <- SpaceDown ;
      Mutex.unlock space.space_mutex ;
      Join_hash.iter space.remote_spaces
        (fun _ rspace -> kill_remote_space space rspace) ;
      let listsock = match space.space_listener with
      | Deaf (fd,_) | Listen fd -> fd in
      Unix.shutdown listsock Unix.SHUTDOWN_ALL ;
      verbose_close "halt" listsock ;
      ()
  end
*)

let halt () = do_halt local_space



(************************************************)
(* Flush messages to rspace as much as possible *)
(************************************************)

(*
   Well, at least all replies are delivered.
   This will go into deadlock if some remote sync call
   is pending on local definition.

   Nothing particular is done for other remote message,
   except that the queue is flushed
 *)

let flush_out_queue space rspace =
(* First wait for replies to be passed to out queue *)
(*DEBUG*)debug2 "WAIT PENDING REPLIES" (space_to_string rspace.rspace_id) ;
  wait_zero rspace.replies_pending ;
(*DEBUG*)debug2 "NO PENDING REPLIES" (space_to_string rspace.rspace_id) ;
(* Then wait for sender to discover empty queue *)
  try
    let queue =
      match rspace.link_out with
      | Connected {out_queue = queue ; } | Connecting queue -> queue
      | NoConnection _ -> raise Exit in
    Join_queue.wait_empty queue ;
(*DEBUG*)debug2 "FLUSHED" (space_to_string rspace.rspace_id) ;
  with
  | Exit -> ()


let do_flush_out_queues space =
(*DEBUG*)debug2 "FLUSH SPACE" "enter" ;
  Join_hash.iter space.remote_spaces
    (fun _ rspace -> flush_out_queue space rspace)

let flush_space () =  do_flush_out_queues local_space
