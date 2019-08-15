#!/bin/bash
VOLUMES=`zfs list -o name -H | grep -v freenas-boot | grep -v tmp`
for VOLUME in $VOLUMES; do
  ./backup_script.sh $VOLUME
done
