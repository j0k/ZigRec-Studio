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

echo [check] самопроверка кодирования
if not exist ".check" mkdir ".check"
"zig-out\bin\zigrec.exe" encode-smoke ".check\encode.mp4" 90
if errorlevel 1 (
  echo [check] ПРОВАЛ: mp4 не получился или получился негодным
  exit /b 1
)

rem Обратная проверка чужим декодером: наш файл распаковывает ffmpeg, а мы
rem читаем таймкоды из распакованных кадров. Своим декодером проверять себя же
rem — значит не заметить общей ошибки в обе стороны. ffmpeg нужен только для
rem проверки, в самой программе его нет.
set "FFMPEG="
for /f "delims=" %%i in ('where ffmpeg 2^>nul') do if not defined FFMPEG set "FFMPEG=%%i"
if not defined FFMPEG (
  for /f "delims=" %%i in ('dir /b /s "%LOCALAPPDATA%\Microsoft\WinGet\Packages\ffmpeg.exe" 2^>nul') do if not defined FFMPEG set "FFMPEG=%%i"
)
if not defined FFMPEG (
  echo [check] ffmpeg не найден — обратная проверка таймкодов пропущена
) else (
  "%FFMPEG%" -y -v error -i ".check\encode.mp4" -pix_fmt bgra -f rawvideo ".check\encode.raw"
  if errorlevel 1 (
    echo [check] ПРОВАЛ: чужой декодер не смог открыть наш mp4
    exit /b 1
  )
  "zig-out\bin\zigrec.exe" verify-raw ".check\encode.raw" 384 64
  if errorlevel 1 (
    echo [check] ПРОВАЛ: таймкоды не пережили кодирование
    exit /b 1
  )
)

rem Звук проверяем на синтезе, а не на живом микрофоне: микрофон у каждого свой
rem и шумит по-разному, а синус заданной амплитуды — проверяемое число.
if defined FFMPEG (
  echo [check] самопроверка звука на эталонных тонах
  if not exist ".check\audio" mkdir ".check\audio"
  call :tone 0.99 tone_0 -0.09
  if errorlevel 1 exit /b 1
  call :tone 0.5 tone_6 -6.02
  if errorlevel 1 exit /b 1
  call :tone 0.1 tone_20 -20.0
  if errorlevel 1 exit /b 1
  call :tone 0.001 tone_60 -60.0
  if errorlevel 1 exit /b 1
) else (
  echo [check] ffmpeg не найден — проверка звука на тонах пропущена
)

echo [check] ВСЁ ЗЕЛЁНОЕ
exit /b 0

goto :eof

rem %1 — амплитуда, %2 — имя, %3 — ожидаемый уровень в децибелах
:tone
"%FFMPEG%" -y -v error -f lavfi -i "aevalsrc=%~1*sin(2*PI*1000*t):d=1:s=48000" -c:a pcm_s16le ".check\audio\%~2.wav"
if errorlevel 1 (
  echo [check] ПРОВАЛ: не получилось сделать эталонный тон %~2
  exit /b 1
)
"zig-out\bin\zigrec.exe" audio-check ".check\audio\%~2.wav" %~3
if errorlevel 1 (
  echo [check] ПРОВАЛ: уровень тона %~2 не сошёлся
  exit /b 1
)
exit /b 0
