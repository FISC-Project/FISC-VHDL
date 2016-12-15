MODELSIM_PATH = C:\modeltech_6.5
MODELSIM_EXE_PATH = $(MODELSIM_PATH)/win32
FLI_LIB_PATH = $(MODELSIM_EXE_PATH)/mtipli.dll
VCOM = $(MODELSIM_EXE_PATH)/vcom
VDEL = $(MODELSIM_EXE_PATH)/vdel
VLIB = $(MODELSIM_EXE_PATH)/vlib
VMAP = $(MODELSIM_EXE_PATH)/vmap
VSIM = $(MODELSIM_EXE_PATH)/vsim
VSIMCOMMANDS = vcd file top.vcd; vcd add -r /*; run 100 ns; quit -f

BIN = bin
OBJ = obj
WAVE = gtkwave
WAVESPATH = waves
LIBPATH = lib
FLASM = toolchain/Windows/Tools/flasm
CFLAGS = -I -g -O2 -Wall -ansi -fms-extensions -std=c99 -pedantic -m32 -freg-struct-return -I$(MODELSIM_PATH)/include

# Virtual Machine's object files:
VMOBJS = $(OBJ)/test.o

BOOTLOADER:
	@printf "> Compiling Bootloader: "
	$(FLASM) ./src/boot/bootloader.fc -o $(BIN)/bootloader.bin -a

##### Compilation rules and objects: #####
#__GENMAKE__
BINS = $(OBJ)/test.o \
	$(OBJ)/foo.o 

$(OBJ)/test.o: ./src/machine/test.c
	@printf "> Compiling C file 'src/machine/test.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/foo.o: ./src/userapps/foo.c
	@printf "> Compiling C file 'src/userapps/foo.c': "
	gcc $(CFLAGS) -c $< -o $@

#__GENMAKE_END__

##### Main rules:

all: BOOTLOADER $(BINS)
	@printf "\n> Linking the Virtual Machine's object files into a shared library: "
	gcc -shared -Wl,-Bsymbolic -Wl,-export-all-symbols -std=c99 -m32 -o $(BIN)/libvm.dll $(VMOBJS) $(FLI_LIB_PATH)

	@printf "\n> Compiling VHDL code: "
	$(VDEL) -all
	$(VLIB) work
	$(VMAP) work work
	$(VCOM) -2008 rtl/test.vhd
	$(VCOM) -2008 rtl/defines.vhd
	$(VCOM) -2008 rtl/alu.vhd
	$(VCOM) -2008 rtl/dram_controller_sim.vhd
	$(VCOM) -2008 rtl/flags.vhd
	$(VCOM) -2008 rtl/memory_handler.vhd
	$(VCOM) -2008 rtl/microcode.vhd
	$(VCOM) -2008 rtl/registers.vhd
	$(VCOM) -2008 rtl/stage1_fetch.vhd
	$(VCOM) -2008 rtl/stage2_decode.vhd
	$(VCOM) -2008 rtl/stage3_execute.vhd
	$(VCOM) -2008 rtl/stage4_memory_access.vhd
	$(VCOM) -2008 rtl/stage5_writeback.vhd
	$(VCOM) -2008 rtl/fisc.vhd
	$(VCOM) -2008 rtl/top.vhd
	
	@$(RM) modelsim.ini
	@printf "\n>> DONE COMPILING <<"

# Simulate:
%:
	@printf "\n>> Simulating Top Module and producing GTKWave VCD file <<\n"
	@$(VSIM) -c -do "$(VSIMCOMMANDS)" top
	@printf "\n>> END OF SIMULATION <<\n"
	@mv top.vcd $(WAVESPATH)
	$(RM) transcript
	$(RM) vsim.wlf
	
# GTKWave:
w%:
	@printf "\n>> Displaying signals with GTKWave <<\n"
	$(WAVE) $(WAVESPATH)/top.vcd

clean:
	@printf "\n>> Cleaning built files <<\n"
	$(RM) $(BIN)/*
	$(RM) $(OBJ)/*
	$(RM) transcript
	$(RM) modelsim.ini
	$(RM) vsim.wlf

clean_waves:
	@printf "\n>> Cleaning wave (VCD) files <<\n"
	$(RM) $(WAVESPATH)/*