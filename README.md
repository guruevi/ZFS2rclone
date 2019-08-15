# ZFS2rclone
This is a collection of backup and restore scripts to store ZFS streams into an rclone-compatible repository (eg. Box.com)

It allows for splitting a ZFS stream into multiple parts that can be individually uploaded. Eg. if you have Box.com or Amazon S3, it is sometimes only allowed or effective to upload small portions (eg. 4GB). A ZFS stream of several TB's doesn't work very well in that regard. You could do a file-based transfer but there are various problems with that, first of all, it's slow and consumes lots of IOPS especially if you have lots of small files and it doesn't work if you have files that are larger than the upload limit.

How it works:
It simply calls ZFS send into mbuffer, which halts the stream when the maximum file size has been met. It then calls a helper script to rclone the file up to the online repository, truncates the file back to zero and starts over.

You can thus stream and perhaps even replicate a server using any Cloud Storage platform rclone supports. This is only effective as long as your bandwidth can keep up with the changes on the disk, you should play with the number of transfers and buffer sizes for rclone as they can impact your upload speed immensely.

TODO:
Write a helper script to pull down the data and re-assemble it. It works when I do it manually. Hint: rclone cat
