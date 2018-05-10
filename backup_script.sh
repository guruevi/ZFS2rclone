#!/bin/bash
NAME=$1
CURRENTSNAP=$2
SCRIPTPATH=/mnt/Backup
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

function run_cmd() {
    exec $1
    rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi
    return $rc
}

MOVE_CMD="$SCRIPTPATH/move_script.sh $NAME $CURRENTSNAP"

mkdir -p $DESTPATH/$NAME/$SNAPSHOT
run_cmd zfs list -r $NAME > $DESTPATH/$NAME/volume_list
run_cmd zfs list -r -t snapshot $NAME > $DESTPATH/$NAME/snapshot_list
run_cmd zfs send $INCREMENT $NAME@$CURRENTSNAP | $MBUFFERPATH -o $DESTPATH/$NAME/tapedev -D $TAPESIZE -A "$MOVE_CMD"
run_cmd $MOVE_CMD
run_cmd $LASTSNAP > $DESTPATH/$NAME/lastsnap
run_cmd rclone copy $DESTPATH/$NAME/lastsnap URBox:/ZFS-SEND/$NAME/
run_cmd rm $DESTPATH/$NAME/tapedev
