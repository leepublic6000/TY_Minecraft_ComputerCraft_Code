# TY 遊戲內玩家登入 — 操作與驗收（實作候選版）

範圍僅限 **Minecraft 世界內的 CC:Tweaked / Advanced Peripherals 電腦與 Chat Box**。不讀取、修改雲端主機或 Minecraft 伺服器設定。

> **安全與上線狀態**：本版已進行 Lua 5.3/CC 相容語法與模擬測試，尚未在 ATM10 8.3 遊戲內驗證；**預設未啟用身分授權**，你必須從資料中心 #0 本機完成管理員註冊，並執行 `auth enable` 後才會阻擋舊有未登入的遠端管理請求。啟用前原有 ID 白名單仍有效，不能把它當成已上線的登入防護。

## 安裝方式（沿用統一安裝器）

1. 在資料中心 #0，保留原本 `dc-center` 分頁。切換到 `shell`，執行 `ty update`（使用舊安裝器更新自身）並確認 `YES`，接著再執行 `ty install`（新版安裝器安裝 `dc_auth.lua`），確認 `YES`。**兩項要連續完成，不要在中途重新啟動資料中心。**
2. 回到 `dc-center` 輸入 `exit`，在 Shell 執行 `bg dc_center.lua`，新版資料中心會載入 `dc_auth.lua`。Chat Box 已確認在資料中心 #0 的 `right`。保持其所在區塊載入。
3. 在 Pocket #6 使用 `ty update`、`ty install`，確認 `dc_remote.lua`、`dc_2fa.lua` 與 `dc_shell_client.lua` 已安裝，關閉舊的 `pdc>` 後再執行 `dc_remote.lua`。
4. 建議先不動核電廠 #3、基地 #4 的 `dc_agent.lua`、`mek_send.lua`、`mek_watch.lua`。新認證控制的是經資料中心 #0 的管理命令／完整 Shell 工作階段，不會自行操作反應爐。

## 首次註冊玩家與啟用身分驗證

在資料中心 #0 的 **本機** `dc>`：

```text
auth status
auth claim
```

主控台會顯示 `$tyclaim XXXXXXXX`（8 位數示例）。由希望成為管理員的玩家在 Minecraft 聊天輸入那一行，待 #0 顯示已收到 Chat Box 事件後，在 #0 本機輸入：

```text
auth confirm
auth status
```

這會登錄該玩家的 UUID，**不會將第一個登入 Pocket 的玩家自動提升成管理員**。若要增加另一位只能唯讀的玩家，資料中心本機執行 `auth enroll`、聊天輸入新挑戰，再 `auth confirm`。

**先確定新版 Pocket 可以執行** `dc_remote.lua`，再於 #0 本機下達 `auth enable`。這才會啟用資料中心的集中登入檢查；此後 ID #6 本身不再是登入憑證。若 Chat Box 斷線或狀態檔損壞，中心以保留現場權限為前提拒絕不可信登入，需到 #0 本機處理。

## Pocket 首次登入／信任

啟用後在 Pocket #6 的 `pdc>` 輸入 `login`，畫面會提供 `$tylogin <隨機挑戰碼>`，請在 Minecraft 聊天輸入該指令；Chat Box 收到玩家 UUID 後，以指定玩家聊天回傳六位數驗證碼。將驗證碼輸入 Pocket，通過後即取得暫時登入工作階段。

- 驗證碼 **120 秒內有效，每筆挑戰最多錯誤 5 次**；逾期或失敗後必須重新申請。
- 首次成功後詢問是否 `YES` 信任 Pocket #6。若同意，Pocket 本機 `ty_device_key.json` 保存可撤銷裝置憑證；下次開啟 `dc_remote.lua` 可嘗試自動登入。
- `pdc> logout` 登出目前工作階段，但不撤銷已信任的裝置。要全面註銷，使用聊天 `$tyrevokeall`。
- 無管理員角色的玩家只能使用資料中心的 `nodes`、`info`、`status`；不能操作遠端 Shell 或變更管理服務。

