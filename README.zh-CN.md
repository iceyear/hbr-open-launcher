# HBR 开源启动器

[English](README.md) · **简体中文** · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md)

这个开源启动器与部署工具用于在 Linux / Wine / Proton 上启动 Steam 日版 **Heaven Burns Red**（AppID **1973710**）。

## 一键部署

先在 Steam 安装游戏，关闭游戏窗口。解压二进制发布包，在解压目录打开终端，执行：

```sh
./deploy.sh
```

脚本自动查找 Steam 库，把原 EXE 和 metadata **备份到游戏目录内**，再部署启动器和当前版本对应的 metadata 修复。完成后从 Steam 正常启动，无需管理员权限。

如果找不到游戏，或找到多份安装，可指定目录：

```sh
./deploy.sh --game-dir '/path/to/steamapps/common/HeavenBurnsRed'
```

二进制包内有 `build/HeavenBurnsRed.exe` 和静态链接的 Linux x86-64 工具 `build/hbr-metadata`。部署只依赖 Bash、常用 Linux 工具和 `flock`。在源码目录运行时，如果缺少构建产物，脚本会自动执行 `make`。

## Steam 更新与还原

等 Steam 更新完成后，关闭游戏，再运行**相同的部署命令**。版本变化后，脚本会保存新的原文件快照；Steam 没有替换的补丁文件会从已记录的原始备份取回，Steam 替换过的文件则备份为新版原文件。没有变化时重复运行，不会覆盖原始备份。

```sh
./deploy.sh status
./deploy.sh restore
```

备份和部署状态保存在 `游戏目录/.hbr-open-launcher/`，还原后保留备份。`restore` 恢复当前部署版本的两个原文件；如果 Steam 已改变游戏文件，请先重新部署，再还原，避免混用不同版本。

metadata 不受支持或备份损坏时，脚本会在部署前报错。写入失败会回滚到操作前的状态；中断的事务会在下次执行时恢复。游戏运行期间，脚本拒绝修改文件。

### 已经使用其他补丁的安装

首次迁移时，先让 Steam 恢复原文件，或者同时提供**与当前版本配套的两个已知原文件**：

```sh
./deploy.sh --game-dir '/path/to/HeavenBurnsRed' \
  --original-exe '/path/to/original/HeavenBurnsRed.exe' \
  --original-metadata '/path/to/original/global-metadata.dat'
```

只有尚未建立部署记录的首次迁移才能使用这个选项，避免把旧补丁误认为原文件。脚本不会猜测其他 `.bak` 文件是否属于当前版本。

## 构建与测试

需要 GNU Make、Linux C 编译器、静态 libc，以及 x86-64 MinGW-w64 GCC / binutils 交叉编译器：

```sh
make
make test
make package
```

可通过 `WINCC`、`DLLTOOL`、`HOSTCC` 指定编译器。如果没有静态 libc，可执行 `make HOSTLDFLAGS=`，生成依赖本机 libc 的原生工具。请在兼容系统上使用。打包产物保存在 `dist/`。

GitHub Actions 会构建两个程序、执行 ShellCheck 与合成数据部署测试，并上传工作流产物；不会自动公开发布 Release。

## 原理与限制

C 启动器加载游戏自己的 UnityPlayer.dll，解析 UnityMain，正确传递 Unicode 参数和 NULL 保留参数。它直接使用 Windows API。

**链接时**，导入库把 kernel32 的导入名写为 `KeRnEl32.dLl`，满足原生加载器区分大小写的宿主检查；Windows / Wine 仍正常解析为 kernel32。ASLR、DEP 保持启用。

原生 C metadata 工具使用当前版本的数据，按每个程序集恢复连续的 MethodDef token，保持长度和其他字段不变，并检查表范围及方法归属。输出文件必须不存在：

```sh
./build/hbr-metadata original-metadata.dat patched-metadata.dat
```

目前只支持 metadata **v31**。如果游戏更新改变了数据布局或原生加载器检查，需要适配新的工具版本。

## 参考与许可

UnityMain 的启动思路与 [unitymain-patch](https://github.com/Irevirt/unitymain-patch/tree/bugfix/warning-cast-incompatible-function-types) 相关，这个项目还实现了 Steam 客户端所需的兼容条件。

源码采用 [MIT 许可](LICENSE)。
