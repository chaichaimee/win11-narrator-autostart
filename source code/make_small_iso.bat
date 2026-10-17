@echo off
setlocal EnableExtensions
title make_small_iso - shrink install image and build a bootable ISO
rem Run as Administrator, AFTER boot_narrator.bat. No beeps. The window always waits at the end.
rem Keeps ONE edition, compresses it with recovery compression (smallest), builds a UEFI ISO.
rem Default media folder C:\work. ISO goes to C:\iso_out\Win11_lite.iso (outside the media folder).
rem oscdimg.exe is downloaded automatically from Microsoft if it is missing (get_oscdimg.ps1).
rem Optional: make_small_iso.bat "C:\work" "C:\iso_out\name.iso" "C:\path\oscdimg.exe"

set "work=C:\work"
if not "%~1"=="" set "work=%~1"
set "iso=C:\iso_out\Win11_lite.iso"
if not "%~2"=="" set "iso=%~2"
set "here=%~dp0"
set "step=0"
set "wim=%work%\sources\install.wim"
set "esd=%work%\sources\install.esd"
set "tmpdir=C:\iso_tmp"
set "newesd=%tmpdir%\install.esd"

echo ===== make_small_iso.bat started =====
echo Media folder: %work%
echo ISO file: %iso%

set "step=1"
echo [Step 1 of 6] Checking Administrator rights.
net session >nul 2>&1
if not "%errorlevel%"=="0" goto :e_admin
echo OK: running as Administrator.

set "step=2"
echo [Step 2 of 6] Looking for oscdimg.exe. It is downloaded automatically if missing.
set "osc="
if not "%~3"=="" if exist "%~3" set "osc=%~3"
if defined osc goto :s2_ok
if exist "%here%oscdimg.exe" set "osc=%here%oscdimg.exe"
if defined osc goto :s2_ok
if exist "C:\iso_tools\oscdimg.exe" set "osc=C:\iso_tools\oscdimg.exe"
if defined osc goto :s2_ok
for %%P in ("%ProgramFiles(x86)%\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe" "%ProgramFiles%\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe") do if exist %%P set "osc=%%~P"
if defined osc goto :s2_ok
echo Not found on this PC. Downloading oscdimg.exe from Microsoft, the same way Tiny11Builder does.
if not exist "%here%get_oscdimg.ps1" goto :e_osc
powershell -NoProfile -ExecutionPolicy Bypass -File "%here%get_oscdimg.ps1" -Dest "C:\iso_tools\oscdimg.exe"
if exist "C:\iso_tools\oscdimg.exe" set "osc=C:\iso_tools\oscdimg.exe"
if not defined osc goto :e_osc
:s2_ok
echo OK: using %osc%

set "step=3"
echo [Step 3 of 6] Checking the install image.
if not exist "%work%\sources\boot.wim" goto :e_media
if exist "%esd%" goto :s3_skip
if not exist "%wim%" goto :e_noinst
set "cnt=0"
for /f %%N in ('dism /English /Get-WimInfo /WimFile:"%wim%" ^| find /c "Index :"') do set "cnt=%%N"
if "%cnt%"=="1" goto :s3_single
echo Found install.wim with %cnt% editions:
dism /English /Get-WimInfo /WimFile:"%wim%" | findstr /i "Index Name"
set "idx=1"
set /p idx=Type the Index number of the edition to keep and press Enter. Just Enter means 1: 
echo Keeping index %idx%.
set "mode=M"
set /p mode=Compression. Press Enter for Max WIM, faster. Type R for Recovery ESD, smallest, 30 to 100 minutes: 

set "step=4"
echo [Step 4 of 6] Exporting that edition. Max WIM can take a few minutes, Recovery ESD up to 100 minutes. Keep this window open.
:s4_go
echo Clearing read-only flags on the media folder.
attrib -r -s -h "%work%\*" /s /d >nul 2>&1
if exist "%tmpdir%" rmdir /s /q "%tmpdir%" >nul 2>&1
mkdir "%tmpdir%\scratch"
if not exist "%tmpdir%\scratch" goto :e_tmpdir
echo Working folder for the new file: %tmpdir%. It needs about 6 GB free on C:.
if /i "%mode%"=="R" goto :s4_esd
echo Mode: Max WIM.
dism /Export-Image /SourceImageFile:"%wim%" /SourceIndex:%idx% /DestinationImageFile:"%tmpdir%\install.wim" /Compress:max /ScratchDir:"%tmpdir%\scratch"
if not "%errorlevel%"=="0" goto :e_export
move /y "%tmpdir%\install.wim" "%work%\sources\install_new.wim" >nul
if not "%errorlevel%"=="0" goto :e_move
del /f /q "%wim%"
if exist "%wim%" goto :e_delwim
ren "%work%\sources\install_new.wim" install.wim
if not "%errorlevel%"=="0" goto :e_move
goto :s4_done
:s4_esd
echo Mode: Recovery ESD.
dism /Export-Image /SourceImageFile:"%wim%" /SourceIndex:%idx% /DestinationImageFile:"%newesd%" /Compress:recovery /ScratchDir:"%tmpdir%\scratch"
if not "%errorlevel%"=="0" goto :e_export
move /y "%newesd%" "%esd%" >nul
if not "%errorlevel%"=="0" goto :e_move
del /f /q "%wim%"
if exist "%wim%" goto :e_delwim
:s4_done
rmdir /s /q "%tmpdir%" >nul 2>&1
echo OK: the install image now holds one edition. The old multi-edition file was removed.
goto :s5
:s3_single
echo install.wim already has one edition.
set "mode=S"
set /p mode=Press Enter to skip, or type R to recompress it as Recovery ESD, the smallest, 30 to 100 minutes: 
if /i not "%mode%"=="R" goto :s3_skip
set "idx=1"
set "step=4"
goto :s4_go
:s3_skip
echo OK: the install image already has one edition, or it is an ESD. Skipping the export.
set "step=4"
echo [Step 4 of 6] Skipped, nothing to export.

