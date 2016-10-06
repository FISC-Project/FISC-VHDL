BIN = bin
OBJ = obj
ifeq ($(OS),Windows_NT)
	GHDL = toolchain/Windows/Tools/ghdl-0.33/bin/ghdl
else
	GHDL = ghdl
endif
WAVE = gtkwave
WAVESPATH = waves
WORKPATH = work
LIBPATH = lib

GHDLFLAGS = --workdir="$(PWD)$(WORKPATH)" -P"$(PWD)$(LIBPATH)" --std=02 --ieee=synopsys -fexplicit
SIMFLAGS = 
WAVEFLAGS =

CWD = $(CURDIR)
makefile_dir:=$(shell dirname \"$("realpath $(lastword $(MAKEFILE_LIST)))\")

# NOTE: We can only interface C files with GHDL through Linux:
ifneq ($(OS),Windows_NT)
##### Compilation rules and objects: #####
#__GENMAKE__
BINS = $(OBJ)/foo.o 

$(OBJ)/foo.o: ./src/foo.c
	@printf "2.1- Compiling C file 'src/foo.c': "
	gcc -c $< -o $@

#__GENMAKE_END__
endif

##### Main rules:
# Compile:
ELDESIGN:
	@printf "1- Importing source files and Elaborating Design: \n"
	$(GHDL) -i $(GHDLFLAGS) rtl/*.vhd*
	$(GHDL) -m $(GHDLFLAGS) top

all: ELDESIGN $(BINS)
	@printf "\n2- Elaborating Top Module: "
ifneq ($(OS),Windows_NT)
	$(GHDL) -e -Wl,$(BINS) $(GHDLFLAGS) top
else
	$(GHDL) -e $(GHDLFLAGS) top
	@printf "\n>> Finished! <<\n"
endif

# Simulate:
%:
	@printf "\n>> Simulating Top Module and producing GTKWave VCD file <<\n"
	$(GHDL) -r $(GHDLFLAGS) top --stop-time=100fs --vcd=top.vcd
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