## 從其他電腦登入（Pocket 2FA）

先完成 Pocket #6 永久信任，再在 Pocket Shell **另一個分頁**執行 `bg dc_2fa.lua`。要登入的另一台電腦（例如基地 #4）需有 Wireless/Ender Modem 與 `dc_remote.lua`，在該電腦開啟 `dc_remote.lua` 並輸入 `login`，照畫面輸入 `$tylogin <挑戰碼>`。

Chat Box 確認遊戲內玩家後，六位數驗證碼會改以 Rednet 發到信任的 Pocket #6，由 `dc_2fa.lua` 分頁顯示。把驗證碼輸入發起登入的電腦。**Pocket 離線、未信任或遺失時不可自動略過第二因素**。目前這只保護透過 TY 管理中心的操作，不能阻止有實體存取權的人直接使用目標 Computer 的一般 CraftOS Shell。

## 裝置遺失／全數撤銷

玩家在 Minecraft 隱藏聊天輸入：

```text
$tyrevokeall
```

資料中心根據 Chat Box 的 UUID，將該玩家所有信任裝置憑證撤銷、全部登入工作階段作廢、清空進行中的登入挑戰，並要求既有遠端 Shell 工作階段關閉。撤銷會先保存至 #0 的 `ty_auth_state.json`（保留 `.bak`）。如私訊回覆受 Chat Box 冷卻影響，撤銷仍可能已寫入；應以 #0 本機事件記錄核對，不要盲目重複觸發。

稽核資料存在 `ty_auth_audit.jsonl`，記錄玩家 UUID、裝置、事件與時間，不記錄 OTP、裝置秘密、貼上的程式碼或 Shell 輸入。

## 重要限制 — 不要把這版當成安全的真正 SSH

- Rednet 沒有端對端加密／可靠來源驗證。Pocket 的裝置憑證和管理工作階段 Token 經 Rednet 傳送，可能被能竊聽該網路的人重播或複製。
- CC:Tweaked 提供的 `math.random` **不是加密安全亂數來源**。這套功能可供可信任的私人遊戲世界管理與身分關聯，不能宣稱能抵禦具惡意且有電腦／Modem 存取權的玩家。若將來需要面對不可信玩家，必須增加經驗證的亂數來源、訊息認證、防重放設計後，才可視為高信任登入。
- 資料中心 #0 的**直接**遠端 Shell 在啟用玩家登入後會被 Host 拒絕，以避免繞過資料中心授權。#4 的遠端 Shell 仍由 #0 中央驗證；#3 的完整 Shell 仍僅限反應爐停機維護模式。
- `mek_send.lua` 對 #4／#6 的舊式直接控制 API 尚未納入玩家登入簽章；**其遠端控制預設均為鎖定狀態，不得為了測試登入而開放**。本版是管理通道的認證整合，不應把它描述成反應爐控制通道全面完成授權改造。
- 初次啟用認證、管理員登記與撤銷緊急狀態都在 Minecraft 世界內的資料中心操作；本專案不觸及 Minecraft 伺服器實體主機。

## 驗收（先完成才適合正式使用）

- Pocket #6：成功／錯誤 OTP、120 秒過期、五次錯誤、信任裝置後重啟自動登入。
- 基地 #4：Pocket #6 收到 2FA、輸入正確才得到資料中心權限；Pocket 離線時拒絕。
- 未登入：`nodes`、`start 4`、`shell 4` 全部遭到拒絕；管理員登入後可用，唯讀玩家仍無法執行變更或完整 Shell。
- `$tyrevokeall`：撤銷所有裝置，已建立的遠端 Shell 中止；資料中心重啟後憑證也不能恢復。
- 遊戲遠距離 Chat Box 已由使用者確認收發正常；正式登入流程仍待在 ATM10 8.3 驗證。

官方依據：[Advanced Peripherals 0.8 Chat Box](https://docs.advanced-peripherals.de/0.8/peripherals/chat_box/)、[CC:Tweaked Rednet](https://tweaked.cc/module/rednet.html)。
