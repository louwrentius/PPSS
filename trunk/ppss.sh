#!/bin/bash
#*
#* PPSS, the Parallel Processing Shell Script
#* 
#* Copyright (c) 2009, Louwrentius
#* All rights reserved.
#*
#* Redistribution and use in source and binary forms, with or without
#* modification, are permitted provided that the following conditions are met:
#*     * Redistributions of source code must retain the above copyright
#*       notice, this list of conditions and the following disclaimer.
#*     * Redistributions in binary form must reproduce the above copyright
#*       notice, this list of conditions and the following disclaimer in the
#*       documentation and/or other materials provided with the distribution.
#*     * Neither the name of the <organization> nor the
#*       names of its contributors may be used to endorse or promote products
#*       derived from this software without specific prior written permission.
#*
#* THIS SOFTWARE IS PROVIDED BY Louwrentius ''AS IS'' AND ANY
#* EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#* WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#* DISCLAIMED. IN NO EVENT SHALL Louwrentius BE LIABLE FOR ANY
#* DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#* (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#* LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#* ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#* (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#* SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


#------------------------------------------------------
# It should not be necessary to edit antyhing.
# Ofcource you can if it is necesary for your needs.
# Send a patch if your changes may benefit others.
#------------------------------------------------------

# Handling control-c for a clean shutdown.
trap 'kill_process; ' INT

# Setting some vars. Do not change. 
SCRIPT_NAME="Parallel Processing Shell Script"
SCRIPT_VERSION="1.05"

RUNNING_SIGNAL="$0_is_running"
GLOBAL_LOCK="PPSS-$RANDOM-$RANDOM"
PAUSE_SIGNAL="pause.txt"
ARRAY_POINTER_FILE="array-pointer-$RANDOM-$RANDOM"
JOB_LOG_DIR="job_log"
LOGFILE="ppss-log.txt"
MAX_DELAY=2
PERCENT="0"
PID="$$"
LISTENER_PID=""
IFS_BACKUP="$IFS"

showusage () {
    
    echo 
    echo "$SCRIPT_NAME"
    echo "Version: $SCRIPT_VERSION"
    echo 
    echo "Description: this script processess files or other items in parallel. It is designed to make"
    echo "use of the multi-core CPUs. It will detect the number of available CPUs and start a thread "
    echo "for each CPU core. It will also use hyperthreading if available."
    echo 
    echo "Usage: $0 [ options ]"
    echo 
    echo "Options are:"
    echo 
    echo -e "\t- c [ command ] \t\t\tCommand to execute. Can be a custom script or just a plain command."
    echo -e "\t- d [ directory] \t\t\tDirectory containing items to be processed."
    echo -e "\t- f [ input file ] \t\t\tFile containing items to be processed. Either -d or -f" 
    echo -e "\t- l [ logfile ] \t\t\tSpecifies name and location of the logfile."
    echo -e "\t- p [ no of parallel processes ] \tOptional: specifies number of simultaneous processes manually."
    echo -e "\t- j ( enable hyperthreading ) \t\tOptiona: Enable or disable hyperthreading. Enabled by default."
    echo
    echo -e "Example: encoding some wav files to mp3 using lame:"
    echo 
    echo -e "$0 -c 'lame' -d /path/to/wavfiles -l logfile -j "
    
}

kill_process () {

    kill $LISTENER_PID >> /dev/null 2>&1
    while true
    do
        JOBS=`ps ax | grep -v grep | grep ppss.sh | wc -l`
        if [ "$JOBS" -gt "2" ]
        then
            for x in `ps ax | grep -v grep | grep ppss.sh | awk '{ print $1 }'`
            do
                if [ ! "$x" == "$PID" ] && [ ! "$x" == "$$" ]
                then
                    kill -9 $x >> /dev/null 2>&1
                fi
            done
            sleep 5
        else
            cleanup 
            echo -en "\033[1B"
            log INFO "Finished."
            echo ""
            exit 0
        fi
    done
}


