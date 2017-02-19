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
#include "mmu.h"
#include "signal_conv.h"

#define get_pdp() sigv_to_int(mmu_ip->pdp)

typedef struct {
	mtiSignalIdT clk;
	mtiSignalIdT en;
	mtiSignalIdT pdp;
	mtiDriverIdT pfla;
	mtiDriverIdT pfla_wr;
} mmu_t;

mmu_t * mmu_ip;

/* This function converts a Virtual Address into a Physical Address */
uint32_t address_translate(uint32_t vaddress) {
	uint64_t pdp = get_pdp(); /* Read value of the wire PDP (Page Directory Pointer) */

	return vaddress;
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
