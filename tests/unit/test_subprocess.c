#include "subprocess.h"
#include "unity.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>

void
setUp(void)
{
}

void
tearDown(void)
{
}

static void
child_abort(void)
{
    printf("subprocess about to abort\n");
    abort();
}

static void
child_segv(void)
{
    printf("subprocess triggering segv\n");
#if BAL_PLATFORM_WINDOWS
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnull-dereference"
#endif
    volatile int *ptr = NULL;
    *ptr              = 42;
#if defined(__clang__)
#pragma clang diagnostic pop
#endif
#else
    raise(SIGSEGV);
#endif
}

static void
child_sigill(void)
{
    printf("subprocess triggering sigill\n");
#if defined(__GNUC__) || defined(__clang__)
    __builtin_trap();
#else
    raise(SIGILL);
#endif
}

static void
test_Subprocess_AbortTerminatesWithSignal(void)
{
    TEST_ASSERT_DEATH(child_abort, SIGABRT);
}

static void
test_Subprocess_SigsegvTerminatesWithSignal(void)
{
    TEST_ASSERT_DEATH(child_segv, SIGSEGV);
}

static void
test_Subprocess_SigillTerminatesWithSignal(void)
{
    TEST_ASSERT_DEATH(child_sigill, SIGILL);
}

int
main(void)
{
    UNITY_BEGIN();
    RUN_TEST(test_Subprocess_AbortTerminatesWithSignal);
    RUN_TEST(test_Subprocess_SigsegvTerminatesWithSignal);
    RUN_TEST(test_Subprocess_SigillTerminatesWithSignal);
    return UNITY_END();
}

/*** end of file ***/
