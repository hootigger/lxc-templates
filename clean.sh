#!/bin/bash -x

git clean -nxdf
#（查看要删除的文件及目录，确认无误后再使用下面的命令进行删除）
git checkout . && git clean -xdf

