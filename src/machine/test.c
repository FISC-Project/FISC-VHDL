/*
 * test.c
 *
 *  Created on: 14/12/2016
 *      Author: Miguel
 */
#include <mti.h>
#include <stdio.h>

typedef struct
{
   mtiSignalIdT clk;
} testbench_t;

void on_clock(void * param) {
	testbench_t * ip = (testbench_t *) param;
	_Bool clk = clk = mti_GetSignalValue (ip->clk);
	if(clk) {
		printf("\nPOSEDGE CLOCK\n");
	} else {
		printf("\nNEGEDGE CLOCK\n");
	}

	fflush(stdout);
}

void test_init(
	mtiRegionIdT region,
	char *param,
	mtiInterfaceListT *generics,
	mtiInterfaceListT *ports
) {
	testbench_t *ip;
	ip = (testbench_t *) mti_Malloc( sizeof( testbench_t) );
	ip->clk = mti_FindPort( ports, "clk" );

	mtiProcessIdT testbench_process = mti_CreateProcess("testbench_p", on_clock, ip);
	mti_Sensitize(testbench_process, ip->clk, MTI_EVENT);
}
