@cd "%~dp0"
@echo off
cls

call clean.bat && printf "\n>> Updating Project Makefile <<\n" && python toolchain/genmake.pyc && call toolchain/Windows/build.bat && call toolchain/Windows/simulate.bat %1 && call toolchain/Windows/wavegen.bat %2 