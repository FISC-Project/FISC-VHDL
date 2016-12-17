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
#include "signal_conv.h"

#define BOOTLOADER_FILE "bin/bootloader.bin"
#define MEMORY_DEPTH 1024 /* Size of memory in bytes */
#define MEMORY_LOADLOC 0  /* Where to load the program on startup */

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

enum DATATYPE {
	SZ_8, SZ_16, SZ_32, SZ_64
};

uint8_t memory_contents[MEMORY_DEPTH]; /* The actual Main Memory */

#define ALIGN16(addr) ((addr)*2)
#define ALIGN32(addr) ((addr)*4)
#define ALIGN64(addr) ((addr)*8)

#define MEMORY_DATA_OUT_BUFF_SIZE 64
char read_memory_ret[MEMORY_DATA_OUT_BUFF_SIZE+1];

char write_memory(uint32_t address, uint64_t data, uint8_t access_width) {
	if(address >= MEMORY_DEPTH) return 0;
	switch(access_width) {
		case SZ_8:
			memory_contents[address]            = (uint8_t)data;
			break;
		case SZ_16:
			memory_contents[ALIGN16(address)]   = (uint8_t)((data & 0xFF00) >> 8);
			memory_contents[ALIGN16(address)+1] = (uint8_t)  data & 0xFF;
			break;
		case SZ_32:
			memory_contents[ALIGN32(address)]   = (uint8_t)((data & 0xFF000000) >> 24);
			memory_contents[ALIGN32(address)+1] = (uint8_t)((data & 0xFF0000)   >> 16);
			memory_contents[ALIGN32(address)+2] = (uint8_t)((data & 0xFF00)     >> 8);
			memory_contents[ALIGN32(address)+3] = (uint8_t)  data & 0xFF;
			break;
		case SZ_64:
			memory_contents[ALIGN64(address)]   = (uint8_t)((data & 0xFF00000000000000) >> 56);
			memory_contents[ALIGN64(address)+1] = (uint8_t)((data & 0xFF000000000000)   >> 48);
			memory_contents[ALIGN64(address)+2] = (uint8_t)((data & 0xFF0000000000)     >> 40);
			memory_contents[ALIGN64(address)+3] = (uint8_t)((data & 0xFF00000000)       >> 32);
			memory_contents[ALIGN64(address)+4] = (uint8_t)((data & 0xFF000000)         >> 24);
			memory_contents[ALIGN64(address)+5] = (uint8_t)((data & 0xFF0000)           >> 16);
			memory_contents[ALIGN64(address)+6] = (uint8_t)((data & 0xFF00)             >> 8);
			memory_contents[ALIGN64(address)+7] = (uint8_t)  data & 0xFF;
			break;
		default: return 0;
	}
	return 1;
}

char * read_memory(uint32_t address, uint8_t access_width) {
	/* Zero out the whole memory data out buffer */
	for(int i = 0; i < MEMORY_DATA_OUT_BUFF_SIZE; i++)
		read_memory_ret[i] = 2; /* this is a 0 when it's a std_logic variable */
	read_memory_ret[MEMORY_DATA_OUT_BUFF_SIZE] = '\0'; /* End of the Buffer */

	switch(access_width) {
		case SZ_8:  if(address >= MEMORY_DEPTH) return read_memory_ret; break;
		case SZ_16: if(ALIGN16(address)+1 >= MEMORY_DEPTH) return read_memory_ret; break;
		case SZ_32: if(ALIGN32(address)+3 >= MEMORY_DEPTH) return read_memory_ret; break;
		case SZ_64: if(ALIGN64(address)+7 >= MEMORY_DEPTH) return read_memory_ret; break;
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
			char * val = int_to_sigv(memory_contents[ALIGN16(address)+1], 8);
			memcpy(read_memory_ret + (7*8), val, 8);
			val = int_to_sigv(memory_contents[ALIGN16(address)], 8);
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
	printf("Size of bootloader: %d bytes\n", address);
	return 1;
}

void on_clock(void * param) {
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
				uint32_t address = sigv_to_int(ip->address2);
				uint64_t data = sigv_to_int(ip->data_in);
				uint8_t access_width = sigv_to_int(ip->access_width);
				printf("WR (@0x%x <%d>) = 0x%" PRIx64 " ", address, access_width, data);
				if(!write_memory(address, data, access_width))
					printf(" ERROR: Could not write to address 0x%x", address);
			}


			/******************************************************************/
			/* Handle Memory Reads for Channel 1 (used by the fetch stage 1): */
			/******************************************************************/
			char * rd = sigv_to_str(ip->rd, 0);
			if(rd[1] > 0) {
				uint32_t address = sigv_to_int(ip->address1);
				char * returned_data = read_memory(address /= 4, SZ_32);
				char cpy[65];
				strcpy(cpy, returned_data);
				for(int i=0;i<64;i++) cpy[i] = (cpy[i] + '0') - 2;
				uint64_t to_int = strtoull(cpy, 0, 2);

				printf("RD CH1 (@0x%x <2>) = 0x%" PRIx64 " ", ALIGN32(address), to_int);
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
				uint32_t address = sigv_to_int(ip->address2);
				uint8_t access_width = sigv_to_int(ip->access_width);
				char * returned_data = read_memory(address, access_width);
				char cpy[65];
				strcpy(cpy, returned_data);
				for(int i=0;i<64;i++) cpy[i] = (cpy[i] + '0') - 2;
				uint64_t to_int = strtoull(cpy, 0, 2);

				printf("RD CH2 (@0x%x <%d>) = 0x%" PRIx64 " ", address, access_width, to_int);
				mti_ScheduleDriver(ip->data_out2, (long)returned_data, 0, MTI_INERTIAL);
				mti_ScheduleDriver(ip->ready, (long)int_to_sigv(3,2), 1, MTI_INERTIAL);

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
