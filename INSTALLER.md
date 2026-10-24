# 統一安裝／更新腳本 `ty.lua`

適用：ATM10 8.3、CC:Tweaked 與現有 `TY_Minecraft_ComputerCraft_Code` 專案。**只需使用同一份腳本**，依 Minecraft 電腦 ID 辨識角色。初次安裝的每台電腦仍必須有一種方式收到 `ty.lua`（遊戲拖曳 Lua 檔案或 `wget`）；沒有接收代理的電腦無法被 Rednet 隔空安裝。

## 已確認的電腦角色

| ID | 角色 | `ty.lua install` 安裝的程式 |
| ---: | --- | --- |
| 0 | 資料中心 | `dc_center.lua`、`dc_shell_host.lua`、`dc_chat_probe.lua`、`ty.lua` |
| 3 | 核電廠 | `dc_agent.lua`、`mek_send.lua`、`dc_shell_host.lua`、`ty.lua` |
| 4 | 基地 | `dc_agent.lua`、`mek_watch.lua`、`dc_shell_host.lua`、`ty.lua` |
| 6 | 新 Pocket | `dc_remote.lua`、`mek_pocket.lua`、`dc_shell_client.lua`、`ty.lua` |

未知 ID 不會猜測角色，也不會修改任何檔案。更新不碰 `startup.lua`、`dc_center.id`、核電廠的世界資料或其它自訂檔案。

## 第一次：每台電腦只需要匯入 `ty.lua`

1. 在 Windows 開啟 [ty.lua Raw](https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/ty.lua)，`Ctrl+S` 下載成 `ty.lua`；也可以於 CraftOS 用 `wget <Raw URL> ty.lua`。
2. 在遊戲內開啟電腦（返回 `>` 命令列，不是 `(lua)>`），將 `ty.lua` 從檔案總管拖進電腦視窗。
3. 執行 `ty.lua status` 先確認 ID，再執行 `ty.lua install`。會列出將安裝的檔案，輸入**大寫 `YES`** 後才寫入。
4. 程式會先下載、檢查 Lua 語法，再以暫存檔替換；若有舊版，備份為 `原檔名.tybak`。下載或驗證失敗不會覆蓋原始檔案。

## 以後：不用再逐一輸入 GitHub URL

- `ty.lua status`：只查看本機已安裝的檔案。
- `ty.lua check`：比對所有本機受管理檔案與 GitHub 的版本，**不寫入**；也可用 `ty.lua check ty.lua` 只檢查單檔。
- `ty.lua update`：**僅列出這台電腦可選擇更新的程式，不下載或改寫檔案**。
- `ty.lua update <檔名>`：例如 `ty.lua update ty.lua` 或 `ty.lua update dc_agent.lua`，**僅更新指定的一個受管理檔案**，不重新啟動執行中的程式。
- `ty.lua update all`：明確更新**這台電腦所有**角色檔案與安裝器本身；與原本的全檔更新流程一樣，如無差異不覆寫。
- `ty.lua fleet`：**僅在資料中心 #0**，透過已配對的現有 `dc_agent.lua` 安全更新基地 #4 的監控服務（必要時先停止、更新後恢復執行）。
- `ty.lua all`：**僅在資料中心 #0**，先更新資料中心程式，再執行 `fleet`；這是日後最常用的集中更新命令。

執行 `ty.lua all` 時，需要依畫面回覆 `YES`（本機檔案替換確認），與 `FLEET`（遠端更新確認）。它不會自動重啟執行中的 `dc_center.lua`，所以有更新時仍需切回資料中心主控台，輸入 `exit`，再從 Shell 執行 `dc_center.lua`。已運行的 #3、#4 代理不受影響。

選擇更新和全部更新都沿用相同的語法檢查、暫存檔、`.tybak` 備份、安裝後讀回驗證與失敗回復流程。可更新的檔名只能來自本機電腦 ID 對應的白名單，不接受任意路徑或網址；`ty.lua update all` 只作用於**本機**，不會遠端更新其他電腦。

## 舊版 ty.lua 升級到選擇更新

如果 #3 的舊管理器顯示 `Unknown command boot`，代表它尚未支援選擇更新；**不要直接在舊版下輸入 `ty.lua update ty.lua`**，因為舊版會忽略第二個參數，仍嘗試全部更新。

在 #3 的 CraftOS `>` 終端下載最新版至**另一個不存在的檔名**，例如：

