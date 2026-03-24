# CLAUDE.md — worker-faster_whisper (Blackwell fork)

## Context

Fork of `runpod-workers/worker-faster_whisper`.

Goal: upgrade the worker to run reliably on NVIDIA RTX 5090 / Blackwell GPUs
on RunPod Serverless, while preserving the existing request/response contract.

Scope of this session:
- Upgrade the code and Dockerfile
- Build and push the image to Docker Hub
- Validate on a real RTX 5090 using a temporary RunPod pod
- Commit and push all changes

Out of scope (done manually via RunPod UI after this session):
- Updating the RunPod template
- Configuring the serverless endpoint
- GPU selection, timeouts, scaler settings

---

## Repo inspection checklist

Before changing anything, read and summarise:
- `Dockerfile` — base image, CUDA version, build steps
- `requirements.txt` or `pyproject.toml` — pinned versions of
  faster-whisper, ctranslate2, runpod SDK, and all other deps
- `src/handler.py` (or equivalent) — document the exact request fields
  consumed and response fields returned; this is the contract to preserve
- Any `builder/` scripts or build-time model download logic
- `test_input.json` if present — note the sample payload shape

Do not modify the handler's request/response interface unless strictly
required for a compatibility fix. If a change is required, document it
explicitly.

---

## Environment

All credentials and config live in `.env` at the repo root (git-ignored).
Before any shell command that needs credentials:
  `set -a && source .env && set +a`
For docker commands: `--env-file .env`

Before any git operation, verify SSH auth:
  `ssh -T git@github.com`

Read git identity and remote from the repo — do not hardcode or set them:
  `git config user.name`
  `git config user.email`
  `git remote -v`
  `git branch --show-current`

### Required .env variables

| Variable | Purpose |
|---|---|
| `REGISTRY_IMAGE` | Full image name e.g. `docker.io/youruser/faster-whisper-blackwell` |
| `REGISTRY_USERNAME` | Docker Hub username |
| `REGISTRY_PASSWORD` | Docker Hub access token |
| `IMAGE_TAG_PREFIX` | Tag prefix e.g. `blackwell-` |
| `RUNPOD_API_KEY` | For creating/terminating the validation test pod |
| `TEST_AUDIO_URL` | URL to a short audio clip for smoke test |
| `TEST_AUDIO_URL_LONG` | URL to a longer clip (optional) |

No HuggingFace token is required. All Whisper models used here
(`Systran/faster-whisper-small` etc.) are fully public and require no auth.

---

## Target stack

| Component | Target | Notes |
|---|---|---|
| CUDA | 12.8 | Minimum for Blackwell / sm_90 |
| cuDNN | 9.x | Paired with CUDA 12.8 |
| Base image | `nvidia/cuda:12.8.0-cudnn9-runtime-ubuntu22.04` | Verify exact tag exists on Docker Hub before use |
| Python | 3.11 | |
| faster-whisper | latest stable, pinned | Resolve and pin exact version |
| ctranslate2 | latest stable, pinned | Must support sm_90 — verify PyPI wheel targets CUDA 12.x |
| runpod SDK | latest stable, pinned | Check for breaking changes vs current |

**ctranslate2 / sm_90 note:** The PyPI wheel must be built against CUDA 12.x
to support Blackwell. Verify this before pinning. If the standard wheel does
not support sm_90, the fallback is building ctranslate2 from source in the
Dockerfile — document this clearly if taken.

---

## Model: baked in at build time

Models are baked into the image during `docker build`. Never downloaded at
worker startup.

- Bake in the `small` model only (`Systran/faster-whisper-small`, ~460MB).
- No HuggingFace token needed — the model is fully public.
- Remove or disable any runtime model-download logic in the handler.
- If a `builder/` script already handles this, reuse it — just confirm it
  runs at build time, not startup time.
- Do not bake in `medium` or larger unless explicitly asked.

---

## Build and push

