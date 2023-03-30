#!/bin/bash
NAME=$1
SCRIPTPATH=~/code/ZFS2rclone
DESTPATH=/tmp/backup
MAX_TEMP_FILES=10
MAX_ARCHIVE_SIZE=4

REMOTE=$2

if [[ -z $NAME ]]; then
   echo "No ZFS Volume specified"
   exit 1
fi

mkdir -p ${DESTPATH}/${NAME}
touch ${DESTPATH}/${NAME}/lastsnap
LASTSNAP=`cat ${DESTPATH}/${NAME}/lastsnap 2>/dev/null`


zfs list -Hpr -t snapshot -d 1 $NAME > $DESTPATH/$NAME/snapshot_list
CURRENTSNAP=`cat ${DESTPATH}/${NAME}/snapshot_list | tail -n 1 | awk -F"[@\t]" '{ print $2 }'`


if [[ -z $CURRENTSNAP ]]; then
  echo "There are no snapshots for this volume"
  exit 1
fi

# Find out if we ran this before
if [[ ! -z $LASTSNAP ]]; then
  echo Last snapshot: $LASTSNAP
  INCREMENT="-I $LASTSNAP"
  if [[ $CURRENTSNAP = $LASTSNAP ]]; then
     echo "Snapshot is the same as the last backup"
     exit 0
  fi
else
  INCREMENT=""
  # Pick the last snapshot
fi
echo Current snapshot: $CURRENTSNAP

#TODO: IF Remote $SNAPSHOT already exist, most likely that's a previous failure. Move or delete that remote snapshot and rewrite it from scratch

SNAP_SEND_CMD="zfs send $INCREMENT $NAME@$CURRENTSNAP"

export ARCHIVE_SAVE_PATH="$DESTPATH/$NAME/$CURRENTSNAP"
mkdir -p $ARCHIVE_SAVE_PATH
export REMOTE="$REMOTE/$NAME/$CURRENTSNAP"

save_archive_to_disk () {
    ret=9999999
    while [ $ret -gt 5 ]; do
	ret=$(ls $ARCHIVE_SAVE_PATH/*.par 2>/dev/null | wc -l)
	echo "waiting for more space" 1>&2
	sleep 5;
    done

    /bin/cat - > $ARCHIVE_SAVE_PATH/$1.par
    echo "$1.par saved to disk." 1>&2
    echo "$1.par"
}

export -f save_archive_to_disk

send_file_and_monitor () {
    FILEPATH=$1
    FILENAME=$2
    REMOTE=$3

    echo "Backing up $FILENAME"
    jobid=$(rclone rc sync/move --json '{"_async": true, "_filter": {"IncludeRule": ["'$FILENAME'"]}, "srcFs": "'$FILEPATH'", "dstFs": "'$REMOTE'"}' | jq .jobid)

    done="false"
    while [ $done == "false" ]; do
	done=$(rclone rc job/status jobid=$jobid | jq .finished)
	percent=$(rclone rc core/stats group=job/$jobid | jq '.transferring[0].percentage' )
	if [ "$percent" != "null" ]; then
	    echo "$FILENAME ... $percent%"
	fi
	sleep 1
    done

    success=$(rclone rc job/status jobid=$jobid | jq .success)
    if [ $success == "true" ]; then
	transfers=$(rclone rc core/stats group=job/$jobid | jq '.transfers' )
	if [ $transfers == 0 ]; then
	    echo "$FILENAME transfer tasks reports OK, but no files got sent. Error."
	    exit 1
	fi
	
	echo "$FILENAME done"
	exit 0
    fi

    error=$(rclone rc job/status jobid=$jobid | jq .error)
    echo "an error occured for $FILENAME ($error)"
    exit 1
}

export -f send_file_and_monitor

BACKUP_CMD="$SNAP_SEND_CMD | parallel --pipe --line-buffer -j3 --block 1.9G \"save_archive_to_disk {#}\" | parallel --lb -j3 \"send_file_and_monitor $ARCHIVE_SAVE_PATH {} $REMOTE\""

echo $BACKUP_CMD

eval $BACKUP_CMD
