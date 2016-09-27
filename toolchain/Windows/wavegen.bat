@cd "%~dp0"
@echo off

IF [%1] == [] GOTO NoVcd

cd ..\..

make -f toolchain/makefile.mak w%1

@GOTO:EOF

:NoVcd
printf "ERROR: No argument provided. Argument must be the name of a VCD file.\n"