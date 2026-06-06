Place bundled Whisper GGML models in this directory.

Required bundled filenames:

- `ggml-base.bin`
- `ggml-small.bin`

These files are too large for normal Git history, so they must be tracked with
Git LFS. Run the repository download script to fetch them locally:

```powershell
.\scripts\download_whisper_models.ps1
```

After the files are downloaded, commit them with Git LFS enabled so future
clones can receive the models by running `git lfs pull`.
