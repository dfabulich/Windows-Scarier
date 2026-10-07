@echo off
rem Runs build.ps1 without changing the machine's PowerShell execution
rem policy, which blocks .ps1 scripts by default.  Arguments are passed
rem through, e.g. "build -Configuration Debug" or "build -Rebuild".
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
