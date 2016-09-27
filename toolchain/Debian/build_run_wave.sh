#!/bin/bash
cd `dirname $0`
call build.bat && call toolchain/Windows/simulate.bat $1 && call toolchain/Windows/wavegen.bat $2 