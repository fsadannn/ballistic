#include "subprocess.h"
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if BAL_PLATFORM_WINDOWS

static void
bal_subprocess_check_child(void)
{
    const char *cmdline = GetCommandLineA();
    const char *prefix  = "--bal-subprocess=";
    const char *match   = strstr(cmdline, prefix);

    if (NULL == match)
    {
        return;
    }

    match += strlen(prefix);

    size_t offset = 0;
    if (sscanf_s(match, "%zu", &offset) != 1)
    {
        fprintf(stderr, "[bal_subprocess] Error: invalid target offset\n");
        ExitProcess(127);
    }

    HMODULE                         hMod = GetModuleHandleA(NULL);
    const bal_subprocess_function_t target_fn
        = (bal_subprocess_function_t)((uintptr_t)hMod + offset);

    // Suppress system crash and abort modal dialogs on Windows so the test does not hang.
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);

    target_fn();

    ExitProcess(0);
}

// Automatically intercept execution before main() is called if we are a child process.
static void __attribute__((constructor))
bal_subprocess_auto_intercept(void)
{
    bal_subprocess_check_child();
}

bal_subprocess_result_t
bal_subprocess_run(const bal_subprocess_function_t fn)
{
    bal_subprocess_result_t result;
    memset(&result, 0, sizeof(result));

    if (NULL == fn)
    {
        return result;
    }

    char exe_path[MAX_PATH];
    if (GetModuleFileNameA(NULL, exe_path, MAX_PATH) == 0)
    {
        return result;
    }

    HMODULE      hMod   = GetModuleHandleA(NULL);
    const size_t offset = (size_t)((uintptr_t)fn - (uintptr_t)hMod);

    char command_line[MAX_PATH + 512];
    (void)snprintf(
        command_line, sizeof(command_line), "\"%s\" --bal-subprocess=%zu", exe_path, offset);

    STARTUPINFOA si;
    memset(&si, 0, sizeof(si));
    si.cb = (DWORD)sizeof(STARTUPINFOA);

    PROCESS_INFORMATION pi;
    memset(&pi, 0, sizeof(pi));

    if (!CreateProcessA(NULL, command_line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi))
    {
        return result;
    }

    const DWORD wait_res = WaitForSingleObject(pi.hProcess, 30000);
    if (wait_res == WAIT_TIMEOUT)
    {
        (void)TerminateProcess(pi.hProcess, 1);
    }

    DWORD raw_exit_code = 0;
    (void)GetExitCodeProcess(pi.hProcess, &raw_exit_code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);

    result.completed = true;

    if (raw_exit_code == 0xC0000005U) // EXCEPTION_ACCESS_VIOLATION
    {
        result.terminated_by_signal = true;
        result.signal_number        = SIGSEGV;
    }
    else if (raw_exit_code == 0xC000001DU) // EXCEPTION_ILLEGAL_INSTRUCTION
    {
        result.terminated_by_signal = true;
        result.signal_number        = SIGILL;
    }
    else if (raw_exit_code == 0x40000015U || raw_exit_code == 3U) // STATUS_FATAL_APP_EXIT / abort()
    {
        result.terminated_by_signal = true;
        result.signal_number        = SIGABRT;
    }
    else if ((raw_exit_code & 0xC0000000U) == 0xC0000000U) // Other fatal exception
    {
        result.terminated_by_signal = true;
        result.signal_number        = SIGSEGV;
    }

    return result;
}

#else

#include <errno.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

bool
bal_subprocess_check_child(void)
{
    // On POSIX, fork() does not re-exec the binary so main() is not invoked as a child.
    return false;
}

bal_subprocess_result_t
bal_subprocess_run(const bal_subprocess_function_t subprocess_function)
{
    bal_subprocess_result_t subprocess_result;
    (void)memset(&subprocess_result, 0, sizeof(subprocess_result));

    if (NULL == subprocess_function)
    {
        return subprocess_result;
    }

    const pid_t pid = fork();

    if (pid < 0)
    {
        return subprocess_result;
    }

    if (0 == pid)
    {
        (void)signal(SIGSEGV, SIG_DFL);
        (void)signal(SIGILL, SIG_DFL);
        (void)signal(SIGABRT, SIG_DFL);

        subprocess_function();
        _exit(0);
    }

    int status = 0;
    (void)waitpid(pid, &status, 0);
    subprocess_result.completed = true;

    if (WIFSIGNALED(status))
    {
        subprocess_result.terminated_by_signal = true;
        subprocess_result.signal_number        = WTERMSIG(status);
    }

    return subprocess_result;
}

#endif // BAL_PLATFORM_WINDOWS
