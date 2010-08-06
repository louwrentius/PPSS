#!/bin/bash

INPUT="$1"
RESOLUTION="$3"
SEPARATE="$4"
TITLES=0
OPTS_HIGHRES="-e x264 -q 20.0 -r 29.97 --pfr  -a 1 -E faac -B 160 -6 dpl2 -R Auto -D 0.0 -f mp4 -4 -X 1024 --strict-anamorphic -m"
OPTS_LOWRES="-e x264 -q 20.0 -a 1 -E faac -B 128 -6 dpl2 -R 48 -D 0.0 -f mp4 -X 480 -m -x cabac=0:ref=2:me=umh:bframes=0:subme=6:8x8dct=0:trellis=0"
OPTS_SOURCE="-e x264  -q 20.0 -a 1,1 -E faac,ac3 -l 576 -B 160,160 -6 dpl2,auto -R Auto,Auto -D 0.0,0.0 -f mp4 --detelecine --decomb --strict-anamorphic -m -x b-adapt=2:rc-lookahead=50"
MODE=""
HANDBRAKE=HandBrakeCLI
DIRNAME=`dirname "$INPUT"`
BASENAME=`basename "$INPUT"`
OPTS=""
OUTPUT_DIR="$2"
OUTPUT_FILE_NAME=""

if [ -z "$INPUT" ] 
then
	echo "usage $0 <input file / folder> <output folder> <highres|lowres> <separate>"	
	echo
	echo "Input either file, VIDEO_TS directory or .ISO"
	echo 
	echo -e "highres:\t1024 x 576"
	echo -e "lowres:\t\t480 x 320"
	echo -e "source:\t\tsame as source."
	echo 
	echo -e "separate:\tseparate files for episodes of a serie."
	exit 1
fi

if [ ! -z "$OUTPUT_DIR" ]
then
	if [ ! -e "$OUTPUT_DIR" ] || [ ! -d "$OUTPUT_DIR" ]
	then
		echo "Output directory does not exist or is not a directory."
		exit 1
	fi
else
	echo "Output to current directory."
	OUTPUT_DIR="."
fi


if [ ! -e "$INPUT" ]
then
	echo "$INPUT does not exist!"
	exit 1
fi

if [ -d "$INPUT" ] 
then
	MODE=DIR
else
	MODE=FILE
fi

echo "Input type is $MODE"

case "$RESOLUTION" in 
	highres|HIGHRES	) 
			OPTS="$OPTS_HIGHRES" ;;
	lowres|LOWRES  	)
			OPTS="$OPTS_LOWRES" ;;
	source|SOURCE	)
			OPTS="$OPTS_SOURCE" ;;
			*) 	
			echo "Resolution must be 'highres', 'source' or 'lowres'." 
			exit 1 
			;;
esac

function titles () {

	TITLES=`./$HANDBRAKE -t 0 -i "$INPUT" 2>&1 | grep "+ title" | awk '{ print $3 }'  | sed s/://g`
	echo $TITLES
}

if [ "$MODE" = "FILE" ]
then
	mkdir -p "$OUTPUT_DIR/$DIRNAME" 
	OUTPUT_FILE_NAME="$OUTPUT_DIR/$DIRNAME/${BASENAME%.*}"
elif [ "$MODE" = "DIR" ]
then
	echo "$INPUT" | grep -i video_ts >> /dev/null 2>&1
	if [ "$?" = "0" ]
	then
		INTERMEDIATE2=`basename "$DIRNAME"`
		mkdir -p "$OUTPUT_DIR/$DIRNAME"
		OUTPUT_FILE_NAME="$OUTPUT_DIR/$DIRNAME/$INTERMEDIATE2"
	else
		INTERMEDIATE2="$BASENAME"
		mkdir -p "$OUTPUT_DIR/$DIRNAME/$INTERMEDIATE2"
		OUTPUT_FILE_NAME="$OUTPUT_DIR/$DIRNAME/$INTERMEDIATE2/$INTERMEDIATE2"
	fi
	echo "INTERMEDIATE2 = $INTERMEDIATE2"
else
	echo "Mode is not determined..."
	exit 1
fi

if [ "$SEPARATE" = "separate" ]
then
	TITLES=`titles $INPUT`
	echo "TITLES = $TITLES"
	ERROR=0

	for x in $TITLES
	do
		HandBrakeCLI $OPTS -i "$INPUT" -o "$OUTPUT_FILE_NAME-$x.mp4" 
		if [ ! "$?" = "0" ]
		then 
			ERROR="1"
		fi 
	done
	exit "$ERROR"
else
	echo "Creating a single file."
	HandBrakeCLI $OPTS -i "$INPUT" -o "$OUTPUT_FILE_NAME.mp4" 
fi




