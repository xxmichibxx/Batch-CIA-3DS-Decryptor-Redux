<h3 align="center">Batch CIA 3DS Decryptor Redux</h3>
<p align="center"><a href="https://github.com/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux"><img src="https://i.imgur.com/tm9OXKI.png)" alt="Logo" width="100" height="100"></a></p>
<h3 align="center">A batch for decrypting Nintendo 3DS games and applications (3DS/CIA files)</h3>
<hr>

Batch CIA 3DS Decryptor Redux is a rewritten version of the Batch CIA 3DS Decryptor by matiffeder.

Original thread: https://gbatemp.net/threads/batch-cia-3ds-decryptor-a-simple-batch-file-to-decrypt-cia-3ds.512385/

> [!IMPORTANT]  
> I'm currently rewriting the script for version 1.0.7. Because of this, larger pull requests or issues will be addressed at a later time.

![GitHub Release](https://img.shields.io/github/v/release/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux?style=flat) ![GitHub Repo stars](https://img.shields.io/github/stars/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux?style=flat) ![Issues](https://img.shields.io/github/issues/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux?style=flat) 

## Redux features
* Improved error handling: Invalid and already decrypted CIAs will be detected.
* Improved script logging: Logging title, title version. Check programlog.txt for more details in the log folder.
* Proper CIA versioning: Decrypted files will use the same version as the source file. No more version 0 for update CIAs.
* Fixed decryption for CIA Demo, System and TWL titles
* Fixed invalid NCCH decryption with crypto seed titles (thanks to @davidmorom)
* Updated CTRTool to v1.2.1 (x64)
* Updated makerom.exe to v0.18.4 (x64)
* Including seeddb.bin for games using seed crypto introduced in 9.6.0-24

## Original features
* DLC/Patch CIA: Decrypted CIA, able to install in emulators
* 3DS Games: Decrypted and trimmed 3DS, so it is smaller
* CIA Games: Decrypted CCI (NCSD), not CXI (NCCH)
* Auto detect CIA type (DLC/Patch/Game)

## Usage

### Windows
* Copy CIA or 3DS files into the root directory containing the batch
* Run `Batch CIA 3DS Decryptor Redux.bat`

### Linux
A native Bash port is available as `Batch_CIA_3DS_Decryptor_Redux_Linux.sh` and does not require Wine.

```bash
chmod +x Batch_CIA_3DS_Decryptor_Redux_Linux.sh
./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --install-tools
```

See [LINUX.md](LINUX.md) for setup, options, limitations, and troubleshooting.

## Requirements

### Windows
* Windows 7 SP1 (x64) or higher
* Windows Server 2008 R2 SP1 (x64) or higher
* Visual C++ Redistributable for Visual Studio 2015

### Linux
* Linux x86_64 for automatic native-tool downloads
* Bash 4 or newer
* `curl` and `unzip`

## Notes
* It's strongly recommended to move all processed files to your desired destination. Further decryption processes may interfere with already processed files. For example, the CCI conversion function deletes all decrypted CIAs after conversion, regardless of success.
* Already decrypted CIA files won't be converted to CCI. This tool is still a decrypter, not a converter.
* TWL CIAs (DSi) can be decrypted by the Windows version, but should only be installed on retail consoles. Current 3DS emulators don't support TWL CIAs. Use a DSi emulator like melonDS for playing TWL titles. Decrypting TWL titles will remove the manual because makeROM offers no parameter for adding manuals.
* The native Linux backend currently does not support TWL/DSi CIA titles.
* Please avoid filenames with Japanese, Cyrillic, or Arabic characters when using the Windows batch. The Linux wrapper handles shell quoting, but the underlying CTRTool/MakeROM utilities can still have limitations with non-ASCII paths.

## Credits
* `Batch CIA 3DS Decryptor` - [matiffeder](https://github.com/matiffeder/3DS-stuff)
* `CTRTool.exe/MakeROM.exe` and native Linux builds - [3DSGuy](https://github.com/3DSGuy/Project_CTR)
* `seeddb.bin` - [ihavamac](https://github.com/ihaveamac/3DS-rom-tools/tree/master/seeddb)
* `decrypt.exe` - [davidmorom](https://github.com/davidmorom)
* Native `ctrdecrypt` backend - [shijimasoft](https://github.com/shijimasoft/ctrdecrypt)
