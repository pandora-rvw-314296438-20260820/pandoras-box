from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

NATIVE = Path(__file__).resolve().parents[1] / "platform/android/app/src/main/cpp"
HEADER = NATIVE / "prompt_decode_transaction.h"
SOURCE = NATIVE / "ai_chat.cpp"
CASES = ['multi_batch_success', 'cancel_before_decode', 'cancel_after_first_batch_retry', 'abort_inside_microbatch', 'fatal_second_batch', 'invalid_batch_preserves_raw_code', 'rollback_failure_is_not_cancel_success', 'capacity_retries_same_offset', 'capacity_exhaustion_bounded', 'cancel_during_capacity_retry', 'last_batch_cancel_rolls_back_all', 'exact_capacity_boundary', 'oversize_no_shift_or_decode', 'empty_prompt', 'negative_start', 'invalid_batch_limit', 'integer_overflow']

HARNESS = r"""#include "prompt_decode_transaction.h"
#include <cassert>
#include <climits>
#include <iostream>
#include <string>
#include <vector>
using pandora_local_ai::decode_prompt_transaction;
struct KV {
    int tail = 9, calls = 0, rollbacks = 0;
    bool cancel = false, reject_rollback = false;
    std::vector<int> offsets, sizes;
    bool rollback() {
        ++rollbacks;
        if (reject_rollback) return false;
        tail = 9;
        return true;
    }
    int append(int offset, int count) {
        ++calls;
        offsets.push_back(offset); sizes.push_back(count);
        assert(tail + 1 == 10 + offset);
        tail += count;
        return 0;
    }
};
int main(int argc, char **argv) {
    assert(argc == 2);
    const std::string name = argv[1];
    KV kv;
    auto cancel = [&] { return kv.cancel; };
    auto rollback = [&] { return kv.rollback(); };
    if (name == "multi_batch_success") {
        auto r = decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){return kv.append(o,n);},cancel,rollback);
        assert(r.code==0 && r.processed_tokens==130 && kv.tail==139);
        assert((kv.offsets==std::vector<int>{0,64,128}) && kv.rollbacks==0);
    } else if (name == "cancel_before_decode") {
        kv.cancel=true;
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){return kv.append(o,n);},cancel,rollback);
        assert(r.code==9 && kv.calls==0 && kv.tail==9 && kv.rollbacks==0);
    } else if (name == "cancel_after_first_batch_retry") {
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){int code=kv.append(o,n);kv.cancel=true;return code;},cancel,rollback);
        assert(r.code==9 && r.processed_tokens==64 && kv.tail==9 && kv.rollbacks==1);
        kv.cancel=false;
        auto retry=decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){return kv.append(o,n);},cancel,rollback);
        assert(retry.code==0 && kv.tail==139);
    } else if (name == "abort_inside_microbatch") {
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){kv.append(o,n/2);return 2;},cancel,rollback);
        assert(r.code==9 && r.raw_decode_code==2 && kv.tail==9 && kv.rollbacks==1);
    } else if (name == "fatal_second_batch") {
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){kv.append(o,o==0?n:3);return o==0?0:-7;},cancel,rollback);
        assert(r.code==2 && r.raw_decode_code==-7 && r.batch_offset==64);
        assert(r.processed_tokens==64 && kv.tail==9 && kv.rollbacks==1);
    } else if (name == "invalid_batch_preserves_raw_code") {
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int,int){++kv.calls;return -1;},cancel,rollback);
        assert(r.code==2 && r.raw_decode_code==-1 && kv.calls==1 && kv.tail==9);
    } else if (name == "rollback_failure_is_not_cancel_success") {
        kv.reject_rollback=true;
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){kv.append(o,n);kv.cancel=true;return 0;},cancel,rollback);
        assert(r.code==4 && r.rollback_failed && kv.tail==73);
    } else if (name == "capacity_retries_same_offset") {
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int o,int n){if(n>16){++kv.calls;kv.offsets.push_back(o);return 1;}
                             return kv.append(o,n);},cancel,rollback);
        assert(r.code==0 && r.capacity_retries==2 && kv.tail==139);
        assert(kv.offsets[0]==0 && kv.offsets[1]==0 && kv.offsets[2]==0);
    } else if (name == "capacity_exhaustion_bounded") {
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int,int){++kv.calls;return 1;},cancel,rollback);
        assert(r.code==2 && r.raw_decode_code==1 && r.capacity_retries==6);
        assert(kv.calls==7 && kv.tail==9 && kv.rollbacks==1);
    } else if (name == "cancel_during_capacity_retry") {
        auto r=decode_prompt_transaction(130,10,2044,64,
            [&](int,int){++kv.calls;kv.cancel=true;return 1;},cancel,rollback);
        assert(r.code==9 && kv.calls==1 && kv.rollbacks==1);
    } else if (name == "last_batch_cancel_rolls_back_all") {
        auto r=decode_prompt_transaction(65,10,2044,64,
            [&](int o,int n){kv.append(o,n);if(o==64)kv.cancel=true;return 0;},cancel,rollback);
        assert(r.code==9 && r.processed_tokens==65 && kv.tail==9);
    } else if (name == "exact_capacity_boundary") {
        auto r=decode_prompt_transaction(54,10,64,64,
            [&](int o,int n){return kv.append(o,n);},cancel,rollback);
        assert(r.code==0 && kv.tail==63);
    } else {
        int count=130, start=10, limit=64, batch=64;
        if(name=="empty_prompt") {count=0;limit=2044;}
        else if(name=="negative_start") {start=-1;limit=2044;}
        else if(name=="invalid_batch_limit") {batch=0;limit=2044;}
        else if(name=="integer_overflow") {start=INT_MAX-2;count=10;limit=INT_MAX;}
        else assert(name=="oversize_no_shift_or_decode");
        auto r=decode_prompt_transaction(count,start,limit,batch,
            [&](int,int){++kv.calls;return 0;},cancel,rollback);
        assert(r.code==3 && kv.calls==0 && kv.rollbacks==0 && kv.tail==9);
    }
    std::cout << name << " PASS\n";
}
"""


