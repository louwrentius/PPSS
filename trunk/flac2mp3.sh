#!/usr/bin/env bash

INPUT="$1"

METATAGS="--export-tags-to="
LAMEOPTS=""
ERROR_STATUS="0"

function usage () {

	echo 
	echo "Usage: $0 <flac file name>"
	echo
	exit 1
}

function error () {

	ERROR="$1"
	MSG="$2"

	echo "Error: $MSG"
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

FILETYPE="`file -b "$INPUT" | awk '{ print $1 }'`"
if [ ! "$FILETYPE" == "FLAC" ]
then
	echo "File $FILE is not a flac file..."
	exit 0
fi

checkvar () {

	VAR="$1"

	if [ -z "$VAR" ] || [ "$VAR" == "" ] 
	then
		echo "Unknown"
	else
		echo "$VAR"
	fi
}


METATAGS="TITLE ARTIST ALBUM GENRE COMPOSER CONDUCTOR ENSEMBLE TRACKNUMBER DATE ALBUM ARTIST DISCNUMBER DISC"

function convert () {

	FILE="$1"
	META="$FILE.meta"
	MP3FILE="`echo ${FILE%flac}mp3`"
	DIR="`dirname "$FILE"`"

	metaflac --export-tags-to="$META" "$FILE"

	ARTIST="`metaflac "$FILE" --show-tag=ARTIST | sed s/.*=//g`"
    	TITLE="`metaflac "$FILE" --show-tag=TITLE | sed s/.*=//g`"
    	ALBUM="`metaflac "$FILE" --show-tag=ALBUM | sed s/.*=//g`"
    	GENRE="`metaflac "$FILE" --show-tag=GENRE | sed s/.*=//g`"
    	TRACKNUMBER="`metaflac "$FILE" --show-tag=TRACKNUMBER | sed s/.*=//g`"

	for x in $METATAGS
	do
		declare $x="`grep "$x" "$META" | cut -d "=" -f 2`"

		VAR=$(eval echo " \$$x")
		VAR="`checkvar $VAR`"
	done


	flac -s -c -d "$FILE" | lame --tt "$TITLE" --tn "$TRACKNUMBER"  --tg "$GENRE"  --ty "$DATE"  --ta "$ARTIST" --tl "$ALBUM"  --ty "$YEAR"  --preset insane - "$MP3FILE"
	ERROR_STATUS="$?"
	if [ -e "$META" ]
	then
		rm "$META"
	fi
}

convert "$INPUT"

exit "$ERROR_STATUS"
