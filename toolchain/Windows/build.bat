@cd "%~dp0"
@echo off
cls

cd ..\..

printf "\n>> Building Makefile... <<\n"
make -f toolchain/makefile.mak all
printf "\n"

