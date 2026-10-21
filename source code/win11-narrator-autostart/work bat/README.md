# win11-narrator-autostart

Make **Narrator start by itself** when Windows 11 Setup boots from a USB drive, so a blind or low-vision person knows Setup is ready without having to press **Win+Ctrl+Enter** blind.

The project is a small set of Windows batch and PowerShell scripts plus one answer file (`autounattend.xml`). They patch the Windows Setup boot image (`sources\boot.wim`, index 2) of a Windows 11 ISO that **you** supply, optionally shrink the install image, and rebuild a bootable ISO.

An **optional lightweight mode** (`debloat_install_image.bat`) can also remove unneeded apps, services and components from the install image for old, low-memory PCs, while protecting everything Narrator, audio, speech, language support and Windows Defender need. It is driven by one editable text file where a line starting with `#` means "keep this".

> **Status: experimental (v0.4.1).** Written for Windows 11 25H2 and 26H2 x64 media. Earlier versions of the Narrator auto-start were tested by the author on a Rufus-made USB drive and **did not start Narrator by themselves** (it stayed silent until Win+Ctrl+Enter was pressed). v0.4.0 changes the method (see [The Setup CmdLine hook](#the-setup-cmdline-hook)) and has **not yet been confirmed on real hardware**. The lightweight mode (`debloat_install_image`) completed all 10 steps on the author's PC with Windows 11 Pro media, but the resulting image has not yet been installed and tested. Always test in a virtual machine or on a spare PC before relying on the result. See [Known limitations](#known-limitations).

---

## Table of contents

1. [Why this exists](#why-this-exists)
2. [What it does and does not do](#what-it-does-and-does-not-do)
3. [What is in the repository](#what-is-in-the-repository)
4. [Requirements](#requirements)
5. [Quick start](#quick-start)
6. [Step-by-step guide](#step-by-step-guide)
   - [Lightweight image for old PCs (optional)](#lightweight-image-for-old-pcs-optional)
7. [How it works](#how-it-works)
8. [Script reference](#script-reference)
9. [Using it with Tiny11Builder or other tools](#using-it-with-tiny11builder-or-other-tools)
10. [Accessibility design of the scripts](#accessibility-design-of-the-scripts)
11. [Troubleshooting](#troubleshooting)
12. [Known limitations](#known-limitations)
13. [Safety notes](#safety-notes)
14. [Distributing this project to other people](#distributing-this-project-to-other-people)
15. [Contributing and reporting problems](#contributing-and-reporting-problems)
16. [Legal](#legal)
17. [License](#license)
18. [Changelog](#changelog)

---

## Why this exists

Windows Setup has a built-in screen reader, Narrator, but it does not start on its own. The documented way to start it is to press **Win+Ctrl+Enter** after the Setup window has appeared. A person who cannot see the screen gets no sound until they do that, and there is no way to know when the PC has finished booting into Setup. Pressing the shortcut too early does nothing, and pressing it after Narrator has already started turns Narrator off again.

This project removes the guesswork: after the PC boots from the USB drive, Narrator starts by itself, so the first thing you hear tells you Setup is ready.

## What it does and does not do

**It does:**

- Add a small helper script, `start_narrator.cmd`, to the Windows Setup boot image (`boot.wim`, index 2).
- Make the boot image run that helper at start-up, in the background, so Setup is never blocked.
- Make the helper wait (up to about 30 seconds) for the Windows Audio service before it launches `Narrator.exe`, and make sure Narrator is launched only once.
- Provide an `autounattend.xml` that starts Narrator a second way (from Setup's `windowsPE` pass) and again at first sign-in after installation.
- Write plain-text logs (`X:\narrator_log.txt` while booted into Setup, and `C:\boot_diag.txt` on the PC where you ran the script) so a failure can be diagnosed without seeing the screen.

**It does not:**

- Remove, disable, or change any Windows app, service, feature, driver, or setting by default. `boot_narrator.bat` and `autounattend.xml` contain no app or service removal commands. Removal happens only if you run the optional `debloat_install_image.bat`, and then only for items listed in `debloat_config.txt`.
- Touch audio, Narrator, speech, language, Windows Defender or Microsoft Store components in the optional lightweight mode. They are protected in the code and are skipped even if listed.
- Bypass the TPM, Secure Boot, RAM, storage or CPU-model checks, unless you leave `BypassHardwareChecks=1` in `debloat_config.txt` (the shipped default, see [Lightweight image](#lightweight-image-for-old-pcs-optional)). It never bypasses the Microsoft-account page.
- Skip or hide any Setup page. Setup stays fully interactive so it can be driven with Narrator.
- Download, bundle, or redistribute Windows. You must supply your own ISO.
- Change anything on your PC outside the folders named below (it needs administrator rights only because DISM does).
- Cover the first-run screens after installation (OOBE). Press **Win+Ctrl+Enter** there. See [Known limitations](#known-limitations).

## What is in the repository

All files must stay **together in one folder**. The scripts look for each other next to themselves.

- `boot_narrator.bat`: the main script. Mounts `boot.wim` index 2, patches it, saves it, verifies it, and copies `autounattend.xml` into the media folder.
- `patch_setup_image.ps1`: called by `boot_narrator.bat`. Does the actual patching and writes `C:\boot_diag.txt`.
- `autounattend.xml`: the Windows Setup answer file that starts Narrator.
- `debloat_install_image.bat` and `debloat_install_image.ps1`: optional. Remove the apps, services, capabilities and features listed in the config from the install image.
- `debloat_config.txt`: the one file you edit to choose what is removed. A line starting with `#` is kept.
- `.github/ISSUE_TEMPLATE/bug_report.md`: a bug-report form that asks for the right logs.
- `.gitattributes`, `.gitignore`, `LICENSE`.

## Requirements

On the PC where you run the scripts (the "build PC"):

- Windows 10 or Windows 11, 64-bit, with an administrator account. The build PC's DISM should be at least as new as the Windows version you are patching. The author used DISM 10.0.26100.
- PowerShell 5.1 (included with Windows).
- An **official Windows 11 x64 ISO** from Microsoft, extracted to a folder. The default folder is `C:\work`.
- Free disk space on `C:`: about 9 GB for the extracted ISO, plus about 8 GB of temporary space while `debloat_install_image.bat` exports and recompresses the install image.
- [Rufus](https://rufus.ie) (or another tool that writes a bootable UEFI USB from an ISO) to create the USB drive.
- A USB drive of at least 8 GB.

On the target PC: a PC that can boot Windows 11 Setup from USB, with working speakers or headphones. Narrator needs an audio device that Setup's boot environment supports.

## Quick start

For people who just want the commands. Details are in the next section.

1. Download the ZIP of this repository and extract it to a folder, for example `C:\win11-narrator-autostart`.
2. Extract your Windows 11 ISO into `C:\work` so that `C:\work\sources\boot.wim` exists.
3. Right-click `boot_narrator.bat`, choose **Run as administrator**, and wait for `SUCCESS. All 9 steps finished.`
4. (Optional, for old PCs) Run `debloat_install_image.bat` as administrator to remove unneeded apps and services. Edit `debloat_config.txt` first if you want to keep or remove other items.
5. Put the contents of `C:\work` on a bootable USB drive (see [Create the USB drive](#6-create-the-usb-drive)). **If you use Rufus, leave the boxes in its "Windows User Experience" dialog unticked, or copy `autounattend.xml` onto the drive after Rufus has finished.**
6. Boot the USB drive. Wait up to a minute. Narrator should start by itself.

## Step-by-step guide

### 1. Get the files

- Download this repository as a ZIP (**Code**, then **Download ZIP**) or from the **Releases** page, and extract it. Keep every file in the same folder. Folder names with spaces work.
- Download an official Windows 11 ISO from Microsoft's website.

### 2. Extract the ISO to `C:\work`

Open the ISO (double-click it to mount it) and copy everything to `C:\work`, or extract it with an archive tool. After this, these paths must exist:

- `C:\work\sources\boot.wim`
- `C:\work\sources\install.wim` (or `install.esd`)
- `C:\work\efi\microsoft\boot\efisys.bin`

You can use another folder. Pass it as the first argument to each script, for example `boot_narrator.bat "D:\media"`.

### 3. Prepare antivirus (recommended)

DISM mounts the boot image as a folder. Real-time scanning of that folder can make the final unmount report error `0xc1420117`. In Windows Security, add exclusions for `C:\work` and `C:\MountBoot` (and `C:\MountInstall` and `C:\iso_tmp` if you use `debloat_install_image.bat`). This is optional. The script verifies the result either way.

### 4. Run `boot_narrator.bat`

Right-click it and choose **Run as administrator**. (A normal double-click will stop at Step 1 with a clear message.) The window prints one line per step and stays open at the end. It does not beep.

Expected output, in order:

1. `[Step 1 of 9] Checking Administrator rights.`
2. `[Step 2 of 9] Checking required files.` It needs `C:\work\sources\boot.wim` and `patch_setup_image.ps1` next to the script.
3. `[Step 3 of 9] Removing any old boot.wim backup ...` Deletes `*.bak` files in the media folder so they are not packed into your ISO. **The script makes no backup of `boot.wim`.** Keep your original ISO.
4. `[Step 4 of 9] Preparing mount folder C:\MountBoot.`
5. `[Step 5 of 9] Mounting boot.wim index 2.`
6. `[Step 6 of 9] Patching the Setup image.` Prints what it found (for example `startnet.cmd`), what it changed, and a `RESULT:` line.
7. `[Step 7 of 9] Saving changes into boot.wim.` If DISM reports `0xc1420117`, the script prints a `NOTE` and cleans up. This is usually harmless. Step 8 decides.
8. `[Step 8 of 9] Verifying boot.wim by mounting it read-only.` Confirms `start_narrator.cmd` is really inside the saved image.
9. `[Step 9 of 9] Copying autounattend.xml to the media root.`

The last line is either `===== SUCCESS. All 9 steps finished. =====` or `===== FAILED at step N of 9. =====` with the reason on the lines before it.

### 5. (Optional) Make the install image lightweight

See [Lightweight image for old PCs](#lightweight-image-for-old-pcs-optional). In short: edit `debloat_config.txt` if you want, then right-click `debloat_install_image.bat` and choose **Run as administrator**. It asks which edition to keep, removes everything else, applies the removals, and recompresses `install.wim`.

Measured by the author with Windows 11 Pro from an 11-edition ISO: the original `install.wim` was 7.6 GB, and after this step the single-edition `install.wim` was 6.72 GB. There is no extra compression step. In the author's test the Recovery ESD option did not reduce the size meaningfully (the cause was not diagnosed), so it was removed from the project.

### 6. Create the USB drive

The project no longer builds an ISO for you. You need to turn the contents of `C:\work` into a bootable USB drive. Two ways:

**Way A: build an ISO, then write it with Rufus.** Microsoft's `oscdimg` tool (part of the Windows ADK "Deployment Tools") can build a bootable ISO from the folder. This is the command that an earlier version of this project used. It built an ISO on the author's PC; booting that ISO has not been reported yet:

```
oscdimg -m -o -u2 -udfver102 -lWIN11_LITE -bootdata:2#p0,e,bC:\work\boot\etfsboot.com#pEF,e,bC:\work\efi\microsoft\boot\efisys.bin C:\work C:\iso_out\Win11_lite.iso
```

If `C:\work\boot\etfsboot.com` does not exist, use UEFI only: `-bootdata:1#pEF,e,bC:\work\efi\microsoft\boot\efisys.bin`. Then write the ISO to a USB drive with Rufus.

**Way B: write the original ISO with Rufus, then copy files over it.** After Rufus finishes, copy these files from `C:\work` onto the USB drive and choose **Replace**:

- `sources\boot.wim` (the patched Setup image: **required**, it contains the Narrator start)
- `sources\install.wim` (only if you ran `debloat_install_image.bat`)
- `autounattend.xml` (to the root of the drive)

Check that the drive has `sources\install.wim` and no leftover `sources\install.swm`. The install image is larger than 4 GB, so the drive must be formatted as NTFS (Rufus does this automatically for large images). This way has not been verified by the author.

**About the Rufus dialog.** In Rufus 4.x the **Windows User Experience** dialog is not in the main window. It appears **after you press START**, for Windows ISO images, and lists boxes such as removing the TPM, Secure Boot and RAM requirements, removing the online-account requirement, creating a local account, and turning off data collection. If you tick any box, Rufus writes its own `autounattend.xml` to the drive. If you do not see the dialog, your Rufus version or the image type may not offer it. That is fine; nothing needs to be ticked, because this project already writes the hardware-check bypass into the images.

**Copying `autounattend.xml` after Rufus has finished is safe and recommended.** It replaces whatever file Rufus wrote. The only thing you lose is any setting Rufus put in its own answer file (for example the local account). Narrator auto-start in `boot.wim` does not depend on `autounattend.xml`.

A plain copy to a FAT32 USB drive cannot hold a file over 4 GB.

### 7. Test the result

1. Boot the target PC (or a virtual machine) from the USB drive.
2. Wait up to about one minute without pressing anything. Narrator should announce itself and then read the Setup window.
3. **If you hear Narrator, do not press Win+Ctrl+Enter.** It toggles Narrator off.
4. If it stays silent, press **Win+Ctrl+Enter** once to start it manually, then press **Shift+F10** to open a command prompt and run `type X:\narrator_log.txt`. The file says whether the helper ran, how long it waited for audio, whether Narrator was started, and where `autounattend.xml` was found. Include that text in any bug report.

### Lightweight image for old PCs (optional)

Windows 11 officially needs 4 GB of RAM, a TPM 2.0 chip, Secure Boot, and a fairly recent processor. This optional mode helps when you want to install a lean Windows 11 on an older PC, for example one with 2 GB of RAM. It will still be slow on such a PC: Microsoft does not support Windows 11 below its minimums, so test on the real hardware before you commit to it.

**What it does**

- Removes pre-installed apps (news, weather, Xbox, Teams, Copilot, Clipchamp and similar), a few unused optional components, and telemetry scheduled tasks.
- Disables a short list of background services that use memory and disk on old PCs (telemetry, error reporting, Xbox services, maps, location, SysMain/Superfetch).
- Switches off sponsored-app delivery, reserved storage and automatic device encryption.
- Optionally (on by default) writes the TPM, Secure Boot, RAM, storage and CPU-model check bypass into both the Setup image and the install image, so Setup does not stop on old hardware. It cannot add CPU instructions an old processor lacks, so very old processors still cannot run Windows 11.
- Keeps only the edition you choose (all other editions are removed from `install.wim`) and recompresses the result with Max compression.

**What it never touches (protected in the code, even if you list it)**

- Audio: the Windows Audio and Audio Endpoint Builder services and everything named `Audio*`, the multimedia scheduler, plug-and-play and their dependencies.
- Narrator and every speech component: text-to-speech, speech recognition, and all `Language.*` capabilities.
- Language and input features, including the "Language for non-Unicode programs" (system locale) support and text input services.
- Windows Defender, Windows Security, the firewall, and Security Center.
- Microsoft Store, Notepad, Calculator, the App Installer, media codecs, and the audio apps Sound Recorder and Media Player.
- Bluetooth services (many people use Bluetooth headphones), Windows Update, networking, and core shell services.
- Edge is **kept by default** because it is the only browser in the image, and you need a browser to download a screen reader such as NVDA unless you bring its installer on the USB drive. Set `RemoveEdge=1` only if you have planned for that.

**Order of the steps**

1. `boot_narrator.bat` (patches the Setup image, including the hardware-check bypass if enabled in the config).
2. Edit `debloat_config.txt` if you want different choices.
3. `debloat_install_image.bat` (this mode).
4. Create the USB drive (see [Create the USB drive](#6-create-the-usb-drive)).

**How to choose what is removed: `debloat_config.txt`**

One rule: a line that does **not** start with `#` is acted on (the item is removed or disabled). Put `#` at the start of a line to keep that item. Remove the `#` to act on it. The file has sections:

- `[options]`: `Key=1` to turn a feature on or `Key=0` to turn it off. Keys: `RemoveOneDrive`, `RemoveEdge`, `RemoveTelemetryTasks`, `DisableConsumerFeatures`, `DisableTelemetry`, `DisableReservedStorage`, `DisableDeviceEncryption`, `ComponentCleanup`, `BypassHardwareChecks`, and `HookSetupCmdLine` (read by `boot_narrator.bat`: `1` adds the Narrator start hook, `0` removes it).
- `[apps]`: pre-installed app package names. `Microsoft.BingNews` matches the package `Microsoft.BingNews_<version>`.
- `[services]`: service names to disable (set to Start = 4, which you can reverse later in Services).
- `[capabilities]`: Windows capabilities (optional components), matched by name prefix.
- `[features]`: Windows optional features to disable.

Example: to keep Weather, change `Microsoft.BingWeather` to `#Microsoft.BingWeather`. To also remove Photos, change `#Microsoft.Windows.Photos` to `Microsoft.Windows.Photos`.

If you list a protected item, the script prints `PROTECTED: skipped ...` and leaves it alone.

**Important notes**

- The install image must be a `.wim` that you can edit. An `install.esd` cannot be edited.
- Removed apps are gone from the image. They can often be reinstalled later from the Microsoft Store (which is kept), but this has not been tested here.
- `ComponentCleanup=1` runs `/ResetBase`, which makes the cleaned-up updates in the image impossible to uninstall. It makes the image smaller.
- Hardware-check bypass means the PC runs Windows 11 on hardware Microsoft does not officially support. Updates may be limited, and Microsoft can change this behavior.
- Everything is applied to the image file, not to a running system, so the result can be tested in a virtual machine before you use it.

## How it works

### The boot image

A Windows 11 ISO contains `sources\boot.wim`. It has two images. **Index 1** is a plain Windows PE. **Index 2**, "Microsoft Windows Setup", is what actually runs when you boot the installer. This project patches only index 2.

Inside index 2 of the media the author tested (Windows 11 26H2):

- There is no `winpeshl.ini`.
- `Windows\System32\startnet.cmd` contains only `wpeinit`.
- The registry value `SYSTEM\Setup\CmdLine` is `winpeshl.exe`, with `SetupType = 1` and `SystemSetupInProgress = 1`.
- `AudioSrv` and `AudioEndpointBuilder` are on the `Setup\AllowStart` list, so audio services are allowed to start in Setup mode.

Because Setup's launch layout differs between builds and tools, the patch script looks at what is actually in the image and adapts:

- If `winpeshl.ini` exists (for example Tiny11Builder's Core mode writes one), it inserts one launch line immediately before the line that starts `setup.exe` or `setup_old.exe`.
- Otherwise, if `startnet.cmd` exists, it inserts one launch line at the top of it.
- If neither exists, it changes nothing about start-up and relies on `autounattend.xml`.
- It **never creates** a `winpeshl.ini` that was not there, because that would change how Setup itself starts. (An early version did this by mistake. The current version detects that exact file and removes it.)

### Three triggers, one helper

Because it was not certain which start-up file this Setup image really uses, Narrator can be started by three independent triggers. All of them call the same helper, which runs only once (a flag file stops the others):

- **Trigger A, the Setup CmdLine hook** (v0.4.0, on by default). See below.
- **Trigger B, `startnet.cmd` or `winpeshl.ini`**, whichever the image really has. On the author's media there is no `winpeshl.ini`, and `startnet.cmd` only holds `wpeinit`. It is not known whether Setup runs `startnet.cmd` at all. This is the trigger that earlier versions relied on, and the author's tests showed Narrator did not start with it.
- **Trigger C, `autounattend.xml`** (`windowsPE` pass). It only works if the answer file is on the root of the USB drive and was not replaced by Rufus.

### The Setup CmdLine hook

In the author's image the registry value `HKLM\SYSTEM\Setup\CmdLine` is `winpeshl.exe`, with `SystemSetupInProgress = 1`. In Setup mode, Windows runs that value at start-up. It is the one command that is certain to run, whatever else the image contains. The hook:

1. Reads the original value (and saves it in `Setup\CmdLineOriginal`).
2. Writes `Windows\System32\setup_hook.cmd`, which starts the helper detached and then runs the **original** command.
3. Sets `CmdLine` to run that wrapper.

If the original value cannot be read as a plain string, the hook is skipped. To turn it off, set `HookSetupCmdLine=0` in `debloat_config.txt` and run `boot_narrator.bat` again: the original command is restored and the wrapper deleted. If the hook ever stops Setup from starting, do that, or start from the original ISO.

This hook has not been tested on real hardware yet. The assumption behind it (that Windows runs `CmdLine` at start-up in Setup mode) comes from the registry layout seen in the author's image, not from a test.

### The helper: `start_narrator.cmd`

The helper runs detached (`cmd /c start "" /min`), because Windows start-up commands wait until the program exits and Narrator never exits. It:

1. Writes a log, `X:\narrator_log.txt` (`X:` is the boot environment's RAM drive).
2. Exits at once if the flag file `X:\Windows\Temp\narrator.started` already exists, so Narrator is not started twice (a second launch would toggle it off).
3. **Beeps once** (a console beep and a system beep), so you know the helper ran, even before any speech.
4. Logs which tools are present in the image. On the author's media `tasklist`, `findstr` and `sc` are **not** in the Setup image, so the helper uses only commands that are (`for`, `if`, `reg`, `ping`, `start`).
5. Waits, up to about 45 seconds, until the registry shows an **active audio output** (`MMDevices\Audio\Render ... DeviceState = 1`), so Narrator is not started before audio exists. If none appears it starts Narrator anyway after the timeout.
6. Starts `Narrator.exe` once. It cannot check that Narrator is running, because there is no tool for that in the image, so it does not retry.
7. **Beeps twice** after the start command is issued (this does not prove Narrator is running).
8. Records where it found `autounattend.xml`.
9. Copies the log to the **root of the USB drive** as `narrator_log.txt` (it looks for the drive that holds `sources\boot.wim`), so you can read it later on any PC.

The beeps are made with the console bell and `MessageBeep`. Whether either makes a sound in Windows Setup depends on the hardware and on whether the audio stack is ready. If you hear no beeps but Narrator starts, that is why. A missing beep together with a missing log file on the USB drive means that none of the triggers ran.

### The answer file: `autounattend.xml`

- **windowsPE pass**: a `RunSynchronousCommand` writes a line to the log, then calls the helper (or, if the helper is missing, starts `Narrator.exe` directly with `start`). This is the second, independent way Narrator can start, and it also proves in the log that Setup read the file.
- **oobeSystem pass**: a `FirstLogonCommands` entry starts Narrator at the first sign-in after installation.
- It declares the `wcm` XML namespace. An earlier version of this file used `wcm:action` without declaring the prefix, so the file was not well-formed XML and Setup could reject it. This is one likely cause of the 26H2 failure that motivated the project, but it is not confirmed as the only one.
- There is deliberately **no** Narrator launch in the `specialize` pass, which runs without an interactive desktop.

Setup picks up `autounattend.xml` from the root of the USB drive (it checks removable drives).

### Verifying the saved image

DISM can report an unmount error even though the image was saved. So after saving, `boot_narrator.bat` mounts `boot.wim` again read-only and checks that `start_narrator.cmd` is present. That check, not the unmount message, decides success.

### The diagnostics file

`patch_setup_image.ps1` writes `C:\boot_diag.txt`: a listing of the image root, the relevant files in `System32`, the contents of `startnet.cmd`, and the registry values under `SYSTEM\Setup` and `Audiosrv`. It reads a **copy** of the SYSTEM registry file, so the image is never touched. Attach this file to bug reports.

## Script reference

### `boot_narrator.bat`

Usage, from an administrator prompt or by right-click, **Run as administrator**:

```
boot_narrator.bat
boot_narrator.bat "D:\media"
boot_narrator.bat "D:\media" "D:\my\autounattend.xml"
```

- Argument 1: media folder containing `sources\boot.wim`. Default `C:\work`.
- Argument 2: the answer file to copy into the media root. Default: `autounattend.xml` next to the script. If none is found, Step 9 is skipped.
- Mount folder: `C:\MountBoot` (fixed). It is deleted and recreated.
- Exit code 0 on success, 1 on failure. No beeps. The window waits for a key press at the end.

Because an administrator "Run as" launch starts in `C:\Windows\System32`, the script never relies on the current folder. It finds its companion files with its own path.

### `patch_setup_image.ps1`

Called by the batch file with `-Mount <folder>`. It is safe to run repeatedly. Output is one fact per line, ending with a `RESULT:` line that says whether Narrator is started from `winpeshl.ini`, from `startnet.cmd`, or only through `autounattend.xml`.

### `debloat_install_image.bat` and `debloat_install_image.ps1`

```
debloat_install_image.bat
debloat_install_image.bat "D:\media" "D:\my\debloat_config.txt"
```

- Argument 1: media folder containing `sources\install.wim`. Default `C:\work`.
- Argument 2: the config file. Default: `debloat_config.txt` next to the script.
- Needs administrator rights, and a `.wim` install image (not `.esd`).
- If `install.wim` has several editions, it lists them, asks for the Index to keep, and exports only that one first.
- Mounts the image at `C:\MountInstall`, then runs 10 numbered steps: admin check, read config, choose edition, mount, remove apps, remove capabilities/features/files, edit the offline registry (services and settings), component cleanup, save, and recompress (Max compression).
- Every removal prints one line (`Removed app: ...`, `Disabled service: ...`, `Not present: ...`, `PROTECTED: skipped ...`). A failing item is reported and skipped; the run continues.
- If a step fails, it unmounts and discards unsaved changes. If DISM reports `0xc1420117` when saving, it verifies by re-mounting read-only before calling it a success.
- Ends with `SUCCESS` and the before and after size of `install.wim`, or `FAILED at step N of 10` with the reason.

### Files and folders the scripts use

- `C:\work`: your extracted media (default).
- `C:\MountBoot`: temporary DISM mount folder.
- `C:\MountInstall`: temporary DISM mount folder for `debloat_install_image`.
- `C:\iso_tmp`: temporary export folder for `debloat_install_image`.
- `C:\debloat_log.txt`: full log of the last `debloat_install_image` run.
- `C:\boot_diag.txt`: diagnostics from the last patch run.
- Inside the booted Setup environment: `X:\narrator_log.txt`, `X:\narrator_sc.txt`, `X:\Windows\Temp\narrator.started`.

## Using it with Tiny11Builder or other tools

This project is independent of, and not affiliated with, Tiny11Builder or any other Windows customisation tool. It does not include or redistribute them.

A typical pipeline:

1. Build your trimmed ISO with the other tool.
2. Extract that ISO to `C:\work`.
3. Run `boot_narrator.bat`. **Always run it after the other tool has finished.**
4. Create the USB drive.

Notes:

- **Narrator and audio must survive the trimming.** Do not remove Narrator, the Windows Audio and Audio Endpoint Builder services, their dependencies, or the text-to-speech language capabilities (`Language.TextToSpeech~~~<language>`) for the language you want spoken. Heavy "core" modes that prune the component store (WinSxS) can delete these components and are not recommended if you rely on Narrator.
- Some tools write their own `autounattend.xml` (for example to hide pages or create a local account). Copying this project's file over it discards those settings. To keep them, keep the other tool's file and add only this project's two blocks: the `RunSynchronous` block in the `windowsPE` pass, and the `FirstLogonCommands` block in the `oobeSystem` pass.
- Some tools switch Setup to a legacy installer by writing a `winpeshl.ini`. The patch script handles that: it inserts its line before the `setup_old.exe` line.
- By default this project removes no apps. If you want fewer apps, you can use the optional `debloat_install_image.bat`, or use a separate tool and then run `boot_narrator.bat` last.

## Accessibility design of the scripts

The scripts are written to be used with a screen reader:

- Output is plain, linear text: one numbered step per line, `OK:` after each success, `ERROR:` with a reason on failure.
- No colours, boxes, animations, progress spinners, or sound effects. No beeps.
- The window always stays open at the end and waits for a key press, so a quick failure cannot vanish before it is read.
- Every failure names the step number and the likely cause.
- Diagnostics are saved to plain text files you can open in Notepad or attach to a report.

## Troubleshooting

**The window opens and closes immediately.**
Older drafts of the script did this when started with "Run as administrator" (the working folder becomes `C:\Windows\System32`). The current script does not depend on the working folder and always pauses at the end. Make sure you downloaded the latest files and kept them in one folder.

**`FAILED at step 1`: not running as Administrator.**
Right-click the `.bat` file and choose **Run as administrator**.

**`FAILED at step 2`: boot.wim not found.**
The media folder is wrong or empty. The file must be at `C:\work\sources\boot.wim`, or pass your folder as the first argument.

**Mount fails at step 5.**
Read the DISM lines above the error. Run `dism /Cleanup-Wim` as administrator to clear stale mounts, check that index 2 exists with `dism /Get-WimInfo /WimFile:C:\work\sources\boot.wim`, and check that your build PC's DISM is not older than the media.

**`0xc1420117` at step 7 ("directory could not be completely unmounted").**
DISM saved the image but could not recreate the empty `C:\MountBoot` folder, usually because antivirus or another program is touching it. Add `C:\MountBoot` to your antivirus exclusions. If step 8 passes, the image is fine.

**Step 8 fails ("start_narrator.cmd is missing").**
The changes were not saved. Run the script again.

**`debloat_install_image` says `Only install.esd was found`.**
An ESD cannot be edited. Use media that has `install.wim`, or convert the ESD to a WIM first, and run the lightweight mode again.

**An app or service was not removed.**
Read the line for it. `Not present` means it is not in that Windows build. `PROTECTED` means the code keeps it on purpose. `FAILED ... code N` means DISM refused; the run continued. Some system apps cannot be removed from the image.

**Setup still stops with "This PC can't run Windows 11".**
Make sure `BypassHardwareChecks=1` was set in `debloat_config.txt` **before** you ran `boot_narrator.bat`, because that script writes the Setup-image part. Re-run `boot_narrator.bat`. Very old processors that lack required instructions cannot be fixed this way.

**The result is still large.**
A single edition after `debloat_install_image` measured 6.72 GB for `install.wim` and 7.53 GB for an ISO. The project has no further compression step. To shrink more, trim more with a separate tool before these scripts, but note that heavy "core" modes that prune WinSxS can remove Narrator and audio components.

**Narrator does not start by itself.**
1. Listen for beeps during boot: one beep when the helper starts, two when it sees Narrator running. Wait a full minute.
2. Press **Win+Ctrl+Enter** only if Narrator is clearly not running. If it is running silently, the shortcut turns it off.
3. After the test, plug the USB drive into a PC and open `narrator_log.txt` in the drive root. The helper copies it there. What it tells you:
   - **No `narrator_log.txt` on the USB drive:** the helper never ran, so none of the three triggers fired, or the USB drive could not be written. Check `C:\boot_diag.txt` on the build PC: it must say that the hook is in place (`Setup CmdLine hook in place`) and list `setup_hook.cmd`. Also check that `boot_narrator.bat` finished with `SUCCESS` after the hook option was on.
   - **The log says `Narrator start command issued` but there was no speech:** the helper ran and launched Narrator, yet Narrator did not speak. That points to the launch method itself. The next thing to try is starting Narrator through the accessibility infrastructure instead of `Narrator.exe` directly. Send the log.
   - **The log says `active audio output found: 0`:** the helper waited the full time and no audio output appeared in the registry. Send the log; the audio driver may not be ready in Setup on that PC.
   - **The log lists `tool MISSING` lines:** this is normal for `tasklist`, `findstr` and `sc`. Missing `reg`, `ping` or `rundll32` matters; send the log.
4. If you can read the Setup screen, press **Shift+F10** and run `type X:\narrator_log.txt`.
5. If you used Rufus and ticked boxes in its Windows User Experience dialog, copy `autounattend.xml` onto the drive again afterwards (the hook does not depend on it).
6. Send `narrator_log.txt` and `C:\boot_diag.txt` in a bug report.

**Windows Setup shows an answer-file error.**
Open Shift+F10 and read `X:\Windows\Panther\setuperr.log` or `X:\$WINDOWS.~BT\Sources\Panther\setuperr.log`. Make sure `autounattend.xml` is the one from this project and was not edited into invalid XML.

**Setup fails with a message about missing `setup_old.exe`.**
The media came from a "core" mode that switched to the legacy installer, and the file is missing. Rebuild the media with the other tool.

## Known limitations

- **Tested scope.** In the author's repeated tests on a Rufus-made USB drive with Windows 11 26H2 media, the earlier triggers (B and C) did not start Narrator. The hook and the beeps added in v0.4.0 have not been confirmed on real hardware.
- **How Setup starts is partly unknown.** On the author's media, `winpeshl.exe` is the Setup start command, there is no `winpeshl.ini`, and `startnet.cmd` holds only `wpeinit`. Which of the two start paths (`startnet.cmd` or `autounattend.xml`) actually fired is recorded in `X:\narrator_log.txt` and may differ on other media.
- **x64 only.** The answer file and tools target `amd64`. ARM64 media is not supported.
- **OOBE is not covered.** The first-run screens after installation (region, keyboard, network, account) do not start Narrator automatically. Press **Win+Ctrl+Enter** there. An experimental sign-in Narrator registry setting exists but is not verified on 26H2 and is not included.
- **Natural Narrator voices** are downloaded and need internet. Offline installs use the built-in voices.
- **No boot.wim backup** is created on purpose (it would be packed into the ISO). Keep your original ISO.
- **Size.** One edition after the lightweight mode measured 6.72 GB for `install.wim` and 7.53 GB for the ISO. There is no further compression step. An earlier Recovery ESD option did not shrink the author's image and was removed.
- **No ISO builder.** The project does not build an ISO. See [Create the USB drive](#6-create-the-usb-drive) for two manual ways, neither of which has been fully verified.
- **The lightweight mode is only partly tested.** It was written from the structure of the original tiny11 scripts and Microsoft's DISM documentation. It ran to completion on one PC, but nobody has yet installed and checked the resulting Windows (Narrator, audio, Defender, speech). Test every image in a virtual machine and report problems.
- **Old hardware limits.** The bypass removes Setup's checks only. It cannot make Windows 11 fast on 2 GB of RAM or run on processors without the instructions Windows 11 needs.
- **No Secure Boot signing is done.** The scripts do not alter the boot loader, so Secure Boot behaves as it does with the original media.

## Safety notes

- `boot_narrator.bat` modifies `sources\boot.wim` **in place** with no backup. Keep a copy of the original ISO.
- `debloat_install_image.bat` replaces the multi-edition `install.wim` with a single-edition one and then edits it. Keep the original ISO if you may want other editions.
- Both scripts delete `*.bak` files under the media folder and temporary folders under `C:\`.
- `boot_narrator.bat` and `autounattend.xml` do not modify the installed system's registry, services, or apps. `debloat_install_image` does, only as listed in `debloat_config.txt`, and never for protected items.
- Test the result in a virtual machine or on a spare PC. Installing Windows can erase the disk you choose.

## Distributing this project to other people

This section is for the maintainer.

### What you may and may not share

- **Share:** the scripts, the answer file, and this documentation.
- **Do not share:** Windows ISO files, `boot.wim`, `install.wim`, `install.esd`, or ISOs produced by these scripts. They contain Microsoft software. Each user should build their own from an ISO they downloaded from Microsoft. The `.gitignore` already blocks these file types.
- **Do not bundle** `oscdimg.exe`, Tiny11Builder, Rufus, or the Windows ADK. This keeps the repository clean and avoids redistribution questions.
- Users still need a valid Windows license for the edition they install.

### Publishing on GitHub (first time)

1. Create a new repository named `win11-narrator-autostart`. Choose **Public**. You can leave "Add a README" and "Add .gitignore" unticked because this folder already has them.
2. Upload the contents of this folder (drag the files into the browser upload page, or use Git). Keep `.gitattributes` so the batch files keep Windows line endings. Check that `.github/ISSUE_TEMPLATE/bug_report.md` was uploaded in its folder.
3. Open `LICENSE` and replace `REPLACE-WITH-YOUR-NAME` with your name or handle (or use GitHub's **Add file**, **Create new file**, type `LICENSE` and pick a template).
4. In the repository **Settings**, set the description and website fields, and add topics (suggestions below). Turn **Issues** on.
5. Commit with a clear message such as `Initial release v0.1.0`.

Suggested description:

> Make Narrator start automatically in Windows 11 Setup when booting from USB. Patches boot.wim and provides an autounattend.xml so blind and low-vision users know Setup is ready. Works with 25H2 and 26H2 media. No apps or services are removed.

Suggested topics: `windows-11`, `narrator`, `accessibility`, `screen-reader`, `windows-setup`, `autounattend`, `boot-wim`, `dism`, `winpe`, `unattended-install`, `usb-installer`, `batch-script`, `powershell`.

### Making a release for general users

1. Decide the version (for example `v0.1.0`). Update the changelog below.
2. Create a ZIP containing the repository files (not the `.git` folder), named like `win11-narrator-autostart-v0.1.0.zip`.
3. Compute its checksum so users can verify the download:
   ```
   certutil -hashfile win11-narrator-autostart-v0.1.0.zip SHA256
   ```
4. On GitHub, open **Releases**, **Draft a new release**, create the tag `v0.1.0`, and attach the ZIP. Paste the checksum and the release notes (what changed, what was tested, known limitations).
5. Mark early versions as **pre-release** until more people have tested them.
6. Point users to the **Quick start** section of this README.

### Instructions you can give to end users

- Download the release ZIP and check its SHA-256 against the value in the release notes.
- Extract it to a folder, keep all files together, and follow the **Quick start**.
- Build the USB drive yourself from an official Microsoft ISO. Never download a pre-built ISO from anyone, including this project: it should not exist.
- Test in a virtual machine first. If anything fails, attach the console text, `C:\boot_diag.txt`, and `X:\narrator_log.txt` to an issue.

### Keeping the project healthy

- Re-test on each new Windows 11 feature update, because Microsoft can change how Setup starts.
- Ask people reporting problems to include the Windows version, the Rufus options used, and the three log files.
- Keep a short compatibility list in the README of media versions that have been confirmed.

## Contributing and reporting problems

Issues and pull requests are welcome. For a bug report, use the issue template and attach logs as **text**, not screenshots, because many contributors use screen readers.

Guidelines for changes:

- Keep output plain and linear. No colour codes, no beeps, no screens that clear.
- Keep every failure message specific: say which step failed and why.
- Never name a batch variable after a Windows environment variable (`tmp`, `temp`, `path`, `comspec`, and so on).
- In batch files, DISM exit codes can be negative numbers. Test them with `if not "%errorlevel%"=="0"`, not with `if errorlevel 1`.
- Keep `.bat` files in CRLF (Windows) line endings. `.gitattributes` enforces this. If a `goto` label stops working, check the line endings first.
- Do not add removal of audio, Narrator, speech, language or Defender components. Keep the protected lists in `debloat_install_image.ps1` conservative, and add to them rather than shrink them.
- Test in a virtual machine and say which Windows media you used.

## Legal

- This project is not affiliated with, endorsed by, or sponsored by Microsoft. Windows, Narrator, DISM, and Windows ADK are trademarks or products of Microsoft Corporation.
- It does not distribute Windows or any Microsoft binary.
- Use it only with Windows media you are licensed to use. Follow the license terms of Windows and of every tool you combine it with.
- Windows 11 on hardware that does not meet Microsoft's requirements is not officially supported by Microsoft. Using `BypassHardwareChecks` is your own decision and risk.
- The lightweight mode's removal lists were modelled on the public tiny11 scripts. That project is separate and is not included here.
- Rufus and Tiny11Builder are separate projects with their own licenses. Check them before redistributing anything.
- The software is provided as is, without warranty. Modifying installation media can make it fail to install. You are responsible for testing and for backups of your data.

## License

Released under the MIT License. See [LICENSE](LICENSE).

## Changelog

### v0.4.1

- The Narrator helper no longer uses `sc`, `findstr` or `tasklist`, which are missing from the Windows Setup image on the author's media. It waits for an active audio output by reading the registry, then starts Narrator once. Beeps now mean the start command was issued, not that Narrator is confirmed running.
- README: how to find the Rufus Windows User Experience dialog, and that copying `autounattend.xml` after Rufus has finished is safe.

### v0.4.0

- Narrator auto-start redesigned after tests showed the earlier method did not start Narrator: new Setup `CmdLine` hook (trigger A), retry logic that checks whether Narrator is really running, beeps when the helper starts and when Narrator is running, and a log that is copied to the root of the USB drive.
- `HookSetupCmdLine` option (default 1) in `debloat_config.txt`; `boot_narrator.bat` shows whether the hook is in place.
- Not yet confirmed on real hardware.

### v0.3.0

- Removed `make_small_iso.bat` and `get_oscdimg.ps1`. The Recovery ESD option did not shrink the author's image, and the script was not worth its run time. The project now has two steps: `boot_narrator.bat` and the optional `debloat_install_image.bat`.
- Added manual instructions for creating the USB drive.

### v0.2.2

- `make_small_iso.bat`: removed a stray duplicated block that printed a wrong message ("install.esd already exists") and repeated step 4. The prompt for single-edition images now shows the current size and says plainly that Enter skips compression.
- Confirmed on the author's PC: `debloat_install_image` fix from v0.2.1 works (all 10 steps), `boot_narrator.bat` finished with no unmount error on the last run.

### v0.2.1

- `debloat_install_image`: fixed a failure at step 6 that was most likely caused by Windows PowerShell 5.1 turning native-program error text (from `takeown`, `icacls`, `reg`) into a terminating error. Native calls now discard that text safely, and `takeown /r` is only used on folders. The script now also writes a full log to `C:\debloat_log.txt` and prints the failing script line. The cause of the earlier failure was not seen in the log, so this fix is a probable cause, not a confirmed one.
- `patch_setup_image.ps1`: the hardware-check bypass block no longer aborts on error text from `reg.exe`.

### v0.2.0

- New optional lightweight mode: `debloat_install_image.bat`, `debloat_install_image.ps1` and `debloat_config.txt` (`#` keeps an item). Removes listed apps, capabilities, features and services from the install image, with protected lists for audio, Narrator, speech, language, Defender and Store.
- `boot_narrator.bat` and `patch_setup_image.ps1` can write the TPM, Secure Boot, RAM, storage and CPU check bypass into the Setup image when `BypassHardwareChecks=1` is set in the config.
- Not yet tested on Windows.

### v0.1.0 (initial release)

- `boot_narrator.bat` and `patch_setup_image.ps1`: patch `boot.wim` index 2 so Narrator starts automatically; verify the saved image; write diagnostics; no backup.
- `autounattend.xml`: well-formed answer file with the `wcm` namespace declared; Narrator started from the `windowsPE` pass and at first sign-in; no `specialize` launch.
- `make_small_iso.bat` and `get_oscdimg.ps1`: keep one edition, compress (Max WIM or Recovery ESD), build a UEFI ISO, download and verify `oscdimg.exe`. Experimental: end-to-end result not yet confirmed.
- Fixed in development: `winpeshl.ini` is never created when missing; DISM negative exit codes are handled; the `TMP` environment variable is no longer overwritten.
