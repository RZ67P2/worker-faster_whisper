# Upgrade Notes: Blackwell / RTX 5090

**Date:** 2026-03-28
**Branch:** main
**Commit range:** fa4087c..62decfa

---

## Summary of changes

| Commit | Description |
|---|---|
| `fa4087c` | Add CLAUDE.md and update .gitignore |
| `2315cac` | Upgrade base image to CUDA 12.8 + cuDNN 9, Python 3.10 → 3.11 |
| `fdf25b8` | Pin faster-whisper 1.2.1, ctranslate2 4.7.1, runpod 1.8.2 |
| `346281e` | Bake only `small` model at build time, restrict AVAILABLE_MODELS |
| `c9bfadf` | Update test inputs and configs for Blackwell |
| `830a020` | Update README and add UPGRADE_NOTES for Blackwell |
| `62decfa` | Fix CUDA base image to 12.8.1 for driver 570 compat |

---

## Exact versions pinned

| Component | Previous | New |
|---|---|---|
| Base image | `nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04` | `nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04` |
| CUDA | 12.3.2 | 12.8.1 |
| cuDNN | 9.x | 9.x (tag naming changed: `cudnn` instead of `cudnn9`) |
| Python | 3.10 | 3.11 (via deadsnakes PPA) |
| faster-whisper | 1.1.0 | 1.2.1 |
| ctranslate2 | unpinned (transitive) | 4.7.1 (explicit pin) |
| runpod SDK | ~=1.7.9 | ==1.8.2 |
| Models baked | All 10 (tiny → turbo) | `small` only (~460MB) |

---

## Docker image

- **Registry:** docker.io/rz67p2/faster-whisper-blackwell
- **Tags pushed:**
  - `blackwell-latest`
  - `blackwell-62decfa`
- **Digest:** `sha256:ba4821ae56e53505c42dd1507f226e9dbd017f5e6b9b5bf613bb6c016abfe369`
- **Platform:** linux/amd64

---

## Model changes

- Only `Systran/faster-whisper-small` is baked into the image at build time
- `AVAILABLE_MODELS` in `src/predict.py` restricted to `{"small"}`
- Default model in `src/rp_schema.py` changed from `"base"` to `"small"`
- Requests for other models (tiny, base, medium, large-*, turbo) will return an error
- No runtime model downloads — handler rejects unavailable models before reaching WhisperModel()

---

## Request/response contract

The handler contract is **preserved**. All input fields and output fields are unchanged.

**One behavioral change:** the default `model` field changed from `"base"` to `"small"`. Clients that explicitly set `model` are unaffected. Clients relying on the default will now get `small` instead of `base` (higher quality, slightly slower).

---

## GPU validation

**Status:** Confirmed working on RTX 5090 via RunPod Serverless (2026-03-28).

- **Host driver:** 570.195.03
- **GPU:** NVIDIA GeForce RTX 5090 (32GB)
- **CUDA:** 12.8.1 (runs natively on driver 570+, no forward compat needed)
- **ctranslate2:** PTX 8.7 JIT-compiles to sm_120 (Blackwell) at runtime
- **Performance:** ~2x faster than A40 endpoint

### CUDA version history

| CUDA version | Result | Reason |
|---|---|---|
| 12.8.0 | Failed ("unsupported display driver") | Tested on host with driver 580.x |
| 12.9.1 | Failed ("forward compat on non supported HW") | CUDA 12.9.1 > driver 570's native 12.9.0 support; compat library failed |
| **12.8.1** | **Working** | Runs natively on driver 570+ |

---

## Manual steps required (RunPod UI)

1. **Update the existing template** to point to image `rz67p2/faster-whisper-blackwell:blackwell-62decfa`
2. **Configure Docker Hub credentials** in the template (repo is private)
3. **Set GPU type** to RTX 5090
4. **Set minimum CUDA version** to 12.8 in endpoint config
5. **Run a test job** from the RunPod UI to confirm cold start and transcription work

---

## Risks and follow-up

- **Driver version variance:** RunPod serverless hosts may have different driver versions. CUDA 12.8.1 is confirmed on driver 570.x. If future hosts run older drivers (< 565), the image may fail. Monitor logs for CUDA errors.
- **runpod SDK 1.8.2:** Minor version bump from 1.7.9. No breaking changes observed in the handler's usage (`serverless.start`, `rp_cuda`, `rp_validator`, `download_files_from_urls`).
- **Image size:** Significantly smaller than before (1 model vs 10). Cold start should be faster.
- **If more models are needed later:** Add them to `model_names` in `builder/fetch_models.py` and `AVAILABLE_MODELS` in `src/predict.py`, then rebuild and push.
