#!/bin/bash

set -x

FILEPATH=$1
FILENAME=$2
REMOTE=$3

jobid=$(rclone rc sync/move --json '{"_async": true, "_filter": {"IncludeRule": ["'$FILENAME'"]}, "srcFs": "'$FILEPATH'", "dstFs": "'$REMOTE'"}' | jq .jobid)

done="false"
while [ $done == "false" ]; do
  done=$(rclone rc job/status jobid=$jobid | jq .finished)
  percent=$(rclone rc core/stats group=job/$jobid | jq '.transferring[0].percentage' )
  if [ "$percent" != "null" ]; then
    echo "$FILENAME ... $percent%"
  fi
  sleep 1
done

success=$(rclone rc job/status jobid=$jobid | jq .success)
if [ $success == "true" ]; then
    transfers=$(rclone rc core/stats group=job/$jobid | jq '.transfers' )
    if [ $transfers == 0 ]; then
	echo "$FILENAME transfer tasks reports OK, but no files got sent. Error."
	exit 1
    fi
    
    echo "$FILENAME done"
    exit 0
fi

error=$(rclone rc job/status jobid=$jobid | jq .error)
echo "an error occured for $FILENAME ($error)"
exit 1
