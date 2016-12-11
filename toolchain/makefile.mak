BIN = bin
OBJ = obj
WAVE = gtkwave
WAVESPATH = waves
LIBPATH = lib
FLASM = toolchain/Windows/Tools/flasm
VCOM = vcom
VSIMCOMMANDS = vcd file top.vcd; vcd add -r /*; run 10ns; quit -f

BOOTLOADER:
	@printf "> Compiling Bootloader Assembly code: "
	$(FLASM) ./src/bootloader.fc -o $(BIN)/bootloader.bin -a

##### Compilation rules and objects: #####
#__GENMAKE__
BINS = $(OBJ)/foo.o 

$(OBJ)/foo.o: ./src/foo.c
	@printf "1- Compiling C file 'src/foo.c': "
	gcc -c $< -o $@

#__GENMAKE_END__

##### Main rules:

all: BOOTLOADER $(BINS) $(HDLS)
	@printf "\n> Compiling VHDL code: "
	$(VCOM) -2008 rtl\alu.vhd
	$(VCOM) -2008 rtl\dram_controller_sim.vhd
	$(VCOM) -2008 rtl\defines.vhd
	$(VCOM) -2008 rtl\flags.vhd
	$(VCOM) -2008 rtl\memory_handler.vhd
	$(VCOM) -2008 rtl\microcode.vhd
	$(VCOM) -2008 rtl\registers.vhd
	$(VCOM) -2008 rtl\stage1_fetch.vhd
	$(VCOM) -2008 rtl\stage2_decode.vhd
	$(VCOM) -2008 rtl\stage3_execute.vhd
	$(VCOM) -2008 rtl\stage4_memory_access.vhd
	$(VCOM) -2008 rtl\stage5_writeback.vhd
	$(VCOM) -2008 rtl\fisc.vhd
	$(VCOM) -2008 rtl\top.vhd
	@#@$(MAKE) -f toolchain\vhdl_make.mak work/_lib.qdb
	@printf "\n>> DONE COMPILING <<"

# Simulate:
%:
	@printf "\n>> Simulating Top Module and producing GTKWave VCD file <<\n"
	@vsim -c -do "$(VSIMCOMMANDS)" top
	@printf "\n>> END OF SIMULATION <<\n"
	@mv top.vcd $(WAVESPATH)
	$(RM) transcript
	
# GTKWave:
w%:
	@printf "\n>> Displaying signals with GTKWave <<\n"
	$(WAVE) $(WAVESPATH)/top.vcd

clean:
	@printf "\n>> Cleaning built files <<\n"
	$(RM) $(BIN)/*
	$(RM) $(OBJ)/*
	$(RM) transcript

clean_waves:
	@printf "\n>> Cleaning wave (VCD) files <<\n"
	$(RM) $(WAVESPATH)/*