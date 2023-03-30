#!/bin/bash

REMOTE=$1

VOLUMES=`zfs list -o name -H | grep home | head -1`
for VOLUME in $VOLUMES; do
  ./backup_script.sh $VOLUME $REMOTE
done
