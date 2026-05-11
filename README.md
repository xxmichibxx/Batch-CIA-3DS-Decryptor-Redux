<h3 align="center">Batch CIA 3DS Decryptor Redux - CXI Auto Fork</h3>
<p align="center">
  <a href="https://github.com/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux">
    <img src="https://i.imgur.com/tm9OXKI.png" alt="Logo" width="100" height="100">
  </a>
</p>
<h3 align="center">Automatic CIA to CXI conversion and Azahar/Citra Update/DLC loose-layout extraction</h3>
<hr>

This fork is based on **Batch CIA 3DS Decryptor Redux** by xxmichibxx, which itself is a rewritten version of the original Batch CIA 3DS Decryptor by matiffeder.

Original thread:  
https://gbatemp.net/threads/batch-cia-3ds-decryptor-a-simple-batch-file-to-decrypt-cia-3ds.512385/

Upstream project:  
https://github.com/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux

## What this fork adds

This fork adds a PowerShell-based conversion workflow for emulator use.

Main goals:

- Convert game CIA files directly into launchable `.cxi`
- Automatically distinguish game CIA from Update/DLC CIA
- Generate Azahar/Citra-compatible loose SD layouts for Update/DLC packages
- Keep normal output clean by default
- Preserve useful title metadata in optional logs and CSV reports
- Keep the original batch workflow available for classic decryption tasks

## Tested workflow

This fork has been tested on **Azahar Android** with multiple modified / fan-translated CIA titles.

Tested cases include:

- Game CIA -> CXI conversion
- Converted `.cxi` loading successfully in Azahar Android
- Update/DLC CIA detected as install-only content
- Update/DLC loose patch files copied into the virtual SDMC `title` layout
- Patched content being picked up correctly by Azahar Android

## Features

### Game CIA

For normal game CIA files, the script:

- Decrypts the CIA using the bundled Redux toolset
- Extracts NCCH contents
- Detects the main executable CXI-like content
- Writes the result to:

```text
_cxi_out/cxi/<game>.cxi
```

The generated `.cxi` can usually be launched directly in Azahar/Citra.

### Update and DLC CIA

Update/DLC packages are detected as install-only titles.

Title family mapping:

```text
Game:   00040000XXXXXXXX
Update: 0004000eXXXXXXXX
DLC:    0004008cXXXXXXXX
```

For example:

```text
Install TitleId:        0004008c00078a00
Expected Base TitleId:  0004000000078a00
```

By default, install-only packages are exported as an Azahar/Citra loose SD layout under:

```text
_cxi_out/loosepatch/title/
```

If you also want a best-effort rebuilt decrypted install CIA for debugging or fallback use, run the script with:

```powershell
-KeepInstallCia
```

That optional output is written to:

```text
_cxi_out/_cia_install/
```

### Azahar/Citra loose SD layout

When CIA installation does not work, this fork can generate loose `.app` files under:

```text
_cxi_out/loosepatch/title/
```

Example output:

```text
_cxi_out/loosepatch/title/0004000e/001acb00/content/00000000.app
_cxi_out/loosepatch/title/0004000e/001acb00/content/00000001.app

_cxi_out/loosepatch/title/0004008c/00078a00/content/00000000.app
_cxi_out/loosepatch/title/0004008c/00078a00/content/00000001.app
...
```

Copy the generated `title` folder into your Azahar/Citra virtual SD path:
```test
_cxi_out/loosepatch/title/
```
into your Azahar/Citra virtual SD path:
```text
data folder/
  sdmc/
    00000000000000000000000000000000/
      00000000000000000000000000000000/
        title/  <- copy/merge the generated title folder here
```
For Azahar Android, this is usually under the data folder you selected in Azahar:
```text
<Azahar data folder>/
  sdmc/
    00000000000000000000000000000000/
      00000000000000000000000000000000/
        title/
```
After copying, the final layout should look like:
```text
<Azahar/Citra data folder>/
  sdmc/
    00000000000000000000000000000000/
      00000000000000000000000000000000/
        title/
          0004000e/
            XXXXXXXX/
              content/
                00000000.app
          0004008c/
            XXXXXXXX/
              content/
                00000000.app
```
## Important note about `.app` names

Real CIA metadata uses ContentId values, but Azahar direct-CXI loose lookup expects index-based file names.

So this fork writes loose `.app` files using ContentInfo index order:

```text
ContentInfo index 0x0000 -> 00000000.app
ContentInfo index 0x0001 -> 00000001.app
ContentInfo index 0x0002 -> 00000002.app
```

This matters because some update CIAs may contain mappings like:

```text
ContentInfo 0x0000 / ContentId 00000003
ContentInfo 0x0001 / ContentId 00000002
```

For Azahar loose loading, those should still become:

```text
00000000.app
00000001.app
```

If `-ReportCsv` is enabled, the script also writes a loose mapping CSV:

```text
_cxi_out/loosepatch/loose_map_<titleid>.csv
```

## Output layout

Default successful output is intentionally minimal:

```text
_cxi_out/
  cxi/
    <game>.cxi

  loosepatch/
    title/
      0004000e/
        XXXXXXXX/
          content/
            00000000.app
            00000001.app

      0004008c/
        XXXXXXXX/
          content/
            00000000.app
            00000001.app
            ...
```

Optional/internal output directories are created only when needed:

