#!/bin/bash
NAME=$1
SCRIPTPATH=~/code/ZFS2rclone
DESTPATH=/tmp/backup
export MAX_TEMP_FILES=5
export MAX_ARCHIVE_SIZE=1.9G

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

export ARCHIVE_SAVE_PATH="$DESTPATH/$NAME/$CURRENTSNAP"
mkdir -p $ARCHIVE_SAVE_PATH
export REMOTE="$REMOTE/$NAME/$CURRENTSNAP"

split_backup_monitor_archive () {
    FILENAME=$1.par
    
    /bin/cat -  > $ARCHIVE_SAVE_PATH/$FILENAME
    echo "$FILENAME saved to disk." 1>&2

    echo "Backing up $FILENAME"
    jobid=$(rclone rc sync/move --json '{"_async": true, "_filter": {"IncludeRule": ["'$FILENAME'"]}, "srcFs": "'$ARCHIVE_SAVE_PATH'", "dstFs": "'$REMOTE'"}' | jq .jobid)

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


export -f split_backup_monitor_archive
 
SNAP_SEND_CMD="zfs send -c $INCREMENT $NAME@$CURRENTSNAP"
BACKUP_CMD="$SNAP_SEND_CMD | parallel --pipe --line-buffer -j$MAX_TEMP_FILES --block 1.9G \"split_backup_monitor_archive {#}\""

echo $BACKUP_CMD

eval $BACKUP_CMD
