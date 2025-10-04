<# 
.SYNOPSIS
  Транскрибує аудіо у текст (з Telegram .ogg/.opus теж), з авто або явним вибором мови,
  з опціональним перекладом на RU/UK. 
  Потрібен OPENAI_API_KEY у змінній середовища.

.PARAMETER Input
  Шлях до аудіофайлу. Якщо не задано — відкриється діалог вибору файлу.

.PARAMETER Language
  Код мови ISO 639-1 (наприклад, "uk", "ru", "en"). 
  За замовчуванням "auto" (не передаємо параметр у API — авто-детект).

.PARAMETER TranslateTo
  Куди перекладати результат: "none" (без перекладу), "ru" або "uk". За замовчуванням "none".

.PARAMETER Model
  Модель для транскрипції: за замовчуванням "gpt-4o-transcribe".

.PARAMETER TranslateModel
  Модель для перекладу тексту: за замовчуванням "gpt-4o-mini".

.EXAMPLE
  .\Transcribe-Audio.ps1 -Input ".\voice.ogg" -Language auto -TranslateTo ru

.EXAMPLE
  .\Transcribe-Audio.ps1 -Language uk -TranslateTo none
#>

param(
  [string]$Input,
  [ValidateSet("auto","uk","ru","en","de","pl","fr","es")][string]$Language = "auto",
  [ValidateSet("none","ru","uk")][string]$TranslateTo = "none",
  [string]$Model = "gpt-4o-transcribe",
  [string]$TranslateModel = "gpt-4o-mini"
)

# ---------- Helpers ----------
function Get-ApiKey {
  $k = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY","User")
  if ([string]::IsNullOrWhiteSpace($k)) {
    $k = [Environment]::GetEnvironmentVariable("OPENAI_API_KEY","Machine")
  }
  if ([string]::IsNullOrWhiteSpace($k)) {
    Write-Error "OPENAI_API_KEY не знайдено. Встановіть:  setx OPENAI_API_KEY ""sk-..."""
    exit 1
  }
  return $k
}

function Ensure-FFmpeg {
  $ff = "ffmpeg.exe"
  $exists = $false
  try { $null = & $ff -version 2>$null; if ($LASTEXITCODE -eq 0) { $exists = $true } } catch {}
  if (-not $exists) {
    Write-Host "ffmpeg не знайдено. Спробую встановити через winget..."
    try {
      winget install --id Gyan.FFmpeg --silent --accept-package-agreements --accept-source-agreements
    } catch { }
    try { $null = & $ff -version 2>$null; if ($LASTEXITCODE -eq 0) { $exists = $true } } catch {}
    if (-not $exists) {
      Write-Warning "ffmpeg не встановлено. Продовжую — API зазвичай приймає .ogg/.opus напряму, але краще мати ffmpeg."
    }
  }
}

function Convert-IfNeeded {
  param([string]$Path)
  $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
  # Whisper API приймає .mp3, .mp4, .mpeg, .mpga, .m4a, .wav, .webm, .ogg тощо.
  # Якщо .ogg/.opus — інколи зручніше подати WAV 16k mono.
  if ($ext -in @(".ogg",".oga",".opus")) {
    $ffOk = $false
    try { $null = & ffmpeg.exe -version 2>$null; if ($LASTEXITCODE -eq 0) { $ffOk = $true } } catch {}
    if ($ffOk) {
      $out = [IO.Path]::ChangeExtension($Path, ".wav")
      Write-Host "Конвертація $Path -> $out (PCM 16kHz mono)..."
      & ffmpeg.exe -y -i "$Path" -ac 1 -ar 16000 -vn "$out" | Out-Null
      if ($LASTEXITCODE -eq 0 -and (Test-Path $out)) { return $out }
    }
  }
  return $Path
}

function Show-OpenFileDialog {
  Add-Type -AssemblyName System.Windows.Forms | Out-Null
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Title = "Виберіть аудіо"
  $dlg.Filter = "Audio|*.mp3;*.wav;*.m4a;*.aac;*.flac;*.ogg;*.opus;*.mp4;*.webm|All files|*.*"
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
  else { Write-Error "Файл не обрано."; exit 1 }
}