```text
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/ty.lua ty_select.lua
ty_select.lua check ty.lua
ty_select.lua update ty.lua
```

依提示輸入大寫 `YES`。這只會替換磁碟上的 `ty.lua`，保留 `ty.lua.tybak`，不更新 `mek_send.lua`、不停止服務，也不會啟動或關閉反應爐。完成後才使用 `ty.lua update` 列出選項，以及 `ty.lua boot status`／`ty.lua boot on` 設定開機恢復。若 `ty_select.lua` 已存在，請改用其他未使用的檔名，避免覆寫自訂檔案。

## 核電廠專用安全規範

- **不自動更新執行中的核電廠 #3。** `ty.lua fleet` / `ty.lua all` 會跳過 #3，不會自動 SCRAM，也不會讓監控突然中斷。
- 若確定反應爐已安全停止，可在 Pocket #6 透過資料中心管理指令 `stop 3`（代理會獨立檢查 `getStatus() == false`），然後由你主動下 `update 3`、`start 3`。更新會用 GitHub 版本覆蓋 `mek_send.lua`，既有安全 CFG 設定會變更；**操作前要另存並確認原有安全設定，不可無條件更新**。
- 在 #3 本機用**新版** `ty.lua update ty.lua`、`ty.lua update dc_agent.lua` 等指令，只更換選定的非反應爐控制程式**磁碟檔案**，反應爐運轉中也可進行；不會停止或重啟目前服務，但舊程式要到下一次正常啟動才會載入新版。
- 在 #3 本機執行 `ty.lua update mek_send.lua` 或 `ty.lua update all`，仍必須確認 `getStatus() == false` 才允許覆寫；若現有 `mek_send.lua` 與最新內容不同，仍須輸入 `REPLACE`，避免默默覆蓋本機安全設定。**不能靠更新其他程式繞過此檢查**。
- 新版程式在磁碟安裝完成，不代表背景正在執行的舊程式已載入新版；必須在確認設備安全時才重啟服務。

## 管理限制

所有遠端管理仍受舊有白名單與節點配對限制，不提供任意遠端 Shell。`Rednet` 本身缺乏密碼學驗證，不可在不可信任的多人伺服器將電腦 ID 當作安全憑證。HTTP 失敗、無 ACK、離線或 Chunk 未載入時，須先檢查實際狀態，不可把失聯等同於執行失敗。

`ty.lua` 更新檔案時會保留一份 `.tybak` 舊版（後續更新會替換該備份），並在某次套用失敗時嘗試還原本次修改的檔案；若提示還原失敗，應先檢查檔案，不要直接重複執行。

> 版本狀態：原版更新流程曾通過 Lua 5.4 語法及模擬測試；本次新增的「選擇／全部更新」已做靜態分支與白名單檢查，仍須在 ATM10 8.3 實機驗證其更新結果，不能將原版測試視為新版完整通過。

## 開機自動恢復（opt-in，不會自動啟動反應爐）

從本版開始，統一安裝器可以建立 **獨立的 `startup/ty_managed.lua`**，不覆蓋既有 `startup.lua`，也不會在安裝當下停止／重新啟動任何正在執行的服務。CC:Tweaked 在下一次開機時載入這個腳本，從新的 Multishell 分頁啟動允許的程式。

| 電腦 ID | 下次開機自動開啟 | 額外規則 |
| ---: | --- | --- |
| **0** 資料中心 | `dc_center.lua` | 只啟動管理主控台，不擅自修改節點 |
| **3** 核電廠 | `dc_agent.lua` | 由代理依持久化意圖恢復 `mek_send.lua`；**絕不啟動核反應爐或 SCRAM** |
| **4** 基地 | `dc_agent.lua` | 由代理依持久化意圖恢復 `mek_watch.lua` |
| **6** Pocket | `dc_remote.lua`（可選） | 不需 `dc_agent.lua`，只開啟遠端管理終端 |

### 第一次啟用（每台電腦只需一次）

