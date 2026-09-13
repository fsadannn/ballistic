#ifndef BALLISTIC_TEST_SUBPROCESS_H
#define BALLISTIC_TEST_SUBPROCESS_H

#include "bal_platform.h"
#include <stdbool.h>
#include <stdint.h>

#if BAL_PLATFORM_WINDOWS

#include <windows.h>

#endif

#include "unity.h"

#if defined(noreturn)
#undef noreturn
#endif

typedef void (*bal_subprocess_function_t)(void);

typedef struct
{
    int     signal_number;
    bool    completed;
    bool    terminated_by_signal;
    uint8_t _padding[2];
} bal_subprocess_result_t;

bal_subprocess_result_t bal_subprocess_run(bal_subprocess_function_t subprocess_function);

#define TEST_ASSERT_DEATH(fn, expected_signal)                                                 \
    do                                                                                         \
    {                                                                                          \
        const bal_subprocess_result_t subprocess_result = bal_subprocess_run(fn);              \
        TEST_ASSERT_TRUE_MESSAGE(subprocess_result.completed,                                  \
                                 "Subprocess failed to run to completion");                    \
        TEST_ASSERT_TRUE_MESSAGE(subprocess_result.terminated_by_signal,                       \
                                 "Subprocess was expected to terminate with a signal, but "    \
                                 "exited normally");                                           \
        TEST_ASSERT_EQUAL_INT_MESSAGE(                                                         \
            (expected_signal), subprocess_result.signal_number, "Subprocess signal mismatch"); \
    } while (0)

#endif
