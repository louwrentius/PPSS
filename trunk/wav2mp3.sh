#!/usr/bin/env bash

SRC="$1"
DEST="$2"

            
TYPE=`file -b "$SRC"`
RES=`echo "$TYPE" | grep "WAVE audio"`
if [ ! "$?" == "0" ]
then
    echo "File $FILE is not a wav file..."
    echo "Type is $TYPE"
    exit 0
fi

BASENAME=`basename "$SRC"`
MP3FILE="`echo ${BASENAME%wav}mp3`"
lame --quiet --preset insane "$SRC" "$DEST/$MP3FILE"
exit "$?"
