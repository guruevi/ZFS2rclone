#!/bin/bash
NAME=$1
SCRIPTPATH=/mnt/Backup/ZFS2rclone
DESTPATH=/mnt/Backup/tmp
DESTVOL=Backup/tmp
MBUFFERPATH=/usr/local/bin/mbuffer

if [[ -z $NAME ]]; then
   echo "No ZFS Volume specified"
   exit 1
fi

# TODO: Perhaps we should save/query LASTSNAP on the remote?
mkdir -p ${DESTPATH}/${NAME}
touch ${DESTPATH}/${NAME}/lastsnap
LASTSNAP=`cat ${DESTPATH}/${NAME}/lastsnap 2>/dev/null`

TAPESIZE="16G" #Set this to the smaller number of what your system can handle and your destination allows
NUM_TAPES=256

zfs list -Hpr $NAME > $DESTPATH/$NAME/volume_list
zfs list -Hpr -t snapshot -d 1 $NAME > $DESTPATH/$NAME/snapshot_list
CURRENTSNAP=`cat ${DESTPATH}/${NAME}/snapshot_list | tail -n 1 | awk -F"[@\t]" '{ print $2 }'`

# Find out if we ran this before
if [[ ! -z $LASTSNAP ]]; then
  echo Last snapshot: $LASTSNAP
  INCREMENT="-i $LASTSNAP"
  if [[ $CURRENTSNAP = $LASTSNAP ]]; then
     echo "Snapshot is the same as the last backup"
     exit 1
  fi
else
  INCREMENT=""
  # Pick the last snapshot
fi
echo Current snapshot: $CURRENTSNAP

#TODO: IF Remote $SNAPSHOT already exist, most likely that's a previous failure. Move or delete that remote snapshot and rewrite it from scratch

MOVE_CMD="$SCRIPTPATH/move_script.sh $NAME $CURRENTSNAP $DESTPATH $NUM_TAPES" 
SEND_CMD="$SCRIPTPATH/send_script.sh $DESTPATH"
set -e

echo $DESTPATH/$NAME/$CURRENTSNAP
mkdir -p $DESTPATH/$NAME/$CURRENTSNAP
zfs send $INCREMENT $NAME@$CURRENTSNAP | $MBUFFERPATH -o $DESTPATH/$NAME/tapedev -D $TAPESIZE -A "$MOVE_CMD && $SEND_CMD"
$MOVE_CMD
$SEND_CMD 1
echo $CURRENTSNAP > $DESTPATH/$NAME/lastsnap
rclone copy --ignore-checksum $DESTPATH/$NAME/lastsnap RCBI-S3DG:/rcbi/$NAME/
rm $DESTPATH/$NAME/tapedev
