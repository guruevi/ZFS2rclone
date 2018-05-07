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

#TODO: IF Remote $SNAPSHOT already exist, most likely that's a previous failure. Move or delete that remote snapshot and rewrite it from scratch?

SEND_CMD="$SCRIPTPATH/send_script.sh $NAME $CURRENTSNAP"

mkdir -p $DESTPATH/$NAME
zfs send $INCREMENT $NAME@$CURRENTSNAP | \
    $MBUFFERPATH -o $DESTPATH/$NAME/tapedev -D $TAPESIZE -A "$SEND_CMD" && \
    $SEND_CMD && echo $LASTSNAP > $DESTPATH/$NAME/lastsnap && rm $DESTPATH/$NAME/tapedev
