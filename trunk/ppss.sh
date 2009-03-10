#!/usr/bin/env bash
#
# PPSS, the Parallel Processing Shell Script
# 
# Copyright (c) 2009, Louwrentius
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#     * Redistributions of source code must retain the above copyright
#       notice, this list of conditions and the following disclaimer.
#     * Redistributions in binary form must reproduce the above copyright
#       notice, this list of conditions and the following disclaimer in the
#       documentation and/or other materials provided with the distribution.
#     * Neither the name of the <organization> nor the
#       names of its contributors may be used to endorse or promote products
#       derived from this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY Louwrentius ''AS IS'' AND ANY
# EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL Louwrentius BE LIABLE FOR ANY
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

#------------------------------------------------------------------------------
# It should not be necessary to edit antyhing in this script..
# Ofcource you can if it is necessary for your needs.
# Send a patch if your changes may benefit others.
#------------------------------------------------------------------------------

# Handling control-c for a clean shutdown.
trap 'kill_process; ' INT

# Setting some vars. Do not change. 
SCRIPT_NAME="Distributed Parallel Processing Shell Script"
SCRIPT_VERSION="2.0"

# The first argument to this script is always the 'mode'.
MODE="$1"
shift

ARGS=$@
CONFIG="config.cfg"
HOSTNAME=`hostname`
ARCH=`uname`
RUNNING_SIGNAL="$0_is_running"          # Prevents running mutiple instances of PPSS.. 
GLOBAL_LOCK="PPSS-GLOBAL-LOCK"          # Global lock file used by local PPSS instance.
PAUSE_SIGNAL="pause_signal"                # Not implemented yet (pause processing).
PAUSE_DELAY=300
STOP_SIGNAL="stop_signal"
ARRAY_POINTER_FILE="ppss-array-pointer" # 
JOB_LOG_DIR="JOB_LOG"                   # Directory containing log files of processed items.
LOGFILE="ppss-log.txt"                  # General PPSS log file. Contains lots of info.
STOP=9                                  # STOP job.
MAX_DELAY=2
PERCENT="0"
PID="$$"
LISTENER_PID=""
IFS_BACKUP="$IFS"
INTERVAL="30"                           # Polling interval to check if there are running jobs.
CPUINFO=/proc/cpuinfo

SSH_SERVER=""                           # Remote server or 'master'.
SSH_KEY=""                              # SSH key for ssh account.
SSH_SOCKET="/tmp/PPSS-ssh-socket"       # Multiplex multiple SSH connections over 1 master.
SSH_OPTS="-o BatchMode=yes -o ControlPath=$SSH_SOCKET \
                           -o GlobalKnownHostsFile=./known_hosts \
                           -o ControlMaster=auto \
                           -o ConnectTimeout=5"
SSH_MASTER_PID=""

PPSS_HOME_DIR="ppss"
ITEM_LOCK_DIR="PPSS_ITEM_LOCK_DIR"      # Remote directory on master used for item locking.
PPSS_LOCAL_TMPDIR="PPSS_LOCAL_TMPDIR" # Local directory on slave for local processing.
PPSS_LOCAL_OUTPUT="PPSS_LOCAL_OUTPUT" # Local directory on slave for local output.
TRANSFER_TO_SLAVE="0"                   # Transfer item to slave via (s)cp.
SECURE_COPY="1"                         # If set, use SCP, Otherwise, use cp.
REMOTE_OUTPUT_DIR=""                    # Remote directory to which output must be uploaded.
SCRIPT=""                               # Custom user script that is executed by ppss.


