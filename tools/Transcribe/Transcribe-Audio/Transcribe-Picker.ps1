#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$Path,                                # optional: file path, else picker
  [ValidateSet('off','ru','uk','auto')]         # auto = translate to ru if lang!=ru/uk
  [string]$Translate = 'off'
)

$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

# --------- CONFIG: adjust once ----------
$WhisperExe = 'C:\whisper.cpp\build\bin\Release\whisper-cli.exe'
$ModelPath  = 'C:\whisper.cpp\models\ggml-medium.bin'
$FfmpegExe  = 'ffmpeg'
# Call Argos via python -m to avoid PATH issues
$ArgosCli   = 'py -3.11 -m argostranslate.cli'
# ----------------------------------------

function Test-Tool([string]$exe, [string]$hint) {
  if (-not (Get-Command $exe -ErrorAction SilentlyContinue) -and -not (Test-Path $exe)) {
    throw "Not found: $exe. $hint"
  }
}

function Pick-File {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = 'Select an audio/video file'
  $dlg.Filter = 'Media|*.wav;*.mp3;*.m4a;*.ogg;*.opus;*.flac;*.aac;*.wma;*.mp4;*.mkv;*.mov;*.webm;*.avi;*.*'
  $dlg.Multiselect = $false
  if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
    throw "Canceled by user."
  }
  return $dlg.FileName
}

function Convert-ToWav16k([string]$inPath) {
  $wav = [IO.Path]::ChangeExtension($inPath, '.wav')
  & $FfmpegExe -y -i "$inPath" -ar 16000 -ac 1 -vn "$wav" | Out-Null
  if (-not (Test-Path $wav)) { throw "ffmpeg failed to produce wav: $wav" }
  return $wav
}

function Run-Whisper([string]$wavPath) {
  $log = "$wavPath.whisper.log"
  $args = @('-m', $ModelPath, '-f', $wavPath, '-l', 'auto', '-otxt')
  & $WhisperExe @args | Tee-Object -FilePath $log | Out-Null

  $txt = "$wavPath.txt"
  if (-not (Test-Path $txt)) {
    throw "Transcription file not found: $txt. See log: $log"
  }

  $langMatch = (Select-String -Path $log -Pattern 'auto-detected language:\s+(\w+)' -AllMatches).Matches
  $lang = if ($langMatch.Count) { $langMatch[0].Groups[1].Value } else { 'unknown' }

  [PSCustomObject]@{ TextPath = $txt; Lang = $lang; LogPath = $log }
}

function Ensure-Argos-Packages([string]$src, [string]$dst) {
  try { & $ArgosCli --download-package $src $dst | Out-Null } catch {}
  if ($src -ne 'en' -and $dst -ne 'en') {
    try { & $ArgosCli --download-package $src en | Out-Null } catch {}
    try { & $ArgosCli --download-package en $dst | Out-Null } catch {}
  }
}

function Translate-Text([string]$inTxt, [string]$srcLang, [string]$dstLang) {
  Ensure-Argos-Packages $srcLang $dstLang
  $outTxt = [IO.Path]::ChangeExtension($inTxt, ".$dstLang.txt")

  $ok = $true
  try { & $ArgosCli --from $srcLang --to $dstLang -i "$inTxt" -o "$outTxt" } catch { $ok = $false }
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outTxt)) { $ok = $false }

  if (-not $ok -and $srcLang -ne 'en' -and $dstLang -ne 'en') {
    $tmp = [IO.Path]::ChangeExtension($inTxt, '.en.tmp.txt')
    & $ArgosCli --from $srcLang --to en -i "$inTxt" -o "$tmp"
    & $ArgosCli --from en --to $dstLang -i "$tmp" -o "$outTxt"
    Remove-Item $tmp -ErrorAction SilentlyContinue
  }

  if (-not (Test-Path $outTxt)) { throw "Argos failed to produce: $outTxt" }
  return $outTxt
}

try {
  Test-Tool $WhisperExe "Build whisper.cpp or fix path."
  if (-not (Test-Path $ModelPath)) { throw "Model not found: $ModelPath" }
  Test-Tool $FfmpegExe "Install: winget install Gyan.FFmpeg"

  if (-not $Path) { $Path = Pick-File }
  if (-not (Test-Path $Path)) { throw "File not found: $Path" }
  Write-Host "Input: $Path" -ForegroundColor Cyan

  $wav = Convert-ToWav16k $Path
  Write-Host "WAV:   $wav" -ForegroundColor DarkCyan

  $res = Run-Whisper $wav
  Write-Host "Transcript: $($res.TextPath)" -ForegroundColor Green
  Write-Host "Detected language: $($res.Lang)" -ForegroundColor Yellow

  $needTranslate = $false
  $target = $Translate
  if ($Translate -eq 'auto') {
    if ($res.Lang -notin @('ru','uk')) { $needTranslate = $true; $target = 'ru' }
  } elseif ($Translate -in @('ru','uk') -and $res.Lang -ne $Translate) {
    $needTranslate = $true
  }

  if ($needTranslate) {
    Write-Host "Translating to: $target ..." -ForegroundColor Magenta
    $out = Translate-Text $res.TextPath $res.Lang $target
    Write-Host "Done: $out" -ForegroundColor Green
  } else {
    Write-Host "Translation skipped." -ForegroundColor DarkGray
  }
}
catch {
  Write-Error $_.Exception.Message
  exit 1
}
