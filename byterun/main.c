/***********************************************************************/
/*                                                                     */
/*                           Objective Caml                            */
/*                                                                     */
/*         Xavier Leroy and Damien Doligez, INRIA Rocquencourt         */
/*                                                                     */
/*  Copyright 1996 Institut National de Recherche en Informatique et   */
/*  en Automatique.  All rights reserved.  This file is distributed    */
/*  under the terms of the GNU Library General Public License, with    */
/*  the special exception on linking described in file ../LICENSE.     */
/*                                                                     */
/***********************************************************************/

/* $Id$ */

/* Main entry point (can be overridden by a user-provided main()
   function that calls caml_main() later). */

#include "misc.h"
#include "mlvalues.h"
#include "sys.h"

CAMLextern void caml_main (char **);

#ifdef _WIN32
CAMLextern void caml_expand_command_line (int *, char ***);
#endif

#if macintosh
#include "rotatecursor.h"
#include "signals.h"
#endif

int main(int argc, char **argv)
{
#ifdef _WIN32
  /* Expand wildcards and diversions in command line */
  caml_expand_command_line(&argc, &argv);
#endif
#if macintosh
  rotatecursor_options (&caml_something_to_do, 0, NULL);
#endif /* macintosh */
  caml_main(argv);
  caml_sys_exit(Val_int(0));
  return 0; /* not reached */
}
