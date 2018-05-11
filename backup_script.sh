#!/bin/bash
NAME=$1
CURRENTSNAP=$2
SCRIPTPATH=/mnt/Backup/ZFS2rclone
DESTPATH=/mnt/Backup/tapes
MBUFFERPATH=/mnt/Backup/jails_2/build/usr/local/bin/mbuffer

# TODO: Perhaps we should save/query this on the remote?
LASTSNAP=`cat ${DESTPATH}/${NAME}/lastsnap`
TAPESIZE="12G" #Set this to the smaller number of what your system can handle and your destination allows

#TODO: If currentsnap is not set, create one, or pick the last one if it isn't LASTSNAP

# Find out if we ran this before
if [[ ! -z $LASTSNAP ]]; then
  INCREMENT="-i $LASTSNAP"
else
  INCREMENT=""
fi

#TODO: IF Remote $SNAPSHOT already exist, most likely that's a previous failure. Move or delete that remote snapshot and rewrite it from scratch

#TODO: Every year, 


MOVE_CMD="$SCRIPTPATH/move_script.sh $NAME $CURRENTSNAP"

set -e

echo $DESTPATH/$NAME/$CURRENTSNAP
mkdir -p $DESTPATH/$NAME/$CURRENTSNAP
zfs list -r $NAME > $DESTPATH/$NAME/volume_list
zfs list -r -t snapshot $NAME > $DESTPATH/$NAME/snapshot_list
zfs send $INCREMENT $NAME@$CURRENTSNAP | $MBUFFERPATH -o $DESTPATH/$NAME/tapedev -D $TAPESIZE -A "$MOVE_CMD"
$MOVE_CMD
echo $CURRENTSNAP > $DESTPATH/$NAME/lastsnap
rclone copy $DESTPATH/$NAME/lastsnap URBox:/ZFS-SEND/$NAME/
rm $DESTPATH/$NAME/tapedev
