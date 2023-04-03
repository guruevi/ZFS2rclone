#!/bin/bash
NAME=$1
SCRIPTPATH=~/code/ZFS2rclone
DESTPATH=/tmp/backup
export MAX_TEMP_FILES=5
export MAX_ARCHIVE_SIZE=1.9G
export REMOTE=$2

LASTSNAPFILE=${DESTPATH}/${NAME}/lastsnap
export REMOTE_LASTSNAPFILE="$REMOTE/$NAME/lastsnap"



exit_if_error () {
    
    [ $1 -gt 0 ] && echo "Exiting... ($2)" >&2 && kill -s TERM $TOP_PID
}

copy_or_move_file () {
    SRC=$1
    DEST=$2
    ACTION=$3
    ERRORS_ARE_OK=${4:-""}
    
    SRC_FILENAME=$(basename $SRC)
    SRC_FS=$(dirname $SRC)
    
    echo "mkdir to $REMOTE" >&2
    json_response=$(rclone rc operations/mkdir --json '{"remote": "", "fs": "'$DEST'"}')
    exit_if_error $?
    echo "Backing up $FILENAME to $REMOTE" >&2
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
	
    echo "$FILENAME:backedup successfully"
}

export -f exit_if_error
export -f copy_or_move_file

split_backup_monitor_archive () {
    trap "echo bye; exit 1" TERM

    FILENAME=$(printf "%08d"  $1).par
    export TOP_PID=$$

    /bin/cat -  > $ARCHIVE_SAVE_PATH/$FILENAME
    echo "$FILENAME:saved to disk"

    copy_or_move_file $ARCHIVE_SAVE_PATH/$FILENAME $REMOTE "movefile"
    exit $?
}

export -f split_backup_monitor_archive



if [[ -z $NAME ]]; then
   echo "No ZFS Volume specified" >&2
   exit 1
fi

rclone rcd --rc-no-auth --config /home/nodemo/.config/rclone/rclone.conf &
RCLONE_PID=$!


mkdir -p ${DESTPATH}/${NAME}
touch $LASTSNAPFILE
copy_or_move_file $REMOTE_LASTSNAPFILE $DESTPATH/$NAME "copyfile" "errors_are_ok"
cat $LASTSNAPFILE
LASTSNAP=$(cat ${DESTPATH}/${NAME}/lastsnap)

zfs list -Hpr -t snapshot -d 1 $NAME | grep daily > $DESTPATH/$NAME/snapshot_list
CURRENTSNAP=`cat ${DESTPATH}/${NAME}/snapshot_list | tail -n 1 | awk -F"[@\t]" '{ print $2 }'`


if [[ -z $CURRENTSNAP ]]; then
  echo "There are no snapshots for this volume" >&2
  exit 1
fi

# Find out if we ran this before
if [[ ! -z $LASTSNAP ]]; then
  echo Last snapshot: $LASTSNAP >&2
  INCREMENT="-I $LASTSNAP"
  if [[ $CURRENTSNAP = $LASTSNAP ]]; then
     echo "Snapshot is the same as the last backup" >&2
     exit 0
  fi
else
  INCREMENT=""
  # Pick the last snapshot
fi

echo Current snapshot: $CURRENTSNAP >&2

#TODO: IF Remote $SNAPSHOT already exist, most likely that's a previous failure. Move or delete that remote snapshot and rewrite it from scratch
export ARCHIVE_SAVE_PATH="$DESTPATH/$NAME/$CURRENTSNAP"
mkdir -p $ARCHIVE_SAVE_PATH

export REMOTE="$REMOTE/$NAME/$CURRENTSNAP"




trap "echo bye; kill $RCLONE_PID exit 1" TERM

SNAP_SEND_CMD="zfs send -c $INCREMENT $NAME@$CURRENTSNAP"
BACKUP_CMD="$SNAP_SEND_CMD | parallel --halt now,fail=1 --pipe --line-buffer -j$MAX_TEMP_FILES --block 1.9G \"split_backup_monitor_archive {#}\""

eval $BACKUP_CMD
exit_if_error $?

echo $CURRENTSNAP > $LASTSNAPFILE
copy_or_move_file $LASTSNAPFILE $(dirname $REMOTE) "movefile"
