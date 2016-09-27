#!/bin/bash
cd `dirname $0`

if [ -z "$1" ]
then
	printf "ERROR: No argument provided. Argument must be the name of a VCD file.\n"
else
	cd ../..
	
	make -f toolchain/makefile.mak w$1
fi