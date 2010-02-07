#!/bin/bash

DEBUG="$1"
VERSION=2.55
TMP_DIR="ppss"
PPSS=./ppss
PPSS_DIR=ppss_dir

cleanup () {

    for x in $REMOVEFILES
    do
        if [ -e ./$x ]
        then
            rm -r ./$x
        fi
    done
}

parseJobStatus () {

    TMP_FILE="$1"

    RES=`grep "Status:" "$JOBLOG/$TMP_FILE"`
    STATUS=`echo "$RES" | awk '{ print $2 }'`
    echo "$STATUS"

}

oneTimeSetUp () {

	JOBLOG=./$PPSS_DIR/job_log
	INPUTFILENORMAL=test-normal.input
    INPUTFILESPECIAL=test-special.input
    LOCALOUTPUT=ppss_dir/PPSS_LOCAL_OUTPUT

	REMOVEFILES="$PPSS_DIR test-ppss-*"

    cleanup

	for x in $NORMALTESTFILES
	do
		echo "$x" >> "$INPUTFILENORMAL"
	done

    for x in $SPECIALTESTFILES
    do
        echo $x >> "$INPUTFILESPECIAL"
    done
}

testVersion () {

    RES=`./$PPSS -v`
    
    for x in $RES
    do
        echo "$x" | grep [0-9] >> /dev/null
        if [ "$?" == "0" ]
        then
            assertEquals "Version mismatch!" "$VERSION" "$x"
        fi
    done
}

rename-ppss-dir () {

	TEST="$1"

	if [ -e "$PPSS_DIR" ] && [ -d "$PPSS_DIR" ] && [ ! -z "$TEST" ]
	then
		mv "$PPSS_DIR" test-ppss-"$TEST"
	fi
}

oneTimeTearDown () {

	if [ ! "$DEBUG" == "debug" ]
	then
        cleanup 
    fi
}

createDirectoryWithSomeFiles () {

    A="File with Spaces"
    B="File\With\Slashes"

    mkdir "/tmp/$TMP_DIR"
    for x in "$A" "$B"
    do
        TMP_FILE="/tmp/$TMP_DIR/$x"
        touch "$TMP_FILE"
    done
}

testSpacesInFilenames () {

    createDirectoryWithSomeFiles

    RES=$( { ./$PPSS -d /tmp/$TMP_DIR -c 'ls -alh ' >> /dev/null ; } 2>&1 )  
	assertEquals "PPSS did not execute properly." 0 "$?"

    assertNull "PPSS retured some errors..." "$RES"
    if [ ! "$?" == "0" ]
    then
        echo "RES IS $RES"
    fi
    
    grep "SUCCESS" $JOBLOG/* >> /dev/null 2>&1
    assertEquals "Found error with space in filename $TMP_FILE" "0" "$?"

    rm -rf "/tmp/$TMP_DIR"   
    rename-ppss-dir $FUNCNAME
}

testSpecialCharacterHandling () {

    RES=$( { ./$PPSS -f "$INPUTFILESPECIAL" -c 'echo ' >> /dev/null ; } 2>&1 )  
	assertEquals "PPSS did not execute properly." 0 "$?"

    assertNull "PPSS retured some errors..." "$RES"
    if [ ! "$?" == "0" ]
    then
        echo "RES IS $RES"
    fi

    RES=`find ppss_dir/PPSS_LOCAL_OUTPUT | wc -l | sed 's/\ //g'`
    LINES=`wc -l "$INPUTFILESPECIAL" | awk '{ print $1 }'`
    assertEquals "To many lock files..." "$((LINES+1))" "$RES"

    RES1=`ls -1 $JOBLOG`
    RES2=`ls -1 $LOCALOUTPUT`

    assertEquals "RES1 $RES1 is not the same as RES2 $RES2" "$RES1" "$RES2"

    rename-ppss-dir $FUNCNAME
}

testSkippingOfProcessedItems () {

    createDirectoryWithSomeFiles    

    RES=$( { ./$PPSS -d /tmp/$TMP_DIR -c 'echo ' >> /dev/null ; } 2>&1 )
    assertEquals "PPSS did not execute properly." 0 "$?"
    assertNull "PPSS retured some errors..." "$RES"

    RES=$( { ./$PPSS -d /tmp/$TMP_DIR -c 'echo ' >> /dev/null ; } 2>&1 )
    assertEquals "PPSS did not execute properly." 0 "$?"
    assertNull "PPSS retured some errors..." "$RES"

    grep -i skip ./$PPSS_dir/* >> /dev/null 2>&1
    assertEquals "Skipping of items went wrong." 0 "$?"

    rename-ppss-dir $FUNCNAME-1

    RES=$( { ./$PPSS -f $INPUTFILESPECIAL -c 'echo ' >> /dev/null ; } 2>&1 )
    assertEquals "PPSS did not execute properly." 0 "$?"
    assertNull "PPSS retured some errors..." "$RES"

    RES=$( { ./$PPSS -f $INPUTFILESPECIAL -c 'echo ' >> /dev/null ; } 2>&1 )
    assertEquals "PPSS did not execute properly." 0 "$?"
    assertNull "PPSS retured some errors..." "$RES"

    grep -i skip ./$PPSS_dir/* >> /dev/null 2>&1
    assertEquals "Skipping of items went wrong." 0 "$?"

    rm -rf "/tmp/$TMP_DIR"   
    rename-ppss-dir $FUNCNAME-2
}

testExistLogFiles () {

	./$PPSS -f "$INPUTFILENORMAL" -c 'echo "$ITEM"' >> /dev/null
	assertEquals "PPSS did not execute properly." 0 "$?"

	for x in $NORMALTESTFILES
	do
		assertTrue "[ -e $JOBLOG/$x ]"
	done

	rename-ppss-dir $FUNCNAME
}

getStatusOfJob () {

	EXPECTED="$1"

	if [ "$EXPECTED" == "SUCCESS" ]
	then
		./$PPSS -f "$INPUTFILENORMAL" -c 'echo ' >> /dev/null
        	assertEquals "PPSS did not execute properly." 0 "$?"
	elif [ "$EXPECTED" == "FAILURE" ]
	then
		./$PPSS -f "$INPUTFILENORMAL" -c 'thiscommandfails ' >> /dev/null
        	assertEquals "PPSS did not execute properly." 0 "$?"
	fi

	for x in $NORMALTESTFILES
	do
        STATUS=`parseJobStatus "$x"`
        assertEquals "FAILED WITH STATUS $STATUS." "$EXPECTED" "$STATUS"
    done

	rename-ppss-dir "$FUNCNAME-$EXPECTED"
}


testErrorHandlingOK () {

	getStatusOfJob SUCCESS
}

testErrorHandlingFAIL () {

	getStatusOfJob FAILURE
}




. ./shunit2
