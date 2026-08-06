@echo off
REM Abre IZC: inicia servidores en :8080 y :5500, luego el navegador.
cd /d "%~dp0.."

if exist "%~dp0INICIAR_VIGILANCIA.vbs" (
  wscript //nologo "%~dp0INICIAR_VIGILANCIA.vbs"
)

wscript //nologo "%~dp0INICIAR_SERVIDOR.vbs"

REM Esperar a que el servidor 8080 responda (archivos e API)
set /a _n=0
:wait
set /a _n+=1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor_control.ps1" -Action health >nul 2>&1
if %ERRORLEVEL%==0 goto :open
if %_n% GEQ 12 goto :open
timeout /t 1 /nobreak >nul
goto :wait

:open
start "" "http://127.0.0.1:8080/index.html"