showusage () {
    
    echo 
    echo "$SCRIPT_NAME"
    echo "Version: $SCRIPT_VERSION"
    echo 
    echo "PPSS is a Bash shell script that executes commands in parallel on a set  "
    echo "of items, such as files, or lines in a file."
    echo 
    echo "Usage: $0 MODE [ options ]"
    echo " or "
    echo "Usage: $0 MODE -c <config file>"
    echo 
    echo "Modes are:"
    echo 
    echo " standalone   For execution of PPSS on a single host."
    echo " node         For execution of PPSS on a node, that is part of a 'cluster'."
    echo " config       Generate a config file based on the supplied option parameters."
    echo " deploy       Deploy PPSS and related files on the specified nodes."
    echo " erase        Erase PPSS and related files from the specified nodes."
    echo
    echo " start        Starting PPSS on nodes."
    echo " pause        Pausing PPSS on all nodes."
    echo " stop         Stopping PPSS on all nodes."
    echo 
    echo "Options are:"
    echo 
    echo -e "--command | -c     Command to execute. Syntax: '<command> ' including the single quotes."
    echo -e "                   Example: -c 'ls -alh '. It is also possible to specify where an item "
    echo -e "                   must be inserted: 'cp \"\$ITEM\" /somedir'."
    echo 
    echo -e "--sourcedir | -d   Directory that contains files that must be processed. Individual files" 
    echo -e "                   are fed as an argument to the command that has been specified with -c." 
    echo 
    echo -e "--sourcefile | -f  Each single line of the supplied file will be fed as an item to the"
    echo -e "                   command that has been specified with -c."
    echo 
    echo -e "--config | -c      If the mode is config, a config file with the specified name will be"
    echo -e "                   generated based on all the options specified. In the other modes". 
    echo -e "                   this option will result in PPSS reading the config file and start"
    echo -e "                   processing items based on the settings of this file."
    echo
    echo -e "--enable-ht | -j   Enable hyperthreading. Is disabled by default."
    echo 
    echo -e "--log | -l         Sets the name of the log file. The default is ppss-log.txt."
    echo
    echo -e "--processes | -p   Start the specified number of processes. Ignore the number of available"
    echo -e "                   CPU's."
    echo
    echo -e "The following options are used for distributed execution of PPSS."
    echo 
    echo -e "--server | -s      Specifies the SSH server that is used for communication between nodes."
    echo -e "                   Using SSH, file locks are created, informing other nodes that an item "
    echo -e "                   is locked. Also, often items, such as files, reside on this host. SCP "
    echo -e "                   is used to transfer files from this host to nodes for local procesing."
    echo
    echo -e "--node | -n        File containig a list of nodes that act as PPSS clients. One IP / DNS "
    echo -e "                   name per line."
    echo
    echo -e "--key | -k         The SSH key that a node uses to connect to the server."
    echo
    echo -e "--user | -u        The SSH user name that is used when logging in into the master SSH"
    echo -e "                   server."
    echo 
    echo -e "--script | -s      Specifies the script/program that must be copied to the nodes for "
    echo -e "                   execution through PPSS. Only used in the deploy mode."
    echo -e "                   This option should be specified if necessary when generating a config."
    echo
    echo -e "--transfer | -t    This option specifies that an item will be downloaded by the node "
    echo -e "                   from the server or share to the local node for processing."
    echo 
    echo -e "--no-scp | -b      Do not use scp for downloading items. Use cp instead. Assumes that a"
    echo -e "                   network file system (NFS/SMB) is mounted under a local mountpoint."
    echo 
    echo -e "--outputdir | -o   Directory on server where processed files are put. If the result of "
    echo -e "                   encoding a wav file is an mp3 file, the mp3 file is put in the "
    echo -e "                   directory specified with this option."
    echo 
    echo -e "Example: encoding some wav files to mp3 using lame:"
    echo 
    echo -e "$0 standalone -c 'lame ' -d /path/to/wavfiles -j " 
    echo 
    echo -e "Running PPSS based on a configuration file."
    echo
    echo -e "$0 node -C config.cfg"
    echo 
    echo -e "Running PPSS on a client as part of a cluster."
    echo 
    echo -e "$0 node -d /somedir -c 'cp "$ITEM" /some/destination' -s 10.0.0.50 -u ppss -t -k ppss-key.key"
    echo    
}

kill_process () {

    kill $LISTENER_PID >> /dev/null 2>&1
    while true
    do
        JOBS=`ps ax | grep -v grep | grep -v -i screen | grep ppss.sh | grep -i bash | wc -l`
        if [ "$JOBS" -gt "2" ]
        then
            for x in `ps ax | grep -v grep | grep -v -i screen | grep ppss.sh | grep -i bash | awk '{ print $1 }'`
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
            # The master SSH connection should be killed.
            if [ ! -z "$SSH_MASTER_PID" ]
            then
                kill -9 "$SSH_MASTER_PID"
            fi
            echo ""
            exit 0
        fi
    done
    
}

exec_cmd () { 

    CMD="$1"

    if [ ! -z "$SSH_SERVER" ] && [ "$SECURE_COPY" == "1" ]
    then
        ssh $SSH_OPTS $SSH_KEY $USER@$SSH_SERVER $CMD
    else
        eval "$CMD"
    fi
}

