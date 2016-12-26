/*
 * memory.c
 *
 *  Created on: 14/12/2016
 *      Author: Miguel
 */
#include <mti.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include "defines.h"
#include "signal_conv.h"
#include "virtual_memory.h"
#include "address_space.h"
#include "io_controller.h"

typedef struct {
	mtiSignalIdT clk;
	mtiSignalIdT en;
	mtiSignalIdT wr;
	mtiSignalIdT rd;
	mtiDriverIdT ready;
	mtiSignalIdT address1;
	mtiSignalIdT address2;
	mtiSignalIdT data_in;
	mtiDriverIdT data_out1;
	mtiDriverIdT data_out2;
	mtiSignalIdT access_width;
} memory_t;

uint8_t memory_contents[MEMORY_DEPTH]; /* The actual Main Memory */

char read_memory_ret[MAX_INTEGER_SIZE+1];

char write_memory(uint32_t address, uint64_t data, uint8_t access_width) {
	if(address >= MEMORY_DEPTH) return 0;
	switch(access_width) {
		case SZ_8:
			memory_contents[address]            = (uint8_t)data;
			break;
		case SZ_16:
			memory_contents[address]   = (uint8_t)((data & 0xFF00) >> 8);
			memory_contents[address+1] = (uint8_t)  data & 0xFF;
			break;
		case SZ_32:
			memory_contents[address]   = (uint8_t)((data & 0xFF000000) >> 24);
			memory_contents[address+1] = (uint8_t)((data & 0xFF0000)   >> 16);
			memory_contents[address+2] = (uint8_t)((data & 0xFF00)     >> 8);
			memory_contents[address+3] = (uint8_t)  data & 0xFF;
			break;
		case SZ_64:
			memory_contents[address]   = (uint8_t)((data & 0xFF00000000000000) >> 56);
			memory_contents[address+1] = (uint8_t)((data & 0xFF000000000000)   >> 48);
			memory_contents[address+2] = (uint8_t)((data & 0xFF0000000000)     >> 40);
			memory_contents[address+3] = (uint8_t)((data & 0xFF00000000)       >> 32);
			memory_contents[address+4] = (uint8_t)((data & 0xFF000000)         >> 24);
			memory_contents[address+5] = (uint8_t)((data & 0xFF0000)           >> 16);
			memory_contents[address+6] = (uint8_t)((data & 0xFF00)             >> 8);
			memory_contents[address+7] = (uint8_t)  data & 0xFF;
			break;
		default: return 0;
	}
	return 1;
}

char * read_memory(uint32_t address, uint8_t access_width) {
	/* Zero out the whole memory data out buffer */
	for(int i = 0; i < MAX_INTEGER_SIZE; i++)
		read_memory_ret[i] = 2; /* this is a 0 when it's a std_logic variable */
	read_memory_ret[MAX_INTEGER_SIZE] = '\0'; /* End of the Buffer */

	switch(access_width) {
		case SZ_8:  if(address   >= MEMORY_DEPTH) return read_memory_ret; break;
		case SZ_16: if(address+1 >= MEMORY_DEPTH) return read_memory_ret; break;
		case SZ_32: if(address+3 >= MEMORY_DEPTH) return read_memory_ret; break;
		case SZ_64: if(address+7 >= MEMORY_DEPTH) return read_memory_ret; break;
		default: return read_memory_ret;
	}

	/* Fill the buffer: */
	switch(access_width) {
		case SZ_8: {
			char * val = int_to_sigv(memory_contents[address], 8);
			memcpy(read_memory_ret + (7*8), val, 8);
			break;
		}
		case SZ_16: {
			char * val = int_to_sigv(memory_contents[address+1], 8);
			memcpy(read_memory_ret + (7*8), val, 8);
			val = int_to_sigv(memory_contents[address], 8);
			memcpy(read_memory_ret + (6*8), val, 8);
			break;
		}
		case SZ_32: {
			char * val = int_to_sigv(memory_contents[ALIGN32(address)+3], 8);
			memcpy(read_memory_ret + (7*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN32(address)+2], 8);
			memcpy(read_memory_ret + (6*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN32(address)+1], 8);
			memcpy(read_memory_ret + (5*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN32(address)], 8);
			memcpy(read_memory_ret + (4*8), val, 8);
			break;
		}
		case SZ_64: {
			char * val = int_to_sigv(memory_contents[ALIGN64(address)+7], 8);
			memcpy(read_memory_ret + (7*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN64(address)+6], 8);
			memcpy(read_memory_ret + (6*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN64(address)+5], 8);
			memcpy(read_memory_ret + (5*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN64(address)+4], 8);
			memcpy(read_memory_ret + (4*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN64(address)+3], 8);
			memcpy(read_memory_ret + (3*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN64(address)+2], 8);
			memcpy(read_memory_ret + (2*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN64(address)+1], 8);
			memcpy(read_memory_ret + (1*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN64(address)], 8);
			memcpy(read_memory_ret + (0*8), val, 8);
			break;
		}
		default: break;
	}

	return read_memory_ret;
}

