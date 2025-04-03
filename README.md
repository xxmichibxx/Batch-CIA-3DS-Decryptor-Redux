<h3 align="center">Batch CIA 3DS Decryptor Redux</h3>
<p align="center"><a href="https://github.com/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux"><img src="https://i.imgur.com/tm9OXKI.png)" alt="Logo" width="100" height="100"></a></p>
<h3 align="center">A batch for decrypting Nintendo 3DS games and applications (3DS/CIA files)</h3>
<hr>

Batch CIA 3DS Decryptor Redux is a rewritten version of the Batch CIA 3DS Decryptor by matiffeder.

Original thread: https://gbatemp.net/threads/batch-cia-3ds-decryptor-a-simple-batch-file-to-decrypt-cia-3ds.512385/

![GitHub Release](https://img.shields.io/github/v/release/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux) ![Issues](https://img.shields.io/github/issues/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux) ![GitHub Repo stars](https://img.shields.io/github/stars/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux) 

## Redux features
* Improved error handling: Invalid and already decrypted CIAs will be detected.
* Improved script logging: Logging title, title version. Check programlog.txt for more details in the log folder.
* Proper CIA versioning: Decrypted files will use the same version as the source file. No more version 0 for update CIAs.
* Fixed decryption for CIA Demo, System and TWL titles
* Updated CTRTool to v1.2.1 (x64)
* Updated makerom.exe to v0.18.4 (x64)
* Including seeddb.bin for games using seed crypto introduced in 9.6.0-24

## Original features
* DLC/Patch CIA: Decrypted CIA, able to install in emulators
* 3DS Games: Decrypted and trimmed 3DS, so it is smaller
* CIA Games: Decrypted CCI (NCSD), not CXI (NCCH)
* Auto detect CIA type (DLC/Patch/Game)

## Usage
* Copy CIA or 3DS files into the root directory containing the batch
* Run "Batch CIA 3DS Decryptor Redux.bat"

## Requirements
* Windows 7 SP1 (x64) or higher
* Windows Server 2008 R2 SP1 (x64) or higher
* Visual C++ Redistributable for Visual Studio 2015

## Notes
* It's strongly recommended to move all processed files to your desired destination. Further decryption processes may interfere with already processed files. For example, the CCI conversion function deletes all decrypted CIAs after conversion, regardless of success.
* Already decrypted CIA files won't be converted to CCI. This tool is still a decrypter, not a converter.
* TWL CIAs (DSi) can be decrypted, but should only be installed on retail consoles. Current 3DS emulators don't support TWL CIAs. Use a DSi emulator like melonDS for playing TWL titles.
* Files with an exclamation mark cannot be decrypted. The decryptor will report them as invalid because it is unable to find them.

## Credits
* `Batch CIA 3DS Decryptor` - [matiffeder](https://github.com/matiffeder/3DS-stuff)
* `CTRTool.exe/MakeROM.exe` - [3DSGuy](https://github.com/3DSGuy/Project_CTR)
* `seeddb.bin` - [ihavamac](https://github.com/ihaveamac/3DS-rom-tools/tree/master/seeddb)
* `decrypt.exe` - 54634564
