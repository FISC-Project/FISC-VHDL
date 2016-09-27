@cd "%~dp0"
@echo off
cls

call clean.bat && python toolchain/genmake.pyc && call toolchain/Windows/build.bat