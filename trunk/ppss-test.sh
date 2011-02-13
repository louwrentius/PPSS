#!/bin/bash

DEBUG="$1"
VERSION="2.86"
TMP_DIR="/tmp/ppss"
PPSS=./ppss
PPSS_DIR=ppss_dir
export PPSS_DEBUG=1
HOST_ARCH=`uname`
SPECIAL_DIR=$TMP_DIR/root/special
. "$PPSS"

cleanup () {

        unset RES1
        unset RES2
        GLOBAL_COUNTER=1
    if [ ! "$DEBUG" = "debug" ]
    then
        for x in $REMOVEFILES
        do
            if [ -e ./$x ]
            then
                rm -r ./$x
            fi
        done
    fi

        if [ ! -z "$TMP_DIR" ]
        then
            rm -rf "/$TMP_DIR"   
        fi
}

parseJobStatus () {

    TMP_FILE="$1"

    RES=`grep "Status:" "$JOBLOG/$TMP_FILE"`
    STATUS=`echo "$RES" | awk '{ print $2 }'`
    echo "$STATUS"
}

get_item_count_of_input_file () {

    if [ -e "$PPSS_DIR/INPUT_FILE-$$" ]
    then
        CONTENTS_OF_INPUTFILE=`cat $PPSS_DIR/INPUT_FILE-$$ | wc -l | awk '{ print $1 }'`
        echo "$CONTENTS_OF_INPUTFILE"
    else
        echo "Error, file $PPSS_DIR/INPUT_FILE-$$ does not exist."
    fi
}

oneTimeSetUp () {

	JOBLOG=./$PPSS_DIR/job_log
	INPUTFILENORMAL=test-normal.input
    INPUTFILESPECIAL_DIR=test-special.input
    LOCALOUTPUT=ppss_dir/PPSS_LOCAL_OUTPUT
	REMOVEFILES="$PPSS_DIR test-ppss-*"

    if [ ! -e "$TMP_DIR" ]
    then
        mkdir "$TMP_DIR"
    fi

    cleanup
}

testVersion () {

    assertEquals "Version mismatch!" "$VERSION" "$SCRIPT_VERSION"
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

    ROOT_DIR=$TMP_DIR/root
    CHILD_1=$ROOT_DIR/child_1
    CHILD_2=$ROOT_DIR/child_2

    mkdir -p "$ROOT_DIR" 
    mkdir -p "$CHILD_1"
    mkdir -p "$CHILD_2"

    for x in {1..10}
    do
        touch "$ROOT_DIR/file-$x" 
        touch "$CHILD_1/file-$x"
        touch "$CHILD_2/file-$x"
    done

    ln -s /etc/resolve.conf "$ROOT_DIR" 2> /dev/null
    ln -s /etc/hosts "$ROOT_DIR" 2> /dev/null
}

createSpecialFilenames () {

    ERROR=0
    mkdir -p "$SPECIAL_DIR"

    touch "$SPECIAL_DIR/a file with spaces" 
    touch "$SPECIAL_DIR/a\\'file\\'with\\'quotes"
    touch "$SPECIAL_DIR/a{file}with{curly}brackets}"
    touch "$SPECIAL_DIR/a(file)with(parenthesis)"
    touch "$SPECIAL_DIR/a\\file\\with\\backslashes"
    touch "$SPECIAL_DIR/a!file!with!exclamationmarks"
    touch "$SPECIAL_DIR/a filé with special characters"
    touch "$SPECIAL_DIR/a\"file\"with\"double\"quotes"
}

testMD5 () {

    ARCH=Darwin
    set_md5
    assertEquals "MD5 executable not set properly - $MD5" "$MD5" "md5" 
    ARCH=Linux
    set_md5
    assertEquals "MD5 executable not set properly - $MD5" "$MD5" "md5sum" 
    ARCH=$HOST_ARCH
}

init_get_all_items () {

    DIR="$1"
    RECURSION="$2"
    createDirectoryWithSomeFiles
    create_working_directory
    export SRC_DIR=$DIR
    init_vars > /dev/null 2>&1
    get_all_items
}

testRecursion () {

    init_get_all_items $TMP_DIR/root 1
    RESULT=`get_item_count_of_input_file`
    EXPECTED=32
    assertEquals "Recursion not correct." "$EXPECTED" "$RESULT"

    rename-ppss-dir $FUNCNAME
}

testNoRecursion () {

    init_get_all_items $TMP_DIR/root 0    
    RESULT=`get_item_count_of_input_file`
    EXPECTED=12

    assertEquals "Recursion not correct." "$EXPECTED" "$RESULT"

    rename-ppss-dir $FUNCNAME
}

testGetItem () {

    createSpecialFilenames
    init_get_all_items $TMP_DIR/root 1
    get_item
    if [ -z "$ITEM" ]
    then
        ERROR=1
    else 
        ERROR=0
    fi
    EXPECTED=0
    assertEquals "Get item failed." "$EXPECTED" "$ERROR"

    i=1
    ERROR=0
    while get_item
    do
        ((i++))
    done
    EXPECTED=40
    assertEquals "Got wrong number of items." "$EXPECTED" "$i"

    rename-ppss-dir $FUNCNAME
    cleanup
}

return_all_items () {

    while get_item
    do
        ALL_ITEMS="$ALL_ITEMS$ITEM"$'\n'
    done
    echo "$ALL_ITEMS"
}

testNumberOfItems () {

    createSpecialFilenames
    RESULT=`init_get_all_items $TMP_DIR/root 1`

    RES1=`find $TMP_DIR/root/ ! -type d`

    RES2=`return_all_items`

    echo "$RES1" > a
    echo "$RES2" > b

    assertEquals "Input file and actual files not the same!" "$RES1" "$RES2"
    rename-ppss-dir $FUNCNAME
}

testNumberOfLogfiles () {

    createSpecialFilenames
    init_get_all_items $TMP_DIR/root 1
    COMMAND='echo ' 
    while get_item
    do
        commando "$ITEM"
    done
    RESULT=`ls -1 $PPSS_DIR/job_log/ | wc -l | awk '{ print $1}'`
    EXPECTED=40
    assertEquals "Got wrong number of log files." "$EXPECTED" "$RESULT"
    rename-ppss-dir $FUNCNAME
}

testUserInputFile () {

    cleanup
    INPUT_FILE=test-special.input
    create_working_directory
    init_vars > /dev/null 2>&1
    get_all_items    
    RESULT=`return_all_items`
    ORIGINAL=`cat $INPUT_FILE`
    assertEquals "User input processing not ok." "$RESULT" "$ORIGINAL"
    rename-ppss-dir $FUNCNAME
}

. ./shunit2
