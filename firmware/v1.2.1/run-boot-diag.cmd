@echo off
chcp 65001 >nul
title AlphaPi OneS boot diagnosis
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ones_boot_diag.ps1" %*
if errorlevel 1 pause
