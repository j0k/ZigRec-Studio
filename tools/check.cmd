@echo off
rem Проверка проекта одной командой: форматирование, сборка, тесты.
rem Возвращает 0 только если прошло всё. Задумано как единственный способ
rem сказать «работает» — без «запусти и посмотри».
setlocal enabledelayedexpansion
cd /d "%~dp0.."

rem Zig из PATH, иначе из установки winget: после winget install PATH
rem обновляется только в новых окнах, а проверка должна работать сразу.
set "ZIG="
for /f "delims=" %%i in ('where zig 2^>nul') do if not defined ZIG set "ZIG=%%i"
if not defined ZIG if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links\zig.exe" set "ZIG=%LOCALAPPDATA%\Microsoft\WinGet\Links\zig.exe"
if not defined ZIG (
  rem dir /s ищет по ИМЕНИ файла от каталога: подстановка в середине пути не работает.
  for /f "delims=" %%i in ('dir /b /s "%LOCALAPPDATA%\Microsoft\WinGet\Packages\zig.exe" 2^>nul') do if not defined ZIG set "ZIG=%%i"
)
if not defined ZIG (
  echo [check] Zig не найден. Поставить: winget install --id zig.zig -e
  exit /b 127
)

for /f "delims=" %%v in ('"%ZIG%" version') do set "ZIGVER=%%v"
echo [check] zig %ZIGVER%  ^(%ZIG%^)

echo [check] формат
"%ZIG%" fmt --check build.zig src tools 2>nul
if errorlevel 1 (
  echo [check] ПРОВАЛ: код не отформатирован. Поправить: zig fmt build.zig src
  exit /b 1
)

echo [check] сборка
"%ZIG%" build
if errorlevel 1 (
  echo [check] ПРОВАЛ: сборка
  exit /b 1
)

echo [check] тесты
"%ZIG%" build test
if errorlevel 1 (
  echo [check] ПРОВАЛ: тесты
  exit /b 1
)

echo [check] релизная сборка
"%ZIG%" build -Doptimize=ReleaseFast
if errorlevel 1 (
  echo [check] ПРОВАЛ: релизная сборка
  exit /b 1
)

for %%f in ("zig-out\bin\zigrec.exe") do set "EXESIZE=%%~zf"
set /a EXEKB=%EXESIZE%/1024
echo [check] zigrec.exe: %EXEKB% КБ
"zig-out\bin\zigrec.exe" --version
if errorlevel 1 (
  echo [check] ПРОВАЛ: exe не запускается
  exit /b 1
)

echo [check] самопроверка захвата
"zig-out\bin\zigrec.exe" capture-smoke 60
if errorlevel 1 (
  echo [check] ПРОВАЛ: захват не снимает то, что показано
  exit /b 1
)

echo [check] ВСЁ ЗЕЛЁНОЕ
exit /b 0
