Place the bundled Android GGUF summary model in this directory.

Expected filename:
- `lecture_vault_summary.gguf`

The app intentionally keeps the real model out of the repository. When the GGUF
file is absent, the Android local LLM path reports itself as unavailable and the
existing extractive summary pipeline stays active as a fallback.
