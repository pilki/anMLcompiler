let rec tak (x, y, z) =
  if x > y then tak(tak (x-1, y, z), tak (y-1, z, x), tak (z-1, x, y))
           else z

let break_handler _ =
  print_string "Thank you for pressing ctrl-C."; print_newline();
  print_string "Allocating a bit..."; flush stdout;
  tak(18,12,6); print_string "done."; print_newline()

let _ =
  Sys.signal Sys.sigint (Sys.Signal_handle break_handler);
  print_string "Computing like crazy..."; print_newline();
  for i = 1 to 100 do tak(18,12,6) done;
  print_string "Reading on input..."; print_newline();
  for i = 1 to 5 do
    let s = read_line () in
    print_string ">> "; print_string s; print_newline()
  done;
  exit 0