```text
_cxi_out/
  _work/
    work_xxx/
      logs/
```

Created when:

- A file fails, so the work folder is kept for debugging
- `-KeepWork` is used

```text
_cxi_out/
  _logs/
    report_YYYYMMDD_HHMMSS.csv
```

Created when:

- `-ReportCsv` is used

```text
_cxi_out/
  _cci/
    <game>.cci
```

Created when:

- `-Mode CCI` or `-Mode Both` is used

```text
_cxi_out/
  _cia_install/
    <title> [0004000eXXXXXXXX].decrypted.cia
    <title> [0004008cXXXXXXXX].decrypted.cia
```

Created when:

- `-KeepInstallCia` is used

## Usage

Put your `.cia` files in the project root folder, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Force
```

By default, the script scans the current folder for `.cia` files and writes output to:

```text
.\_cxi_out
```

Default output only keeps final usable files:

```text
_cxi_out/cxi/
_cxi_out/loosepatch/
```

Temporary logs and work files are removed after a successful conversion.

### Common commands

Scan current folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Force
```

Scan recursively:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Recurse -Force
```

Use custom input/output folders:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Root "E:\3DS" -OutDir "E:\3DS\_cxi_out" -Force
```

Keep work files and logs for debugging:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Force -KeepWork
```

Generate a CSV report:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Force -ReportCsv
```

Generate both CXI and CCI where possible:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Mode Both -Force
```

Also keep rebuilt decrypted install CIA output for Update/DLC packages:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Force -KeepInstallCia
```

Debug everything:

```powershell
powershell -ExecutionPolicy Bypass -File .\Convert-CIA-To-CXI.ps1 -Force -KeepWork -ReportCsv -KeepInstallCia
```

## Report CSV

CSV reporting is disabled by default.

To generate a report, use:

```powershell
-ReportCsv
```

The report is written to:

```text
_cxi_out/_logs/report_YYYYMMDD_HHMMSS.csv
```

Useful columns include:

```text
file
status
issues
method
auto_type
install_title_id
expected_base_title_id
title_id
program_id
cxi_path
cci_path
install_cia_path
loose_install_path
log_dir
```

For successful files, temporary work logs are normally deleted. Use `-KeepWork` if you want `log_dir` paths to remain available after the run.

## Troubleshooting

### Azahar says the ROM is encrypted

Use the generated `.cxi` from:

```text
_cxi_out/cxi/
```

Do not launch the original encrypted CIA.

### Update/DLC CIA cannot be installed

Some decrypted Update/DLC CIAs may still be rejected by Azahar's CIA installer or by `makerom`.

Use the generated loose SD layout instead:

```text
_cxi_out/loosepatch/title/
```

Copy this `title` folder into Azahar/Citra's virtual SD directory.

### Update does not apply

Check the Azahar log. If it says something like:

```text
Failed to open .../title/0004000e/XXXXXXXX/content/00000000.app
```

make sure the generated loose layout was copied to the correct virtual SD path.

### DLC does not appear

Check that the DLC title id matches the base game:

```text
Base game: 00040000XXXXXXXX
DLC:       0004008cXXXXXXXX
```

The last 8 hex digits must match.

### Update/DLC title mismatch

For update titles:

```text
Update: 0004000eXXXXXXXX
Base:   00040000XXXXXXXX
```

For DLC titles:

```text
DLC:    0004008cXXXXXXXX
Base:   00040000XXXXXXXX
```

If the expected base title id does not match your game, the update/DLC package is for a different title.

### Need more debug information

Use:

```powershell
-KeepWork -ReportCsv
```

This keeps temporary work logs under:

```text
_cxi_out/_work/
```

and writes the summary report under:

```text
_cxi_out/_logs/
```

## Requirements

- Windows 7 SP1 x64 or newer
- PowerShell
- Visual C++ Redistributable for Visual Studio 2015
- Bundled Redux toolset:
  - `decrypt.exe`
  - `ctrtool.exe`
  - `makerom.exe`
  - `seeddb.bin`

## Notes

- This fork is mainly intended for emulator-oriented personal workflows.
- The original batch file is still useful for standard decryption tasks.
- This PowerShell workflow is focused on automatic CXI extraction and Azahar/Citra Update/DLC loose layout generation.
- TWL/DSi CIAs are not useful for current 3DS emulators. Use a DSi emulator such as melonDS for TWL titles.
- Do not commit real ROM/CIA/CXI/CCI output files to the repository.

## Recommended `.gitignore`

```gitignore
# Generated output
_cxi_out/

# Real game files / conversion outputs
*.cia
*.3ds
*.cci
*.cxi

# Redux temporary files
bin/tmp.*
bin/__cia_build_*/
tmp.*.ncch
tmp.*.cia
__cxi_stage*
```

## Credits

- `Batch CIA 3DS Decryptor Redux` - [xxmichibxx](https://github.com/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux)
- `Batch CIA 3DS Decryptor` - [matiffeder](https://github.com/matiffeder/3DS-stuff)
- `CTRTool.exe / makerom.exe` - [3DSGuy](https://github.com/3DSGuy/Project_CTR)
- `seeddb.bin` - [ihaveamac](https://github.com/ihaveamac/3DS-rom-tools/tree/master/seeddb)
- `decrypt.exe` - [davidmorom](https://github.com/davidmorom)
