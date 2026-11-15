@echo off
rem Command-line fallback: auto-detect serial port, wait for ROM download mode,
rem write 4 images, retry per segment on failure. Uses local esptool 4.8.1.
cd /d "%~dp0"
python flash_cli.py %*
pause
