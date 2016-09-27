#!/bin/bash
cd `dirname $0`
clear

cd ../..

printf "***** Building Makefile... *****\n\n"
make -f toolchain/makefile.mak all

printf "\n***** Done *****\n\n"
