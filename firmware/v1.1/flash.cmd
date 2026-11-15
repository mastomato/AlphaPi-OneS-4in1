@echo off
rem Recommended path: browser flasher (Web Serial, no esptool install needed).
rem This shortcut launches the local http server and opens the flasher page.
cd /d "%~dp0"
call "%~dp0start-web-flasher.cmd"
