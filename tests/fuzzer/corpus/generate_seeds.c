#include "bal_decoder.h"
#include "bal_log.h"
#include "generated/decoder_table.h"
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

int
main(void)
{
    bal_logger_init_default();
    FILE *seeds_file = fopen("seeds.bin", "wb");

    if (NULL == seeds_file)
    {
        BAL_LOG_ERROR(&bal_thread_logger,
                      "Aborting process: failed to open seeds.bin for writing.");
        return EXIT_FAILURE;
    }

    const bal_decoder_instruction_metadata_t *BAL_RESTRICT metadata_cursor
        = g_bal_decoder_arm64_instructions;
    uint32_t seeds_written_to_file = 0U;

    for (uint32_t i = 0U; i < BAL_DECODER_ARM64_INSTRUCTIONS_SIZE; ++i)
    {
        const uint32_t                                         seed = metadata_cursor->expected;
        const bal_decoder_instruction_metadata_t *BAL_RESTRICT decoded_instruction_metadata
            = bal_decode_arm64(seed);

        if (decoded_instruction_metadata != NULL)
        {
            (void)fwrite(&seed, sizeof(seed), 1U, seeds_file);
            ++seeds_written_to_file;
        }

        ++metadata_cursor;
    }

    (void)fclose(seeds_file);
    BAL_LOG_INFO(&bal_thread_logger,
                 "Wrote %u/%u seeds to seeds.bin\n",
                 seeds_written_to_file,
                 (uint32_t)BAL_DECODER_ARM64_INSTRUCTIONS_SIZE);
    return EXIT_SUCCESS;
}