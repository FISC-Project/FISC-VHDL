/*
 * utils.c
 *
 *  Created on: 17/12/2016
 *      Author: Miguel
 */
#include "../vmachine/utils.h"

#include <string.h>

char * int2bin(int a, char *buffer, int buf_size) {
    buffer += (buf_size - 1);
    for (int i = 31; i >= 0; i--) {
        *buffer-- = (a & 1) + '0';
        a >>= 1;
    }
    return buffer;
}

char * int2bin64(uint64_t a, char *buffer, int buf_size) {
	uint64_t j = 63;
	for(uint64_t i = 0; i < 64; i++) {
		uint64_t r = a & (1ULL<<i);
		if((uint32_t)r)
			buffer[j--] = '1';
		else
			buffer[j--] = '0';
	}
	return buffer;
}

void reverse_string(char *str) {
    if (str == 0)  return;
    if (*str == 0) return;

    /* get range */
    char *start = str;
    char *end = start + strlen(str) - 1; /* -1 for \0 */
    char temp;

    /* reverse */
    while (end > start) {
        /* swap */
        temp = *start;
        *start = *end;
        *end = temp;

        /* move */
        ++start;
        --end;
    }
}


