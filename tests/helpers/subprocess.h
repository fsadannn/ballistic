#ifndef BALLISTIC_TEST_SUBPROCESS_H
#define BALLISTIC_TEST_SUBPROCESS_H

#include "bal_platform.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#if BAL_PLATFORM_WINDOWS
#include <windows.h>
#endif

#include "unity.h"

#if defined(noreturn)
#undef noreturn
#endif

typedef void (*bal_subprocess_fn_t)(void);

typedef struct
{
    int     signal_number;
    bool    completed;
    bool    terminated_by_signal;
    uint8_t _padding[2];
} bal_subprocess_result_t;

bal_subprocess_result_t bal_subprocess_run(bal_subprocess_fn_t fn);

#define TEST_ASSERT_DEATH(fn, expected_sig)                                                 \
    do                                                                                      \
    {                                                                                       \
        const bal_subprocess_result_t _res = bal_subprocess_run(fn);                        \
        TEST_ASSERT_TRUE_MESSAGE(_res.completed, "Subprocess failed to run to completion"); \
        TEST_ASSERT_TRUE_MESSAGE(_res.terminated_by_signal,                                 \
                                 "Subprocess was expected to terminate with a signal, but " \
                                 "exited normally");                                        \
        TEST_ASSERT_EQUAL_INT_MESSAGE(                                                      \
            (expected_sig), _res.signal_number, "Subprocess signal mismatch");              \
    } while (0)

#endif
