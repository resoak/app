param(
    [ValidateSet('base', 'small', 'all')]
    [string]$Model = 'all'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetDir = Join-Path $repoRoot 'assets/models/whisper'

if (-not (Test-Path -LiteralPath $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir | Out-Null
}

$models = @(
    @{
        Name = 'base'
        FileName = 'ggml-base.bin'
        Url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin'
    },
    @{
        Name = 'small'
        FileName = 'ggml-small.bin'
        Url = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin'
    }
)

foreach ($entry in $models) {
    if ($Model -ne 'all' -and $Model -ne $entry.Name) {
        continue
    }

    $outputPath = Join-Path $targetDir $entry.FileName
    if (Test-Path -LiteralPath $outputPath) {
        "Found $($entry.FileName), skipping download."
        continue
    }

    "Downloading $($entry.FileName) to $outputPath ..."
    Invoke-WebRequest -Uri $entry.Url -OutFile $outputPath
}

"Whisper model download complete."
