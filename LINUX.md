# Native Linux port

`Batch_CIA_3DS_Decryptor_Redux_Linux.sh` is a native Bash port of the Windows batch workflow. It does not require Wine.

The Linux port uses:

- [`ctrdecrypt`](https://github.com/shijimasoft/ctrdecrypt) to decrypt CIA/3DS NCCH content
- [`ctrtool`](https://github.com/3DSGuy/Project_CTR) to inspect title metadata
- [`makerom`](https://github.com/3DSGuy/Project_CTR) to rebuild decrypted CIA/CCI images
- `seeddb.bin` for seed-crypto titles

## Requirements

- Linux x86_64 for automatic tool downloads
- Bash 4 or newer
- `curl`, `unzip`, and standard GNU userland tools

Other Linux architectures can be used when compatible `ctrdecrypt`, `ctrtool`, and `makerom` binaries are installed manually and supplied with `--tools-dir`.

## Quick start

Copy the script into a working directory containing your legally obtained `.cia` or `.3ds` files, then run:

```bash
chmod +x Batch_CIA_3DS_Decryptor_Redux_Linux.sh
./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --install-tools
```

The downloaded native tools are stored in `bin-linux/` beside the script.

By default, the script asks whether supported game CIAs should be converted to CCI when run interactively. In noninteractive use, decrypted CIA files are kept unless `--convert-to-cci` is supplied.

## Common commands

Keep decrypted CIA files:

```bash
./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --no-convert-to-cci
```

Convert supported game CIAs to CCI:

```bash
./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --convert-to-cci
```

Process files in another directory:

```bash
./Batch_CIA_3DS_Decryptor_Redux_Linux.sh \
  --input-dir "/path/to/3DS files"
```

Replace existing output files:

```bash
./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --force
```

Show every option:

```bash
./Batch_CIA_3DS_Decryptor_Redux_Linux.sh --help
```

## Output and logs

Outputs are written beside the input files. Logs are written to:

```text
log/programlog-linux.txt
```

Each input is processed in its own temporary directory to avoid partition files from one title interfering with another. The source ROM is hard-linked or reflinked into that directory where supported, avoiding a full multi-gigabyte copy.

## Current limitation

TWL/DSi CIA titles with title IDs beginning `00048` are not supported by the native `ctrdecrypt` backend. The script detects these titles and reports them instead of producing an invalid file.

If native decryption fails for a title, decrypting it on original 3DS hardware remains the safest fallback.

## Legal note

Use this only with content and keys you are legally permitted to access. No ROM files or downloaded tool binaries are included in this repository.
