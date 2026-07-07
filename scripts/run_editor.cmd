@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_editor.ps1"
exit /b %ERRORLEVEL%
