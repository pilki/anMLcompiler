/***********************************************************************/
/*                                                                     */
/*                           Objective Caml                            */
/*                                                                     */
/*            Xavier Leroy, projet Cristal, INRIA Rocquencourt         */
/*                                                                     */
/*  Copyright 1996 Institut National de Recherche en Informatique et   */
/*  en Automatique.  All rights reserved.  This file is distributed    */
/*  under the terms of the GNU Library General Public License, with    */
/*  the special exception on linking described in file ../LICENSE.     */
/*                                                                     */
/***********************************************************************/

/* $Id$ */

/* Operations on objects */

#include <string.h>
#include "alloc.h"
#include "fail.h"
#include "gc.h"
#include "major_gc.h"
#include "memory.h"
#include "minor_gc.h"
#include "misc.h"
#include "mlvalues.h"
#include "prims.h"

CAMLprim value static_alloc(value size)
{
  return (value) stat_alloc((asize_t) Long_val(size));
}

CAMLprim value static_free(value blk)
{
  stat_free((void *) blk);
  return Val_unit;
}

CAMLprim value static_resize(value blk, value new_size)
{
  return (value) stat_resize((char *) blk, (asize_t) Long_val(new_size));
}

CAMLprim value obj_is_block(value arg)
{
  return Val_bool(Is_block(arg));
}

CAMLprim value obj_tag(value arg)
{
  if (Is_long (arg)){
    return 1000;
  }else if (Is_young (arg) || Is_in_heap (arg)){
    return Val_int(Tag_val(arg));
  }else{
    return 1001;
  }
}

CAMLprim value obj_set_tag (value arg, value new_tag)
{
  Tag_val (arg) = Int_val (new_tag);
  return Val_unit;
}

CAMLprim value obj_block(value tag, value size)
{
  value res;
  mlsize_t sz, i;
  tag_t tg;

  sz = Long_val(size);
  tg = Long_val(tag);
  if (sz == 0) return Atom(tg);
  res = alloc(sz, tg);
  for (i = 0; i < sz; i++)
    Field(res, i) = Val_long(0);

  return res;
}

CAMLprim value obj_dup(value arg)
{
  CAMLparam1 (arg);
  CAMLlocal1 (res);
  mlsize_t sz, i;
  tag_t tg;

  sz = Wosize_val(arg);
  if (sz == 0) return arg;
  tg = Tag_val(arg);
  if (tg >= No_scan_tag) {
    res = alloc(sz, tg);
    memcpy(Bp_val(res), Bp_val(arg), sz * sizeof(value));
  } else if (sz <= Max_young_wosize) {
    res = alloc_small(sz, tg);
    for (i = 0; i < sz; i++) Field(res, i) = Field(arg, i);
  } else {
    res = alloc_shr(sz, tg);
    for (i = 0; i < sz; i++) initialize(&Field(res, i), Field(arg, i));
  }
  CAMLreturn (res);
}

/* Shorten the given block to the given size and return void.
   Raise Invalid_argument if the given size is less than or equal
   to 0 or greater than the current size.

   algorithm:
   Change the length field of the header.  Make up a white object
   with the leftover part of the object: this is needed in the major
   heap and harmless in the minor heap.
*/
CAMLprim value obj_truncate (value v, value newsize)
{
  mlsize_t new_wosize = Long_val (newsize);
  header_t hd = Hd_val (v);
  tag_t tag = Tag_hd (hd);
  color_t color = Color_hd (hd);
  mlsize_t wosize = Wosize_hd (hd);
  mlsize_t i;

  if (tag == Double_array_tag) new_wosize *= Double_wosize;  /* PR#156 */

  if (new_wosize <= 0 || new_wosize > wosize) invalid_argument ("Obj.truncate");
  if (new_wosize == wosize) return Val_unit;
  /* PR#61: since we're about to lose our references to the elements
     beyond new_wosize in v, erase them explicitly so that the GC
     can darken them as appropriate. */
  if (tag < No_scan_tag) {
    for (i = new_wosize; i < wosize; i++){
      modify(&Field(v, i), Val_unit);
#ifdef DEBUG
      Field (v, i) = Debug_free_truncate;
#endif
    }
  }
  /* We must use an odd tag for the header of the leftovers so it does not
     look like a pointer because there may be some references to it in
     ref_table. */
  Field (v, new_wosize) =
    Make_header (Wosize_whsize (wosize-new_wosize), 1, Caml_white);
  Hd_val (v) = Make_header (new_wosize, tag, color);
  return Val_unit;
}


/* The following functions are used in stdlib/lazy.ml.
   They are not written in O'Caml because they must be atomic with respect
   to the GC.
 */

/* [lazy_is_forward] is obsolete.  Stays here to make bootstrapping
   easier for patched versions of 3.07.  To be removed before 3.08. */
CAMLprim value lazy_is_forward (value v)
{
  return Val_bool (Is_block (v) && Tag_val (v) == Forward_tag);
}

CAMLprim value lazy_follow_forward (value v)
{
  if (Is_block (v) && (Is_young (v) || Is_in_heap (v))
      && Tag_val (v) == Forward_tag){
    return Forward_val (v);
  }else{
    return v;
  }
}

CAMLprim value lazy_make_forward (value v)
{
  CAMLparam1 (v);
  CAMLlocal1 (res);

  res = alloc_small (1, Forward_tag);
  Modify (&Field (res, 0), v);
  CAMLreturn (res);
}

/* For camlinternalOO.ml
   See also GETPUBMET in interp.c
 */

CAMLprim value oo_get_public_method (value obj, value tag)
{
  value meths = Field (obj, 0);
  value tags = Field (meths, 0);
  int li = 0, hi = Wosize_val(tags)-1, mi;
  while (li < hi) {
    mi = (li+hi+1) >> 1;
    if (tag < Field(tags,mi)) hi = mi-1;
    else li = mi;
  }
  return Field (meths, li+1);
}

CAMLprim value oo_cache_public_method (value meths, value tag, value *cache)
{
  value tags = Field (meths, 0);
  value met;
  int li = 0, hi = Wosize_val(tags)-1, mi;
  while (li < hi) {
    mi = (li+hi+1) >> 1;
    if (tag < Field(tags,mi)) hi = mi-1;
    else li = mi;
  }
  // cache[0] = tags;
  modify(cache, tags);
  li++;
  cache[1] = Val_int(li);
  return Field(meths, li);
}

CAMLprim value oo_cache_public_method2 (value obj, value tag, value *cache)
{
  value meths = Field (obj, 0);
  value tags = Field (meths, 0);
  if (tags == cache[0]) return Field(meths, Int_val(cache[1]));
  {
    value met;
    int li = 0, hi = Wosize_val(tags)-1, mi;
    while (li < hi) {
      mi = (li+hi+1) >> 1;
      if (tag < Field(tags,mi)) hi = mi-1;
      else li = mi;
    }
    cache[0] = tags;
    li++;
    cache[1] = Val_int(li);
    return Field(meths, li);
  }
}
