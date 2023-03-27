#!/bin/bash
DEBUG="-vvvv --stats=30s"
DESTPATH=$1
WAIT=$2
REMOTE=$3

COMMAND="rclone $DEBUG --ignore-checksum --fast-list --s3-upload-concurrency=8 --s3-chunk-size=64M --update --use-server-modtime --low-level-retries=100 --exclude=tapedev --exclude=lastsnap --buffer-size=64M move $DESTPATH $REMOTE" 

if pgrep -x rclone; then
  echo "rclone running"
  if [[ -z $WAIT ]]; then
    exit 0
  else
    while pgrep -x rclone; do
       sleep 5
    done
  fi 
fi

if [[ ! -z $WAIT ]]; then
  $COMMAND
else 
  $COMMAND &
fi