cleanup () {

    log DEBUG "$FUNCNAME - Cleaning up all temp files and processes."
    
    if [ -e "$FIFO" ]
    then 
        rm $FIFO 
    fi

    if [ -e "$ARRAY_POINTER_FILE" ]
    then
        rm $ARRAY_POINTER_FILE
    fi

    if [ -e "$GLOBAL_LOCK" ]
    then
        rm -rf "$GLOBAL_LOCK"
    fi

    if [ -e "$RUNNING_SIGNAL" ]
    then
        rm "$RUNNING_SIGNAL"
    fi
}



# check if ppss is already running.
is_running () {

    if [ -e "$RUNNING_SIGNAL" ]
    then
        echo 
        log INFO "$0 is already running (lock file exists)."
        echo
        exit 1
    fi
}

# If no arguments are specified, show usage.
if [ $# -eq 0 ]
then
  showusage
  exit 1
fi

# If rubbish is givven as an argument, display usage info."
echo $1 | grep -e ^- >> /dev/null
ERROR=$?
if [ ! "$ERROR" == "0" ]
then
  showusage
  exit 1
fi

# Process any command-line options that are specified."
while getopts ":f:c:l:i:vhp:jd:" OPTIONS
do
    case $OPTIONS in
        f )
            INPUT_FILE="$OPTARG"
            if [ ! -e "$INPUT_FILE" ]
            then
                echo "ERROR: input file $INPUT_FILE not found."
                exit 1
            fi
            ;;
        d ) 
            SRC_DIR="$OPTARG"
            if [ ! -e "$SRC_DIR" ]
            then
                echo "ERROR: directory $SRC_DIR does not exist."
                exit 1
            fi
            ;; 
        c ) 
            COMMAND="$OPTARG"
            if [ -z "$COMMAND" ]
            then
                echo "ERROR: command not specified."
                exit 1
            fi
            ;;

        h )
            showusage
            exit 1;;
        j )
            HYPERTHREADING=yes
            ;;
        l )
            LOGFILE="$OPTARG"
            ;;
        p )
            TMP="$OPTARG"
            if [ ! -z "$TMP" ]
            then
                MAX_NO_OF_RUNNING_JOBS="$TMP"
            fi
            ;;

        v )
            echo ""
            echo "$SCRIPT_NAME version $SCRIPT_VERSION"
            echo ""
            exit 0
            ;;
        * )
            showusage
            exit 1;;
    esac
done

# Init log file
if [ -e "$LOGFILE" ]
then
    rm $LOGFILE
fi

init_vars () {

    echo 0 > "$ARRAY_POINTER_FILE"

    FIFO=$(pwd)/fifo-$RANDOM-$RANDOM

    if [ ! -e "$FIFO" ]
    then    
        mkfifo -m 600 $FIFO
    fi

    exec 42<> $FIFO

    touch $RUNNING_SIGNAL

    if [ -z "$MAX_NO_OF_RUNNING_JOBS" ]
    then 
        MAX_NO_OF_RUNNING_JOBS=`get_no_of_cpus $HYPERTHREADING`
    fi

    if [ ! -e "$JOB_LOG_DIR" ]
    then
        mkdir "$JOB_LOG_DIR"
    fi
}

expand_str () {

    STR=$1
    LENGTH=$TYPE_LENGTH
    SPACE=" "

    while [ "${#STR}" -lt "$LENGTH" ]
    do
        STR=$STR$SPACE
    done

    echo "$STR"
}

log () {

    TYPE="$1"
    MESG="$2"
    TMP_LOG=""
    TYPE_LENGTH=6 

    TYPE_EXP=`expand_str "$TYPE"`

    DATE=`date +%b\ %d\ %H:%M:%S`
    PREFIX="$DATE: ${TYPE_EXP:0:$TYPE_LENGTH} -"

    LOG_MSG="$PREFIX $MESG"

    echo -e "$LOG_MSG" >> "$LOGFILE"

    if [ "$TYPE" == "INFO" ]
    then
        echo -e "$LOG_MSG"
    fi

}

