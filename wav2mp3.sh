#!/usr/bin/env bash

INPUT="$1"
DEST="$2"

LAMEOPTS=""

function usage () {

	echo 
	echo "Usage: $0 <wav file name>"
	echo
	exit 1
}


if [ -z "$INPUT" ]
then
	usage
fi

if [ ! -e "$INPUT" ]
then
	echo "File $INPUT does not exist!"
	exit 1
fi

TYPE=`file -b "$INPUT"`
RES=`echo "$TYPE" | grep "WAVE audio"`
if [ ! "$?" == "0" ]
then
	echo "File $FILE is not a wav file..."
    	echo "Type is $TYPE"
	exit 0
fi

function convert () {

    FILE="$1"
    MP3FILE="`echo ${FILE%wav}mp3`"
    RAWDIR=`dirname "$MP3FILE"`
    DIR="$DEST/$RAWDIR"
    BASENAME=`basename "$MP3FILE"`

    mkdir -p "$DIR"

    lame --quiet --preset insane "$FILE" "$DIR/$BASENAME"
    return $?
}

convert "$INPUT"
exit "$?"
