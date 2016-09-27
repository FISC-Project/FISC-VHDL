@cd "%~dp0"
@echo off
cls

cd ..\..

printf "***** Building Makefile... *****\n\n"
make -f toolchain/makefile.mak all

printf "\n***** Done *****\n\n"