check_status () {

    ERROR="$1"
    FUNCTION="$2"
    MESSAGE="$3"

    if [ ! "$ERROR" == "0" ]
    then
        log INFO "$FUNCTION - $MESSAGE"
        exit 1
    fi

}

get_no_of_cpus () {

    # Use hyperthreading or not?
    HPT=$1
    NUMBER=""

    if [ -z "$HPT" ]
    then
        HPT=no
    fi

    got_cpu_info () {

    ERROR="$1"
    check_status "$ERROR" "$FUNCNAME" "cannot determine number of cpu cores. Please specify a number of parallell processes manually with -p." 

    }

    if [ "$HPT" == "yes" ]
    then
        if [ `uname` == "Linux" ]
        then
            NUMBER=`cat /proc/cpuinfoo | grep processor | wc -l`
            got_cpu_info "$?"
            
        elif [ `uname` == "Darwin" ]
        then
            NUMBER=`sysctl -a hw | grep -w logicalcpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        elif [ `uname` == "FreeBSD" ]
        then
            NUMBER=`sysctl hw.ncpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        else
            NUMBER=`cat /proc/cpuinfo | grep processor | wc -l`
            got_cpu_info "$?"
        fi
    elif [ "$HPT" == "no" ]
    then
        if [ `uname` == "Linux" ]
        then
            NUMBER=`cat /proc/cpuinfo | grep "cpu cores" | cut -d ":" -f 2 | uniq | sed -e s/\ //g`
            got_cpu_info "$?"
        elif [ `uname` == "Darwin" ]
        then
            NUMBER=`sysctl -a hw | grep -w physicalcpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        elif [ `uname` == "FreeBSD" ]
        then
            NUMBER=`sysctl hw.ncpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        else
            NUMBER=`cat /proc/cpuinfo | grep "cpu cores" | cut -d ":" -f 2 | uniq | sed -e s/\ //g`
            got_cpu_info "$?"
        fi

    fi

    if [ ! -z "$NUMBER" ]
    then
        echo "$NUMBER"
    else
        log INFO "$FUNCNAME ERROR - number of CPUs not obtained."
        exit 1
    fi
}


random_delay () {

    ARGS="$1"

    if [ -z "$ARGS" ]
    then
        log ERROR "$FUNCNAME Function random delay, no argument specified."
        exit 1
    fi

    NUMBER=$RANDOM
    let "NUMBER %= $ARGS"
    sleep "$NUMBER"
}

global_lock () {

    mkdir $GLOBAL_LOCK > /dev/null 2>&1
    ERROR=$?
    if [ ! "$ERROR" == "0" ]
    then
        return 1
    else
        return 0
    fi
}

get_global_lock () {

    while true
    do
        global_lock
        ERROR="$?"
        if [ ! "$ERROR" == "0" ]
        then
            random_delay $MAX_DELAY
            continue
        else
            break
        fi
    done
}

release_global_lock () {

    if [ -e "$GLOBAL_LOCK" ]
    then
        rm -rf "$GLOBAL_LOCK"
        return 0
    else
        log ERROR "$FUNCNAME Lock file $GLOBAL_LOCK not present, something is wrong!"
        return 1
        exit
    fi
}


are_jobs_running () {
   
    NUMBER_OF_PROCS=`jobs | wc -l`
    if [ "$NUMBER_OF_PROCS" -gt "1" ]
    then
        return 0
    else
        return 1
    fi
}

get_all_items () {

    count=0

    if [ -z "$INPUT_FILE" ]
    then
        ITEMS=`ls -1 $SRC_DIR`
        IFS="
"
        for x in $ITEMS
        do
            ARRAY[$count]="$x"
            ((count++))
        done
        IFS=$IFS_BACKUP
    else
        exec 10<$INPUT_FILE

        while read LINE <&10
        do
            ARRAY[$count]=$LINE
            ((count++))
        done
  
    fi
    exec 10>&-

    SIZE_OF_ARRAY="${#ARRAY[@]}"
    if [ "$SIZE_OF_ARRAY" -le "0" ]
    then
        echo "ERROR: source file seems to be empty."
        exit 1
    fi
}

