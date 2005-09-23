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

open Join_types

(* Describe site *)
let local_space = {
  space_id = local_id ;
  space_mutex = Mutex.create () ;
  next_uid =
    begin 
      let uid_counter = ref 0 in
      (fun () -> incr uid_counter; !uid_counter)
    end ;
  uid2local = Join_hash.create () ;
  remote_spaces =  Join_hash.create () ;
  space_listener = Deaf local_socket ;
} 
;;

let do_locked2 lock zyva a b =
  Mutex.lock lock ;
  let r =
    try zyva a b with e -> Mutex.unlock lock ; raise e in
  Mutex.unlock lock ;
  r


let get_remote_space space space_id =
  Join_hash.get space.remote_spaces
    (fun id ->
      {
        rspace_id = id ;
        link_in = NoHandler ;
        link_out = NoConnection (Mutex.create ()) ;
       })
    space_id

let import_remote_automaton space space_id uid =
  let rspace = get_remote_space space space_id in
  RemoteAutomaton (rspace, uid)

let find_local_automaton space uid =  
  try Join_hash.find space.uid2local uid
  with Not_found -> assert false

type poly_ref = { mutable f : 'a . Join_types.automaton -> int -> 'a -> unit }

let send_async_ref = {f =  (fun _ _ _ -> assert false) }

external do_marshal_message :
  'a -> Marshal.extern_flags list -> string * (Join_types.t_local) array
  = "caml_marshal_message" 

external do_unmarshal_message :
  string -> (Join_types.t_local) array -> 'a
  = "caml_unmarshal_message" 

let space_to_string (addr, port, _) =
  sprintf "%s:%i" (Unix.string_of_inet_addr addr) port

let string_of_space = space_to_string 
  
let rec start_listener space =
  begin match space.space_listener with
  | Deaf sock ->
      let listener () =
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
                 Handler
                  {in_channel = inc ;
                   in_thread = Join_scheduler.create_real_process
                    (join_handler space inc) ; }
          end
        done in
      space.space_listener <-
         Listen (Join_scheduler.create_real_process listener)
  | _ -> assert false
  end

and join_handler space inc () =
  while true do
    let msg = input_value inc in
    match msg with
    | AsyncSend (uid, idx, v) ->
        let auto = find_local_automaton space uid
        and v = unmarshal_message_rec space v in
        send_async_ref.f auto idx v
  done

and export_stub space local =  match local with
  | LocalAutomaton a ->
      if a.ident > 0 then
        GlobalAutomaton (space.space_id, a.ident)
      else begin
        Mutex.lock space.space_mutex ;
        let r =
          (* Race condition *)
          if a.ident > 0 then begin
            Mutex.unlock space.space_mutex ;
            GlobalAutomaton (space.space_id, a.ident)
          end else begin
            let uid = space.next_uid () in
            a.ident <- uid ;
            Mutex.unlock space.space_mutex ;            
(* Listener is started  at first export *)
            if uid = 1 then start_listener space ;
            Join_hash.add space.uid2local uid a ;
            GlobalAutomaton (space.space_id, uid)
          end in
        r
      end
  | RemoteAutomaton (rspace, uid) ->
      GlobalAutomaton (rspace.rspace_id, uid)

and import_stub space local = match local with
| GlobalAutomaton (space_id, uid) ->
    if same_space space_id space.space_id then begin
      LocalAutomaton (find_local_automaton space uid)
    end else
      import_remote_automaton space space_id uid

and marshal_message_rec space v flags =
  let s,t =  do_marshal_message v flags in
  s, Array.map (export_stub space) t


and unmarshal_message_rec space (s,locals) =
  do_unmarshal_message s (Array.map (import_stub space) locals)
  

let marshal_message v flags = marshal_message_rec local_space v flags
and  unmarshal_message v = unmarshal_message_rec local_space v

let sender_work rspace queue outc =
  while true do
    let msg = Join_queue.get queue in
(*DEBUG*)debug2 "SENDER" ("message for "^string_of_space rspace.rspace_id) ;
    output_value outc msg ; flush outc ;
  done

let start_sender_work space rspace queue () =
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
         out_channel = outc ;
         out_thread = Thread.self () ; } ;
  output_value outc space.space_id  ; flush outc ;
(*DEBUG*)debug1 "SENDER"
(*DEBUG*)  (sprintf "just sent my name %s" (string_of_space space.space_id)) ;
  sender_work rspace queue outc

let do_remote_send_async space rspace uid idx a =
  let queue =
    match rspace.link_out with
    | Connected {out_queue = queue ; } -> queue
    | Connecting queue -> queue
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
(* The sender thread is not join-scheduled *)
              ignore
                (Join_scheduler.create_real_process
                   (start_sender_work space rspace queue)) ;
              queue
         end in
        do_rec () in
  Join_queue.put queue
    (AsyncSend
       (uid, idx, marshal_message_rec space a []))
              
              

let remote_send_async rspace uid idx a =
(*DEBUG*)debug3 "REMOTE" "SEND ASYNC" ;
  do_remote_send_async local_space rspace uid idx a
  
