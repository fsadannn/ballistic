#define _POSIX_C_SOURCE 200809L
#include "bal_fuzzer_ipc.h"
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

#define PIPE_READ_END  0
#define PIPE_WRITE_END 1
#define IPC_TIMEOUT_MS 60000

/// Waits until `fd` is ready for events (see poll(2)).
static bal_error_t ipc_wait_for_file_descriptor(int file_descriptor, short events, int timeout_ms);

bal_error_t
bal_fuzzer_ipc_spawn(bal_fuzzer_worker_handle_t *handle, const char *worker_path)
{
    if (NULL == handle || NULL == worker_path)
    {
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    int to_child[2];
    int from_child[2];

    (void)setenv("ASAN_OPTIONS", "detect_leaks=0", 1);

    if (pipe(to_child) != 0)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting function: pipe(to_chile) failed because %s.",
                      strerror(errno));
        return BAL_ERROR_THREAD_CREATION;
    }

    if (pipe(from_child) != 0)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting function: pipe(from_child) failed because %s"
                      ".",
                      strerror(errno));
        (void)close(to_child[PIPE_READ_END]);
        (void)close(to_child[PIPE_WRITE_END]);
        return BAL_ERROR_THREAD_CREATION;
    }

    const pid_t pid = fork();

    if (pid < 0)
    {
        BAL_LOG_ERROR(&bal_thread_logger, "fork() failed because %s.", strerror(errno));
        (void)close(to_child[PIPE_READ_END]);
        (void)close(to_child[PIPE_WRITE_END]);
        (void)close(from_child[PIPE_READ_END]);
        (void)close(from_child[PIPE_WRITE_END]);
        return BAL_ERROR_THREAD_CREATION;
    }

    if (0 == pid)
    {
        // This is a child process, so rewire stdio and exec the worker. We read to_child's read end
        // and write from_child's write end. Close the other two.
        (void)close(to_child[PIPE_WRITE_END]);
        (void)close(from_child[PIPE_READ_END]);

        if (dup2(to_child[PIPE_READ_END], STDIN_FILENO) < 0
            || dup2(from_child[PIPE_WRITE_END], STDOUT_FILENO) < 0)
        {
            _exit(127);
        }

        (void)close(to_child[PIPE_READ_END]);
        (void)close(from_child[PIPE_WRITE_END]);

        (void)execl(worker_path, worker_path, (char *)NULL);
        _exit(127);
    }

    // This is a parent process, so keep to_child's write end and from_child's read end.
    (void)close(to_child[PIPE_READ_END]);
    (void)close(from_child[PIPE_WRITE_END]);

    handle->input_file_descriptor  = to_child[PIPE_WRITE_END];
    handle->output_file_descriptor = from_child[PIPE_READ_END];
    handle->child_pid              = (int32_t)pid;

    BAL_LOG_INFO(&bal_thread_logger,
                 "Spawned worker '%s' with pid %d (in fd %d, out fd %d).",
                 worker_path,
                 (int)pid,
                 handle->input_file_descriptor,
                 handle->output_file_descriptor);

    return BAL_SUCCESS;
}

void
bal_fuzzer_ipc_destroy(bal_fuzzer_worker_handle_t *handle)
{
    if (NULL == handle)
    {
        return;
    }

    if (handle->input_file_descriptor >= 0)
    {
        (void)close(handle->input_file_descriptor);
    }

    if (handle->output_file_descriptor >= 0)
    {
        (void)close(handle->output_file_descriptor);
    }

    if (handle->child_pid > 0)
    {
        (void)kill(handle->child_pid, SIGKILL);
        (void)waitpid(handle->child_pid, NULL, 0);
    }

    handle->input_file_descriptor  = -1;
    handle->output_file_descriptor = -1;
    handle->child_pid              = 0;
}

