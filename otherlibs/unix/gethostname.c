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

#include <mlvalues.h>
#include <alloc.h>
#ifndef _WIN32
#include <sys/param.h>
#else
#include <winsock.h>
#endif
#include "unixsupport.h"

#ifdef HAS_GETHOSTNAME

#ifndef MAXHOSTNAMELEN
#define MAXHOSTNAMELEN 256
#endif

value unix_gethostname(value unit)         /* ML */
{
  char name[MAXHOSTNAMELEN];
  gethostname(name, MAXHOSTNAMELEN);
  name[MAXHOSTNAMELEN-1] = 0;
  return copy_string(name);
}

#else
#ifdef HAS_UNAME

#include <sys/utsname.h>

value unix_gethostname(value unit)
{
  struct utsname un;
  uname(&un);
  return copy_string(un.nodename);
}

#else

value unix_gethostname(value unit)
{ invalid_argument("gethostname not implemented"); }

#endif
#endif
