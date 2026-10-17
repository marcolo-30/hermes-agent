# Hermes-Agent

A [Hermes](https://hermes-agent.nousresearch.com) agent running in Docker and connected to a local model served by Ollama (which runs outside the container, on the same machine). The goal is a personal agent you can control from Telegram, with access limited to a single working folder.

> Status: phase B in progress (agent in Docker with Ollama and an isolated working folder). Telegram and the tasks (documents, web, Google, email) are still pending.

## How it is set up

```
Your PC / WSL
├── Ollama (system service, outside Docker)  ← local model
└── Docker
    └── "hermes" container
        ├── /opt/data   ← volume: config, .env, sessions   (docker/data)
        └── /workspace  ← volume: the only working folder  (docker/workspace)
```

- Hermes runs **inside** the container as an unprivileged user (uid 1000). The container is the isolation layer, which is why the terminal backend is `local`.
- The agent only sees `/workspace` as its working folder. Your home directory and `/mnt/c` are not mounted.
- Ollama is an **external requirement**: Docker does not start it.

## Repository layout

```
hermes-agent/
├── README.md
├── .gitignore
├── config/
│   └── config.template.yaml   # copy of data/config.yaml WITHOUT secrets
└── docker/
    ├── docker-compose.yml
    ├── .env.example           # variable names only, no values
    ├── .env                   # (ignored) real values
    ├── data/                  # (ignored) config, Hermes .env, sessions
    └── workspace/             # (ignored) the agent's working folder
```

## Requirements

- Docker (Engine, or Docker Desktop with WSL integration).
- Ollama installed and running as a service.
- Model pulled: `ollama pull qwen3.5:4b`.
- Reference hardware used: 6 GB VRAM GPU and ~16 GB RAM.

## 1. Configure Ollama (one time)

The container reaches Ollama over the network, so Ollama must listen beyond localhost. Set the variables on the service:

```bash
sudo systemctl edit ollama
```

Write this between the comments the file already contains:

```ini
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q4_0"
Environment="OLLAMA_NUM_PARALLEL=1"
Environment="OLLAMA_KEEP_ALIVE=24h"
Environment="OLLAMA_CONTEXT_LENGTH=65536"
```

Apply and verify:

```bash
sudo systemctl daemon-reload
sudo systemctl restart ollama
systemctl show ollama -p Environment
ollama run qwen3.5:4b "hello"
ollama ps        # the context column should show 65536
```

What each variable does:

| Variable | Purpose |
|---|---|
| `OLLAMA_HOST=0.0.0.0` | Required: without it the container cannot reach Ollama |
| `OLLAMA_FLASH_ATTENTION=1` and `OLLAMA_KV_CACHE_TYPE=q4_0` | Make a 64k context fit in little VRAM |
| `OLLAMA_NUM_PARALLEL=1` | Does not reserve context for several simultaneous requests |
| `OLLAMA_KEEP_ALIVE=24h` | Keeps the model loaded |
| `OLLAMA_CONTEXT_LENGTH=65536` | Minimum context Hermes needs (applies to every model) |

With 6 GB of VRAM and a 64k context, a small part of the model ends up on the CPU (~8%). That is acceptable; what matters is the real speed (tokens/s).

## 2. Prepare the project

```bash
git clone <repo-URL> hermes-agent
cd hermes-agent/docker

# IMPORTANT: create the folders BEFORE the first "up".
# If Docker creates them, they are owned by root and the agent cannot write.
mkdir -p data workspace

cp .env.example .env
# edit .env and set HERMES_DASH_PASSWORD and HERMES_DASH_SECRET
# (for example: openssl rand -base64 24)
```

If your user is not uid 1000 (`id -u`), adjust `HERMES_UID` and `HERMES_GID` in `docker-compose.yml`.

## 3. Start

```bash
docker compose up -d
docker logs -f hermes
```

## 4. Configure Hermes (one time)

The configuration is stored in `docker/data/` (a volume), so it survives `down`/`up` and container recreation. Without an interactive terminal, use commands:

```bash
docker exec hermes hermes config set model.provider custom
docker exec hermes hermes config set model.base_url http://host.docker.internal:11434/v1
docker exec hermes hermes config set model.default qwen3.5:4b
docker exec hermes hermes config set terminal.backend local
docker exec hermes hermes config set terminal.cwd /workspace
```

(Interactive alternative: `docker exec -it hermes hermes setup`.)

Key points in `data/config.yaml`:

- `model.base_url` uses `host.docker.internal`, **not** `localhost` or `127.0.0.1`: inside the container, those point to the container itself.
- `terminal.cwd` must be an **absolute path** (`/workspace`). A relative path is resolved from the data directory and creates folders inside `data/`.
- `terminal.backend: local`, because the container already provides the isolation.
- Do not use `sudo_password`, and do not store secrets the agent should not handle: the agent can read its own data directory.

Save a secret-free copy as the repo template:

```bash
cp data/config.yaml ../config/config.template.yaml
# review the file and remove any key or token before committing
```

To reproduce on another machine: copy the template to `docker/data/config.yaml` before the first `up`, and create `data/.env` by hand.

## 5. Verify

```bash
# Ollama reachable from the container
docker exec hermes curl http://host.docker.internal:11434/v1/models

# Terminal chat (-w /workspace is needed: the CLI uses the launch directory)
docker exec -it -w /workspace hermes hermes
```

Recommended tests (always check the result on disk, not what the model says):

1. A simple tool call: `pwd` should print `/workspace`.
2. Create a file and check that it shows up in `docker/workspace/` on your PC.
3. Chain two or three steps (create, write, read).
4. Isolation: the agent must not see your home directory or `/mnt/c`.

Persistence:

```bash
docker compose down && docker compose up -d
grep -n "cwd" data/config.yaml     # should still show /workspace
```

## Switching models

```bash
ollama pull <model>
docker exec hermes hermes config set model.default <model>
```

Then run `docker compose restart hermes` if needed, and check which model actually loaded with `ollama ps`. Repeat the tool tests with the new model: not all models call tools equally well. With `OLLAMA_CONTEXT_LENGTH=65536`, a larger model may spill to the CPU and become slow.

## Security

- `data/`, `workspace/` and every `.env` are in `.gitignore`. Check `git status` before each commit.
- The dashboard is published only on `127.0.0.1:9119`. If you move this to a server, do not expose it to the internet without a TLS reverse proxy (or use an SSH tunnel).
- The agent runs as an unprivileged user and only writes to `/workspace`.
- Telegram: restrict the bot to your numeric user ID (not your username).
- Email: drafts only at first; automatic sending last, and only if wanted.
- A small model can improvise steps or misreport what it did. Verify real results before giving it access to external services.

## Known issues

| Symptom | Cause and fix |
|---|---|
| `Permission denied` when creating files in `/workspace` | The folder was created owned by root. Run `sudo chown -R 1000:1000 docker/workspace` |
| `workspace` folders appear inside `data/` | `terminal.cwd` is relative. Use `/workspace` |
| The file does not appear where expected when testing via CLI | Launch the CLI with `docker exec -it -w /workspace hermes hermes` |
| `hermes setup` says "non-interactive mode" | `-it` is missing from `docker exec`, or use the `hermes config set` commands |
| The container cannot reach Ollama | Check `OLLAMA_HOST=0.0.0.0`, `extra_hosts` in the compose file, and that `base_url` uses `host.docker.internal` |
| Compose changes are not applied | `docker compose restart` does not re-read the file: use `docker compose up -d --force-recreate` |
| `docker: command not found` in WSL | Install Docker Engine in WSL or enable WSL integration in Docker Desktop |

## Plan

- [x] **A. Base:** environment, repo, Ollama with long context
- [x] **B1. Agent:** Hermes in Docker connected to Ollama, persistent configuration, isolated working folder
- [ ] **B2. Telegram:** bot created with BotFather, restricted to a single user
- [ ] **C. Tasks:** documents in `/workspace`, web search with citations, dedicated Google account, email as drafts
- [ ] **D. Wrap-up:** per-phase documentation and VPS deployment
