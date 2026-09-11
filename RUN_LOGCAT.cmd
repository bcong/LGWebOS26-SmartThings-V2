@echo off
cd /d "%~dp0"
set "CLI=%~dp0.tools\smartthings.exe"
if exist "%CLI%" goto runlocal
where smartthings >nul 2>nul
if %errorlevel%==0 goto runglobal
echo SmartThings CLI not found. Run RUN_INSTALL.cmd first.
pause
exit /b 1

:runlocal
"%CLI%" edge:drivers:logcat
pause
exit /b

:runglobal
smartthings edge:drivers:logcat
pause
