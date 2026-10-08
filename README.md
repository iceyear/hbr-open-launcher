# HBR Open Launcher

**English** · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

An open source launcher and deployment toolkit for the Steam Japanese client of **Heaven Burns Red** (AppID **1973710**) on Linux with Wine/Proton.

## Quick deployment

Install the game through Steam and close its window. Extract the binary package, open a terminal in the extracted directory, and run:

```sh
./deploy.sh
```

The script locates the game in your Steam libraries, saves the original EXE and metadata **inside the game directory**, and deploys the launcher and matching metadata fix. Then launch the game normally from Steam. No administrator access is required.

If the script finds no installation or more than one, specify the game directory:

```sh
./deploy.sh --game-dir '/path/to/steamapps/common/HeavenBurnsRed'
```

The binary package contains `build/HeavenBurnsRed.exe` and the statically linked Linux x86-64 tool `build/hbr-metadata`. Deployment uses Bash, standard Linux utilities, and `flock`. When run from a source checkout, the script automatically runs `make` if these outputs are missing.

## Steam updates and restore

After a Steam update finishes, close the game and run the **same deployment command again**. The script saves a new snapshot of the original files for each changed version. It recovers files that Steam leaves patched from the tracked original backup and backs up files replaced by Steam as the new originals. Running it again without changes keeps the existing backup.

```sh
./deploy.sh status
./deploy.sh restore
```

Backups and deployment state live in `GAME/.hbr-open-launcher/`. Backups are retained after restore. `restore` returns the two original files for the currently deployed version. If Steam changed files since deployment, rerun deployment before restoring to avoid mixing versions.

The script rejects invalid metadata or damaged backups before deployment. If a write fails, it rolls back to the previous installation; if a transaction is interrupted, it recovers it on the next run. It refuses to modify a running game.

### Already patched installations

For a first-time migration from another solution, restore Steam's originals first, or provide **both known original files from the matching game version**:

```sh
./deploy.sh --game-dir '/path/to/HeavenBurnsRed' \
  --original-exe '/path/to/original/HeavenBurnsRed.exe' \
  --original-metadata '/path/to/original/global-metadata.dat'
```

This migration option is accepted only when there is no tracked deployment. It prevents the script from saving a previous patch as the original. The script does not guess which unrelated `.bak` files belong to the current build.

## Build and test

Source builds need GNU Make, a Linux C compiler, static libc, and the x86-64 MinGW-w64 GCC/binutils cross compiler:

```sh
make
make test
make package
```

`WINCC`, `DLLTOOL`, and `HOSTCC` can select the compilers. If static libc is unavailable, `make HOSTLDFLAGS=` builds the native helper against the host libc; use it on a compatible system. Packaging creates source and binary archives in `dist/`.

GitHub Actions builds both programs, runs ShellCheck and synthetic deployment tests, and uploads the packages as workflow artifacts. It does not publish a release automatically.

## How it works

The C launcher loads the game's own UnityPlayer.dll, resolves UnityMain, and passes the Unicode command line with a NULL reserved argument. It uses Windows APIs directly.

The import library declares kernel32 as `KeRnEl32.dLl` **at link time**. This spelling satisfies the native loader's case-sensitive host check; it still resolves to kernel32 in Windows/Wine. ASLR and DEP remain enabled.

The native C metadata helper restores sequential MethodDef tokens independently for each assembly. It uses the installed build's metadata, preserves its length and unrelated fields, validates table ranges and method ownership, and refuses to overwrite an existing output:

```sh
./build/hbr-metadata original-metadata.dat patched-metadata.dat
```

Only metadata **v31** is supported. An update that changes the metadata layout or native loader requirements may need a new toolkit version.

## References and license

The UnityMain approach is related to [unitymain-patch](https://github.com/Irevirt/unitymain-patch/tree/bugfix/warning-cast-incompatible-function-types). The implementation here is source-built and includes the additional Steam-client compatibility requirement.

Source is licensed under [MIT](LICENSE).
