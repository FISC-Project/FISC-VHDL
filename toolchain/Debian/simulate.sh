#!/bin/bash
cd `dirname $0`

if [ -z "$1" ]
then
	printf "ERROR: No argument provided. Argument must be the name of an object file.\n"
else
	cd ../..

	make -f toolchain/makefile.mak $1
fi
