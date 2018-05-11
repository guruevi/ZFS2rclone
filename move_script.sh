#!/bin/bash
NOW=`perl -MTime::HiRes=gettimeofday -MPOSIX=strftime -e '($s,$us) = gettimeofday(); printf "%d.%06d\n", $s, $us'`
NAME=$1
SNAPSHOT=$2

DEBUG="-vvvv --stats=30s"
DESTPATH="/mnt/Backup/tapes"

while [ `ls $DESTPATH/$NAME/$SNAPSHOT | wc -l` -gt 16 ]; do
    sleep 5
    echo "Waiting for free space"
done

mv $DESTPATH/$NAME/tapedev $DESTPATH/$NAME/$SNAPSHOT/$NOW || exit 1
touch $DESTPATH/$NAME/tapedev
