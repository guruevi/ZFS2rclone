#!/bin/bash

usage () {
    echo "usage: backup [ -j <int|0> ] [ -d <rclone server address> ] [ -l <rclone config path> ]  [ -r <rclone_remote_name> ] [ -s <snapshot_name> ] <backup|restore> <dataset_name>" >&2

    exit 2
}


exit_if_error () {
    if [ "$1" -gt "0" ]; then
	echo "Exiting... ($2)" >&2
	kill -s TERM $TOP_PID
    fi
}

is_snapshot_complete () {
    rclone cat $1/completed
    exit_if_error $? "incomplete snapshot $1"
}

copy_or_move_file () {
    SRC=$1
    DEST=$2
    ACTION=${3:-"copyfile"}
    ERRORS_ARE_OK=${4:-""}
    
    SRC_FILENAME=$(basename $SRC)
    SRC_FS=$(dirname $SRC)
    
    echo "mkdir to $DEST" >&2
    json_response=$(rclone rc operations/mkdir --json '{"remote": "", "fs": "'$DEST'"}')
 
    echo "Backing up $SRC to $DEST" >&2
    json_response=$(rclone rc operations/$ACTION --json '{"_async": true, "srcFs": "'$SRC_FS'", "srcRemote": "'$SRC_FILENAME'", "dstFs": "'$DEST'", "dstRemote": "'$SRC_FILENAME'"}')
    exit_if_error $?
    jobid=$(echo $json_response | jq .jobid)
    
    done="false"
    while [ "$done" == "false" ]; do
	json_response=$(rclone rc job/status jobid=$jobid)
	exit_if_error $? "status"
	
	done=$(echo $json_response | jq .finished)

	json_response=$(rclone rc core/stats group=job/$jobid)
	exit_if_error $? "stats"
	percent=$(rclone rc core/stats group=job/$jobid | jq '.transferring[0].percentage' )
	if [ "$percent" != "null" ]; then
	    echo "$FILENAME ... $percent%" >&2
	fi
	
	sleep 1
    done

    success=$(rclone rc job/status jobid=$jobid | jq .success)
    if [ "$success" == "false" ] && [ -z "$ERRORS_ARE_OK" ]; then
	json_response=$(rclone rc job/status jobid=$jobid)
	exit_if_error $? "status"
	error=$(echo $json_response | jq .error)
	
	echo "an error occured for $FILENAME ($error)" >&2
	exit 1
    fi

    json_response=$(rclone rc core/stats group=job/$jobid)
    exit_if_error $? "stats after success"

    transfers=$(echo $json_response | jq '.transfers' )
    if [ "$transfers" == "0" ] && [ -z "$ERRORS_ARE_OK" ]; then
	echo "$FILENAME transfer tasks reports OK, but no files got sent. Error." >&2
	exit 1
    fi
	
    echo "$FILENAME:backedup successfully" >&2
}


split_backup_monitor_archive () {
    export TOP_PID=$$

    trap "echo bye; exit 1" TERM
    
    FILENAME=$(printf "%08d"  $1).par
    /bin/cat -  > $ARCHIVE_SAVE_PATH/$FILENAME
    echo "$FILENAME:saved to disk" >&2

    copy_or_move_file $ARCHIVE_SAVE_PATH/$FILENAME $REMOTE "movefile"
    exit $?
}

export -f split_backup_monitor_archive
export -f exit_if_error
export -f copy_or_move_file

get_chain () {
    DATASET=$(echo $DATASET_NAME | cut -d@ -f1)
    SNAPSHOT=${SNAPSHOT_NAME}


    end=0
    snapshots=""
    snapshot=$SNAPSHOT
    while [ $end -eq 0 ]; do
	is_snapshot_complete $REMOTE/$DATASET/$snapshot
	exit_if_error $?
	snapshots="$snapshot $snapshots"
	if [ $snapshot = "$FIRST_SNAPSHOT" ]; then
	    end=1
	fi
	echo "snapshot $snapshot added to the queue" >&2
	
	next_snapshot=$(rclone cat $REMOTE/$DATASET/$snapshot/depends_on)
	exit_if_error $? "cannot read depends_on file for $snapshot"
	snapshot=$next_snapshot

	if [ $next_snapshot = "none" ]; then
	    end=1
	fi
    done

    echo $snapshots >&2
    export SNAPSHOTS=$snapshots
}

restore_backup () {

    DATASET=$(echo $DATASET_NAME | cut -d@ -f1)
    SNAPSHOT=$1
    
    WORKDIR=/var/run/zfs2rclone/${DATASET}/$SNAPSHOT    
    mkdir -p $WORKDIR

    rclone lsf --include "*.par" $REMOTE/$DATASET/$SNAPSHOT | sort > $WORKDIR/files
    parallel --retries 4 -j1 -a $WORKDIR/files -k "echo loading {} >&2; rclone cat $REMOTE/${DATASET}/$SNAPSHOT/{}" | eval "$RESTORE_COMMAND"
}