CLOSURE_PRELUDE = r"""#include "prompt_decode_transaction.h"
#include <atomic>
#include <cassert>
#include <initializer_list>
#include <string>
#include <iostream>
using llama_token = int;
struct JNIEnv {};
struct Vocab { int eot=2, eos=1; } vocab;
struct Batch { int token=-1, position=-1; bool logits=true; } g_batch;
void *g_model=nullptr, *g_context=nullptr, *g_sampler=nullptr;
int current_position=2044, g_context_size=2048, kv_tail=2043;
bool turn_in_progress=true, reject_rollback=false, raised=false, was_cancelled=false;
int decode_code=0, decode_calls=0, rollbacks=0, accepts=0;
std::atomic_bool g_cancel_requested{false};
pandora_local_ai::PromptDecodeResult recorded;
const Vocab *llama_model_get_vocab(void *) { return &vocab; }
int llama_vocab_eot(const Vocab *v) { return v->eot; }
int llama_vocab_eos(const Vocab *v) { return v->eos; }
bool llama_vocab_is_eog(const Vocab *,int token) { return token==1 || token==2; }
void common_batch_clear(Batch &b) { b={}; }
void common_batch_add(Batch &b,int token,int position,std::initializer_list<int>,bool logits) {
    b.token=token; b.position=position; b.logits=logits;
}
int llama_decode(void *,Batch b) {
    ++decode_calls;
    assert(b.position==kv_tail+1 && b.position<g_context_size);
    assert(!b.logits);
    kv_tail=b.position; // Retain partial work even when injected decode aborts.
    return decode_code;
}
bool rollback_unfinished_turn() {
    if(!turn_in_progress) return true;
    ++rollbacks;
    if(reject_rollback) return false;
    current_position=20; kv_tail=19; turn_in_progress=false;
    return true;
}
void throw_native_generation_error(JNIEnv *,bool cancelled,const std::string &) {
    raised=true; was_cancelled=cancelled;
}
void record_prompt_result(const pandora_local_ai::PromptDecodeResult &r,int,int) { recorded=r; }
void common_sampler_accept(void *,int token,bool generated) {
    assert(generated && (token==1 || token==2)); ++accepts;
}
"""

CLOSURE_MAIN = r"""int main(int argc,char **argv) {
    assert(argc==2);
    const std::string name=argv[1];
    if(name=="closure_eos_fallback") vocab.eot=-1;
    if(name=="closure_no_end_token") {vocab.eot=-1;vocab.eos=-1;}
    if(name=="closure_pre_cancel") g_cancel_requested=true;
    if(name=="closure_decode_abort") decode_code=2;
    if(name=="closure_decode_fatal") decode_code=-7;
    if(name=="closure_rollback_failure") {decode_code=2;reject_rollback=true;}
    if(name=="closure_no_active_turn") turn_in_progress=false;
    if(name=="closure_no_capacity") {current_position=2048;kv_tail=2047;}
    JNIEnv env;
    const bool result=close_turn_at_limit(&env);
    if(name=="closure_eot" || name=="closure_eos_fallback") {
        assert(result && !raised && decode_calls==1 && accepts==1);
        assert(current_position==2045 && kv_tail==2044 && rollbacks==0);
        assert(g_batch.token==(name=="closure_eot"?2:1));
    } else if(name=="closure_no_active_turn") {
        assert(result && !raised && decode_calls==0 && accepts==0 && rollbacks==0);
    } else {
        assert(!result && raised && accepts==0);
        if(name=="closure_rollback_failure") {
            assert(!was_cancelled && recorded.code==4 && recorded.rollback_failed);
            assert(turn_in_progress);
        } else {
            assert(!turn_in_progress && current_position==20 && kv_tail==19 && rollbacks==1);
            assert(was_cancelled==(name=="closure_pre_cancel" || name=="closure_decode_abort"));
        }
        if(name=="closure_no_end_token" || name=="closure_pre_cancel" || name=="closure_no_capacity")
            assert(decode_calls==0);
        if(name=="closure_decode_fatal") assert(recorded.raw_decode_code==-7);
        if(name=="closure_decode_abort") assert(recorded.raw_decode_code==2);
    }
    std::cout<<name<<" PASS\n";
}
"""

