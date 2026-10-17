# win11-narrator-autostart

Make **Narrator start by itself** when Windows 11 Setup boots from a USB drive, so a blind or low-vision person knows Setup is ready without having to press **Win+Ctrl+Enter** blind.

The project is a small set of Windows batch and PowerShell scripts plus one answer file (`autounattend.xml`). They patch the Windows Setup boot image (`sources\boot.wim`, index 2) of a Windows 11 ISO that **you** supply, optionally shrink the install image, and rebuild a bootable ISO.

> **Status: experimental (v0.1.0).** Written for Windows 11 25H2 and 26H2 x64 media. Automatic Narrator start from a Rufus-made USB has been confirmed by the author on one test machine. The ISO shrinking script (`make_small_iso.bat`) has been run on the author's machine up to the export stage. After a bug fix, a complete end-to-end run has not been reported yet. Always test in a virtual machine or on a spare PC before relying on the result. See [Known limitations](#known-limitations).

---

## Table of contents

1. [Why this exists](#why-this-exists)
2. [What it does and does not do](#what-it-does-and-does-not-do)
3. [What is in the repository](#what-is-in-the-repository)
4. [Requirements](#requirements)
5. [Quick start](#quick-start)
6. [Step-by-step guide](#step-by-step-guide)
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
- Optionally keep a single Windows edition, recompress the install image, and rebuild a UEFI-bootable ISO with `oscdimg`.

**It does not:**

- Remove, disable, or change any Windows app, service, feature, driver, or setting inside the installed system. (The scripts contain no app or service removal commands. The only thing `make_small_iso.bat` cuts is the *other editions* inside `install.wim`.)
- Bypass the TPM, Secure Boot, RAM, or Microsoft-account checks.
- Skip or hide any Setup page. Setup stays fully interactive so it can be driven with Narrator.
- Download, bundle, or redistribute Windows. You must supply your own ISO.
- Change anything on your PC outside the folders named below (it needs administrator rights only because DISM does).
- Cover the first-run screens after installation (OOBE). Press **Win+Ctrl+Enter** there. See [Known limitations](#known-limitations).

## What is in the repository

All files must stay **together in one folder**. The scripts look for each other next to themselves.

- `boot_narrator.bat`: the main script. Mounts `boot.wim` index 2, patches it, saves it, verifies it, and copies `autounattend.xml` into the media folder.
- `patch_setup_image.ps1`: called by `boot_narrator.bat`. Does the actual patching and writes `C:\boot_diag.txt`.
- `autounattend.xml`: the Windows Setup answer file that starts Narrator.
- `make_small_iso.bat`: optional. Keeps one edition, compresses, and builds the ISO.
- `get_oscdimg.ps1`: called by `make_small_iso.bat` when `oscdimg.exe` is missing. Downloads and verifies it.
- `.github/ISSUE_TEMPLATE/bug_report.md`: a bug-report form that asks for the right logs.
- `.gitattributes`, `.gitignore`, `LICENSE`.

## Requirements

On the PC where you run the scripts (the "build PC"):

- Windows 10 or Windows 11, 64-bit, with an administrator account. The build PC's DISM should be at least as new as the Windows version you are patching. The author used DISM 10.0.26100.
- PowerShell 5.1 (included with Windows).
- An **official Windows 11 x64 ISO** from Microsoft, extracted to a folder. The default folder is `C:\work`.
- Free disk space on `C:`: about 9 GB for the extracted ISO, plus about 6 GB of temporary space while `make_small_iso.bat` exports the install image, plus room for the output ISO.
- Internet access only the first time `make_small_iso.bat` runs, to download `oscdimg.exe` from Microsoft (skipped if you already have the Windows ADK or Tiny11Builder's copy).
- [Rufus](https://rufus.ie) (or another tool that writes a bootable UEFI USB from an ISO) to create the USB drive.
- A USB drive of at least 8 GB.

On the target PC: a PC that can boot Windows 11 Setup from USB, with working speakers or headphones. Narrator needs an audio device that Setup's boot environment supports.

## Quick start

For people who just want the commands. Details are in the next section.

1. Download the ZIP of this repository and extract it to a folder, for example `C:\win11-narrator-autostart`.
2. Extract your Windows 11 ISO into `C:\work` so that `C:\work\sources\boot.wim` exists.
3. Right-click `boot_narrator.bat`, choose **Run as administrator**, and wait for `SUCCESS. All 9 steps finished.`
4. (Optional) Run `make_small_iso.bat` as administrator to shrink the image and build `C:\iso_out\Win11_lite.iso`.
5. Write the ISO, or your edited `C:\work` contents, to a USB drive with Rufus. **Do not tick "Customize Windows installation".**
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

DISM mounts the boot image as a folder. Real-time scanning of that folder can make the final unmount report error `0xc1420117`. In Windows Security, add exclusions for `C:\work` and `C:\MountBoot` (and `C:\iso_tmp` if you use `make_small_iso.bat`). This is optional. The script verifies the result either way.

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

### 5. (Optional) Shrink the image and build an ISO

Run `make_small_iso.bat` as administrator. It:

1. Checks administrator rights.
2. Finds `oscdimg.exe`. If it is missing, it downloads it (see [Script reference](#script-reference)).
3. Lists the editions in `install.wim` and asks which **Index** to keep (for example Windows 11 Pro). It then asks for a compression mode: press **Enter** for Max WIM (faster) or type **R** for Recovery ESD (smallest, can take up to about 100 minutes).
4. Exports only that edition. The original multi-edition `install.wim` is deleted only after the new file is safely in place.
5. Deletes stray `*.bak` files.
6. Builds `C:\iso_out\Win11_lite.iso` (UEFI bootable; also BIOS bootable if `boot\etfsboot.com` exists) and prints its size.

If the install image already has only one edition, the script offers to skip the export. If an ISO with the same name already exists, it stops rather than overwrite it.

The final size depends on the edition and compression you choose. The author has not yet verified a final size, so none is promised here.

### 6. Create the USB drive

Use Rufus with your ISO (`C:\iso_out\Win11_lite.iso`, or the original ISO if you only ran `boot_narrator.bat` and then rebuilt it yourself).

**Important Rufus setting:** when Rufus offers the **Windows User Experience** dialog (Customize Windows installation), leave every box unticked, or cancel the dialog. Rufus writes its own `autounattend.xml` when options are ticked, and that replaces this project's file. The `boot.wim` patch still works without our answer file, but you lose the second launch path and the first-sign-in launch.

If the ISO is larger than 4 GB per file (`install.wim` or `install.esd`), Rufus will handle it. A plain copy to a FAT32 USB drive cannot hold a file over 4 GB.

### 7. Test the result

1. Boot the target PC (or a virtual machine) from the USB drive.
2. Wait up to about one minute without pressing anything. Narrator should announce itself and then read the Setup window.
3. **If you hear Narrator, do not press Win+Ctrl+Enter.** It toggles Narrator off.
4. If it stays silent, press **Win+Ctrl+Enter** once to start it manually, then press **Shift+F10** to open a command prompt and run `type X:\narrator_log.txt`. The file says whether the helper ran, how long it waited for audio, whether Narrator was started, and where `autounattend.xml` was found. Include that text in any bug report.

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

### The helper: `start_narrator.cmd`

The inserted line starts the helper with `cmd /c start "" /min`, so it runs detached. This matters: Windows start-up commands, `winpeshl.ini` entries, `RunSynchronousCommand` and `FirstLogonCommands` all **wait until the program exits**, and Narrator never exits on its own. Launching Narrator directly from any of them would hang Setup forever.

The helper:

1. Writes `X:\narrator_log.txt` (`X:` is the boot environment's RAM drive).
2. Exits at once if the flag file `X:\Windows\Temp\narrator.started` already exists. This prevents a second launch, which would toggle Narrator off.
3. Creates the flag file.
4. Polls `sc query audiosrv` about once per second, up to about 30 tries, until the Windows Audio service reports `RUNNING`.
5. Launches `Narrator.exe` with `start`.
6. Records the result and whether `narrator.exe` appears in the process list.
7. Records on which drive letters it found `autounattend.xml`.

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

### `make_small_iso.bat`

```
make_small_iso.bat
make_small_iso.bat "D:\media" "D:\out\my.iso"
make_small_iso.bat "D:\media" "D:\out\my.iso" "C:\tools\oscdimg.exe"
```

- Argument 1: media folder. Default `C:\work`.
- Argument 2: output ISO path. Default `C:\iso_out\Win11_lite.iso`. Do not put it inside the media folder.
- Argument 3: path to an existing `oscdimg.exe`.
- Temporary folder: `C:\iso_tmp` (needs about 6 GB free). It is also DISM's scratch folder for the export.
- `oscdimg.exe` search order: argument 3, next to the script, `C:\iso_tools`, the Windows ADK folders, then automatic download.
- Image volume label: `WIN11_LITE`.
- UEFI boot uses `efi\microsoft\boot\efisys.bin`. If `boot\etfsboot.com` exists, BIOS boot is added.

### `get_oscdimg.ps1`

Downloads `oscdimg.exe` to `C:\iso_tools\oscdimg.exe` from Microsoft's public symbol server (the same source and pin used by Tiny11Builder), and **accepts it only if its SHA-256 equals the pinned value**; otherwise the file is deleted:

```
https://msdl.microsoft.com/download/symbols/oscdimg.exe/688CABB065000/oscdimg.exe
SHA-256: 2000160B2C5044691B2F9A0AC308E5207F273D4880A572457AF16D05886BA861
```

If you prefer, install the Windows ADK "Deployment Tools" feature instead (`adksetup.exe /quiet /features OptionId.DeploymentTools`) and the script will find it there. You can verify any copy yourself with `certutil -hashfile oscdimg.exe SHA256`.

### Files and folders the scripts use

- `C:\work`: your extracted media (default).
- `C:\MountBoot`: temporary DISM mount folder.
- `C:\iso_tmp`: temporary export folder.
- `C:\iso_tools\oscdimg.exe`: downloaded tool.
- `C:\iso_out\Win11_lite.iso`: default output ISO.
- `C:\boot_diag.txt`: diagnostics from the last patch run.
- Inside the booted Setup environment: `X:\narrator_log.txt`, `X:\narrator_sc.txt`, `X:\Windows\Temp\narrator.started`.

## Using it with Tiny11Builder or other tools

This project is independent of, and not affiliated with, Tiny11Builder or any other Windows customisation tool. It does not include or redistribute them.

A typical pipeline:

1. Build your trimmed ISO with the other tool.
2. Extract that ISO to `C:\work`.
3. Run `boot_narrator.bat`. **Always run it after the other tool has finished.**
4. Optionally run `make_small_iso.bat`.

Notes:

- **Narrator and audio must survive the trimming.** Do not remove Narrator, the Windows Audio and Audio Endpoint Builder services, their dependencies, or the text-to-speech language capabilities (`Language.TextToSpeech~~~<language>`) for the language you want spoken. Heavy "core" modes that prune the component store (WinSxS) can delete these components and are not recommended if you rely on Narrator.
- Some tools write their own `autounattend.xml` (for example to hide pages or create a local account). Copying this project's file over it discards those settings. To keep them, keep the other tool's file and add only this project's two blocks: the `RunSynchronous` block in the `windowsPE` pass, and the `FirstLogonCommands` block in the `oobeSystem` pass.
- Some tools switch Setup to a legacy installer by writing a `winpeshl.ini`. The patch script handles that: it inserts its line before the `setup_old.exe` line.
- This project removes no apps. If you want fewer apps in the installed system, use a separate tool for that and then run these scripts last.

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

**DISM `Error: 5` (Access is denied) or `Error: 267` (The directory name is invalid) in `make_small_iso.bat`.**
Both were caused by an early bug in this project: a batch variable named `tmp` overwrote the Windows `TMP` environment variable, which DISM uses as its scratch folder. This is fixed in current versions. If you modify the scripts, never name a variable `tmp`, `temp`, `path`, or any other environment-variable name.

**`oscdimg.exe` could not be downloaded.**
Check your internet connection, or install the ADK Deployment Tools, or copy `oscdimg.exe` next to the script, or pass its path as the third argument.

**The ISO is larger than you hoped.**
`boot_narrator.bat` does not change the size. Run `make_small_iso.bat` to keep one edition. Choose **R** (Recovery ESD) for the smallest result. If you also want fewer components, use a trimming tool before these scripts.

**Narrator does not start by itself.**
1. Wait a full minute. The helper waits for the audio service first.
2. In Rufus, make sure "Customize Windows installation" was **not** ticked (it replaces `autounattend.xml`).
3. Press **Win+Ctrl+Enter**, then **Shift+F10**, then run `type X:\narrator_log.txt`.
   - No file at all: neither start path ran. The boot image may use a different start layout. Send `C:\boot_diag.txt` in a bug report.
   - The log says the helper ran but Narrator is not in the process list: Narrator was launched and failed. Send the log.
   - The log says `autounattend windowsPE command ran`: Setup read the answer file.
   - The log lists where `autounattend.xml` was found: if it is missing from the list, the file is not on the USB root.
4. Test with another audio output or headphones. Setup's audio support depends on the hardware.

**Windows Setup shows an answer-file error.**
Open Shift+F10 and read `X:\Windows\Panther\setuperr.log` or `X:\$WINDOWS.~BT\Sources\Panther\setuperr.log`. Make sure `autounattend.xml` is the one from this project and was not edited into invalid XML.

**Setup fails with a message about missing `setup_old.exe`.**
The media came from a "core" mode that switched to the legacy installer, and the file is missing. Rebuild the media with the other tool.

## Known limitations

- **Tested scope.** Automatic start has been confirmed by the author on one test machine, using Windows 11 26H2 media and a Rufus-made USB drive. It has not been tested on a range of hardware, in every virtual machine type, or with Windows Server media.
- **Why it works is partly unverified.** On the author's media, `winpeshl.exe` is the Setup start command, there is no `winpeshl.ini`, and `startnet.cmd` holds only `wpeinit`. Which of the two start paths (`startnet.cmd` or `autounattend.xml`) actually fired is recorded in `X:\narrator_log.txt` and may differ on other media.
- **x64 only.** The answer file and tools target `amd64`. ARM64 media is not supported.
- **OOBE is not covered.** The first-run screens after installation (region, keyboard, network, account) do not start Narrator automatically. Press **Win+Ctrl+Enter** there. An experimental sign-in Narrator registry setting exists but is not verified on 26H2 and is not included.
- **Natural Narrator voices** are downloaded and need internet. Offline installs use the built-in voices.
- **No boot.wim backup** is created on purpose (it would be packed into the ISO). Keep your original ISO.
- **`make_small_iso.bat` final sizes are not verified.** The export and ISO-build stages were corrected after failures reported by the author, and a complete successful run has not yet been reported.
- **No Secure Boot signing is done.** The scripts do not alter the boot loader, so Secure Boot behaves as it does with the original media.

## Safety notes

- `boot_narrator.bat` modifies `sources\boot.wim` **in place** with no backup. Keep a copy of the original ISO.
- `make_small_iso.bat` deletes the original multi-edition `install.wim` after it has created the single-edition replacement. Keep the original ISO if you may want other editions.
- Both scripts delete `*.bak` files under the media folder and temporary folders under `C:\`.
- The scripts do not modify the installed system's registry, services, or apps.
- Test the result in a virtual machine or on a spare PC. Installing Windows can erase the disk you choose.

## Distributing this project to other people

This section is for the maintainer.

### What you may and may not share

- **Share:** the scripts, the answer file, and this documentation.
- **Do not share:** Windows ISO files, `boot.wim`, `install.wim`, `install.esd`, or ISOs produced by these scripts. They contain Microsoft software. Each user should build their own from an ISO they downloaded from Microsoft. The `.gitignore` already blocks these file types.
- **Do not bundle** `oscdimg.exe`, Tiny11Builder, Rufus, or the Windows ADK. The scripts download or find what they need. This keeps the repository clean and avoids redistribution questions.
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
- Do not add commands that remove apps or services. This project's single purpose is Narrator at Setup.
- Test in a virtual machine and say which Windows media you used.

## Legal

- This project is not affiliated with, endorsed by, or sponsored by Microsoft. Windows, Narrator, DISM, and Windows ADK are trademarks or products of Microsoft Corporation.
- It does not distribute Windows or any Microsoft binary. `get_oscdimg.ps1` downloads one Microsoft tool from Microsoft's own server on the user's PC and checks its hash.
- Use it only with Windows media you are licensed to use. Follow the license terms of Windows and of every tool you combine it with.
- Rufus and Tiny11Builder are separate projects with their own licenses. Check them before redistributing anything.
- The software is provided as is, without warranty. Modifying installation media can make it fail to install. You are responsible for testing and for backups of your data.

## License

Released under the MIT License. See [LICENSE](LICENSE).

## Changelog

### v0.1.0 (initial release)

- `boot_narrator.bat` and `patch_setup_image.ps1`: patch `boot.wim` index 2 so Narrator starts automatically; verify the saved image; write diagnostics; no backup.
- `autounattend.xml`: well-formed answer file with the `wcm` namespace declared; Narrator started from the `windowsPE` pass and at first sign-in; no `specialize` launch.
- `make_small_iso.bat` and `get_oscdimg.ps1`: keep one edition, compress (Max WIM or Recovery ESD), build a UEFI ISO, download and verify `oscdimg.exe`. Experimental: end-to-end result not yet confirmed.
- Fixed in development: `winpeshl.ini` is never created when missing; DISM negative exit codes are handled; the `TMP` environment variable is no longer overwritten.
