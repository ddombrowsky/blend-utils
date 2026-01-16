#!/bin/sh

dstr=`date +%Y%m%d`
tarfile=backup/data-$dstr.tar

tar cvf $tarfile data*
xz -v $tarfile
chmod 600 $tarfile.xz
