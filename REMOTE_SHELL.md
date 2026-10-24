# TY 完整遠端 Shell（ATM10 8.3／CC:Tweaked）

本功能針對現有的資料中心 #0、基地 #4、核電廠 #3、Pocket #6，提供類似 SSH 的 **互動式 CraftOS 終端**：可在 Pocket 上使用 `ls`、`cd`、`edit`、`ty.lua update <檔名>`、執行 Lua，以及管理目標電腦檔案。它是目標電腦內的另一個 Shell 工作階段，不是畫面截取 Minecraft 本身、也不是強制接管原有監控分頁。

**安全前提：本系統的 Rednet 沒有加密或密碼學來源驗證。它具有執行任意程式的權限，僅可使用於你自己控制的單人世界／完全可信任的私人伺服器。若伺服器有不可信任的玩家能放置 ComputerCraft 電腦，請不要啟用。**

## 連線路徑

```text
Pocket #6 － Rednet －> 資料中心 #0 － Rednet －> 基地 #4
                                     \－> 核電廠 #3（反應爐停機時）
Pocket #6 － Rednet －> 資料中心 #0 本身的獨立 Shell（目標 #0）
```

資料中心 `dc_center.lua` 仍負責已配對節點的 `nodes/info/start/stop/update`。新增終端通道會檢查來源 #6、目標節點是否已配對 #0、其連線狀態，再把畫面／按鍵在 Pocket 與指定節點之間轉送。舊 Pocket #2 沒有連線權限。服務端 `dc_shell_host.lua` 由各目標電腦**本機手動**允許，預設關閉；不改動原本的 `dc_agent.lua`、`mek_send.lua`、`mek_watch.lua` 的執行邏輯。

| 檔案 | 安裝在 | 功能 |
| --- | --- | --- |
| `dc_center.lua` | #0 | 新增完整終端訊息轉接；原有管理命令保留 |
| `dc_shell_host.lua` | #0、#4；#3 維護時選用 | 目標端建立隔離的 CraftOS Shell 並傳輸畫面 |
| `dc_remote.lua` | Pocket #6 | 在 `pdc>` 新增 `shell <id>` 指令 |
| `dc_shell_client.lua` | Pocket #6 | 即時顯示遠端 Shell、傳送鍵盤、滑鼠及貼上事件 |
| `ty.lua` | 四台電腦 | 統一下載新程式；仍遵守核電廠安全更新限制 |

## 首次部署順序（每個目標電腦只做一次）

### A. 資料中心 #0

在管理主控台 `dc>` 輸入 `exit` 退出舊版；切至 CraftOS `>`：

```text
ty.lua update all
ty.lua install
```

這兩個動作先更新現有 `dc_center.lua`、`ty.lua`，再讓新安裝器補齊 `dc_shell_host.lua`。確認替換提示後輸入大寫 `YES`。只更新**磁碟檔案**，不會重新啟動當前所有電腦。

接著**在本機**允許資料中心 Shell：

```text
dc_shell_host.lua enable
```

鍵入大寫 `ENABLE`。完成後：

```text
bg dc_shell_host.lua
bg dc_center.lua
```

這會產生兩個獨立的分頁：一個負責遠端 Shell 主機，另一個負責資料中心管理；不會影響 #3、#4 的服務。

### B. 新 Pocket #6

在 CraftOS `>`：

```text
ty.lua update all
ty.lua install
dc_remote.lua
```

如果先前尚未有 `ty.lua`，可從 GitHub Raw [ty.lua](https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/ty.lua) 下載並拖入 Pocket。新版 `ty.lua install` 會補齊 `dc_shell_client.lua`。完成後 `dc_remote.lua` 的 `pdc>` 指令支援：

```text
nodes
shell 0
shell 4
```

進入遠端 Shell 後，直接輸入該電腦上的 CraftOS 指令，例如：

```text
ls
ty.lua boot status
edit startup.lua
```

按 **F10** 或點 Pocket 畫面右上角 `[X]`，結束遠端工作階段並回到 `pdc>`；遠端 Shell 內輸入 `exit` 也能離開。一次只有一個 Pocket 工作階段能占用同一目標的遠端 Shell。

### C. 基地 #4

**必須先在基地本機執行一次**，因為舊版 `dc_agent.lua` 並沒有執行任意命令或安裝其他管理服務的能力。可利用 Windows 檔案拖曳方式，不必在遊戲輸入長網址：

```text
ty.lua update all
ty.lua install
dc_shell_host.lua enable
bg dc_shell_host.lua
```

