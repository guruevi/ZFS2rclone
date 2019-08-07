#!/bin/bash
# $NAME $CURRENTSNAP $DESTPATH $NUM_TAPES
NOW=`perl -MTime::HiRes=gettimeofday -MPOSIX=strftime -e '($s,$us) = gettimeofday(); printf "%d.%06d\n", $s, $us'`
NAME=$1
SNAPSHOT=$2
DESTPATH=$3
NUM_TAPES=$4

while [ `ls $DESTPATH/$NAME/$SNAPSHOT | wc -l` -gt $NUM_TAPES ]; do
    sleep 5
    echo "Waiting for free space"
done

mv $DESTPATH/$NAME/tapedev $DESTPATH/$NAME/$SNAPSHOT/$NOW || exit 1
touch $DESTPATH/$NAME/tapedev
