#pragma once

#define NTH_BIT(nth) (1 << (nth))
#define IS_BIT_SET(flag, nth) (flag) & NTH_BIT((nth))
#define FETCH_BIT(val, nth) (IS_BIT_SET((val), (nth)) >> (nth)))

#define BIT_SET(p, n) ((p) |= NTH_BIT((n)))
#define BIT_CLEAR(p, n) ((p) &= ~NTH_BIT((n)))
#define BIT_WRITE(c, p, n) (c ? BIT_SET(p, n) : BIT_CLEAR(p, n))

#define INDEX_FROM_BIT(b, arr_size) ((b) / (arr_size))
#define OFFSET_FROM_BIT(b, arr_size) ((b) % (arr_size))
#define INDEX_FROM_BIT_SZ32(b) INDEX_FROM_BIT(b, 32)
#define OFFSET_FROM_BIT_SZ32(b) OFFSET_FROM_BIT(b, 32)
