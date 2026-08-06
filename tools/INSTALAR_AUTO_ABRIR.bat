@echo off
REM Instala el autoarranque de IZC al iniciar Windows + protocolo izc: para despertar el servidor.
cd /d "%~dp0"

echo Instalando auto-inicio de IZC...
echo - Servidores en http://127.0.0.1:8080 y http://127.0.0.1:5500
echo - Se abre al iniciar sesion en Windows
echo - Si :5500 ya lo usa Live Server de VS Code, se respeta y no se pisa
echo.

wscript //nologo "%~dp0ABRIR.vbs"

set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
copy /Y "%~dp0ABRIR.vbs" "%STARTUP%\IZC_ABRIR.vbs" >nul
if errorlevel 1 (
  echo ERROR: no se pudo copiar al inicio de Windows.
  pause
  exit /b 1
)

if exist "%STARTUP%\IZC_Servidor.vbs" (
  del "%STARTUP%\IZC_Servidor.vbs" >nul
  echo Se reemplazo el auto-inicio anterior del solo-servidor.
)

set "PROTO=%~dp0ABRIR_PROTOCOLO.bat"
reg add "HKCU\Software\Classes\izc" /ve /d "URL:IZC Protocol" /f >nul
reg add "HKCU\Software\Classes\izc" /v "URL Protocol" /d "" /f >nul
reg add "HKCU\Software\Classes\izc\DefaultIcon" /ve /d "shell32.dll,13" /f >nul
reg add "HKCU\Software\Classes\izc\shell\open\command" /ve /d "\"%PROTO%\" \"%%1\"" /f >nul
if errorlevel 1 (
  echo AVISO: no se pudo registrar el protocolo izc: ^(el autoarranque si quedo instalado^).
) else (
  echo Protocolo izc: registrado.
)

echo.
echo Listo.
echo - IZC se abrira solo al encender el PC / iniciar sesion
echo - Tambien: tools\ABRIR.bat  ^(enciende :8080 y :5500^)
echo - Si Live Server ya ocupa :5500, IZC solo asegura :8080
echo.
if /I not "%~1"=="/silent" pause
