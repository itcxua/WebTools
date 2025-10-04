@echo off
setlocal
set "PS1=%~dp0Transcribe-Picker.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
pause
