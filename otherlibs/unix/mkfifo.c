/***********************************************************************/
/*                                                                     */
/*                           Objective Caml                            */
/*                                                                     */
/*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         */
/*                                                                     */
/*  Copyright 1996 Institut National de Recherche en Informatique et   */
/*  en Automatique.  All rights reserved.  This file is distributed    */
/*  under the terms of the GNU Library General Public License.         */
/*                                                                     */
/***********************************************************************/

/* $Id$ */

#include <sys/types.h>
#include <sys/stat.h>
#include <mlvalues.h>
#include "unixsupport.h"

#ifdef HAS_MKFIFO

value unix_mkfifo(value path, value mode)
{
  if (mkfifo(String_val(path), Int_val(mode)) == -1)
    uerror("mkfifo", path);
  return Val_unit;
}

#else

#include <sys/types.h>
#include <sys/stat.h>

#ifdef S_IFIFO

value unix_mkfifo(value path, value mode)
{
  if (mknod(String_val(path), (Int_val(mode) & 07777) | S_IFIFO, 0) == -1)
    uerror("mkfifo", path);
  return Val_unit;
}

#else

value unix_mkfifo() { invalid_argument("mkfifo not implemented"); }

#endif
#endif
