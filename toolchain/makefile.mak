SRC = src
BIN = bin
IVERI = iverilog
VERISIM = vvp
WAVE = gtkwave
WAVESPATH = waves

VERIFLAGS = -g2012 -Isrc
SIMFLAGS = 
WAVEFLAGS =

CWD = $(CURDIR)
makefile_dir:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

##### Compilation rules and objects: #####
#__GENMAKE__
BINS = $(BIN)/instruction_memory.o \
	$(BIN)/legv8.o \
	$(BIN)/microcode.o \
	$(BIN)/stage1_fetch.o \
	$(BIN)/stage2_decode.o \
	$(BIN)/stage3_execute.o \
	$(BIN)/stage4_memory_access.o \
	$(BIN)/stage5_writeback.o \
	$(BIN)/top.o 

$(BIN)/instruction_memory.o: $(SRC)/instruction_memory.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/legv8.o: $(SRC)/legv8.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/microcode.o: $(SRC)/microcode.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/stage1_fetch.o: $(SRC)/stage1_fetch.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/stage2_decode.o: $(SRC)/stage2_decode.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/stage3_execute.o: $(SRC)/stage3_execute.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/stage4_memory_access.o: $(SRC)/stage4_memory_access.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/stage5_writeback.o: $(SRC)/stage5_writeback.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

$(BIN)/top.o: $(SRC)/top.sv
	$(IVERI) -o $@ $(VERIFLAGS) $^

#__GENMAKE_END__

##### Main rules:
# Compile:
all: $(BINS)
	@printf "Finished!\n"

# Simulate:
%:
	@cd $(WAVESPATH) && $(VERISIM) $(CWD)/$(BIN)/$(basename $@).o
	
# GTKWave:
w%:
	$(WAVE) $(WAVESPATH)/$(basename $(@:w%=%)).vcd

clean:
	$(RM) $(BIN)/*

clean_waves:
	$(RM) $(WAVESPATH)/*