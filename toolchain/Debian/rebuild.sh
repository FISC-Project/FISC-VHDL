#!/bin/bash
cd `dirname $0`
clear

cd ../..

sh toolchain/Debian/clean.sh && python toolchain/genmake.pyc && sh toolchain/Debian/build.sh