bal_error_t
bal_fuzzer_ipc_send(const int input_file_descriptor, const bal_fuzzer_input_t *input)
{
    if (input_file_descriptor < 0)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting function: invalid file descriptor %d.",
                      input_file_descriptor);
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    if (NULL == input)
    {
        BAL_LOG_ERROR(&bal_thread_logger, "Aborting function: input is NULL.");
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    // Catch a closed/corrupted descriptor before touching the pipe.
    if (fcntl(input_file_descriptor, F_GETFL) < 0)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting function: file descriptor %d is invalid or "
                      "closed because %s.",
                      input_file_descriptor,
                      strerror(errno));
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    if (input->instruction_count > BAL_FUZZER_MAX_INSTRUCTIONS)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting function: instruction_count %u exceeds "
                      "maximum %u.",
                      input->instruction_count,
                      (unsigned)BAL_FUZZER_MAX_INSTRUCTIONS);
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    const uint8_t *BAL_RESTRICT input_cursor = (const uint8_t *)input;
    size_t                      remaining    = sizeof(*input);

    while (remaining > 0U)
    {
        const bal_error_t wait_status
            = ipc_wait_for_file_descriptor(input_file_descriptor, POLLOUT, IPC_TIMEOUT_MS);

        if (wait_status != BAL_SUCCESS)
        {
            return wait_status;
        }

        const ssize_t written = write(input_file_descriptor, input_cursor, remaining);

        if (written < 0)
        {
            if (EINTR == errno || EAGAIN == errno || EWOULDBLOCK == errno)
            {
                continue;
            }

            if (EPIPE == errno)
            {
                BAL_LOG_ERROR(&bal_thread_logger,
                              "IPC send failed on file descriptor %d because "
                              "worker closed the pipe (EPIPE).",
                              input_file_descriptor);
            }
            else
            {
                BAL_LOG_ERROR(&bal_thread_logger,
                              "IPC send failed on file descriptor %d because "
                              "%s",
                              input_file_descriptor,
                              strerror(errno));
            }

            return BAL_ERROR_THREAD_CLEANUP;
        }

        if (0 == written)
        {
            BAL_LOG_ERROR(&bal_thread_logger,
                          "IPC send failed on file descriptor %d because "
                          "write returned 0 with %zu bytes remaining.",
                          input_file_descriptor,
                          remaining);
            return BAL_ERROR_THREAD_CLEANUP;
        }

        input_cursor += (size_t)written;
        remaining -= (size_t)written;
        BAL_LOG_TRACE(&bal_thread_logger,
                      "IPC sent %zd bytes to file descriptor %d, %zu bytes "
                      "remaining.",
                      written,
                      input_file_descriptor,
                      remaining);
    }

    return BAL_SUCCESS;
}

bal_error_t
bal_fuzzer_ipc_receive(const int output_file_descriptor, bal_fuzzer_response_t *response)
{
    if (output_file_descriptor < 0)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting function: invalid file descriptor %d.",
                      output_file_descriptor);
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    if (NULL == response)
    {
        BAL_LOG_ERROR(&bal_thread_logger, "Aborting function: response is NULL.");
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    // Catch a closed/corrupted descriptor before touching the pipe.
    if (fcntl(output_file_descriptor, F_GETFL) < 0)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting function: file descriptor %d is invalid or "
                      "closed because %s.",
                      output_file_descriptor,
                      strerror(errno));
        return BAL_ERROR_INVALID_ARGUMENT;
    }

    (void)memset(response, 0, sizeof(*response));

    uint8_t *BAL_RESTRICT response_cursor = (uint8_t *)response;
    size_t                remaining       = sizeof(*response);

    while (remaining > 0U)
    {
        const bal_error_t wait_status
            = ipc_wait_for_file_descriptor(output_file_descriptor, POLLIN, IPC_TIMEOUT_MS);

        if (wait_status != BAL_SUCCESS)
        {
            return wait_status;
        }

        const ssize_t bytes_read = read(output_file_descriptor, response_cursor, remaining);

        if (bytes_read < 0)
        {
            if (EINTR == errno || EAGAIN == errno || EWOULDBLOCK == errno)
            {
                continue;
            }

            BAL_LOG_ERROR(&bal_thread_logger,
                          "IPC receive failed on file descriptor %d because "
                          "%s.",
                          output_file_descriptor,
                          strerror(errno));
            return BAL_ERROR_THREAD_CLEANUP;
        }

        if (0 == bytes_read)
        {
            BAL_LOG_ERROR(&bal_thread_logger,
                          "IPC Receive failed on file descriptor %d because "
                          "worker closed the pipe. %zu bytes still expected"
                          ".",
                          output_file_descriptor,
                          remaining);
            return BAL_ERROR_THREAD_CLEANUP;
        }

        response_cursor += (size_t)bytes_read;
        remaining -= (size_t)bytes_read;
        BAL_LOG_TRACE(&bal_thread_logger,
                      "IPC received %zd bytes to file descriptor %d, %zu bytes "
                      "remaining.",
                      bytes_read,
                      output_file_descriptor,
                      remaining);
    }

    if (response->status < BAL_FUZZER_WORKER_OK || response->status > BAL_FUZZER_WORKER_ERROR_END)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Received file descriptor %d worker returned "
                      "out-of-range status %d.",
                      output_file_descriptor,
                      response->status);
        return BAL_ERROR_STRUCT_CORRUPTED;
    }

    return BAL_SUCCESS;
}

static bal_error_t
ipc_wait_for_file_descriptor(const int file_descriptor, const short events, const int timeout_ms)
{
    struct pollfd poll_request = {};
    poll_request.fd            = file_descriptor;
    poll_request.events        = events;

    while (true)
    {
        poll_request.revents  = 0;
        const int poll_result = poll(&poll_request, 1U, timeout_ms);

        if (poll_result > 0)
        {
            return BAL_SUCCESS;
        }

        if (poll_result < 0)
        {
            if (EINTR == errno)
            {
                continue;
            }

            BAL_LOG_ERROR(&bal_thread_logger,
                          "poll() failed on file descriptor %d because %s.",
                          file_descriptor,
                          strerror(errno));
            return BAL_ERROR_THREAD_CLEANUP;
        }
    }
}

/*** end of file ***/