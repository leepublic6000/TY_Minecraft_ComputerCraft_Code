# TY 資料中心：玩家登入與裝置信任整合規格

**適用**：Minecraft 世界內的 ATM10 8.3／CC:Tweaked／Advanced Peripherals 0.8；資料中心 #0、核電廠 #3、基地 #4、Pocket #6。**僅處理遊戲內虛擬電腦的程式及周邊設備；不管理、檢查或修改雲端主機與 Minecraft 伺服器設定。**

**重要：本文件為實作與驗收規格，不代表登入驗證已啟用。** 現有的 `dc_center.lua`、`dc_remote.lua`、`dc_shell_host.lua` 等仍按既有管理機制運作。本輪不更動遠端指令授權，避免在 Chat Box 尚未可用時造成鎖死或認證繞過。

## 已觀察到的前置阻礙

在資料中心 #0 執行 `peripheral.find("chat_box") ~= nil` 回傳 `false`，目前**無法接收玩家聊天 UUID**。請先放置 Advanced Peripherals **Chat Box** 緊貼電腦或以 Wired Modem、Networking Cable 連接，並確認 Wired Modem 已啟用 peripheral。

安裝 Chat Box 後，在 #0 的 CraftOS Shell 先執行 `ty update`（更新安裝器本身），再執行 `ty install`（由新版安裝器安裝 `dc_chat_probe.lua`），最後用 `bg dc_chat_probe.lua` 啟動診斷。玩家於遊戲聊天輸入 `$typrobe`。預期主控台出現 `Hidden event OK`，指定玩家收到私人回覆。此階段 **不會啟用登入功能**。若遙遠位置測試收不到事件，先確認遊戲內 Chat Box 能否接收該訊息、周邊連線及程式是否持續執行，不以近距離通過推論全地圖可用。

本專案將 Chat Box 事件提供的玩家 UUID 當成**遊戲內事件資料**，不聲稱能獨立驗證玩家在遊戲外的真實身分。資料中心僅驗證事件欄位、登入挑戰、裝置憑證及授權；其他環境的設定不屬於本專案。

## 完整驗證流程（待整合實作）

1. **首次 Pocket 登入：** #6 建立登入請求並顯示 `$login <一次性請求碼>`。Chat Box 的 `chat` 事件提供 `uuid, username, message, isHidden`。只接受 `isHidden=true`、非空且有效玩家 UUID、配對請求未過期、請求碼未被使用的事件。中心用 `sendMessage(message, {player=username})` 對玩家傳送六位數 OTP，並由玩家回填到 #6。
2. **OTP 限制：** 2 分鐘有效、每個請求最多錯誤 5 次、一次使用即失效；按玩家 UUID／裝置／來源電腦實施重試節流，避免簡單重建請求繞過限制。使用安全亂數來源，不能把可預測的 `math.random` 當作加密安全 OTP 或永久授權密鑰來源。需記錄失敗、過期、鎖定及撤銷結果。
3. **永久信任裝置：** 使用獨立可撤銷裝置憑證，玩家確認後才核發；期限為「直到撤銷」，不是永久無身分檢查。不得只依據 Rednet 電腦 ID 取得權限；裝置被他人持有、憑證被複製或資料中心重載都需要正確處理。要抗防竊聽／偽冒需額外採用經驗證的訊息認證、加密、防重放機制與可靠金鑰亂數來源。
4. **其他電腦登入（2FA）：** 使用既有、在線且未撤銷的 Pocket 接收一次性核准請求／驗證碼，綁定申請電腦、玩家 UUID、時間與單次登入；沒有可信 Pocket 時只能進入明確的復原流程，不能跳過驗證。
5. **遺失裝置：** 玩家送出隱藏 `$revokeall`；中心依可信的 Chat Box 玩家 UUID 撤銷該玩家全部裝置憑證、管理登入與遠端 Shell 工作階段，也取消尚未完成的 OTP。撤銷狀態先可靠寫入磁碟再發成功回覆；下次開機不得恢復舊憑證。
6. **權限／審計：** 在資料中心本機明確綁定可管理者的 UUID。所有管理指令與 Shell 開啟、維持、關閉、實際目標與執行結果都應由資料中心執行授權檢查，必要時於目標 Host 再驗證；不能只保護 Pocket 畫面。稽核避免保存 OTP、裝置密鑰、貼上內容或其他秘密。

## 上線門檻

- Chat Box 接線、隱藏訊息、指定玩家私訊及跨位置事件收取均經你的 Minecraft 世界內實測。
- 資料中心只使用遊戲內 Chat Box 事件回傳的 UUID 與玩家名稱；缺少身分欄位或無法關聯到登入挑戰時一律拒絕，不聲稱已驗證遊戲外身分。
- 持久化裝置憑證／撤銷狀態、重開機、速率限制、五次錯誤、兩分鐘失效、2FA 離線情況與未授權操作均通過測試。
- 中心 `dc_center.lua` 對所有管理指令與 Shell 訊息實施統一驗證，沒有舊版直通繞過；`mek_send.lua` 等直接 Rednet 控制管道另外核對安全邊界。
- 核電廠保留原本的獨立安全保護；認證程式不能在未測試的情況下修改啟停、SCRAM 或燃燒速率設定。

官方參考：[Advanced Peripherals 0.8 Chat Box](https://docs.advanced-peripherals.de/0.8/peripherals/chat_box/)、[CC:Tweaked peripherals](https://tweaked.cc/module/peripheral.html)。
