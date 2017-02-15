MODELSIM_PATH = C:\MentorGraphics
MODELSIM_EXE_PATH = $(MODELSIM_PATH)/win32
FLI_LIB_PATH = $(MODELSIM_EXE_PATH)/mtipli.dll
VCOM = $(MODELSIM_EXE_PATH)/vcom
VDEL = $(MODELSIM_EXE_PATH)/vdel
VLIB = $(MODELSIM_EXE_PATH)/vlib
VMAP = $(MODELSIM_EXE_PATH)/vmap
VSIM = $(MODELSIM_EXE_PATH)/vsim
VSIMCOMMANDS = log -r top/*; run 60000ms; quit -sim

ifeq ($(OS),Windows_NT)
	SDL_LIB_PATH = -Llib/c_libs/SDL/i686-w64-mingw32/lib -lmingw32 -lSDL2 -lSDL2main
else
	SDL_LIB_PATH = -lSDL2 -lSDL2main
endif

BIN = bin
OBJ = obj
WAVE = toolchain/Windows/Tools/gtkwave/bin/gtkwave
WAVESPATH = waves
LIBPATH = lib
FLASM = toolchain/Windows/Tools/flasm
CFLAGS = -I. -Ilib/c_libs -Ilib/c_libs/include -Ilib/c_libs/SDL -I$(MODELSIM_PATH)/include -g -O2 -Wall -std=c99

# Virtual Machine's object files:
VMOBJS = $(OBJ)/memory.o $(OBJ)/mmu.o $(OBJ)/utils.o $(OBJ)/tinycthread.o $(OBJ)/io_controller.o $(OBJ)/vga.o $(OBJ)/timer.o

BOOTLOADER:
	@printf "> Compiling Bootloader: "
	$(FLASM) ./src/boot/bootloader.fc -o $(BIN)/bootloader.bin -a

##### Compilation rules and objects: #####
#__GENMAKE__
BINS = $(OBJ)/foo.o \
	$(OBJ)/io_controller.o \
	$(OBJ)/memory.o \
	$(OBJ)/mmu.o \
	$(OBJ)/utils.o \
	$(OBJ)/timer.o \
	$(OBJ)/vga.o \
	$(OBJ)/tinycthread.o 

$(OBJ)/foo.o: ./src/userapps/foo.c
	@printf "> Compiling C file 'src/userapps/foo.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/io_controller.o: ./src/vmachine/io_controller.c
	@printf "> Compiling C file 'src/vmachine/io_controller.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/memory.o: ./src/vmachine/memory.c
	@printf "> Compiling C file 'src/vmachine/memory.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/mmu.o: ./src/vmachine/mmu.c
	@printf "> Compiling C file 'src/vmachine/mmu.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/utils.o: ./src/vmachine/utils.c
	@printf "> Compiling C file 'src/vmachine/utils.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/timer.o: ./src/vmachine/iodevices/timer.c
	@printf "> Compiling C file 'src/vmachine/iodevices/timer.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/vga.o: ./src/vmachine/iodevices/vga.c
	@printf "> Compiling C file 'src/vmachine/iodevices/vga.c': "
	gcc $(CFLAGS) -c $< -o $@

$(OBJ)/tinycthread.o: ./src/vmachine/tinycthread/tinycthread.c
	@printf "> Compiling C file 'src/vmachine/tinycthread/tinycthread.c': "
	gcc $(CFLAGS) -c $< -o $@

#__GENMAKE_END__

##### Main rules:

all: BOOTLOADER $(BINS)
	@printf "> Linking the Virtual Machine's object files into a shared library: "
	gcc -shared -Wl,-Bsymbolic -Wl,-export-all-symbols -std=c99 -m32 -o $(BIN)/libvm.dll $(VMOBJS) $(FLI_LIB_PATH) $(SDL_LIB_PATH)

	@printf "\n> Compiling VHDL code: "
	
	$(VCOM) -2002 -quiet rtl/defines.vhd
	$(VCOM) -2002 -quiet rtl/memory.vhd
	$(VCOM) -2002 -quiet rtl/io_controller.vhd
	$(VCOM) -2002 -quiet rtl/alu.vhd
	$(VCOM) -2002 -quiet rtl/cpsr.vhd
	$(VCOM) -2002 -quiet rtl/microcode.vhd
	$(VCOM) -2002 -quiet rtl/registers.vhd
	$(VCOM) -2002 -quiet rtl/stage1_fetch.vhd
	$(VCOM) -2002 -quiet rtl/stage2_decode.vhd
	$(VCOM) -2002 -quiet rtl/stage3_execute.vhd
	$(VCOM) -2002 -quiet rtl/stage4_memory_access.vhd
	$(VCOM) -2002 -quiet rtl/stage5_writeback.vhd
	$(VCOM) -2002 -quiet rtl/fisc.vhd
	$(VCOM) -2002 -quiet rtl/top.vhd
	
	@$(RM) modelsim.ini
	@printf "\n>> DONE COMPILING <<"

# Simulate:
%:
	@printf "\n>> Simulating Top Module and producing GTKWave VCD file <<\n"
	@cp lib\c_libs\SDL\i686-w64-mingw32\bin\SDL2.dll .
	@$(VSIM) -c -do "$(VSIMCOMMANDS)" -wlf top.wlf top
	@printf "\n>> END OF SIMULATION <<\n"
	@wlf2vcd top.wlf -o top.vcd
	@mv top.wlf $(WAVESPATH)
	@mv top.vcd $(WAVESPATH)
	@$(RM) transcript
	@$(RM) SDL2.dll
	
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
	$(RM) SDL2.dll
	$(RM) wlf*
	$(RM) top.*
	$(RM) work/_lock

clean_waves:
	@printf "\n>> Cleaning wave (VCD) files <<\n"
	$(RM) $(WAVESPATH)/*