prepare_backup_environment () {
    if [ $LOCAL_RCLONE -eq 1 ]; then
	rclone rcd --rc-no-auth --config $RCLONE_CONFIG_PATH &
	export RCLONE_PID=$!
	sleep 4
    fi

    mkdir -p $WORKDIR

    rm -f $LOCAL_LASTSNAPFILE
    touch $LOCAL_LASTSNAPFILE
    copy_or_move_file $REMOTE_LASTSNAPFILE $WORKDIR "copyfile" "errors_are_ok"
    LAST_KNOWN_SNAP=$(cat $LOCAL_LASTSNAPFILE)
    if [ -z "$LAST_KNOWN_SNAP" ]; then
       LAST_KNOWN_SNAP="none"
    fi

    echo $SNAPSHOT_NAME >&2
    CURRENTSNAP=${SNAPSHOT_NAME:-$(zfs list -Hpr -t snapshot -d 1 $DATASET_NAME | grep daily |  tail -n 1 | awk -F"[@\t]" '{ print $2 }')}

    INCREMENT=""
    if [ -z "$CURRENTSNAP" ]; then
	echo "There are no snapshots for this volume" >&2
	exit 1
    fi

    # Find out if we ran this before
    if [ "$LAST_KNOWN_SNAP" != "none" ]; then
	echo Last snapshot: $LAST_KNOWN_SNAP >&2
	INCREMENT="-I $LAST_KNOWN_SNAP"
	if [ "$CURRENTSNAP" = "$LAST_KNOWN_SNAP" ]; then
	    echo "Snapshot is the same as the last backup. Nothing to do." >&2
	    exit 0
	fi
    fi

    echo "Backing up snapshot : $CURRENTSNAP" >&2

    export ARCHIVE_SAVE_PATH="$WORKDIR/$CURRENTSNAP"
    mkdir -p $ARCHIVE_SAVE_PATH

    export REMOTE="$REMOTE/$DATASET_NAME/$CURRENTSNAP"
}


backup_snapshot () {
    trap "echo bye; kill $RCLONE_PID; exit 1" TERM

    # We want a job, so that, if parallel finds it, it will restart where
    # it left off. This is useful when a backup fails because the computer
    # is shutdown or suspended mid backup.
    JOBLOG=$ARCHIVE_SAVE_PATH/joblog
    
    zfs send --raw -c $INCREMENT $DATASET_NAME@$CURRENTSNAP \
	| parallel --joblog $JOBLOG \
		   --resume-failed \
		   --halt now,fail=1 \
		   --pipe \
		   --line-buffer \
		   -j$CONCURRENCY \
		   --block 1.9G \
		   "split_backup_monitor_archive {#}"
    
    exit_if_error $?

    COMPLETED=$WORKDIR/$CURRENTSNAP/completed
    DEPENDS_ON=$WORKDIR/$CURRENTSNAP/depends_on
    
    echo $CURRENTSNAP > $LOCAL_LASTSNAPFILE
    echo $LAST_KNOWN_SNAP > $DEPENDS_ON
    touch $COMPLETED
    copy_or_move_file $DEPENDS_ON $REMOTE "movefile"
    copy_or_move_file $COMPLETED $REMOTE "movefile"

    # LAST SNAP FILE goes one level up, so we use dirname for this.
    copy_or_move_file $LOCAL_LASTSNAPFILE $(dirname $REMOTE) "movefile"
}

cleanup () {
    rm $JOBLOG
    kill $RCLONE_PID
}



# Set default variables and parse arguments
LOCAL_RCLONE=1

PARSED_ARGUMENTS=$(getopt -a -n backup -o j:r:d:l:s:c:f: -- "$@")
VALID_ARGUMENTS=$?
if [ "$VALID_ARGUMENTS" != "0" ]; then
  usage
fi
FIRST_SNAPSHOT=""
echo "PARSED_ARGUMENTS is $PARSED_ARGUMENTS" >&2
eval set -- "$PARSED_ARGUMENTS"
while :
do
  case "$1" in
      -j) CONCURRENCY="$2"            ; shift 2 ;;
      -r) REMOTE="$2"                 ; shift 2 ;;
      -d) RCLONE_ADDRESS="$2"; LOCAL_RCLONE=0 ; shift 2 ;;
      -l) RCLONE_CONFIG_PATH="$2"     ; shift 2 ;;
      -s) SNAPSHOT_NAME="$2"          ; shift 2 ;;
      -c) RESTORE_COMMAND="$2"        ; shift 2 ;;
      -f) FIRST_SNAPSHOT="$2"         ; shift 2 ;;
    # -- means the end of the arguments; drop this, and break out of the while loop
      --) shift; break ;;
    # If invalid options were passed, then getopt should have reported an error,
    # which we checked as VALID_ARGUMENTS when getopt was called...
      *) echo "Unexpected option: $1"
	 usage ;;
  esac
done

if [ $# -ne 2 ]; then
    usage
fi

ACTION=$1
export DATASET_NAME=$2
export WORKDIR=/var/run/zfs2rclone/${DATASET_NAME/@/\/}

export MAX_ARCHIVE_SIZE=1.9G

export LOCAL_LASTSNAPFILE=$WORKDIR/lastsnap
export REMOTE_LASTSNAPFILE="$REMOTE/$DATASET_NAME/lastsnap"

export TOP_PID=$$

case $ACTION in
    backup) prepare_backup_environment
	    backup_snapshot
	    cleanup
	    ;;
    restore) get_chain
	     for SNAPSHOT in $SNAPSHOTS; do
		 echo "Restoring $SNAPSHOT"
		 restore_backup $SNAPSHOT
	     done
	     ;;
    *) echo "Unexpected action: $1"
       usage ;;
esac


