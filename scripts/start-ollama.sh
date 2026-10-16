#!/usr/bin/env bash
# Start Ollama with settings tuned for a 6 GB GPU and long-running agents.
export OLLAMA_FLASH_ATTENTION=1      # less memory for attention
export OLLAMA_KV_CACHE_TYPE=q8_0     # quantized KV cache -> more context in VRAM
export OLLAMA_KEEP_ALIVE=24h         # keep the model loaded
exec ollama serve
