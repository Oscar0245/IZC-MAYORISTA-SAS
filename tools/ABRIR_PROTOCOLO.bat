@echo off
REM Protocolo izc: — inicia el servidor; solo abre el navegador si no es "ensure".
cd /d "%~dp0"

set "ARG=%~1"
echo.%ARG%| findstr /I "ensure" >nul
if %ERRORLEVEL%==0 (
  wscript //nologo "%~dp0INICIAR_SERVIDOR.vbs"
  exit /b 0
)

call "%~dp0ABRIR.bat"
