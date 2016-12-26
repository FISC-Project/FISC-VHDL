/*
 * timer.h
 *
 *  Created on: 26/12/2016
 *      Author: Miguel
 */

#ifndef SRC_MACHINE_IODEVICES_TIMER_H_
#define SRC_MACHINE_IODEVICES_TIMER_H_

#define TIMER_IOSPACE 1

int timer_init(void * arg);
void timer_deinit(void);
char timer_write(uint32_t local_ioaddr, uint64_t data, uint8_t access_width);
uint64_t timer_read(uint32_t local_ioaddr, uint8_t access_width);

#endif /* SRC_MACHINE_IODEVICES_TIMER_H_ */
