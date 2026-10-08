# HBR 開源啟動器

[English](README.md) · [简体中文](README.zh-CN.md) · **繁體中文** · [日本語](README.ja.md)

這個開源啟動器與部署工具用於在 Linux / Wine / Proton 上啟動 Steam 日版 **Heaven Burns Red**（AppID **1973710**）。

## 一鍵部署

先在 Steam 安裝遊戲，關閉遊戲視窗。解壓縮二進位發布套件，在解壓縮目錄開啟終端機，執行：

```sh
./deploy.sh
```

腳本自動尋找 Steam 遊戲庫，把原始 EXE 和 metadata **備份到遊戲目錄內**，再部署啟動器與目前版本對應的 metadata 修復。完成後從 Steam 正常啟動，不需要管理員權限。

若找不到遊戲，或發現多份安裝，可指定目錄：

```sh
./deploy.sh --game-dir '/path/to/steamapps/common/HeavenBurnsRed'
```

二進位套件內含 `build/HeavenBurnsRed.exe` 和靜態連結的 Linux x86-64 工具 `build/hbr-metadata`。部署只依賴 Bash、常用 Linux 工具及 `flock`。在原始碼目錄執行時，若缺少建置產物，腳本會自動執行 `make`。

## Steam 更新與還原

等 Steam 更新完成後，關閉遊戲，再執行**相同的部署命令**。版本變更後，腳本會儲存新的原始檔快照；Steam 未取代的補丁檔案會從已記錄的原始備份取回，Steam 取代過的檔案則備份為新版原始檔。沒有變更時重複執行，不會覆寫原始備份。

```sh
./deploy.sh status
./deploy.sh restore
```

備份與部署狀態儲存在 `遊戲目錄/.hbr-open-launcher/`，還原後仍保留備份。`restore` 恢復目前部署版本的兩個原始檔；若 Steam 已變更遊戲檔案，請先重新部署再還原，避免混用不同版本。

metadata 不受支援或備份損壞時，腳本會在部署前報錯。寫入失敗會回復操作前的狀態；中斷的交易會在下次執行時恢復。遊戲執行期間，腳本拒絕修改檔案。

### 已使用其他補丁的安裝

首次遷移時，先讓 Steam 恢復原始檔，或同時提供**與目前版本配套的兩個已知原始檔**：

```sh
./deploy.sh --game-dir '/path/to/HeavenBurnsRed' \
  --original-exe '/path/to/original/HeavenBurnsRed.exe' \
  --original-metadata '/path/to/original/global-metadata.dat'
```

只有尚未建立部署記錄的首次遷移才能使用這個選項，避免把舊補丁誤當成原始檔。腳本不會猜測其他 `.bak` 檔案是否屬於目前版本。

## 建置與測試

需要 GNU Make、Linux C 編譯器、靜態 libc，以及 x86-64 MinGW-w64 GCC / binutils 交叉編譯器：

```sh
make
make test
make package
```

可透過 `WINCC`、`DLLTOOL`、`HOSTCC` 指定編譯器。若沒有靜態 libc，可執行 `make HOSTLDFLAGS=`，產生依賴本機 libc 的原生工具。請在相容系統上使用。封裝產物儲存在 `dist/`。

GitHub Actions 會建置兩個程式、執行 ShellCheck 與合成資料部署測試，並上傳工作流程產物。手動執行工作流程時，勾選 **Publish a Release** 即可發布 Release。在 **Release name** 填寫發布標題，留空則使用建置編號。工作流程會產生 `build-RUN_NUMBER-RUN_ATTEMPT` 格式的 tag，並將封裝產物附加到 Release。

## 原理與限制

C 啟動器載入遊戲自己的 UnityPlayer.dll，取得 UnityMain，正確傳遞 Unicode 參數與 NULL 保留參數。它直接使用 Windows API。

**連結時**，匯入程式庫將 kernel32 的匯入名稱設為 `KeRnEl32.dLl`，符合原生載入器區分大小寫的宿主檢查；Windows / Wine 仍正常解析為 kernel32。ASLR、DEP 維持啟用。

原生 C metadata 工具使用目前版本的資料，依每個組件恢復連續的 MethodDef token，保持長度與其他欄位不變，並檢查資料表範圍及方法歸屬。輸出檔案必須不存在：

```sh
./build/hbr-metadata original-metadata.dat patched-metadata.dat
```

目前只支援 metadata **v31**。若遊戲更新改變了資料配置或原生載入器檢查，需要調整工具版本。

## 參考與授權

UnityMain 的啟動思路與 [unitymain-patch](https://github.com/Irevirt/unitymain-patch/tree/bugfix/warning-cast-incompatible-function-types) 相關，這個專案還實作了 Steam 客戶端需要的相容條件。

原始碼採用 [MIT 授權](LICENSE)。
