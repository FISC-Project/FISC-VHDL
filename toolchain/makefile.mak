MODELSIM_PATH = C:\modeltech_6.5
MODELSIM_EXE_PATH = $(MODELSIM_PATH)/win32
FLI_LIB_PATH = $(MODELSIM_EXE_PATH)/mtipli.dll
VCOM = $(MODELSIM_EXE_PATH)/vcom
VDEL = $(MODELSIM_EXE_PATH)/vdel
VLIB = $(MODELSIM_EXE_PATH)/vlib
VMAP = $(MODELSIM_EXE_PATH)/vmap
VSIM = $(MODELSIM_EXE_PATH)/vsim
VSIMCOMMANDS = log -r top/*; run 100 ns; quit -f

BIN = bin
OBJ = obj
WAVE = toolchain/Windows/Tools/gtkwave/bin/gtkwave
WAVESPATH = waves
LIBPATH = lib
FLASM = toolchain/Windows/Tools/flasm
CFLAGS = -I -g -O2 -Wall -ansi -fms-extensions -std=c99 -pedantic -m32 -freg-struct-return -I$(MODELSIM_PATH)/include

# Virtual Machine's object files:
VMOBJS = $(OBJ)/memory.o $(OBJ)/virtual_memory.o $(OBJ)/io_controller.o $(OBJ)/utils.o

BOOTLOADER:
	@printf "> Compiling Bootloader: "
	$(FLASM) ./src/boot/bootloader.fc -o $(BIN)/bootloader.bin -a

##### Compilation rules and objects: #####
#__GENMAKE__
BINS = $(OBJ)/io_controller.o \
	$(OBJ)/memory.o \
	$(OBJ)/utils.o \
	$(OBJ)/virtual_memory.o \
	$(OBJ)/foo.o 

$(OBJ)/io_controller.o: ./src/machine/io_controller.c
	@printf "> Compiling C file 'src/machine/io_controller.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/memory.o: ./src/machine/memory.c
	@printf "> Compiling C file 'src/machine/memory.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/utils.o: ./src/machine/utils.c
	@printf "> Compiling C file 'src/machine/utils.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/virtual_memory.o: ./src/machine/virtual_memory.c
	@printf "> Compiling C file 'src/machine/virtual_memory.c': "
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
	
	$(VCOM) -2002 -O5 -quiet rtl/defines.vhd
	$(VCOM) -2002 -O5 -quiet rtl/memory.vhd
	$(VCOM) -2002 -O5 -quiet rtl/alu.vhd
	$(VCOM) -2002 -O5 -quiet rtl/flags.vhd
	$(VCOM) -2002 -O5 -quiet rtl/microcode.vhd
	$(VCOM) -2002 -O5 -quiet rtl/registers.vhd
	$(VCOM) -2002 -O5 -quiet rtl/stage1_fetch.vhd
	$(VCOM) -2002 -O5 -quiet rtl/stage2_decode.vhd
	$(VCOM) -2002 -O5 -quiet rtl/stage3_execute.vhd
	$(VCOM) -2002 -O5 -quiet rtl/stage4_memory_access.vhd
	$(VCOM) -2002 -O5 -quiet rtl/stage5_writeback.vhd
	$(VCOM) -2002 -O5 -quiet rtl/fisc.vhd
	$(VCOM) -2002 -O5 -quiet rtl/top.vhd
	
	@$(RM) modelsim.ini
	@printf "\n>> DONE COMPILING <<"

# Simulate:
%:
	@printf "\n>> Simulating Top Module and producing GTKWave VCD file <<\n"
	@$(VSIM) -c -do "$(VSIMCOMMANDS)" -wlf top.wlf top
	@printf "\n>> END OF SIMULATION <<\n"
	@wlf2vcd top.wlf -o top.vcd
	@mv top.wlf $(WAVESPATH)
	@mv top.vcd $(WAVESPATH)
	@$(RM) transcript
	
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

clean_waves:
	@printf "\n>> Cleaning wave (VCD) files <<\n"
	$(RM) $(WAVESPATH)/*