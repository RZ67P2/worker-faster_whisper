# Upgrade Notes: Blackwell / RTX 5090

**Date:** 2026-03-24
**Branch:** main
**Commit range:** fa4087c..c9bfadf

---

## Summary of changes

| Commit | Description |
|---|---|
| `fa4087c` | Add CLAUDE.md and update .gitignore |
| `2315cac` | Upgrade base image to CUDA 12.8 + cuDNN 9, Python 3.10 → 3.11 |
| `fdf25b8` | Pin faster-whisper 1.2.1, ctranslate2 4.7.1, runpod 1.8.2 |
| `346281e` | Bake only `small` model at build time, restrict AVAILABLE_MODELS |
| `c9bfadf` | Update test inputs and configs for Blackwell |

---

## Exact versions pinned

| Component | Previous | New |
|---|---|---|
| Base image | `nvidia/cuda:12.3.2-cudnn9-runtime-ubuntu22.04` | `nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04` |
| CUDA | 12.3.2 | 12.8.0 |
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
  - `blackwell-c9bfadf`
- **Digest:** `sha256:000f7a8a872fdf1cbbe82e0d42721640d7a1e0ce0702359c2d817f237536ce38`
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

**Status:** Not completed via API.

The Docker Hub repo is private, so the RunPod on-demand pod could not pull the image. Validation should be performed via the first serverless test job after configuring the template and endpoint in the RunPod UI.

**What to verify on first deployment:**
1. Serverless logs show the RTX 5090 GPU detected
2. Model loads successfully from HuggingFace cache
3. Transcription completes and returns the expected shape:
   ```json
   {
     "segments": [...],
     "detected_language": "en",
     "transcription": "...",
     "translation": null,
     "device": "cuda",
     "model": "small"
   }
   ```

---

## Manual steps required (RunPod UI)

1. **Update the existing template** to point to image `rz67p2/faster-whisper-blackwell:blackwell-latest`
2. **Configure Docker Hub credentials** in the template (repo is private)
3. **Set GPU type** to RTX 5090
4. **Set minimum CUDA version** to 12.8 in endpoint config
5. **Run a test job** from the RunPod UI to confirm cold start and transcription work

---

## Risks and follow-up

- **ctranslate2 4.7.1 on Blackwell:** The PyPI wheel is built against CUDA 12.x. Blackwell support is expected but not yet confirmed on a real RTX 5090. The first serverless job is the definitive test.
- **runpod SDK 1.8.2:** Minor version bump from 1.7.9. No breaking changes observed in the handler's usage (`serverless.start`, `rp_cuda`, `rp_validator`, `download_files_from_urls`).
- **Image size:** Significantly smaller than before (1 model vs 10). Cold start should be faster.
- **If more models are needed later:** Add them to `model_names` in `builder/fetch_models.py` and `AVAILABLE_MODELS` in `src/predict.py`, then rebuild and push.
