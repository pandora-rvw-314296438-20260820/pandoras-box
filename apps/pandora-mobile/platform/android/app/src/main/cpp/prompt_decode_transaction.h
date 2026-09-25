#pragma once

#include <algorithm>
#include <cstdint>

namespace pandora_local_ai {

// Wrapper codes are deliberately separate from llama_decode's raw result.
// llama.cpp can retain processed microbatches on abort/fatal error.
struct PromptDecodeResult {
    int code = 0;
    int raw_decode_code = 0;
    int processed_tokens = 0;
    int batch_offset = 0;
    int batch_size = 0;
    int capacity_retries = 0;
    bool rollback_failed = false;
};

template <class Decode, class Cancelled, class Rollback>
PromptDecodeResult decode_prompt_transaction(
        const int token_count,
        const int start_position,
        const int end_limit,
        const int initial_batch_size,
        Decode decode,
        Cancelled cancelled,
        Rollback rollback) {
    PromptDecodeResult result;
    if (token_count <= 0 || start_position < 0 || initial_batch_size <= 0 ||
        static_cast<int64_t>(start_position) + token_count > end_limit) {
        result.code = 3; // Invalid/over-capacity prompt; never decode or shift.
        return result;
    }

    bool attempted_decode = false;
    auto fail = [&](const int code) {
        result.code = code;
        if (attempted_decode && !rollback()) {
            result.code = 4; // Caller must not advertise reusable native state.
            result.rollback_failed = true;
        }
        return result;
    };

    int batch_limit = initial_batch_size;
    for (int offset = 0; offset < token_count;) {
        result.batch_offset = offset;
        result.batch_size = std::min(batch_limit, token_count - offset);
        if (cancelled()) return fail(9);

        attempted_decode = true;
        result.raw_decode_code = decode(offset, result.batch_size);
        if (result.raw_decode_code == 1 && result.batch_size > 1) {
            // The pinned API restores memory on KV-slot exhaustion (code 1).
            // Retry this SAME offset, with a strictly smaller bounded batch.
            batch_limit = std::max(1, result.batch_size / 2);
            ++result.capacity_retries;
            continue;
        }
        if (result.raw_decode_code != 0) {
            return fail(result.raw_decode_code == 2 ? 9 : 2);
        }

        offset += result.batch_size;
        result.processed_tokens = offset;
        if (cancelled()) return fail(9);
    }
    return result;
}

} // namespace pandora_local_ai
