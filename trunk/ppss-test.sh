#!/bin/bash

DEBUG="$1"
VERSION="2.70"
TMP_DIR="/tmp/ppss"
PPSS=./ppss
PPSS_DIR=ppss_dir
export PPSS_DEBUG=1
HOST_ARCH=`uname`
. "$PPSS"

cleanup () {

        for x in $REMOVEFILES
        do
            if [ -e ./$x ]
            then
                rm -r ./$x
            fi
        done
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

get_contents_of_input_file () {

    RES=`cat $PPSS_DIR/INPUT_FILE-$$ | wc -l | awk '{ print $1 }'`
    echo "$RES"
}

oneTimeSetUp () {

	JOBLOG=./$PPSS_DIR/job_log
	INPUTFILENORMAL=test-normal.input
    INPUTFILESPECIAL=test-special.input
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

    RECURSION="$1"
    createDirectoryWithSomeFiles
    create_working_directory
    init_vars > /dev/null 2>&1
    export SRC_DIR=$TMP_DIR/root
    get_all_items
    RES=`get_contents_of_input_file`
}

testRecursion () {

    init_get_all_items 1

    EXPECTED=32
    assertEquals "Recursion not correct." "$EXPECTED" "$RES"

    rename-ppss-dir $FUNCNAME
}

testNoRecursion () {

    init_get_all_items 0    
    EXPECTED=12

    assertEquals "Recursion not correct." "$EXPECTED" "$RES"

    rename-ppss-dir $FUNCNAME
}

. ./shunit2