function Invoke-Multipart {
  param(
    [string]$Uri,
    [hashtable]$Fields,
    [string]$FilePath,
    [string]$FileFieldName,
    [string]$ApiKey
  )
  $handler = New-Object System.Net.Http.HttpClientHandler
  $client  = New-Object System.Net.Http.HttpClient($handler)
  $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue("Bearer",$ApiKey)

  $content = New-Object System.Net.Http.MultipartFormDataContent
  foreach ($k in $Fields.Keys) {
    $content.Add((New-Object System.Net.Http.StringContent([string]$Fields[$k])), $k)
  }
  $fs   = [System.IO.File]::OpenRead($FilePath)
  $name = [System.IO.Path]::GetFileName($FilePath)
  $fileContent = New-Object System.Net.Http.StreamContent($fs)
  $fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("application/octet-stream")
  $content.Add($fileContent, $FileFieldName, $name)

  $resp = $client.PostAsync($Uri, $content).Result
  $raw  = $resp.Content.ReadAsStringAsync().Result
  $fs.Dispose()
  if (-not $resp.IsSuccessStatusCode) {
    throw "API error $($resp.StatusCode): $raw"
  }
  return $raw
}

function Chat-Translate {
  param(
    [string]$Text,
    [string]$Target,     # "ru" або "uk"
    [string]$Model,
    [string]$ApiKey
  )
  $uri = "https://api.openai.com/v1/chat/completions"
  $body = @{
    model = $Model
    messages = @(
      @{ role="system"; content="You are a professional translator. Keep meaning and formatting. Do not add commentary." },
      @{ role="user";   content="Translate the following text to $Target (use natural, formal business style if ambiguous).`n---`n$Text" }
    )
    temperature = 0
  } | ConvertTo-Json -Depth 8

  $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers @{Authorization="Bearer $ApiKey"} -ContentType "application/json" -Body $body
  return $resp.choices[0].message.content
}

# ---------- MAIN ----------

$apiKey = Get-ApiKey
Ensure-FFmpeg

if ([string]::IsNullOrWhiteSpace($Input)) {
  $Input = Show-OpenFileDialog
}

if (-not (Test-Path $Input)) {
  Write-Error "Файл не знайдено: $Input"
  exit 1
}

$workFile = Convert-IfNeeded -Path $Input
$base = [IO.Path]::Combine([IO.Path]::GetDirectoryName($workFile), [IO.Path]::GetFileNameWithoutExtension($workFile))

# 1) Транскрипція
$transcribeUri = "https://api.openai.com/v1/audio/transcriptions"
$fields = @{
  model = $Model            # gpt-4o-transcribe
  response_format = "verbose_json"  # хочемо мову/сегменти
  temperature = "0"
}
if ($Language -ne "auto") {
  $fields["language"] = $Language
}

Write-Host "Надсилаю на транскрипцію ($Model)..."
try {
  $jsonRaw = Invoke-Multipart -Uri $transcribeUri -Fields $fields -FilePath $workFile -FileFieldName "file" -ApiKey $apiKey
} catch {
  Write-Error $_
  exit 1
}

# Збережемо повний verbose JSON
$verbosePath = "$base.transcribe.json"
[IO.File]::WriteAllText($verbosePath, $jsonRaw, [Text.Encoding]::UTF8)

# Дістанемо текст і (за наявності) autodetected language
$parsed = $null
try { $parsed = $jsonRaw | ConvertFrom-Json } catch {}
$finalText = $parsed.text
$detected  = $parsed.language
if (-not $finalText) { $finalText = [string]$jsonRaw }  # fallback

# Збережемо «чистий» текст транскрипту
$txtPath = "$base.txt"
[IO.File]::WriteAllText($txtPath, $finalText, [Text.Encoding]::UTF8)

Write-Host "Готово. Транскрибовано -> $txtPath"
if ($detected) { Write-Host "Автовизначена мова: $detected" }

# 2) Переклад (опціонально)
if ($TranslateTo -ne "none") {
  Write-Host "Перекладаю на '$TranslateTo' ($TranslateModel)..."
  try {
    $translated = Chat-Translate -Text $finalText -Target $TranslateTo -Model $TranslateModel -ApiKey $apiKey
    $tgtFile = "$base.$TranslateTo.txt"
    [IO.File]::WriteAllText($tgtFile, $translated, [Text.Encoding]::UTF8)
    Write-Host "Переклад збережено: $tgtFile"
  } catch {
    Write-Warning "Не вдалось перекласти: $_"
  }
}

Write-Host "Готово ✅"
Write-Host "Файли:"
Write-Host " - транскрипт: $txtPath"
Write-Host " - деталі (JSON): $verbosePath"
if ($TranslateTo -ne "none") { Write-Host " - переклад: $base.$TranslateTo.txt" }
