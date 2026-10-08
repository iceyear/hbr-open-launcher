# HBR Open Launcher

[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · **日本語**

Steam 日本版 **ヘブンバーンズレッド**（AppID **1973710**）を Linux / Wine / Proton で起動するオープンソースランチャーと導入ツールです。

## 簡単な導入

Steam でゲームをインストールし、ゲームを終了してください。バイナリパッケージを展開し、展開したディレクトリでターミナルを開いて実行します。

```sh
./deploy.sh
```

スクリプトは Steam ライブラリ内のゲームを自動検出し、元の EXE と metadata を**ゲームのディレクトリ内にバックアップ**してから、ランチャーと現在のバージョンに対応する metadata 修復を適用します。その後、通常どおり Steam から起動してください。管理者権限は不要です。

ゲームが見つからない場合や複数のインストールが見つかる場合は、ディレクトリを指定します。

```sh
./deploy.sh --game-dir '/path/to/steamapps/common/HeavenBurnsRed'
```

バイナリパッケージには `build/HeavenBurnsRed.exe` と、静的リンクされた Linux x86-64 用ツール `build/hbr-metadata` が含まれています。導入に必要なのは Bash、一般的な Linux コマンドと `flock` です。ソースディレクトリで実行し、成果物が見つからない場合は、スクリプトが自動的に `make` を実行します。

## Steam 更新後の再適用と復元

Steam の更新が完了したら、ゲームを終了し、**同じ導入コマンドを再実行**してください。バージョンが変わるたびに、元ファイルの新しいバックアップを保存します。Steam に置き換えられず修復済みのまま残ったファイルは、記録済みの元ファイルを使用します。Steam が置き換えたファイルは新しい元ファイルとして保存します。変更がない状態で再実行しても、元のバックアップを上書きしません。

```sh
./deploy.sh status
./deploy.sh restore
```

バックアップと導入状態は `ゲームディレクトリ/.hbr-open-launcher/` に保存され、復元後も残ります。`restore` は現在適用中のバージョンに対応する二つの元ファイルを復元します。Steam がファイルを更新していた場合は、異なるバージョンを混在させないため、先に再適用してください。

metadata が未対応の場合やバックアップが破損している場合は、適用前にエラーを出します。書き込みに失敗した場合は直前の状態に戻し、中断された処理は次の実行時に復旧します。ゲーム実行中はファイルを変更しません。

### すでに別の修復を適用している場合

初回の移行では Steam の元ファイルに戻すか、**現在のゲームバージョンに対応する二つの元ファイル**を指定してください。

```sh
./deploy.sh --game-dir '/path/to/HeavenBurnsRed' \
  --original-exe '/path/to/original/HeavenBurnsRed.exe' \
  --original-metadata '/path/to/original/global-metadata.dat'
```

このオプションは導入状態がまだ記録されていない初回の移行でのみ使用できます。古い修復済みファイルを元ファイルとして保存しないためです。無関係な `.bak` ファイルが現在のバージョンに対応しているかどうかは推測しません。

## ビルドとテスト

GNU Make、Linux C コンパイラー、静的 libc、x86-64 MinGW-w64 GCC / binutils クロスコンパイラーが必要です。

```sh
make
make test
make package
```

`WINCC`、`DLLTOOL`、`HOSTCC` でコンパイラーを指定できます。静的 libc がない場合、`make HOSTLDFLAGS=` でホストの libc を利用するツールをビルドできます。互換性のあるシステムで使用してください。パッケージは `dist/` に生成されます。

GitHub Actions は二つのプログラムをビルドし、ShellCheck と合成データによる導入テストを実行して、パッケージをワークフローの成果物としてアップロードします。手動実行時に **Publish a Release** を選択すると Release を公開できます。**Release name** にタイトルを入力してください。空欄の場合はビルド番号を使います。ワークフローは `build-RUN_NUMBER-RUN_ATTEMPT` 形式の tag を生成し、パッケージを Release に添付します。

## 仕組みと対応範囲

C ランチャーはゲームの UnityPlayer.dll を読み込み、UnityMain を取得し、Unicode のコマンドラインと NULL の予約引数を正しく渡します。Windows API を直接使用します。

インポートライブラリは**リンク時に** kernel32 の名前を `KeRnEl32.dLl` にして、ネイティブローダーの大文字・小文字を区別するホスト検査に対応します。Windows / Wine では通常の kernel32 として解決されます。ASLR と DEP は有効のままです。

ネイティブ C ツールは、現在のゲームバージョンの metadata を使い、各アセンブリの MethodDef token を連番に戻します。ファイルサイズや他のフィールドを保持し、テーブルの範囲とメソッドの所属を検証します。出力先には既存ファイルを指定できません。

```sh
./build/hbr-metadata original-metadata.dat patched-metadata.dat
```

対応する metadata は **v31** のみです。更新でデータ形式やネイティブローダーの要件が変わった場合は、ツールの更新が必要になります。

## 参考とライセンス

UnityMain を利用する起動方式は [unitymain-patch](https://github.com/Irevirt/unitymain-patch/tree/bugfix/warning-cast-incompatible-function-types) と関連しています。この実装は Steam クライアントに必要な追加の互換条件にも対応しています。

ソースコードは [MIT ライセンス](LICENSE) で提供します。