```bash
# Load env
set -a && source .env && set +a

# Build — explicit platform flag required for Mac/Docker Desktop
docker build \
  --platform linux/amd64 \
  -t ${REGISTRY_IMAGE}:${IMAGE_TAG_PREFIX}latest \
  -t ${REGISTRY_IMAGE}:${IMAGE_TAG_PREFIX}$(git rev-parse --short HEAD) \
  .

# Push
echo $REGISTRY_PASSWORD | docker login -u $REGISTRY_USERNAME --password-stdin
docker push ${REGISTRY_IMAGE}:${IMAGE_TAG_PREFIX}latest
docker push ${REGISTRY_IMAGE}:${IMAGE_TAG_PREFIX}$(git rev-parse --short HEAD)
```

Always tag with both `latest` (prefixed) and the short git SHA.

---

## Validation: test pod on RTX 5090

Use the `runpod` Python SDK (already a project dep) to create a temporary pod
for GPU validation. Use a regular on-demand pod — not a serverless endpoint —
so you can exec into it.

Steps:

1. Query available GPU types to find the exact ID for the RTX 5090:
   ```python
   import runpod, os
   runpod.api_key = os.environ["RUNPOD_API_KEY"]
   # list gpuTypes via SDK or GraphQL and find the RTX 5090 entry
   ```

2. Create an on-demand pod with the pushed image on an RTX 5090.
   Minimum config: ~20GB container disk to safely fit the baked model.

3. Once running, exec or use the RunPod exec API to verify:
   - `nvidia-smi` shows the RTX 5090
   - Model file exists at the expected path inside the container
   - A short transcription against `TEST_AUDIO_URL` completes successfully
   - Response shape matches the documented handler contract
   - If `TEST_AUDIO_URL_LONG` is set, run that too

4. Terminate the pod immediately after validation passes.
   Do not leave it running — it costs money.

If pod creation via API fails (auth, quota, or GPU unavailability):
- Document the exact manual steps needed to do this via the RunPod UI
- Continue with all other work
- Note in UPGRADE_NOTES.md that GPU validation was not completed

---

## Git workflow

```bash
# Verify SSH before any git operation
ssh -T git@github.com

# Read identity — do not set it
git config user.name
git config user.email
```

Commit strategy — one logical commit per concern:
- `deps: upgrade to CUDA 12.8 + cuDNN 9 base image`
- `deps: pin faster-whisper, ctranslate2 for Blackwell / sm_90`
- `feat: bake small model at build time, remove runtime download`
- `chore: update test inputs and build scripts`

Push to the current branch on the configured remote.

---

## Execution policy

- Proceed autonomously through all tasks without waiting for approval.
- If one subsystem is blocked, continue all other work.
- Prefer explicit version pins over ranges everywhere.
- Keep Dockerfile changes minimal. Comment every changed line with the reason.
- Do not leave the repo in a half-configured state.
- Do not touch RunPod template, endpoint, or serverless config — that is manual.

---

## Deliverable: UPGRADE_NOTES.md

When complete, write `UPGRADE_NOTES.md` at the repo root with:

- Summary of every change made and the reason for it
- Exact versions pinned (faster-whisper, ctranslate2, runpod SDK, Python, CUDA, cuDNN)
- Exact base image tag used (include digest if `docker inspect` can retrieve it)
- Exact image tags pushed to Docker Hub
- Test pod results: GPU detected? Model path correct? Transcription output shape?
- Any manual steps still required (template update, endpoint config)
- Remaining risks or recommended follow-up

### Manual steps for operator after this session

The following must be done in the RunPod UI:
1. Update the existing template to point to the new image tag
2. Verify the endpoint is configured for RTX 5090 GPUs only
3. Set CUDA minimum version to 12.8 in endpoint config
4. (Optional) Run a serverless test job via the RunPod UI to confirm cold start

### Example audio files
Do not hardcode TEST_AUDIO_URL or TEST_AUDIO_URL_LONG in any committed file. Read them exclusively from the environment at test time.