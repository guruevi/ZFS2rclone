#!/bin/bash
DEBUG="-vvvv --stats=30s"
DESTPATH="/mnt/Backup/tapes"

rclone $DEBUG --transfers=16 --exclude=tapedev --exclude=lastsnap --buffer-size=64M move $DESTPATH URBox:/ZFS-SEND/