# Batch CIA 3DS Decryptor Redux
Decrypting Nintendo 3DS games and applications (.3ds, .cia)

Batch CIA 3DS Decryptor Redux is a rewritten version of the Batch CIA 3DS Decryptor by matiffeder.

Original thread: https://gbatemp.net/threads/batch-cia-3ds-decryptor-a-simple-batch-file-to-decrypt-cia-3ds.512385/

![GitHub Release](https://img.shields.io/github/v/release/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux) ![Issues](https://img.shields.io/github/issues/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux) ![GitHub Repo stars](https://img.shields.io/github/stars/xxmichibxx/Batch-CIA-3DS-Decryptor-Redux) 

## Redux features
* Improved error handling. Invalid CIAs, already decrypted and TWL CIAs will be detected.
* Improved script logging. Logging title, title version. Check programlog.txt for more details in the log folder.
* Proper CIA versioning. Decrypted files will use the same version as the source file. No more version 0 for update CIAs.
* Fixed decryption for CIA Demo titles and System titles
* Updated CTRTool to v1.2.0 (x64)
* Updated makerom.exe to v0.18.4 (x64)
* Including seeddb.bin for games using seed crypto introduced in 9.6.0-24

## Original features
* DLC/Patch CIA > Decrypted CIA, able to install in Citra
* 3DS Games > Decrypted and trimmed 3DS, so it is smaller
* CIA Games > Decrypted CCI (NCSD), not CXI (NCCH)
* Auto detect CIA type (DLC/Patch/Game)

## Usage
* Copy CIA or 3DS files into the root directory containing the batch
* Run "Batch CIA 3DS Decryptor Redux.bat"

## Supported operating systems
* Windows XP (x64) or higher
* Windows Server 2003 R2 (x64) or higher

## Notes
* Already decrypted CIA files won't be converted to CCI. This tool is still a decrypter, not a converter.
* TWL files (Nintendo DSi) are not compatible with CTRTool. TWL CIAs do not need to be decrypted.

## Credits
* `Batch CIA 3DS Decryptor` - [matiffeder](https://github.com/matiffeder/3DS-stuff)
* `CTRTool.exe/MakeROM.exe` - [3DSGuy](https://github.com/3DSGuy/Project_CTR)
* `seeddb.bin` - [ihavamac](https://github.com/ihaveamac/3DS-rom-tools/tree/master/seeddb)
* `decrypt.exe` - 54634564
