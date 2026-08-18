@echo off
setlocal

rem GoLiveBypass - abre o instalador em janela (sem terminal).
rem Basta dar dois cliques neste arquivo.
rem
rem O caminho nunca e embutido: %~dp0 e resolvido na hora, entao funciona em pastas com
rem espaco e com acento no nome de usuario.

set "GLB_SETUP=%~dp0GoLiveBypass-Setup.ps1"
set "GLB_URL=https://raw.githubusercontent.com/caue-r/GoLiveBypass/main/installer/GoLiveBypass-Setup.ps1"

if not exist "%GLB_SETUP%" (
    echo.
    echo   Baixando o instalador...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -UseBasicParsing -Uri $env:GLB_URL -OutFile $env:GLB_SETUP"
    if not exist "%GLB_SETUP%" (
        echo.
        echo   Nao consegui baixar o instalador. Verifique sua conexao.
        echo.
        pause
        exit /b 1
    )
)

rem Nada de -WindowStyle Hidden: o nCmdShow do processo e herdado pela primeira janela
rem criada, e ele esconderia a janela do instalador junto com o terminal. O proprio
rem GoLiveBypass-Setup.ps1 esconde o terminal dele assim que abre.
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%GLB_SETUP%"
exit /b 0
