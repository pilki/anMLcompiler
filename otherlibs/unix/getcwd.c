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
#include "unixsupport.h"

#if !defined (_WIN32) && !macintosh
#include <sys/param.h>
#endif

#ifndef PATH_MAX
#ifdef MAXPATHLEN
#define PATH_MAX MAXPATHLEN
#else
#define PATH_MAX 512
#endif
#endif

#ifdef HAS_GETCWD

value unix_getcwd(value unit)     /* ML */
{
  char buff[PATH_MAX];
  if (getcwd(buff, sizeof(buff)) == 0) uerror("getcwd", Nothing);
  return copy_string(buff);
}

#else
#ifdef HAS_GETWD

value unix_getcwd(value unit)
{
  char buff[PATH_MAX];
  if (getwd(buff) == 0) uerror("getcwd", copy_string(buff));
  return copy_string(buff);
}

#else

value unix_getcwd(value unit)
{ invalid_argument("getcwd not implemented"); }

#endif
#endif
