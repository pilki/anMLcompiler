#!/bin/sh -e
COMM="ocamlrun$EXE $OTOP/otherlibs/dynlink/extract_crc"
if test "`basename $OTOP`" != "ocaml_stuff"; then
    COMM="$OTOP/boot/$COMM"
fi
echo $COMM $* 1>&2
$COMM $*