char load_memory(void) {
	printf("Loading Bootloader '%s' ...\n", BOOTLOADER_FILE);

	FILE * fptr = fopen(BOOTLOADER_FILE, "rb");
	if(fptr == 0) {
		printf("ERROR: Couldn't open file '%s'!\n", BOOTLOADER_FILE);
		return 0;
	}

	char buffer[10] = {0};
	uint32_t address = 0;
	while(fgets((char*)buffer, sizeof(buffer), fptr))
		write_memory(address++, (uint8_t)strtoul(buffer, 0, 2), SZ_8);
	fclose(fptr);
	printf("Size of bootloader: %d bytes\n", ALIGN32(address));
	return 1;
}

enum ADDR_SPACE_T address_decode(uint32_t address) {
	if(address >= IOSPACE && address < IOSPACE + (uint32_t)(IOSPACE_LEN)) return SPACE_IO;
	return SPACE_MMEM;
}

uint64_t address_align(uint32_t address, uint8_t access_width) {
	switch(access_width) {
		case SZ_8:  return address;
		case SZ_16: return ALIGN16(address);
		case SZ_32: return ALIGN32(address);
		case SZ_64: return ALIGN64(address);
		default:    return address;
	}
}

void fli_cleanup(void) {
	printf("\n> Closing up FLI C interface");
	io_controller_deinit();
	fflush(stdout);
	SDL_Quit();
}