CASES += [
    "closure_eot", "closure_eos_fallback", "closure_no_end_token",
    "closure_pre_cancel", "closure_decode_abort", "closure_decode_fatal",
    "closure_rollback_failure", "closure_no_active_turn", "closure_no_capacity",
]


class NativePromptTransactionTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        compiler = os.environ.get("CXX") or shutil.which("c++") or shutil.which("g++")
        if not compiler:
            raise RuntimeError("A C++17 compiler is required for native prompt regression tests.")
        cls.workspace = tempfile.TemporaryDirectory(prefix="pandora-native-prompt-test-")
        cls.addClassCleanup(cls.workspace.cleanup)
        root = Path(cls.workspace.name)
        source = root / "harness.cpp"
        source.write_text(HARNESS, encoding="utf-8")
        cls.binary = root / "harness"
        result = subprocess.run(
            [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-O2",
             str(source), "-I", str(NATIVE), "-o", str(cls.binary)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        # Compile the ACTUAL production closure function against fault-injected
        # backend/JNI stubs. This is control-flow testing, not model inference.
        native = SOURCE.read_text(encoding="utf-8")
        closure = "static bool close_turn_at_limit(" + native.split(
            "static bool close_turn_at_limit(", 1
        )[1].split("static int decode_tokens_in_batches(", 1)[0]
        closure_source = root / "closure.cpp"
        closure_source.write_text(CLOSURE_PRELUDE + closure + CLOSURE_MAIN, encoding="utf-8")
        cls.closure_binary = root / "closure"
        closure_result = subprocess.run(
            [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-O2",
             str(closure_source), "-I", str(NATIVE), "-o", str(cls.closure_binary)],
            capture_output=True, text=True, timeout=60, check=False,
        )
        if closure_result.returncode:
            raise AssertionError(closure_result.stdout + closure_result.stderr)

    def test_native_wiring_preserves_raw_failure_and_transaction_boundaries(self) -> None:
        source = SOURCE.read_text(encoding="utf-8")
        decoder = source.split("static int decode_tokens_in_batches(", 1)[1].split(
            'extern "C"', 1
        )[0]
        self.assertIn("decode_prompt_transaction(", decoder)
        self.assertIn("rollback_prompt_tokens(context, start_pos)", decoder)
        self.assertNotIn("shift_context();", decoder)
        self.assertIn("return result.code;", decoder)
        self.assertIn("llama_set_abort_callback(context", source)
        self.assertIn("return user_result;", source)
        self.assertIn("return system_result;", source)
        self.assertIn("chat_msgs.resize(original_message_count)", source)
        self.assertIn("available_prompt_tokens <= 0", source)
        self.assertIn("java/util/concurrent/CancellationException", source)
        self.assertIn("lastDecodeCode", source)
        self.assertIn("lastRollbackFailed", source)
        self.assertIn("if (!rollback_unfinished_turn()) return 4;", source)
        generation = source.split(
            "Java_com_arm_aichat_internal_InferenceEngineImpl_generateNextToken(", 1
        )[1].split('extern "C"', 1)[0]
        self.assertNotIn("shift_context();", generation)
        self.assertEqual(generation.count("finish_turn();"), 2)
        self.assertIn("if (!close_turn_at_limit(env)) return nullptr;", generation)
        self.assertIn("llama_vocab_eot(vocab)", source)
        self.assertIn("llama_vocab_eos(vocab)", source)
        self.assertIn("const int token_decode_result = llama_decode", generation)
        self.assertIn("restored && token_decode_result == 2", generation)


def _case(name: str):
    def test(self: NativePromptTransactionTest) -> None:
        result = subprocess.run(
            [str(self.closure_binary if name.startswith("closure_") else self.binary), name],
            capture_output=True, text=True,
            timeout=10, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(name + " PASS", result.stdout)
    return test


for _name in CASES:
    setattr(NativePromptTransactionTest, "test_" + _name, _case(_name))


if __name__ == "__main__":
    unittest.main()