# this function makes remote or local checking of existence of items transparent.
does_file_exist () {

    FILE="$1"
    `exec_cmd "ls -1 $FILE" >> /dev/null 2>&1`
    if [ "$?" == "0" ]
    then
        return 0
    else 
        return 1
    fi
}

check_for_interrupt () {

    does_file_exist "$STOP_SIGNAL"
    if [ "$?" == "0" ]
    then
        log INFO "STOPPING job. Stop signal found."
        STOP="1"
    fi

    does_file_exist "$PAUSE_SIGNAL"
    if [ "$?" == "0" ]
    then
        log INFO "PAUSE: sleeping for $PAUSE_DELAY SECONDS."
        sleep $PAUSE_DELAY
        check_for_interrupt
    fi
}

cleanup () {

    #log DEBUG "$FUNCNAME - Cleaning up all temp files and processes."
    
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
        rm -rf $GLOBAL_LOCK
    fi

    if [ -e "$RUNNING_SIGNAL" ]
    then
        rm "$RUNNING_SIGNAL"
    fi

    if [ -e "$SSH_SOCKET" ]
    then
        rm -rf "$SSH_SOCKET"
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


add_var_to_config () {
    
    if [ "$MODE" == "config" ]
    then

        VAR="$1"
        VALUE="$2"

        echo -e "$VAR=$VALUE" >> $CONFIG
    fi
}

# Process any command-line options that are specified."
while [ $# -gt 0 ]
do
    case $1 in
        --config|-C )
                        CONFIG="$2"

                        if [ "$MODE" == "config" ]
                        then
                            if [ -e "$CONFIG" ]
                            then
                                echo "Do want to overwrite existing config file?"
                                read yn
                                if [ "$yn" == "y" ]
                                then
                                    rm "$CONFIG"
                                else
                                    echo "Aborting..."
                                    cleanup
                                    exit
                                fi 
                            fi
                        fi

                        if [ ! "$MODE" == "config" ]
                        then
                            source $CONFIG
                        fi

                        if [ ! -z "$SSH_KEY" ]
                        then
                            SSH_KEY="-i $SSH_KEY"
                        fi

                        shift 2
                        ;;
        --node|-n ) 
                        NODES_FILE="$2"
                        add_var_to_config NODES_FILE "$NODES_FILE"
                        shift 2
                        ;;

        --sourcefile|-f )
                        INPUT_FILE="$2"
                        add_var_to_config INPUT_FILE "$INPUT_FILE"
                        shift 2
                        ;;
        --sourcedir|-d ) 
                        SRC_DIR="$2"
                        add_var_to_config SRC_DIR "$SRC_DIR"
                        shift 2
                        ;; 
        --command|-c ) 
                        COMMAND=$2
                        if [ "$MODE" == "config" ]
                        then
                            COMMAND=\'$COMMAND\'
                            add_var_to_config COMMAND "$COMMAND"
                        fi
                        shift 2
                        ;;

        --help|-h )
                        showusage
                        exit 1;;
        --homedir|-H)
                        if [ ! -z "$2" ]
                        then
                            PPSS_HOME_DIR="$2"
                            add_var_to_config PPSS_HOME_DIR $PPSS_HOME_DIR
                            shift 2
                        fi
                        ;;
                        
        --disable-ht|-j )
                        HYPERTHREADING=no
                        add_var_to_config HYPERTHREADING $HYPERTHREADING
                        shift 1
                        ;;
        --log|-l )
                        LOGFILE="$2"
                        add_var_to_config LOGFILE "$LOGFILE"
                        shift 2
                        ;;
        --key|-k )
                        SSH_KEY="$2"
                        add_var_to_config SSH_KEY "$SSH_KEY"
                        if [ ! -z "$SSH_KEY" ]
                        then
                            SSH_KEY="-i $SSH_KEY"
                        fi
                        shift 2
                        ;;
        --no-scp |-b )
                        SECURE_COPY=0
                        add_var_to_config SECURE_COPY "$SECURE_COPY"
                        shift 1
                        ;;
        --outputdir|-o )
                        REMOTE_OUTPUT_DIR="$2"
                        add_var_to_config REMOTE_OUTPUT_DIR "$REMOTE_OUTPUT_DIR"
                        shift 2
                        ;;
        --processes|-p )
                        TMP="$2"
                        if [ ! -z "$TMP" ]
                        then
                            MAX_NO_OF_RUNNING_JOBS="$TMP"
                            add_var_to_config MAX_NO_OF_RUNNING_JOBS "$MAX_NO_OF_RUNNING_JOBS" 
                            shift 2
                        fi
                        ;;
        --server|-s ) 
                        SSH_SERVER="$2"
                        add_var_to_config SSH_SERVER "$SSH_SERVER"
                        shift 2
                        ;;
        --script|-S )
                        SCRIPT="$2"
                        add_var_to_config SCRIPT "$SCRIPT"
                        shift 2
                        ;;
        --transfer|-t )
                        TRANSFER_TO_SLAVE="1"    
                        add_var_to_config TRANSFER_TO_SLAVE "$TRANSFER_TO_SLAVE"
                        shift 1
                        ;;
        --user|-u )
                        USER="$2"
                        add_var_to_config USER "$USER"
                        shift 2
                        ;;

        --version|-v )
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

