#!/usr/bin/env bash
# Start Ollama with settings tuned for a 6 GB GPU and long-running agents.
export OLLAMA_FLASH_ATTENTION=1      # less memory for attention
export OLLAMA_KV_CACHE_TYPE=q4_0     # 4-bit KV cache -> 64k context in less VRAM
export OLLAMA_NUM_PARALLEL=1         # one conversation, no extra context buffers
export OLLAMA_KEEP_ALIVE=24h         # keep the model loaded
exec ollama serve
