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

#include <string.h>
#include <mlvalues.h>
#include <memory.h>
#include <signals.h>
#include "unixsupport.h"

CAMLprim value unix_read(value fd, value buf, value ofs, value len)
{
  DWORD numbytes, numread;
  BOOL ret;
  char iobuf[UNIX_BUFFER_SIZE];
  HANDLE h = Handle_val(fd);

  Begin_root (buf);
    numbytes = Long_val(len);
    if (numbytes > UNIX_BUFFER_SIZE) numbytes = UNIX_BUFFER_SIZE;
    enter_blocking_section();
    ret = ReadFile(h, iobuf, numbytes, &numread, NULL);
    leave_blocking_section();
    if (! ret) {
      win32_maperr(GetLastError());
      uerror("read", Nothing);
    }
    memmove (&Byte(buf, Long_val(ofs)), iobuf, numread);
  End_roots();
  return Val_int(numread);
}
