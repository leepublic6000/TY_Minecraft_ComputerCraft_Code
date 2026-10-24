# 統一安裝／更新腳本 `ty.lua`

適用：ATM10 8.3、CC:Tweaked 與現有 `TY_Minecraft_ComputerCraft_Code` 專案。**只需使用同一份腳本**，依 Minecraft 電腦 ID 辨識角色。初次安裝的每台電腦仍必須有一種方式收到 `ty.lua`（遊戲拖曳 Lua 檔案或 `wget`）；沒有接收代理的電腦無法被 Rednet 隔空安裝。

## 已確認的電腦角色

| ID | 角色 | `ty.lua install` 安裝的程式 |
| ---: | --- | --- |
| 0 | 資料中心 | `dc_center.lua`、`ty.lua` |
| 3 | 核電廠 | `dc_agent.lua`、`mek_send.lua`、`ty.lua` |
| 4 | 基地 | `dc_agent.lua`、`mek_watch.lua`、`ty.lua` |
| 6 | 新 Pocket | `dc_remote.lua`、`mek_pocket.lua`、`ty.lua` |

未知 ID 不會猜測角色，也不會修改任何檔案。更新不碰 `startup.lua`、`dc_center.id`、核電廠的世界資料或其它自訂檔案。

## 第一次：每台電腦只需要匯入 `ty.lua`

1. 在 Windows 開啟 [ty.lua Raw](https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/ty.lua)，`Ctrl+S` 下載成 `ty.lua`；也可以於 CraftOS 用 `wget <Raw URL> ty.lua`。
2. 在遊戲內開啟電腦（返回 `>` 命令列，不是 `(lua)>`），將 `ty.lua` 從檔案總管拖進電腦視窗。
3. 執行 `ty.lua status` 先確認 ID，再執行 `ty.lua install`。會列出將安裝的檔案，輸入**大寫 `YES`** 後才寫入。
4. 程式會先下載、檢查 Lua 語法，再以暫存檔替換；若有舊版，備份為 `原檔名.tybak`。下載或驗證失敗不會覆蓋原始檔案。

## 以後：不用再逐一輸入 GitHub URL

- `ty.lua status`：只查看本機已安裝的檔案。
- `ty.lua check`：對比 GitHub 版本，**不寫入**。
- `ty.lua update`：更新該台電腦所需的程式與安裝器本身；如無差異就不覆寫。
- `ty.lua fleet`：**僅在資料中心 #0**，透過已配對的現有 `dc_agent.lua` 安全更新基地 #4 的監控服務（必要時先停止、更新後恢復執行）。
- `ty.lua all`：**僅在資料中心 #0**，先更新資料中心程式，再執行 `fleet`；這是日後最常用的集中更新命令。

執行 `ty.lua all` 時，需要依畫面回覆 `YES`（本機檔案替換確認），與 `FLEET`（遠端更新確認）。它不會自動重啟執行中的 `dc_center.lua`，所以有更新時仍需切回資料中心主控台，輸入 `exit`，再從 Shell 執行 `dc_center.lua`。已運行的 #3、#4 代理不受影響。

## 核電廠專用安全規範

- **不自動更新執行中的核電廠 #3。** `ty.lua fleet` / `ty.lua all` 會跳過 #3，不會自動 SCRAM，也不會讓監控突然中斷。
- 若確定反應爐已安全停止，可在 Pocket #6 透過資料中心管理指令 `stop 3`（代理會獨立檢查 `getStatus() == false`），然後由你主動下 `update 3`、`start 3`。更新會用 GitHub 版本覆蓋 `mek_send.lua`，既有安全 CFG 設定會變更；**操作前要另存並確認原有安全設定，不可無條件更新**。
- 若從 #3 本機執行 `ty.lua update`，只有 `getStatus() == false` 才允許覆寫。若現有 `mek_send.lua` 與最新內容不同，會要求另外輸入 `REPLACE`，提醒安全設定可能被覆蓋。
- 新版程式在磁碟安裝完成，不代表背景正在執行的舊程式已載入新版；必須在確認設備安全時才重啟服務。

## 管理限制

所有遠端管理仍受舊有白名單與節點配對限制，不提供任意遠端 Shell。`Rednet` 本身缺乏密碼學驗證，不可在不可信任的多人伺服器將電腦 ID 當作安全憑證。HTTP 失敗、無 ACK、離線或 Chunk 未載入時，須先檢查實際狀態，不可把失聯等同於執行失敗。

`ty.lua` 更新檔案時會保留一份 `.tybak` 舊版（後續更新會替換該備份），並在某次套用失敗時嘗試還原本次修改的檔案；若提示還原失敗，應先檢查檔案，不要直接重複執行。

> 版本狀態：已通過 Lua 5.4 語法檢查及模擬測試（更新流程、無差異略過、下載失敗、語法錯誤、回滾、核電廠保護、資料中心轉送）；仍待 ATM10 8.3 遊戲內驗證。
