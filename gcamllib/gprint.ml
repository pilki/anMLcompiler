open Format
open Rtype

let rec print_list sep f ppf = function
  | [] -> ()
  | [x] -> f ppf x
  | x::xs -> 
      fprintf ppf "%a%a%a" 
	f x
	sep ()
	(print_list sep f) xs

let print_tuple f ppf v = 
  print_list (fun ppf () -> fprintf ppf ",@ ") f ppf v

let printers =
  [ Builtintypes.int, (fun ppf v -> fprintf ppf "%i" (Obj.obj v));
    Builtintypes.char, (fun ppf v -> fprintf ppf "%C" (Obj.obj v));
    Builtintypes.string, (fun ppf v -> fprintf ppf "%S" (Obj.obj v));
    Builtintypes.float, (fun ppf v -> fprintf ppf "%F" (Obj.obj v));
    Builtintypes.bool, (fun ppf v -> fprintf ppf "%B" (Obj.obj v));
    Builtintypes.unit, (fun ppf v -> fprintf ppf "()");
    Builtintypes.exn, (fun ppf v -> fprintf ppf "<exn>");
    Builtintypes.nativeint, (fun ppf v -> fprintf ppf "%nd" (Obj.obj v));
    Builtintypes.int32, (fun ppf v -> fprintf ppf "%ld" (Obj.obj v));
    Builtintypes.int64, (fun ppf v -> fprintf ppf "%Ld" (Obj.obj v));
  ]

generic val print : {'a} => formatter -> 'a -> unit =
  let rec print =
    fun ty ppf v ->
      match ty.desc with
      | Tvar -> fprintf ppf "<poly>"
      | Tarrow (_,_,_) -> fprintf ppf "<fun>"
      | Ttuple ts -> 
  	(* bind types and values *)
  	let rec bind pos = function
  	  | [] -> []
  	  | t::ts -> (t, Obj.field v pos) :: bind (pos+1) ts
  	in
  	fprintf ppf "(@[%a@])" 
  	  (print_tuple (fun ppf (t,v) -> print t ppf v)) (bind 0 ts)
      | Tconstr ((path, decl), args) -> 
	  begin try
	    List.assq decl printers ppf v
	  with
	  | Not_found -> fprintf ppf "<???>"
	  end
  in
  print
