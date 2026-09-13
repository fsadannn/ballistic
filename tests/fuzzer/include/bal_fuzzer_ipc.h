#ifndef BALLISTIC_BAL_FUZZER_IPC_H
#define BALLISTIC_BAL_FUZZER_IPC_H

#include "bal_errors.h"
#include "bal_fuzzer_protocol.h"
#include <stdint.h>

typedef struct
{
    int     input_file_descriptor;
    int     output_file_descriptor;
    int32_t child_pid;
} bal_fuzzer_worker_handle_t;

/// Spawns a worker executable via an anonymous pipe.
///
/// Creates two pipes: one for sending [`bal_fuzzer_input_t`] to the worker's stdin, and one for
/// receiving [`bal_fuzzer_response_t`] from the worker's stdout.
///
/// # Safety
///
/// * `handle` and `worker_path` must be valid, and not NULL.
/// * `worker_path` must point to a valid executable file accessible by the current process.
/// * The caller retains ownership of `handle` and must eventually call [`bal_fuzzer_ipc_destroy`]
///   to release resources.
///
/// # Errors
///
/// * Returns [`BAL_SUCCESS`] on success.
/// * Returns [`BAL_ERROR_INVALID_ARGUMENT`] if the following occurs:
///     - `handle` or `worker_path` is `NULL`.
///     - the first `pipe()` syscall fails.
/// * Returns [`BAL_ERROR_THREAD_CREATION`] if the following occurs:
///     - the second `pipe()` syscall fails.
///     - the `fork()` syscall fails.
bal_error_t bal_fuzzer_ipc_spawn(bal_fuzzer_worker_handle_t *BAL_RESTRICT handle,
                                 const char *BAL_RESTRICT                 worker_path);

/// Destroys a worker handle.
///
/// This function does not free the memory backing `handle` itself. The caller retains
/// ownership of the struct.
///
/// # Safety
///
/// * `handle` must be a valid pointer.
/// * Must not be called concurrently with [`bal_fuzzer_ipc_send`] or [`bal_fuzzer_ipc_receive`]
///   using the same file descriptors.
void bal_fuzzer_ipc_destroy(bal_fuzzer_worker_handle_t *BAL_RESTRICT handle);

/// Sends data to a worker process via its input pipe.
///
/// # Safety
///
/// * `file_descriptor` must be a valid, open file descriptor (the write-end of a pipe).
///
/// # Errors
///
/// * Returns [`BAL_SUCCESS`] on success.
/// * Returns [`BAL_ERROR_INVALID_ARGUMENT`] if the following occurs:
///     - `file_descriptor` is negative.
///     - `data` is `NULL`.
///     - `file_descriptor` is invalid or closed.
/// * Returns [`BAL_ERROR_THREAD_CLEANUP`] if the following occurs:
///     - `write()` syscall fails with `EPIPE`  (worker closed the pipe).
///     - `write()` syscall fails with any non-retryable error.
///     - `write()` syscall returns 0 with bytes remaining.
///     - `poll()` syscall fails while waiting for the file descriptor to become writable.
bal_error_t bal_fuzzer_ipc_send(int file_descriptor, const void *data, size_t size);

/// Receives a fuzz response from a worker process via its output pipe.
///
/// # Safety
///
/// * `file_descriptor` must be a valid, open file descriptor (the read-end of a pipe).
/// * `data` must point to a writable [`bal_fuzzer_response_t`].
///
/// # Errors
///
/// * Returns [`BAL_SUCCESS`] on success.
/// * Returns [`BAL_ERROR_INVALID_ARGUMENT`] if the following occurs:
///     - `file_descriptor` is negative.
///     - `data` is `NULL`.
///     - `file_descriptor` is invalid or closed.
/// * Returns [`BAL_ERROR_THREAD_CLEANUP`] if the following occurs:
///     - `read()` syscall fails with a non-retryable error.
///     - `read()` syscall returns 0 (EOF), indicating the worker closed the pipe or crashed.
///     - `poll()` syscall fails while waiting for the file descriptor to become readable.
bal_error_t bal_fuzzer_ipc_receive(int file_descriptor, void *data, size_t size);

#endif // BALLISTIC_BAL_FUZZER_IPC_H

/*** end of file ***/