get_item () {

    get_global_lock

    SIZE_OF_ARRAY="${#ARRAY[@]}"

    # Return error if the array is empty.
    if [ "$SIZE_OF_ARRAY" -le "0" ]
    then
        release_global_lock
        return 1
    fi

    # This variable is used to walk thtough all array items.
    ARRAY_POINTER=`cat "$ARRAY_POINTER_FILE"`


    # Gives a status update on the current progress..
    PERCENT=`echo "100 * $ARRAY_POINTER / $SIZE_OF_ARRAY" | bc`
    log INFO "Currently $PERCENT percent complete. Processed $ARRAY_POINTER of $SIZE_OF_ARRAY items." 
    echo -en "\033[1A"

 
    # Check if all items have been processed.
    if [ "$ARRAY_POINTER" -ge "$SIZE_OF_ARRAY" ]
    then
        release_global_lock
        return 2
    fi

    # Select an item. 
    ITEM="${ARRAY[$ARRAY_POINTER]}" 
    if [ -z "$ITEM" ]
    then
        ((ARRAY_POINTER++))
        echo $ARRAY_POINTER > $ARRAY_POINTER_FILE
        release_global_lock
        get_item
    else
        ((ARRAY_POINTER++))
        echo $ARRAY_POINTER > $ARRAY_POINTER_FILE
        release_global_lock
        return 0
    fi

}

start_single_worker () {
    
    get_item
    ERROR=$?
    if [ ! "$ERROR" == "0" ]
    then 
        log DEBUG "Item empty, we are probably almost finished."
        return 1
    else
        get_global_lock
        echo "$ITEM" > $FIFO
        release_global_lock
        return 0
    fi
}

commando () {

    ITEM="$1"

    if [ -e "$JOB_LOG_DIR/$ITEM" ]
    then
        log DEBUG "Skipping item $ITEM - already processed." # <-- disabled because of possible performance penalty.
    else
        #log DEBUG "Starting command on item $ITEM."  # <-- disabled because of possible performance penalty.
        EXECME='$COMMAND"$ITEM" > "$JOB_LOG_DIR/$ITEM"'
        eval "$EXECME"
    fi

    start_single_worker
    return $?
}

listen_for_job () {

    log INFO "Listener started."
    while read event <& 42
    do
        commando "$event" &
    done
}

# This starts an number of parallel workers based on the # of parallel jobs allowed.
start_all_workers () {

    log INFO "Starting $MAX_NO_OF_RUNNING_JOBS workers."

    i=0
    while [ "$i" -lt "$MAX_NO_OF_RUNNING_JOBS" ]
    do
        log DEBUG "$FUNCNAME - NO OF WORKERS is $i"
        start_single_worker
        ((i++))
    done
}


# If this is called, the whole framework will execute.
main () {
    
    log DEBUG "---------------- START ---------------------"
    log INFO "$SCRIPT_NAME version $SCRIPT_VERSION"
    is_running    
    init_vars
    get_all_items
    listen_for_job "$MAX_NO_OF_RUNNING_JOBS" &
    LISTENER_PID=$!
    start_all_workers

}
# This command starts the that sets the whole framework in motion.
main
while true
do
    JOBS=`ps ax | grep -v grep | grep ppss.sh | wc -l`
    if [ "$JOBS" -gt "3" ]
    then
        sleep 20
    else
        echo -en "\033[1B"
        log INFO "There are no more running jobs, so we must be finished."
        echo -en "\033[1B"
        log INFO "Killing listener and remainig processes."
        log INFO "Dying processes may display an error message."
        kill_process
    fi
done
wait
