/*
 * virtual_memory.c
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */
#include <mti.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <inttypes.h>
#include <bit.h>
#include "mmu.h"
#include "signal_conv.h"
#include "address_space.h"

#define get_pdp() sigv_to_int(mmu_ip->pdp)

typedef struct {
	mtiSignalIdT clk;
	mtiSignalIdT en;
	mtiSignalIdT pdp;
	mtiDriverIdT pfla;
	mtiDriverIdT pfla_wr;
} mmu_t;

mmu_t * mmu_ip;

extern uint8_t memory_contents[MEMORY_DEPTH];

/* This function converts a Virtual Address into a Physical Address */
uint32_t address_translate(uint32_t vaddress) {
	uint8_t mmu_enabled = sig_to_int(mmu_ip->en);
	if(!mmu_enabled) return vaddress; /* Return the original virtual address in case the MMU is disabled */

	uint32_t ret = (uint32_t)-1; /* Return value */

	uint64_t pdp = get_pdp(); /* Read value of the wire PDP (Page Directory Pointer) */
	if(pdp >= MEMORY_DEPTH) {
		/* The programmer set a pointer outside memory. We'll need to generate an exception whenever the CPU tries to access this value */
		/* TODO */
	} else {
		printf("MMU:1 "); /* Append this to the stdout as part of the debug message */

		/* Calculate indices from the Virtual Address: */
		uint32_t table_idx = INDEX_FROM_BIT((vaddress)/PAGE_SIZE, PAGES_PER_TABLE);
		uint32_t page_idx  = OFFSET_FROM_BIT((vaddress)/PAGE_SIZE, PAGES_PER_TABLE);

		/* Fetch the directory, table entry and page: */
		paging_directory_t * directory = (paging_directory_t*)((uint32_t)memory_contents + (uint32_t)pdp);
		page_table_t * table = (page_table_t*)((uint32_t)directory + (uint32_t)directory->tables[table_idx]);
		page_t * page = (page_t*)((uint32_t)&table->pages[page_idx]);

		/* TODO: Generate exception if this page is not allowed to the current user */

		/* Return physical address: */
		ret = (page->phys_addr << 12) | (vaddress & 0xFFF);
	}
	return ret;
}

void mmu_init(
	mtiRegionIdT region,
	char * param,
	mtiInterfaceListT * generics,
	mtiInterfaceListT * ports
) {
	mmu_ip          = (mmu_t *)mti_Malloc(sizeof(mmu_t));
	mmu_ip->clk     = mti_FindPort(ports, "clk");
	mmu_ip->en      = mti_FindPort(ports, "en");
	mmu_ip->pdp     = mti_FindPort(ports, "pdp");
	mmu_ip->pfla    = mti_CreateDriver(mti_FindPort(ports, "pfla"));
	mmu_ip->pfla_wr = mti_CreateDriver(mti_FindPort(ports, "pfla_wr"));
}
