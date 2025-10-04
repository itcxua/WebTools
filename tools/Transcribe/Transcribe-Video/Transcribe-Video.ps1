# Transcribe-Video-Ctools.ps1
# ��������� ��������� ������������� � �������
# Windows 11, PowerShell 5.1+

Add-Type -AssemblyName System.Windows.Forms

# ==== ��������� ����� ====
$toolsDir = "C:\tools"
$ffmpeg  = Join-Path $toolsDir "ffmpeg\bin\ffmpeg.exe"
$whisper = Join-Path $toolsDir "whisper.cpp\main.exe" # ��� ���� � faster-whisper
$model   = Join-Path $toolsDir "whisper.cpp\models\ggml-medium.bin"

$python  = Join-Path $toolsDir "argos-translate\env\Scripts\python.exe"
# ���� � argostranslate CLI ����� Python
$ArgosModule = "argostranslate.translate"

# ==== �������� ����� ====
foreach ($p in @($ffmpeg, $whisper, $model, $python)) {
    if (-not (Test-Path $p)) {
        Write-Host "ERROR: Required file not found: $p" -ForegroundColor Red
        exit
    }
}

# ==== ���-���� ====
$logDir = Join-Path $toolsDir "TranscribeLogs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("transcribe_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
function Log { param([string]$msg) "$((Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))`t$msg" | Tee-Object -FilePath $logFile -Append }

Log "=== START TRANSCRIBE SESSION ==="

# ==== GUI ����� ����� ====
$dlg = New-Object System.Windows.Forms.OpenFileDialog
$dlg.Filter = "Video files|*.mp4;*.mkv;*.mov;*.avi"
$dlg.Title = "�������� ����� ��� �������������"

if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Log "�������� �������������."
    exit
}
$inFile = $dlg.FileName
$dir    = Split-Path $inFile
$base   = [IO.Path]::GetFileNameWithoutExtension($inFile)
$wav    = Join-Path $dir ($base + ".wav")
Log "Input file: $inFile"

# ==== Stage 1: Extract audio ====
Log "Stage 1: Extract audio (ffmpeg)"
$ffmpegArgs = "-hide_banner -y -i `"$inFile`" -ar 16000 -ac 1 -vn `"$wav`""
$ffmpegLog = Join-Path $dir ($base + ".ffmpeg.log")
$proc = Start-Process -FilePath $ffmpeg -ArgumentList $ffmpegArgs -RedirectStandardError $ffmpegLog -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -ne 0 -or -not (Test-Path $wav)) {
    Log "ERROR: ffmpeg failed (code $($proc.ExitCode)). See $ffmpegLog"
    throw "������: ffmpeg �� ������ WAV."
}
Log "Audio extracted: $wav"

# ==== Stage 2: Transcribe ====
Log "Stage 2: Transcribe (whisper.cpp)"
$whisperLog = Join-Path $dir ($base + ".whisper.log")
$proc = Start-Process -FilePath $whisper `
    -ArgumentList "-m", "`"$model`"", "-f", "`"$wav`"", "-otxt", "-osrt", "-d", "`"$dir`"" `
    -RedirectStandardError $whisperLog -NoNewWindow -PassThru -Wait

# ����� TXT ����
$txtFiles = Get-ChildItem -Path $dir -Filter "$base*.txt"
if ($txtFiles.Count -eq 0) {
    Log "ERROR: Whisper did not create TXT."
    throw "������ �������������."
} else {
    $txt = $txtFiles[0].FullName
}
Log "Transcription created: $txt"

# ==== Stage 3: Preview text ====
$content = Get-Content $txt -Raw
$preview = $content.Substring(0, [Math]::Min(500, $content.Length))
Log "Text preview (first 500 chars): `n$preview"
Write-Host "`nPreview:" -ForegroundColor Yellow
Write-Host $preview

# ==== Stage 4: Translation ====
$choice = Read-Host "`n��������� �����? (1=���������, 2=�������, Enter=����������)"
switch ($choice) {
    "1" { $lang="uk" }
    "2" { $lang="ru" }
    default { $lang=$null }
}

if ($lang) {
    $outFile = Join-Path $dir ("$base.$lang.txt")
    $pyScript = @"
from argostranslate import translate
text = '''$content'''
translated = translate.translate_text(text, 'auto', '$lang')
with open(r'$outFile', 'w', encoding='utf-8') as f:
    f.write(translated)
"@
    Log "Stage 4: Translating to $lang via Argos Translate (Python)"
    $pyScript | & $python
    if (Test-Path $outFile) {
        Log "Translation saved: $outFile"
        Write-Host "`nTranslation saved: $outFile" -ForegroundColor Green
    } else {
        Log "ERROR: Translation failed."
        Write-Host "`nTranslation failed!" -ForegroundColor Red
    }
} else {
    Log "Translation skipped."
}

Log "=== TRANSCRIBE SESSION COMPLETED ==="
Write-Host "`nAll done! Logs saved to $logFile" -ForegroundColor Cyan
