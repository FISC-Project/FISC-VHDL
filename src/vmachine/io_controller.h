/*
 * io_controller.h
 *
 *  Created on: 19/12/2016
 *      Author: Miguel
 */

#ifndef SRC_VMACHINE_IO_CONTROLLER_H_
#define SRC_VMACHINE_IO_CONTROLLER_H_

#include <stdint.h>

enum INTERRUPT_TYPE {
	INT_ERR, /* For exceptions (Errors) */
	INT_IRQ  /* For normal device interrupt requests */
};

char io_controller_init(void);
char io_controller_deinit(void);
char io_wr_dispatch(uint32_t phys_addr, uint64_t data, uint8_t access_width);
char * io_rd_dispatch(uint32_t phys_addr, uint8_t access_width);
char io_irq(uint8_t devid, enum INTERRUPT_TYPE type);

#endif /* SRC_VMACHINE_IO_CONTROLLER_H_ */
