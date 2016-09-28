SRC = src
BIN = bin
ifeq ($(OS),Windows_NT)
	GHDL = toolchain/Windows/Tools/ghdl-0.33/bin/ghdl
else
	GHDL = ghdl
endif
WAVE = gtkwave
WAVESPATH = waves
WORKPATH = work

GHDLFLAGS = --workdir="$(PWD)$(WORKPATH)" --std=02 --ieee=synopsys
SIMFLAGS = 
WAVEFLAGS =

CWD = $(CURDIR)
makefile_dir:=$(shell dirname \"$("realpath $(lastword $(MAKEFILE_LIST)))\")

##### Compilation rules and objects: #####
#__GENMAKE__
BINS = #__GENMAKE_END__

##### Main rules:
# Compile:
ELDESIGN:
	@printf "1- Importing source files and Elaborating Design: \n"
	$(GHDL) -i --workdir="$(PWD)$(WORKPATH)" $(GHDLFLAGS) src/*.vhdl
	$(GHDL) -m --workdir="$(PWD)$(WORKPATH)" top

all: ELDESIGN $(BINS)
	@printf "\n2- Elaborating Top Module: "
	$(GHDL) -e $(GHDLFLAGS) top
	@printf "\n>> Finished! <<\n"

# Simulate:
%:
	@printf "\n>> Simulating Top Module and producing GTKWave VCD file <<\n"
	$(GHDL) -r --workdir=$(WORKPATH) top --vcd=top.vcd
	@printf ">> END OF SIMULATION <<\n"
	@mv top.vcd $(WAVESPATH)
	
# GTKWave:
w%:
	@printf "\n>> Displaying signals with GTKWave <<\n"
	$(WAVE) $(WAVESPATH)/top.vcd

clean:
	@printf "\n>> Cleaning built files <<\n"
	$(RM) $(BIN)/*
	$(RM) $(WORKPATH)/*

clean_waves:
	@printf "\n>> Cleaning wave (VCD) files <<\n"
	$(RM) $(WAVESPATH)/*