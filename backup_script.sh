#!/bin/bash
NAME=$1
SCRIPTPATH=~/code/ZFS2rclone
DESTPATH=/tmp/backup
MBUFFERPATH=/usr/bin/mbuffer
TAPESIZE="4G" #Set this to the smaller number of what your system can handle and your destination allows
NUM_TAPES=5
REMOTE=$2

if [[ -z $NAME ]]; then
   echo "No ZFS Volume specified"
   exit 1
fi

# TODO: Perhaps we should save/query LASTSNAP on the remote?
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

MOVE_CMD="$SCRIPTPATH/move_script.sh $NAME $CURRENTSNAP $DESTPATH $NUM_TAPES" 
SEND_CMD="$SCRIPTPATH/send_script.sh $DESTPATH $REMOTE"

SNAP_SEND_CMD="zfs send $INCREMENT $NAME@$CURRENTSNAP"
COMPRESSS_CMD="xz -zc -"
MBUFFER_CMD="$MBUFFERPATH -o $DESTPATH/$NAME/tapedev -D $TAPESIZE -A \"$MOVE_CMD && $SEND_CMD\""

if [[ -z "$COMPRESS" ]]; then
    BACKUP_CMD="$SNAP_SEND_CMD | $MBUFFER_CMD"
else
    BACKUP_CMD="$SNAP_SEND_CMD | $COMPRESS_CMD | $MBUFFER_CMD"
fi
set -e

echo $DESTPATH/$NAME/$CURRENTSNAP
mkdir -p $DESTPATH/$NAME/$CURRENTSNAP
eval $BACKUP_CMD
$MOVE_CMD
$SEND_CMD 1
echo $CURRENTSNAP > $DESTPATH/$NAME/lastsnap
rclone copy --ignore-checksum $DESTPATH/$NAME/lastsnap $REMOTE
rm $DESTPATH/$NAME/tapedev
