#!/bin/bash
NOW=`perl -MTime::HiRes=gettimeofday -MPOSIX=strftime -e '($s,$us) = gettimeofday(); printf "%d.%06d\n", $s, $us'`
NAME=$1
SNAPSHOT=$2

DEBUG="-vvvv --stats=30s"
DESTPATH="/mnt/Backup/tapes"

rclone $DEBUG --transfers=8 --buffer-size=64M copyto $DESTPATH/$NAME/tapedev URBox:/ZFS-SEND/$NAME/$SNAPSHOT/$NOW && truncate -s 0 $DESTPATH/$NAME/tapedev
