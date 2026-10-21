@echo off
setlocal EnableExtensions
title boot_narrator - Auto Narrator for Windows Setup
rem Make Narrator start by itself when Windows Setup opens from USB.
rem Run as Administrator. No beeps, no boot.wim backup. Every step prints a line. The window always waits at the end.
rem Default work folder is C:\work (needs C:\work\sources\boot.wim). The mount folder is C:\MountBoot.
rem Optional: boot_narrator.bat "D:\other_media"  "D:\path\autounattend.xml"

set "work=C:\work"
if not "%~1"=="" set "work=%~1"
set "bootWim=%work%\sources\boot.wim"
set "mount=C:\MountBoot"
set "here=%~dp0"
set "unattend=%here%autounattend.xml"
if not "%~2"=="" set "unattend=%~2"
set "step=0"

echo ===== boot_narrator.bat started =====
echo Work folder: %work%
echo Script folder: %here%

set "step=1"
echo [Step 1 of 9] Checking Administrator rights.
net session >nul 2>&1
if not "%errorlevel%"=="0" goto :e_admin
echo OK: running as Administrator.

set "step=2"
echo [Step 2 of 9] Checking required files.
if not exist "%bootWim%" goto :e_nowim
echo OK: found %bootWim%
if not exist "%here%patch_setup_image.ps1" goto :e_nops
echo OK: found patch_setup_image.ps1

set "step=3"
echo [Step 3 of 9] Removing any old boot.wim backup so it is not added to the ISO.
for %%F in ("%work%\sources\*.bak" "%work%\*.bak") do (echo Deleting backup file %%~F & del /f /q "%%~F")
if exist "%bootWim%.bak" goto :e_del
echo OK: no .bak backup files left in %work% and %work%\sources.

set "step=4"
echo [Step 4 of 9] Preparing mount folder %mount%.
dism /Unmount-Image /MountDir:"%mount%" /Discard >nul 2>&1
dism /Cleanup-Wim >nul 2>&1
if exist "%mount%" rmdir /s /q "%mount%" >nul 2>&1
mkdir "%mount%"
if not "%errorlevel%"=="0" goto :e_mkdir
attrib -r "%bootWim%" >nul 2>&1
echo OK: mount folder is ready.

set "step=5"
echo [Step 5 of 9] Mounting boot.wim index 2. This can take a minute.
dism /Mount-Image /ImageFile:"%bootWim%" /Index:2 /MountDir:"%mount%"
if not "%errorlevel%"=="0" goto :e_mount
echo OK: index 2 mounted.

set "step=6"
echo [Step 6 of 9] Patching the Setup image.
if exist "%here%debloat_config.txt" goto :s6_cfg
powershell -NoProfile -ExecutionPolicy Bypass -File "%here%patch_setup_image.ps1" -Mount "%mount%"
goto :s6_done
:s6_cfg
powershell -NoProfile -ExecutionPolicy Bypass -File "%here%patch_setup_image.ps1" -Mount "%mount%" -Config "%here%debloat_config.txt"
:s6_done
if not "%errorlevel%"=="0" goto :e_patch
echo OK: patch applied.

set "step=7"
echo [Step 7 of 9] Saving changes into boot.wim. This can take a minute.
dism /Unmount-Image /MountDir:"%mount%" /Commit
if "%errorlevel%"=="0" goto :s7_ok
echo NOTE: DISM saved the image but could not recreate the empty folder %mount%. Error code %errorlevel%, shown as 0xc1420117 above.
echo This is usually Windows Defender or another program scanning %mount%. Add %mount% to the Defender exclusions to avoid it.
echo It is harmless if Step 8 passes. Cleaning up now.
dism /Cleanup-Wim
goto :s8
:s7_ok
echo OK: changes saved.

:s8
set "step=8"
echo [Step 8 of 9] Verifying boot.wim by mounting it read-only.
if exist "%mount%" rmdir /s /q "%mount%" >nul 2>&1
mkdir "%mount%" >nul 2>&1
dism /Mount-Image /ImageFile:"%bootWim%" /Index:2 /MountDir:"%mount%" /ReadOnly
if not "%errorlevel%"=="0" goto :e_verify
if not exist "%mount%\Windows\System32\start_narrator.cmd" goto :e_verify2
echo OK: start_narrator.cmd is inside boot.wim index 2.
if exist "%mount%\Windows\System32\winpeshl.ini" (echo Info: winpeshl.ini is present in the image.) else (echo Info: no winpeshl.ini in the image.)
if exist "%mount%\Windows\System32\setup_hook.cmd" (echo Info: setup_hook.cmd is present, so the Setup CmdLine hook is in place.) else (echo Info: no setup_hook.cmd, so the Setup CmdLine hook is not in place.)
dism /Unmount-Image /MountDir:"%mount%" /Discard >nul 2>&1
dism /Cleanup-Wim >nul 2>&1
if exist "%mount%" rmdir /s /q "%mount%" >nul 2>&1
echo OK: verification finished and the mount was released.

set "step=9"
echo [Step 9 of 9] Copying autounattend.xml to the media root.
if not exist "%unattend%" goto :s9_skip
copy /y "%unattend%" "%work%\autounattend.xml" >nul
if not "%errorlevel%"=="0" goto :e_copy
echo OK: copied %unattend% to %work%\autounattend.xml
goto :done
:s9_skip
echo SKIPPED: no autounattend.xml found at %unattend%

:done
echo.
echo ===== SUCCESS. All 9 steps finished. =====
echo Diagnostic details were saved to C:\boot_diag.txt
echo At boot you should hear a beep when the Narrator helper starts, and two beeps when Narrator is running. If Narrator is silent, read narrator_log.txt in the USB drive root.
echo This script only patches boot.wim. It does NOT make the media smaller.
echo Next step for old PCs: run debloat_install_image.bat. Otherwise put the media folder on a bootable USB drive and test it.
echo Press any key to close this window.
pause >nul
exit /b 0

:e_admin
echo ERROR: not running as Administrator. Right-click the file and choose Run as administrator.
goto :fail
:e_nowim
echo ERROR: boot.wim not found at %bootWim%
echo Put the extracted ISO files in %work% so that %work%\sources\boot.wim exists.
goto :fail
:e_nops
echo ERROR: patch_setup_image.ps1 must be in the same folder as this file: %here%
goto :fail
:e_del
echo ERROR: could not delete %bootWim%.bak
goto :fail
:e_mkdir
echo ERROR: could not create %mount%
goto :fail
:e_mount
echo ERROR: mount failed. Check the dism lines above. Index 2 must exist in boot.wim.
goto :fail
:e_patch
echo ERROR: patch failed. Discarding changes so boot.wim stays unchanged.
dism /Unmount-Image /MountDir:"%mount%" /Discard
goto :fail
:e_verify
echo ERROR: could not mount boot.wim to verify it. Run: dism /Cleanup-Wim  then run this file again.
goto :fail
:e_verify2
echo ERROR: start_narrator.cmd is missing in boot.wim, so the changes were NOT saved. Run this file again.
dism /Unmount-Image /MountDir:"%mount%" /Discard >nul 2>&1
dism /Cleanup-Wim >nul 2>&1
goto :fail
:e_copy
echo ERROR: could not copy autounattend.xml. boot.wim itself was patched and verified.
goto :fail

:fail
echo.
echo ===== FAILED at step %step% of 9. =====
echo Press any key to close this window.
pause >nul
exit /b 1