void on_clock(void * param) {
	static uint64_t clock_ctr = 0;
	if(clock_ctr++ >= MODELSIM_EXECUTION_TIME) {
		fli_cleanup();
		mti_Quit();
		return;
	}

	memory_t * ip = (memory_t *) param;
	_Bool clk = sig_to_int(ip->clk);
	int en = sigv_to_int(ip->en);

	if(clk) {
		printf("\n> + ");

		if(en > 0) {
			printf("Accessing Memory | ", en);

			/*************************/
			/* Handle Memory Writes: */
			/*************************/
			int wr = sig_to_int(ip->wr);
			if(wr > 0) {
				uint8_t access_width = sigv_to_int(ip->access_width);
				uint32_t vaddress = address_align(sigv_to_int(ip->address2), access_width);
				uint32_t address = address_translate(vaddress);
				uint64_t data = sigv_to_int(ip->data_in);
				enum ADDR_SPACE_T target = address_decode(address);
				char success = 0;

				if(target == SPACE_MMEM) {
					printf("WR (v@0x%x p@0x%x <%d>) = 0x%" PRIx64 " ", vaddress, address, access_width, data);
					success = write_memory(address, data, access_width);
				} else if(target == SPACE_IO) {
					printf("IO WR (v@0x%x p@0x%x <%d>) = 0x%" PRIx64 " ", vaddress, address, access_width, data);
					success = io_wr_dispatch(address, data, access_width);
				}

				if(!success)
					printf("ERROR: Could not write to address v@0x%x p@0x%x ", vaddress, address);
			}

			/******************************************************************/
			/* Handle Memory Reads for Channel 1 (used by the fetch stage 1): */
			/******************************************************************/
			char * rd = sigv_to_str(ip->rd, 0);
			if(rd[1] > 0) {
				uint32_t vaddress = sigv_to_int(ip->address1);
				uint32_t address = address_translate(vaddress); /* The PC is already 32 bit aligned */
				char * returned_data;
				char cpy[65];
				enum ADDR_SPACE_T target = address_decode(address);

				address  /= 4; /* Unalign address */
				vaddress /= 4; /* Unalign address */

				if(target == SPACE_MMEM) {
					returned_data = read_memory(address, SZ_32);
					strcpy(cpy, returned_data);
					for(int i = 0; i < MAX_INTEGER_SIZE; i++) cpy[i] = (cpy[i] + '0') - 2;
					uint64_t to_int = strtoull(cpy, 0, 2);

					printf("RD CH1 (v@0x%x p@0x%x <2>) = 0x%" PRIx64 " ", ALIGN32(vaddress), ALIGN32(address), to_int);
				} else if(target == SPACE_IO) {
					returned_data = io_rd_dispatch(address, SZ_32);
					strcpy(cpy, returned_data);
					for(int i = 0; i < MAX_INTEGER_SIZE; i++) cpy[i] = (cpy[i] + '0') - 2;
					uint64_t to_int = strtoull(cpy, 0, 2);

					printf("IO RD CH1 (v@0x%x p@0x%x <2>) = 0x%" PRIx64 " ", ALIGN32(vaddress), ALIGN32(address), to_int);
				}

				mti_ScheduleDriver(ip->data_out1, (long)returned_data, 1, MTI_INERTIAL);
			}

			/* The Memory has finished the transaction: */
			mti_ScheduleDriver(ip->ready, (long)int_to_sigv(3,2), 1, MTI_INERTIAL);
		}

		printf("\n");
		fflush(stdout);
	} else {
		if(en > 0) {
			/**************************************************************************/
			/* Handle Memory Reads for Channel 2 (used by the memory access stage 4): */
			/**************************************************************************/
			char * rd = sigv_to_str(ip->rd, 0);
			if(rd[0] > 0) {
				printf("\n> - Accessing Memory | ", en);
				uint8_t access_width = sigv_to_int(ip->access_width);
				uint32_t vaddress = address_align(sigv_to_int(ip->address2), access_width);
				uint32_t address = address_translate(vaddress);
				char * returned_data;
				char cpy[65];
				enum ADDR_SPACE_T target = address_decode(address);

				if(target == SPACE_MMEM) {
					returned_data = read_memory(address, access_width);
					strcpy(cpy, returned_data);
					for(int i = 0; i < MAX_INTEGER_SIZE; i++) cpy[i] = (cpy[i] + '0') - 2;
					uint64_t to_int = strtoull(cpy, 0, 2);

					printf("RD CH2 (v@0x%x p@0x%x <%d>) = 0x%" PRIx64 " ", vaddress, address, access_width, to_int);
				} else if(target == SPACE_IO) {
					returned_data = io_rd_dispatch(address, access_width);
					strcpy(cpy, returned_data);
					for(int i = 0; i < MAX_INTEGER_SIZE; i++) cpy[i] = (cpy[i] + '0') - 2;
					uint64_t to_int = strtoull(cpy, 0, 2);

					printf("IO RD CH2 (v@0x%x p@0x%x <%d>) = 0x%" PRIx64 " ", vaddress, address, access_width, to_int);
				}

				mti_ScheduleDriver(ip->data_out2, (long)returned_data, 0,    MTI_INERTIAL);
				mti_ScheduleDriver(ip->ready,     (long)int_to_sigv(3,2), 1, MTI_INERTIAL);

				printf("\n");
				fflush(stdout);
			}
		}
	}
}

void memory_init(
	mtiRegionIdT region,
	char * param,
	mtiInterfaceListT * generics,
	mtiInterfaceListT * ports
) {
	load_memory();

	if(SDL_Init(SDL_INIT_EVERYTHING) != 0)
		printf("\n> ERROR: Could not initialize SDL. (%s)\n", SDL_GetError());
	else
		io_controller_init();

	memory_t * ip;
	ip               = (memory_t *) mti_Malloc( sizeof( memory_t) );
	ip->clk          = mti_FindPort(ports, "clk");
	ip->en           = mti_FindPort(ports, "en");
	ip->wr           = mti_FindPort(ports, "wr");
	ip->rd           = mti_FindPort(ports, "rd");
	ip->ready        = mti_CreateDriver(mti_FindPort(ports, "ready"));
	ip->address1     = mti_FindPort(ports, "address1");
	ip->address2     = mti_FindPort(ports, "address2");
	ip->data_in      = mti_FindPort(ports, "data_in");
	ip->data_out1    = mti_CreateDriver(mti_FindPort(ports, "data_out1"));
	ip->data_out2    = mti_CreateDriver(mti_FindPort(ports, "data_out2"));
	ip->access_width = mti_FindPort(ports, "access_width");

	mtiProcessIdT memory_process = mti_CreateProcess("memory_p", on_clock, ip);
	mti_Sensitize(memory_process, ip->clk, MTI_EVENT);
}
