@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0claude-proxy.ps1" %*
