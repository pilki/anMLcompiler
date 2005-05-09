(* The behavior of  {: ... :} depends on the expected output type *)

Printf.printf "%S\n" (Xml_values.Utf8.to_string_latin1 {: "�" :});;
Printf.printf "%S\n" (Xml_values.Utf8.to_string_utf8 {: "�" :});;
Printf.printf "%S\n" {: "�" :};;