:s5
:s3_esd
echo OK: install.esd already exists.
set "step=4"
echo [Step 4 of 6] Skipped, nothing to export.

:s5
set "step=5"
echo [Step 5 of 6] Cleaning leftovers that would make the ISO bigger.
for %%F in ("%work%\sources\*.bak" "%work%\*.bak") do (echo Deleting backup file %%~F & del /f /q "%%~F")
echo OK: no .bak backup files left in the media folder.
if exist "%esd%" for %%S in ("%esd%") do echo install.esd size in bytes: %%~zS
if exist "%wim%" for %%S in ("%wim%") do echo install.wim size in bytes: %%~zS

set "step=6"
echo [Step 6 of 6] Building the ISO. This can take a few minutes.
if not exist "%work%\efi\microsoft\boot\efisys.bin" goto :e_efi
if not exist "C:\iso_out" mkdir "C:\iso_out"
if exist "%iso%" goto :e_exists
if exist "%work%\boot\etfsboot.com" goto :s6_both
"%osc%" -m -o -u2 -udfver102 -lWIN11_LITE -bootdata:1#pEF,e,b"%work%\efi\microsoft\boot\efisys.bin" "%work%" "%iso%"
goto :s6_check
:s6_both
"%osc%" -m -o -u2 -udfver102 -lWIN11_LITE -bootdata:2#p0,e,b"%work%\boot\etfsboot.com"#pEF,e,b"%work%\efi\microsoft\boot\efisys.bin" "%work%" "%iso%"
:s6_check
if not "%errorlevel%"=="0" goto :e_iso
for %%I in ("%iso%") do echo ISO size in bytes: %%~zI
powershell -NoProfile -Command "'ISO size in GB: ' + [math]::Round((Get-Item '%iso%').Length/1GB,2)"
echo.
echo ===== SUCCESS. ISO is at %iso% =====
echo If install.wim or install.esd is bigger than 4 GB, a FAT32 USB cannot hold it. Use Rufus, which handles this.
echo Press any key to close this window.
pause >nul
exit /b 0

:e_admin
echo ERROR: not running as Administrator.
goto :fail
:e_osc
echo ERROR: oscdimg.exe was not found and the automatic download did not work.
echo Check the internet connection and that get_oscdimg.ps1 is in the same folder as this file: %here%
echo Other ways: install the Windows ADK Deployment Tools, or copy oscdimg.exe into %here%, or pass its full path as the third argument.
goto :fail
:e_media
echo ERROR: %work%\sources\boot.wim not found. Is this the extracted media folder?
goto :fail
:e_noinst
echo ERROR: neither install.wim nor install.esd is in %work%\sources
goto :fail
:e_export
echo ERROR: export failed. install.wim was not touched.
echo Attributes of install.wim:
attrib "%wim%"
echo Last lines of the DISM log, send these to Claude:
powershell -NoProfile -Command "Get-Content 'C:\Windows\Logs\DISM\dism.log' -Tail 25"
goto :fail
:e_tmpdir
echo ERROR: could not create %tmpdir%. Check free space on C:.
goto :fail
:e_delwim
echo ERROR: could not delete install.wim.
goto :fail
:e_move
echo ERROR: could not move the new image into %work%\sources. The old install.wim was kept if it still exists.
goto :fail
:e_efi
echo ERROR: %work%\efi\microsoft\boot\efisys.bin is missing, so a UEFI ISO cannot be built.
goto :fail
:e_exists
echo ERROR: %iso% already exists. Delete it or pass another name as the second argument.
goto :fail
:e_iso
echo ERROR: oscdimg failed. See the lines above.
goto :fail

:fail
echo.
echo ===== FAILED at step %step% of 6. =====
echo Press any key to close this window.
pause >nul
exit /b 1
