/*
 * utils.h
 *
 *  Created on: 17/12/2016
 *      Author: Miguel
 */

#ifndef SRC_MACHINE_UTILS_H_
#define SRC_MACHINE_UTILS_H_

#include <stdint.h>

char * int2bin(int a, char *buffer, int buf_size);
char * int2bin64(uint64_t a, char *buffer, int buf_size);
void reverse_string(char *str);

#endif /* SRC_MACHINE_UTILS_H_ */