在 `enable` 提示輸入大寫 `ENABLE`。這項設定會產生 `startup/ty_shell_host.lua`，使往後開機自動執行遠端 Shell 服務。它與原本的 `startup/ty_managed.lua`、`dc_agent.lua` 是**不同分頁**，不會再啟動一份監控程式。

完成首次本機安裝後，從 Pocket #6 `pdc>` 輸入 `shell 4` 就能遠端操作基地電腦，使用 `ty.lua update <檔名>`、`ty.lua update all`、`ty.lua boot on` 等本來只會在本機執行的命令。這才是完整遠端更新的主要用途。

### D. 核電廠 #3（安全維護時才開放）

**核分裂反應爐運轉中不開放完整 Shell。** 原因：完整 Shell 可直接呼叫 Mekanism API，繞過 `mek_send.lua` 的燃燒速率與啟停控制鎖定。主機 `dc_shell_host.lua` 在開啟工作階段時要求反應爐 `getStatus() == false`，運作期間也會持續檢查；一旦反應爐開始運轉就關閉遠端 Shell。這項檢查不是核電廠本身的安全聯鎖，也無法保證使用者在遠端 Shell 內執行的每一條指令都安全。

未安排核電廠維護時，**不必做這一步**。若已停止反應爐並確認實際冷卻與安全機制正常，可將 `dc_shell_host.lua` 從 GitHub 下載到核電廠（不要為此使用 `ty.lua update all` 覆蓋現有 `mek_send.lua`；可用新版安裝器 `ty.lua update dc_shell_host.lua` 單獨更新該檔案），然後本機輸入：

```text
dc_shell_host.lua enable
```

核電廠會要求輸入 `PLANT` 才允許；接著 `bg dc_shell_host.lua`。日後在 Pocket 用 `shell 3` 遠端維護。運轉中的核電廠仍透過既有的**受限** `dc_remote.lua`、`dc_agent.lua` 管理指令及安全監控，不靠完整 Shell。

## 停用、錯誤與驗收

- 目標電腦本機 `dc_shell_host.lua status` 可檢查是否啟用。`dc_shell_host.lua disable` 輸入 `DISABLE` 後，會移除本功能自己的開機啟動檔與啟用旗標，不停止既有核電廠／基地監控；現行遠端 Shell 於下一輪事件檢查後停止。
- 若 Pocket 顯示 `TIMEOUT`，先檢查資料中心是否已重新啟動**新版** `dc_center.lua`、目標電腦的 Shell Host 分頁是否正常、Ender Modem 是否可用，以及所在 Chunk 是否有載入。單純從 GitHub 更新磁碟文件不代表已運行的舊版程式自動更新。
- 先驗收 `shell 0`：看到資料中心的 CraftOS 提示符且 `id` 回傳 `0`；再驗收 `shell 4`：使用 `id` 應回傳 `4`，在遠端 `ls` 和 `ty.lua boot status` 應可執行。退出後 #0／#4 原本的管理服務必須維持 `RUNNING`。
- 測試核電廠 #3 時先確定已停機；**不要為了驗證完整 Shell 強制停止或重新啟動反應爐**。
- Rednet 工作階段超過 45 秒沒有資料交換會逾時。重連時應用全新工作階段；不要把 `NO ACK` 當成遠端命令確定沒執行。

## 驗證狀態

新版已完成 Lua 5.4 語法檢查及隔離終端、事件轉送、資料中心訊息路由的模擬測試。**尚未在你的 ATM10 8.3 遊戲環境內實測完整 Shell、文字編輯器與 Modem 間的實際終端畫面傳輸；正式使用前請依序驗收。**

參考：[CC:Tweaked window](https://tweaked.cc/module/window.html)、[term](https://tweaked.cc/module/term.html)、[multishell](https://tweaked.cc/module/multishell.html)、[rednet](https://tweaked.cc/module/rednet.html)。

## 特別修正：遠端 Shell 不會重新執行開機初始化

遠端 Shell 透過 `os.run({shell=shell, multishell=false}, "/rom/programs/shell.lua")` 啟動，明確繼承當前 CraftOS Shell 環境；這避免把它誤判為最上層 Shell，重跑 `/rom/startup.lua`、`startup/` 自動啟動程式。遠端 Shell 的 `multishell` 分頁控制刻意關閉，防止遠端建立目標電腦的前景分頁。這項設計已加入模擬檢查，但仍需在 ATM10 8.3 現場驗證。
