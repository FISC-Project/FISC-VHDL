/*
 * signal_conv.h
 *
 *  Created on: 17/12/2016
 *      Author: Miguel
 */

#ifndef SRC_VMACHINE_SIGNAL_CONV_H_
#define SRC_VMACHINE_SIGNAL_CONV_H_

#include <mti.h>
#include <stdio.h>
#include "../vmachine/utils.h"

inline uint32_t get_vector_size(mtiSignalIdT sig) {
	return mti_TickLength(mti_GetSignalType(sig));
}

inline void fix_vector(char * s, uint32_t size, _Bool ascii_mode) {
	for(int i = 0; i < size; i++)
		s[i] = (s[i] & 0x1) + (ascii_mode ? '0' : 0);
}

inline int sig_to_int(mtiSignalIdT sig) {
	return mti_GetSignalValue(sig) & 0x1;
}

inline uint64_t sigv_to_int(mtiSignalIdT sig) {
	char * ret = mti_GetArraySignalValue(sig, 0);
	fix_vector(ret, get_vector_size(sig), 1);
	return (uint64_t)strtoull(ret, 0, 2);
}

inline char * sigv_to_str(mtiSignalIdT sig, _Bool ascii_mode) {
	char * ret = mti_GetArraySignalValue(sig, 0);
	fix_vector(ret, get_vector_size(sig), ascii_mode);
	return ret;
}

inline char * str_to_sigv(char * str) {
	int strl = strlen(str);
	for(int i = 0; i < strl; i++) str[i] = (str[i] + 2) - '0';
	return str;
}

#define max_int_to_sigv_vector_sz 33
char int_to_sigv_vector[max_int_to_sigv_vector_sz];

inline char * int_to_sigv(int n, uint8_t vector_size) {
	int2bin(n, int_to_sigv_vector, max_int_to_sigv_vector_sz-2);
	int_to_sigv_vector[max_int_to_sigv_vector_sz-1] = '\0';
	reverse_string(int_to_sigv_vector);
	int_to_sigv_vector[vector_size] = '\0';
	for(int i = 0; i < vector_size;i++)
		int_to_sigv_vector[i] = (int_to_sigv_vector[i] + 2) - '0';
	reverse_string(int_to_sigv_vector);
	return int_to_sigv_vector;
}

#endif /* SRC_VMACHINE_SIGNAL_CONV_H_ */
