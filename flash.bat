@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul
rem ============================================================
rem   Xiaomi MIX 2S (xiaomi-polaris) Debian 13 console flash tool - Windows
rem   Usage: double-click flash.bat. The phone may already be in fastboot,
rem          or in adb mode (script will reboot it to fastboot for you).
rem   WARNING: this will erase the userdata partition
rem ============================================================

set "HERE=%~dp0"
set "FASTBOOT=%HERE%tools\windows\fastboot.exe"
set "ADB=%HERE%tools\windows\adb.exe"
set "BOOT_IMG=%HERE%images\boot.img"
rem NOTE: file is named .img but the content is a pre-built Android sparse image
set "ROOTFS_IMG=%HERE%images\xiaomi-polaris.img"

echo.
echo ==== Xiaomi MIX 2S Debian 13 console flasher ====
echo.

if not exist "%FASTBOOT%"  ( echo [x] missing %FASTBOOT%  & goto :end )
if not exist "%BOOT_IMG%"  ( echo [x] missing %BOOT_IMG%  & goto :end )
if not exist "%ROOTFS_IMG%" ( echo [x] missing %ROOTFS_IMG% & goto :end )

rem ---- step 1: find fastboot device; if none, try adb -> reboot bootloader ----
echo [+] looking for fastboot device ...
call :wait_fastboot 1
if not errorlevel 1 goto :have_fastboot

echo [!] no fastboot device, trying adb ...
set "ADBDEV="
for /f "skip=1 tokens=1,2" %%a in ('"%ADB%" devices 2^>nul') do (
    rem this system's adbd reports state "host" instead of "device" in adb
    if "%%b"=="device" if not defined ADBDEV set "ADBDEV=%%a"
    if "%%b"=="host" if not defined ADBDEV set "ADBDEV=%%a"
)
if not defined ADBDEV goto :manual

echo [+] adb device found: !ADBDEV! , rebooting to bootloader ...
"%ADB%" reboot bootloader >nul 2>&1
rem this bootloader can take 30-40s to enumerate fastboot after an adb reboot,
rem so poll for up to 60 seconds (one check per second)
call :wait_fastboot 60
if not errorlevel 1 goto :have_fastboot

echo [!] device did not enter fastboot within 60 seconds.
goto :manual

:have_fastboot
"%FASTBOOT%" devices
"%FASTBOOT%" getvar product 2>&1 | findstr /i "product" >nul
if errorlevel 1 goto :manual

echo.
echo [!] WARNING: all data on userdata will be ERASED.
set /p ans="Type yes to continue: "
if /i not "!ans!"=="yes" ( echo cancelled. & goto :end )

echo.
echo [+] flashing boot.img -^> boot
"%FASTBOOT%" flash boot "%BOOT_IMG%"
if errorlevel 1 ( echo [x] flash boot failed & goto :end )

echo.
echo [+] erasing userdata partition first - the bootloader never writes
echo     all-zero data, so the partition must be zeroed before flashing ...
"%FASTBOOT%" erase userdata
if errorlevel 1 ( echo [x] erase userdata failed & goto :end )

echo.
echo [+] flashing xiaomi-polaris.img (sparse) -^> userdata  (image about 1.2G, please wait)
"%FASTBOOT%" flash userdata "%ROOTFS_IMG%"
if errorlevel 1 ( echo [x] flash userdata failed & goto :end )

echo.
echo [+] done, booting the system ...
rem prefer "fastboot reboot". This bootloader occasionally accepts reboot but
rem falls back to fastboot instead of booting, and the host fastboot process can
rem hang forever, so fall back to "fastboot continue" if reboot fails. NOTE: the
rem phone commits the flashed data to UFS here, which can take several minutes
rem (screen may go dark then light up again) - this is normal, just wait.
"%FASTBOOT%" reboot
if errorlevel 1 (
    echo [!] fastboot reboot failed, falling back to continue ...
    "%FASTBOOT%" continue
)
echo     (if the phone stays in fastboot, hold Power 12-15s to reset; data is written)

echo.
echo [+] Finished. First boot auto-grows the root fs to the whole userdata partition
echo     (and generates SSH keys), so it may take 1-2 minutes.
echo     SSH: ssh user@172.16.42.1   password: password
goto :end

:manual
echo.
echo [!] No fastboot device detected. Please enter fastboot mode manually:
echo     - Power off, then hold [Volume Down + Power] until fastboot appears
echo     - If the phone runs this system: sudo systemctl reboot --reboot-argument=bootloader
echo     - If the phone runs Android: adb reboot bootloader
goto :end

rem ---- wait_fastboot <seconds>: poll "fastboot devices" once per second ----
:wait_fastboot
set /a _n=0
:wf_loop
set "FBDEV="
for /f "tokens=1" %%d in ('"%FASTBOOT%" devices 2^>nul') do set "FBDEV=%%d"
if defined FBDEV exit /b 0
set /a _n+=1
if !_n! geq %~1 exit /b 1
ping -n 2 127.0.0.1 >nul
goto :wf_loop

:end
echo.
pause
endlocal
