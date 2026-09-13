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

/// Sends a fuzz input to a worker process via its input pipe.
///
/// # Safety
///
/// * `input_file_descriptor` must be a valid, open file descriptor (the write-end of a pipe).
/// * `input` must point to a fully initialized [`bal_fuzzer_input_t`].
/// * `input->instruction_count` must not exceed [`BAL_FUZZER_MAX_INSTRUCTIONS`].
///
/// # Errors
///
/// * Returns [`BAL_SUCCESS`] on success.
/// * Returns [`BAL_ERROR_INVALID_ARGUMENT`] if the following occurs:
///     - `input_file_descriptor` is negative.
///     - `input` is `NULL`.
///     - `input_file_descriptor` is invalid or closed.
///     - `input->instruction_count` exceeds [`BAL_FUZZER_MAX_INSTRUCTIONS`].
/// * Returns [`BAL_ERROR_THREAD_CLEANUP`] if the following occurs:
///     - `write()` syscall fails with `EPIPE`  (worker closed the pipe).
///     - `write()` syscall fails with any non-retryable error.
///     - `write()` syscall returns 0 with bytes remaining.
///     - `poll()` syscall fails while waiting for the file descriptor to become writable.
bal_error_t bal_fuzzer_ipc_send(int                                    input_file_descriptor,
                                const bal_fuzzer_input_t *BAL_RESTRICT input);

/// Receives a fuzz response from a worker process via its output pipe.
///
/// # Safety
///
/// * `output_file_descriptor` must be a valid, open file descriptor (the read-end of a pipe).
/// * `response` must point to a writable [`bal_fuzzer_response_t`].
///
/// # Errors
///
/// * Returns [`BAL_SUCCESS`] on success.
/// * Returns [`BAL_ERROR_INVALID_ARGUMENT`] if the following occurs:
///     - `output_file_descriptor` is negative.
///     - `response` is `NULL`.
///     - `output_file_descriptor` is invalid or closed.
/// * Returns [`BAL_ERROR_THREAD_CLEANUP`] if the following occurs:
///     - `read()` syscall fails with a non-retryable error.
///     - `read()` syscall returns 0 (EOF), indicating the worker closed the pipe or crashed.
///     - `poll()` syscall fails while waiting for the file descriptor to become readable.
/// * Returns [`BAL_ERROR_STRUCT_CORRUPTED`] if the received `response->status` is outside the
///   valid [`bal_fuzzer_worker_status_t`] enum range.
bal_error_t bal_fuzzer_ipc_receive(int output_file_descriptor, bal_fuzzer_response_t *response);

#endif // BALLISTIC_BAL_FUZZER_IPC_H

/*** end of file ***/