#Requires -Version 5.1
[CmdletBinding()]
param(
  [string]$Path,
  [ValidateSet('off','ru','uk','auto')]
  [string]$Translate = 'auto'
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::UTF8

# --- CONFIG ---
$WhisperExe = 'C:\whisper.cpp\build\bin\Release\whisper-cli.exe'
$ModelPath  = 'C:\whisper.cpp\models\ggml-medium.bin'
$FfmpegExe  = 'ffmpeg'
$ArgosCli   = 'py -3.11 -m argostranslate.cli'
# --------------

function Pick-File {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = "Select audio/video file"
  $dlg.Filter = "Media|*.wav;*.mp3;*.ogg;*.opus;*.flac;*.aac;*.m4a;*.mp4;*.mkv;*.mov;*.webm;*.*"
  if ($dlg.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit }
  return $dlg.FileName
}

function Convert-ToWav([string]$inFile) {
  $outFile = "$inFile.wav"
  & $FfmpegExe -y -i "$inFile" -ar 16000 -ac 1 -vn "$outFile" | Out-Null
  if (-not (Test-Path $outFile)) { throw "ffmpeg failed." }
  return $outFile
}

function Run-Whisper([string]$wav) {
  $args = @("-m",$ModelPath,"-f",$wav,"-l","auto","-otxt")
  & $WhisperExe @args 2>&1 | Tee-Object "$wav.log"
  return "$wav.txt"
}

function Get-DetectedLang([string]$log) {
  $match = (Select-String -Path $log -Pattern "auto-detected language:\s+(\w+)").Matches
  if ($match.Count) { return $match[0].Groups[1].Value } else { return "unknown" }
}

function Translate-Text($txt,$src,$dst) {
  $out = [IO.Path]::ChangeExtension($txt, ".$dst.txt")
  & $ArgosCli --download-package $src $dst | Out-Null
  & $ArgosCli --from $src --to $dst -i "$txt" -o "$out"
  return $out
}

# --- MAIN ---
if (-not $Path) { $Path = Pick-File }
$wav  = Convert-ToWav $Path
$txt  = Run-Whisper $wav
$lang = Get-DetectedLang "$wav.log"

Write-Host "Detected language: $lang" -ForegroundColor Yellow
Write-Host "Transcript saved: $txt" -ForegroundColor Green

if ($Translate -eq 'auto' -and $lang -notin @('ru','uk')) {
  $out = Translate-Text $txt $lang 'ru'
  Write-Host "Translated to RU: $out" -ForegroundColor Cyan
}
elseif ($Translate -in @('ru','uk') -and $lang -ne $Translate) {
  $out = Translate-Text $txt $lang $Translate
  Write-Host "Translated to $Translate: $out" -ForegroundColor Cyan
}
else {
  Write-Host "No translation needed." -ForegroundColor DarkGray
}
