#!/bin/bash -x
SHELL_DIR=$(cd "$(dirname "$0")";pwd)
OUT=$SHELL_DIR/.build/alpine
mkdir -p $OUT && rm -rf $OUT/* && mkdir -p $OUT/rootfs
$SHELL_DIR/templates/lxc-alpine --name alpine --path $OUT $@
if [[ !  $? -eq 0 ]]; then
	echo "错误!"
	exit -1
else
	tar -zcf alpine-3.16-custom-base.tar.gz -C $OUT/rootfs $(dirname $0) 
fi

