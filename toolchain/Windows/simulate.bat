@cd "%~dp0"
@echo off

IF [%1] == [] GOTO NoObj

cd ..\..

make -f toolchain/makefile.mak %1

@GOTO:EOF

:NoObj
printf "ERROR: No argument provided. Argument must be the name of an object file.\n"