# Init all vars
init_vars () {

    if [ -e "$LOGFILE" ]
    then
        rm $LOGFILE
    fi

    if [ -z "$COMMAND" ]
    then
        echo
        echo "ERROR - no command specified."
        echo
        showusage
        cleanup
        exit 1
    fi

    echo 0 > $ARRAY_POINTER_FILE

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

    does_file_exist "$JOB_LOG_DIR"
    if [ ! "$?" == "0" ]
    then
        log INFO "Job log directory $JOB_lOG_DIR does not exist. Creating."
        exec_cmd "mkdir $JOB_LOG_DIR"
    else
        log INFO "Job log directory $JOB_LOG_DIR exists, skipping items for which logs are present."
    fi

    does_file_exist "$ITEM_LOCK_DIR"
    if [ ! "$?" == "0" ] && [ ! -z "$SSH_SERVER" ]
    then
        log DEBUG "Creating remote item lock dir."
        exec_cmd "mkdir $ITEM_LOCK_DIR"
    fi

    if [ ! -e "$JOB_LOG_DIR" ]
    then
        mkdir "$JOB_LOG_DIR"
    fi

    does_file_exist "$REMOTE_OUTPUT_DIR"
    if [ ! "$?" == "0" ]
    then
        echo "ERROR: remote output dir $REMOTE_OUTPUT_DIR does not exist."
        cleanup
        exit
    fi

    if [ ! -e "$PPSS_LOCAL_TMPDIR" ] && [ ! -z "$SSH_SERVER" ]
    then
        mkdir "$PPSS_LOCAL_TMPDIR"
    fi

    if [ ! -e "$PPSS_LOCAL_OUTPUT" ] && [ ! -z "$SSH_SERVER" ]
    then
        mkdir "$PPSS_LOCAL_OUTPUT"
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

log INFO "$0 $@"

check_status () {

    ERROR="$1"
    FUNCTION="$2"
    MESSAGE="$3"

    if [ ! "$ERROR" == "0" ]
    then
        log INFO "$FUNCTION - $MESSAGE"
        cleanup
        exit 1
    fi

}

erase_ppss () {

    echo "Are you realy sure you want to erase PPSS from all nades!?"
    read YN

    if [ "$YN" == "y" ]
    then
        for NODE in `cat $NODES_FILE`
        do
            log INFO "Erasing PPSS homedir $PPSS_HOME_DIR from node $NODE."
            ssh $USER@$NODE "rm -rf $PPSS_HOME_DIR"
        done
    fi
}

deploy_ppss () {

    ERROR=0
    set_error () {

        if [ ! "$1" == "0" ]
        then
            ERROR=$1 
        fi
    }

    if [ -z "$NODES_FILE" ]
    then
        log INFO "ERROR - are you using the right option? -C ?"
        cleanup 
        exit 1
    fi
    
    KEY=`echo $SSH_KEY | cut -d " " -f 2` 
    if [ -z "$KEY" ] || [ ! -e "$KEY" ]
    then
        log INFO "ERROR - nodes require a key file."
        cleanup
        exit 1
    fi

    if [ ! -e "$SCRIPT" ]
    then
        log INFO "ERROR - script $SCRIPT not found."
        cleanup
        exit 1
    fi

    if [ ! -e "$NODES_FILE" ]
    then
        log INFO "ERROR file $NODES with list of nodes does not exist."
        cleanup
        exit 1
    else
        for NODE in `cat $NODES_FILE` 
        do
            ssh -q $USER@$NODE "mkdir $PPSS_HOME_DIR >> /dev/null 2>&1" 
            scp -q $SSH_OPTS $0 $USER@$NODE:~/$PPSS_HOME_DIR
            set_error $?
            scp -q $KEY $USER@$NODE:~/$PPSS_HOME_DIR
            set_error $?
            scp -q $CONFIG $USER@$NODE:~/$PPSS_HOME_DIR
            set_error $?
            scp -q known_hosts $USER@$NODE:~/$PPSS_HOME_DIR
            set_error $?
            scp -q $SCRIPT $USER@$NODE:~/$PPSS_HOME_DIR
            set_error $?
            if [ ! -z "$INPUT_FILE" ]
            then
                scp -q $INPUT_FILE $USER@$NODE:~/$PPSS_HOME_DIR
                set_error $?
            fi

            if [ "$ERROR" == "0" ]
            then
                log INFO "PPSS installed on node $NODE."
            else
                log INFO "PPSS failed to install on $NODE."
            fi
        done
    fi
}

start_ppss_on_node () {

    NODE="$1"

    log INFO "Starting PPSS on node $NODE."
    ssh $USER@$NODE "cd $PPSS_HOME_DIR ; screen -d -m -S PPSS ./ppss.sh node --config $CONFIG" 
}


test_server () {

    # Testing if the remote server works as expected.
    if [ ! -z "$SSH_SERVER" ] 
    then
        exec_cmd "date >> /dev/null"
        check_status "$?" "$FUNCNAME" "Server $SSH_SERVER could not be reached"

        ssh -N -M $SSH_OPTS $SSH_KEY $USER@$SSH_SERVER &
        SSH_MASTER_PID="$!"
    else
        log DEBUG "No remote server specified, assuming stand-alone mode."
    fi
}

get_no_of_cpus () {

    # Use hyperthreading or not?
    HPT=$1
    NUMBER=""

    if [ -z "$HPT" ]
    then
        HPT=yes
    fi

    got_cpu_info () {

    ERROR="$1"
    check_status "$ERROR" "$FUNCNAME" "cannot determine number of cpu cores. Specify with -p." 

    }

    if [ "$HPT" == "yes" ]
    then
        if [ "$ARCH" == "Linux" ]
        then
            NUMBER=`grep ^processor $CPUINFO | wc -l`
            got_cpu_info "$?"
            
        elif [ "$ARCH" == "Darwin" ]
        then
            NUMBER=`sysctl -a hw | grep -w logicalcpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        elif [ "$ARCH" == "FreeBSD" ]
        then
            NUMBER=`sysctl hw.ncpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        else
            NUMBER=`grep ^processor $CPUINFO | wc -l`
            got_cpu_info "$?"
        fi
    elif [ "$HPT" == "no" ]
    then
        log DEBUG "Hyperthreading is disabled."
        if [ "$ARCH" == "Linux" ]
        then
            PHYSICAL=`grep 'physical id' $CPUINFO`
            if [ "$?" == "0" ]
            then
                PHYSICAL=`grep 'physical id' $CPUINFO | sort | uniq | wc -l`
                log DEBUG "Detected $PHYSICAL CPU(s)"
                TMP=`grep 'cpu cores' $CPUINFO` 
                if [ "$?" == "0" ]
                then
                    MULTICORE=`grep 'cpu cores' $CPUINFO | sort | uniq | cut -d ":" -f 2 | sed s/\ //g` 
                    log DEBUG "Detected $MULTICORE cores per CPU."
                    NUMBER=$(($PHYSICAL*$MULTICORE))
                else
                    log DEBUG "Starting job only for each physical CPU."
                    NUMBER=$PHYSICAL
                fi
            else
                log DEBUG "No 'physical id' section found in $CPUINFO."            
                NUMBER=`grep ^processor $CPUINFO | wc -l`
                got_cpu_info "$?"
            fi
                

        elif [ "$ARCH" == "Darwin" ]
        then
            NUMBER=`sysctl -a hw | grep -w physicalcpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        elif [ "$ARCH" == "FreeBSD" ]
        then
            NUMBER=`sysctl hw.ncpu | awk '{ print $2 }'`
            got_cpu_info "$?"
        else
            NUMBER=`cat $CPUINFO | grep "cpu cores" | cut -d ":" -f 2 | uniq | sed -e s/\ //g`
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
    ERROR="$?"

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

    rm -rf "$GLOBAL_LOCK"
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

download_item () {

    ITEM="$1"
    ITEM_WITH_PATH="$SRC_DIR/$ITEM"

    if [ "$TRANSFER_TO_SLAVE" == "1" ]
    then
        log DEBUG "Transfering item $ITEM to local disk."
        if [ "$SECURE_COPY" == "1" ]
        then
            scp -q $SSH_OPTS $SSH_KEY $USER@$SSH_SERVER:"$ITEM_WITH_PATH" $PPSS_LOCAL_TMPDIR
            log DEBUG "Exit code of transfer is $?"
        else
            cp "$ITEM_WITH_PATH" $PPSS_LOCAL_TMPDIR 
            log DEBUG "Exit code of transfer is $?"
        fi
    fi
}

upload_item () {

    ITEM="$1"

    log DEBUG "Uploading item $ITEM."
    if [ "$SECURE_COPY" == "1" ]
    then
        scp -q $SSH_OPTS $SSH_KEY "$ITEM" $USER@$SSH_SERVER:$REMOTE_OUTPUT_DIR
        ERROR="$?"
        if [ ! "$ERROR" == "0" ]
        then
            log DEBUG "ERROR - uploading of $ITEM failed."
        else
            log DEBUG "Upload of item $ITEM success" 
            rm $ITEM
        fi
    else    
        cp "$ITEM" $REMOTE_OUTPUT_DIR
        ERROR="$?"
        if [ ! "$ERROR" == "0" ]
        then
            log DEBUG "ERROR - uploading of $ITEM failed."
        fi
    fi
}

lock_item () {
    
    if [ ! -z "$SSH_SERVER" ]
    then
        ITEM="$1"
        LOCK_FILE_NAME=`echo $ITEM | sed s/^\\\.//g |sed s/^\\\.\\\.//g | sed s/\\\///g`
        ITEM_LOCK_FILE="$ITEM_LOCK_DIR/$LOCK_FILE_NAME"
        log DEBUG "Trying to lock item $ITEM."
        exec_cmd "mkdir $ITEM_LOCK_FILE >> /dev/null 2>&1"
        ERROR="$?"
        if [ -e "$ITEM_LOCK_FILE" ]
        then
            exec_cmd "touch $ITEM_LOCK_FILE/$HOSTNAME"
        fi
        return "$ERROR"
    fi
}

release_item () {

    ITEM="$1"
   
    LOCK_FILE_NAME=`echo $ITEM` # | sed s/^\\.//g | sed s/^\\.\\.//g | sed s/\\\///g`
    ITEM_LOCK_FILE="$ITEM_LOCK_DIR/$LOCK_FILE_NAME"

    exec_cmd "rm -rf ./$ITEM_LOCK_FILE"
}

get_all_items () {

    count=0

    if [ -z "$INPUT_FILE" ]
    then
        if [ ! -z "$SSH_SERVER" ] # Are we running stand-alone or as a slave?"
        then
            ITEMS=`exec_cmd "ls -1 $SRC_DIR"`
            check_status "$?" "$FUNCNAME" "Could not list files within remote source directory."
        else 
            ITEMS=`ls -1 $SRC_DIR`
        fi
        IFS=$'\n'

        for x in $ITEMS
        do
            ARRAY[$count]="$x"
            ((count++))
        done
        IFS=$IFS_BACKUP
    else
        if [ ! -z "$SSH_SERVER" ] # Are we running stand-alone or as a slave?"
        then
            log DEBUG "Running as slave, input file has been pushed (hopefully)."
            if [ ! -e "$INPUT_FILE" ]
            then
                log INFO "ERROR - input file $INPUT_FILE does not exist."
                cleanup 
                exit 1
            fi
        fi
    
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
        log INFO "ERROR: source file/dir seems to be empty."
        cleanup
        exit 1
    fi
}

get_item () {

    check_for_interrupt

    if [ "$STOP" == "1" ]
    then
        return 1
    fi

    get_global_lock

    SIZE_OF_ARRAY="${#ARRAY[@]}"

    # Return error if the array is empty.
    if [ "$SIZE_OF_ARRAY" -le "0" ]
    then
        release_global_lock
        return 1
    fi

    # This variable is used to walk thtough all array items.
    ARRAY_POINTER=`cat $ARRAY_POINTER_FILE`

    # Gives a status update on the current progress..
    PERCENT=$((100 * $ARRAY_POINTER / $SIZE_OF_ARRAY ))
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
        lock_item "$ITEM"
        if [ ! "$?" == "0" ]
        then
            log DEBUG "Item $ITEM is locked."
            release_global_lock
            get_item
        else
            log DEBUG "Got lock on $ITEM, processing."
            release_global_lock
            download_item "$ITEM"
            return 0
        fi
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


elapsed () {

    BEFORE="$1"
    AFTER="$2"

    ELAPSED="$(expr $AFTER - $BEFORE)"

    REMAINDER="$(expr $ELAPSED % 3600)"
    HOURS="$(expr $(expr $ELAPSED - $REMAINDER) / 3600)"

    SECS="$(expr $REMAINDER % 60)"
    MINS="$(expr $(expr $REMAINDER - $SECS) / 60)"

    echo "Elapsed time (h:m:s): $HOURS:$MINS:$SECS"
}

commando () {

    ITEM="$1"
    ITEM_NO_PATH="$1"

    log DEBUG "Processing item $ITEM"

    if [ -z "$INPUT_FILE" ] && [ "$TRANSFER_TO_SLAVE" == "0" ]
    then
        ITEM="$SRC_DIR/$ITEM"
    else
        ITEM="$PPSS_LOCAL_TMPDIR/$ITEM"
    fi

    LOG_FILE_NAME=`echo "$ITEM" | sed s/^\\\.//g | sed s/^\\\.\\\.//g | sed s/\\\///g`
    ITEM_LOG_FILE="$JOB_LOG_DIR/$LOG_FILE_NAME"

    mkdir -p $PPSS_LOCAL_OUTPUT/"$ITEM_NO_PATH"

    does_file_exist "$ITEM_LOG_FILE"
    if [ "$?" == "0" ]
    then
        log DEBUG "Skipping item $ITEM - already processed." 
    else
        
        ERROR=""

        # Some formatting of item log files. 
        DATE=`date +%b\ %d\ %H:%M:%S`
        echo "===== PPSS Item Log File =====" > "$ITEM_LOG_FILE"
        echo -e "Host:\t\t$HOSTNAME" >> "$ITEM_LOG_FILE"
        echo -e "Item:\t\t$ITEM" >> "$ITEM_LOG_FILE"
        echo -e "Start date:\t$DATE" >> "$ITEM_LOG_FILE"
        echo -e "" >> "$ITEM_LOG_FILE"
        
        # The actual execution of the command.
        TMP=`echo $COMMAND | grep -i '$ITEM'`
        if [ "$?" == "0"  ]
        then 
            BEFORE="$(date +%s)"
            eval "$COMMAND" >> "$ITEM_LOG_FILE" 2>&1
            ERROR="$?"
            AFTER="$(date +%s)"
        else
            EXECME='$COMMAND"$ITEM" >> "$ITEM_LOG_FILE" 2>&1'
            BEFORE="$(date +%s)"
            eval "$EXECME"
            ERROR="$?"
            AFTER="$(date +%s)"
        fi

        echo -e "" >> "$ITEM_LOG_FILE"

        # Some error logging. Success or fail.
        if [ ! "$ERROR" == "0" ] 
        then
           echo -e "Status:\t\tError - something went wrong." >> "$ITEM_LOG_FILE"
        else
           echo -e "Status:\t\tSucces - item has been processed." >> "$ITEM_LOG_FILE"
        fi

        if [ "$TRANSFER_TO_SLAVE" == "1" ]      
        then
            if [ -e "$ITEM" ]
            then
                rm $ITEM
            else        
                log DEBUG "ERROR Something went wrong removing item $ITEM from local work dir."
            fi

        fi

        if [ ! -z "$REMOTE_OUTPUT_DIR" ] && [ ! -z "$SSH_SERVER" ] 
        then
            upload_item "$PPSS_LOCAL_OUTPUT/$ITEM_NO_PATH/*"
        fi
        
        elapsed "$BEFORE" "$AFTER" >> "$ITEM_LOG_FILE"
        echo -e "" >> "$ITEM_LOG_FILE"

        if [ ! -z "$SSH_SERVER" ]
        then
            log DEBUG "Uploading item log file $ITEM_LOG_FILE to master."
            scp -q $SSH_OPTS $SSH_KEY $ITEM_LOG_FILE $USER@$SSH_SERVER:~/$JOB_LOG_DIR/ 
        fi
    fi

    start_single_worker
    return $?
}

# This is the listener service. It listens on the pipe for events.
# A job is executed for every event received.
listen_for_job () {

    log INFO "Listener started."
    while read event <& 42
    do
        commando "$event" &
    done
}

# This starts an number of parallel workers based on the # of parallel jobs allowed.
start_all_workers () {

    if [ "$MAX_NO_OF_RUNNING_JOBS" == "1" ]
    then
        log INFO "Starting $MAX_NO_OF_RUNNING_JOBS worker."
    else
        log INFO "Starting $MAX_NO_OF_RUNNING_JOBS workers."
    fi

    i=0
    while [ "$i" -lt "$MAX_NO_OF_RUNNING_JOBS" ]
    do
        start_single_worker
        ((i++))
    done
}

show_status () {

    source $CONFIG
    if [ ! -z "$SSH_KEY" ]
    then
        SSH_KEY="-i $SSH_KEY"
    fi

    if [ -z "$INPUT_FILE" ]
    then
        ITEMS=`exec_cmd "ls -1 $SRC_DIR | wc -l"`
    else
        ITEMS=`exec_cmd "cat $INPUT_FILE | wc -l"` 
    fi
    
    PROCESSED=`exec_cmd "ls -1 $ITEM_LOCK_DIR | wc -l"`
    STATUS=$((100 * $PROCESSED / $ITEMS))

    log INFO "$STATUS percent complete."

}


# If this is called, the whole framework will execute.
main () {
    
    is_running    

    case $MODE in
    node|standalone ) 
                    log DEBUG "---------------- START ---------------------"
                    log INFO "$SCRIPT_NAME version $SCRIPT_VERSION"
                    log INFO `hostname`
                    init_vars
                    test_server
                    get_all_items
                    listen_for_job "$MAX_NO_OF_RUNNING_JOBS" &
                    LISTENER_PID=$!
                    start_all_workers
                    ;;
        start )
                    # This option only starts all nodes.
                    init_vars
                
                    if [ ! -e "$NODES_FILE" ]
                    then
                        log INFO "ERROR file $NODES with list of nodes does not exist."
                        cleanup
                        exit 1
                    else
                        for NODE in `cat $NODES_FILE`
                        do
                            start_ppss_on_node "$NODE"
                        done
                    fi
                    cleanup
                    exit 0
                    ;;
        config )

                    log INFO "Generating configuration file $CONFIG"
                    add_var_to_config PPSS_LOCAL_TMPDIR "$PPSS_LOCAL_TMPDIR"
                    add_var_to_config PPSS_LOCAL_OUTPUT "$PPSS_LOCAL_OUTPUT"
                    cleanup
                    exit 0
                    ;;

        stop )
                    log INFO "Stopping PPSS on all nodes."
                    exec_cmd "touch $STOP_SIGNAL"
                    cleanup
                    exit
                    ;;
        pause )
                    log INFO "Pausing PPSS on all nodes."
                    exec_cmd "touch $PAUSE_SIGNAL"
                    cleanup
                    exit
                    ;;
        continue )
                    if does_file_exist "$STOP_SIGNAL"
                    then
                        log INFO "Continuing processing, please use $0 start to start PPSS on al nodes."
                        exec_cmd "rm -f $STOP_SIGNAL"
                    fi
                    if does_file_exist "$PAUSE_SIGNAL"
                    then
                        log INFO "Continuing PPSS on all nodes."
                        exec_cmd "rm -f $PAUSE_SIGNAL"
                    fi
                    cleanup
                    exit
                    ;;
        deploy )
                    log INFO "Deploying PPSS on nodes."
                    deploy_ppss
                    cleanup
                    exit 0
                    ;;
        status )
                    show_status
                    cleanup
                    exit 0
                    # some show command
                    ;;
        erase )
                    log INFO "Erasing PPSS from all nodes."
                    erase_ppss
                    cleanup
                    exit 0
                    ;;
        * )
                    showusage
                    exit 1
                    ;;
    esac

}
# This command starts the that sets the whole framework in motion.
main

# Either start new jobs or exit, sleep in the meantime.
while true
do
    sleep 5
    JOBS=`ps ax | grep -v grep | grep -v -i screen | grep ppss.sh | wc -l`
    log INFO "There are $JOBS running processes. "
    
    MIN_JOBS=3

    if [ "$ARCH" == "Darwin" ]
    then
        MIN_JOBS=4
    elif [ "$ARCH" == "Linux" ]
    then
        MIN_JOBS=3
    fi

    if [ "$JOBS" -gt "$MIN_JOBS" ] 
    then
        log INFO "Sleeping $INTERVAL seconds." 
        sleep $INTERVAL
    else
            echo -en "\033[1B"
            log INFO "There are no more running jobs, so we must be finished."
            echo -en "\033[1B"
            log INFO "Killing listener and remainig processes."
            log INFO "Dying processes may display an error message."
            kill_process
    fi
done

# Exit after all processes have finished.
wait