1. 先確定要操作的電腦在 CraftOS `>` Shell，而非 `dc>`、`pdc>` 或 `(lua)>`。
2. 更新或從 Windows 拖曳最新版 `ty.lua`。已使用新版安裝器時，可用 `ty.lua update ty.lua` 單獨更新；若 #3 仍是沒有 `boot` 的舊版，請先照上方「舊版 ty.lua 升級到選擇更新」步驟取得新版。**核電廠 #3 運轉中不要執行 `ty.lua update all`**，以免觸及 `mek_send.lua`。
3. 在 #0、#3、#4 各自執行：

   ```text
   ty.lua boot status
   ty.lua boot on
   ty.lua boot status
   ```

   `on` 要求輸入大寫 `BOOT`。對 #3/#4，如果現有 `dc_agent.lua` 尚未支援開機狀態持久化，安裝器會另外要求輸入大寫 `AGENT`，**只更新磁碟上的 `dc_agent.lua`，保留 `dc_agent.lua.tybootbak` 備份；不替換 `mek_send.lua` 或 `mek_watch.lua`，不停止目前運行的服務，也不修改核電廠安全設定**。#3、#4 必須先有 `dc_center.id` 且已配對資料中心 `0`。
4. Pocket #6 若也希望開機直接開啟管理終端，可執行 `ty.lua boot on`；不是必需。
5. `boot on` 只設定**下一次開機**；不會對正在執行的程式建立重複實例。原有的管理分頁應保持正常使用。

### 日後使用與停用

- `ty.lua boot status`：查看此台電腦的自動啟動設定，以及代理是否支援開機恢復。
- `ty.lua boot on`：重複執行不會再新增第二份管理分頁啟動腳本。
- `ty.lua boot off`：輸入 `OFF` 確認後，只移除安裝器所建立的 `startup/ty_managed.lua` 與對應的管理狀態檔，**不會停止當下正在執行的服務**。
- **新代理版本載入後**，資料中心／Pocket 的 `start 3/4` 會保留「開機繼續運作」狀態；`stop 3/4` 會保留「下次開機維持停止」狀態；`restart 3/4` 維持啟動意圖。反應爐運轉時的 `stop 3`／`restart 3` 安全阻擋仍有效。
- 若監控程式意外出錯，代理不會在同一次啟動中無限快速重跑；會保留錯誤以便查詢。若原本設定為開機運作，**下次重新開機才會再次嘗試**。

### 驗收與限制

1. 在各電腦用 `ty.lua boot status` 查看 `ENABLED`，#3/#4 同時確認 `Boot-aware agent: YES`、`Desired ...: RUN`。
2. **先挑基地 #4 或資料中心 #0 安排非關鍵時段重啟驗收**，檢查 #0 的主控台能自動開啟，#4 重新回到 `ONLINE / RUNNING`，基地顯示器實際有資料更新。**不要為了測試而直接重啟運轉中的核電廠 #3**；#3 請待既定安全維護或自然重載時驗收。
3. 啟用時會偵測其他 `startup.lua`、`startup/` 腳本是否已啟動同一個管理服務，發現可能重複會拒絕寫入，應檢查原有開機腳本；不會直接修改其他人的檔案。
4. 若電腦設為不允許 `shell.allow_startup`、連接磁碟有優先執行的 startup、所在 Chunk 未載入、或相關 Modem／周邊未就緒，可能無法正常恢復；請依 [CC:Tweaked 官方開機順序](https://tweaked.cc/reference/startup.html) 檢查。Ender Modem 不會自行載入 Chunk。
5. `ty.lua boot on` **不能透過舊版 `dc_agent.lua` 憑空寫入遠端電腦**。首次啟用需要各台電腦本機各執行一次（或透過玩家已有的合法本機檔案管理方式），此後才具備重啟自動恢復。資料中心 #0 與 Pocket #6 的既有查詢／遠端管理流程不變。

> **版本驗證界線**：Lua 5.4 語法檢查、舊版 12 項與新增 15 項模擬測試通過；自動重啟／重載流程尚未在使用者的 ATM10 8.3 世界中實機驗證，不能當作核電廠安全系統。

## 完整遠端 Shell 的安裝檔案

更新後的 `ty.lua` 會依電腦角色加裝：#0 與 #4 的 `dc_shell_host.lua`、#6 的 `dc_shell_client.lua`（#3 停堆維護時也能選擇安裝 Host）。執行 `ty.lua update <檔名>`／`ty.lua update all`／`ty.lua install` 僅管理磁碟檔案，**不會自動執行 `dc_shell_host.lua enable` 或解除核電廠安全鎖定**。新版資料中心與 Pocket 管理程序須重新啟動，才能使用 `pdc> shell 4`。詳見 [REMOTE_SHELL.md](REMOTE_SHELL.md)。
