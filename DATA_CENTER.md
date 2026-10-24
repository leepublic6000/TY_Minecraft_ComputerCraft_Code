# TY 資料中心（ATM10 8.3 / CC:Tweaked）

此功能延伸現有 `mek_send.lua`、`mek_watch.lua`、`mek_pocket.lua`，**不更動反應爐與渦輪控制方法**。

## 系統角色

| 電腦 | 已知 ID | 管理內容 |
| --- | ---: | --- |
| 資料中心 Advanced Computer | 由你在遊戲內確認 | `dc_center.lua`：集中查看節點與發送受限指令 |
| 核電廠 Advanced Computer | 3 | `dc_agent.lua`：管理 `mek_send.lua` |
| 基地 Advanced Computer | 4 | `dc_agent.lua`：管理 `mek_watch.lua` |
| Pocket Computer | 6 | 可選安裝 `dc_agent.lua`：只回報在線與代理狀態；`mek_pocket.lua` 照常獨立使用 |

由於你已使用 Ender Modem，反應爐資料可以直接由 #3 發往 #4 與 Pocket #6，**資料中心不是必須經過的網路中繼站**；它負責管理層（控制台／節點代理）。這可以避免資料中心故障時連唯讀監控都一同中斷。

## 1. 資料中心：先安裝主控台

在資料中心的 Advanced Computer，返回 CraftOS `>` 命令列。確認已接上 **Wireless 或 Ender Modem**，輸入：

```text
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/dc_center.lua dc_center.lua
dc_center.lua
```

啟動後畫面顯示 `TY Data Centre | Computer #<ID>`。**記下實際 ID**；無須預先猜測這台電腦的 ID。可用已測試的 `bg shell` 保留另一個終端分頁。

執行 `nodes` 時，尚未安裝代理程式的電腦會顯示 `OFFLINE`，這是預期行為。

## 2. 每台受管理電腦：一次性安裝代理

第一次仍須在目標電腦本機安裝代理程式；**Rednet 不會自動替尚未安裝的電腦執行任意程式**。以核電廠 #3 為例：

```text
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/dc_agent.lua dc_agent.lua
dc_agent.lua pair <資料中心ID>
bg dc_agent.lua
```

將 `<資料中心ID>` 替換成資料中心主控台印出的數字。基地 #4 同樣安裝與配對。配對記錄只寫在該電腦本地的 `dc_center.id` 檔案。

**注意**：要讓資料中心管理 `mek_send.lua` / `mek_watch.lua`，請停止原先自行在其他分頁啟動的同名程式，再交給 `dc_agent.lua` 管理，避免同一電腦執行兩份監控程式。

Pocket #6 不必先安裝代理，原本的 `mek_pocket.lua` 仍能直接監控核電廠；若要在資料中心查看 Pocket 在線狀態，可以選擇安裝代理，但需讓它在 Pocket 開機／區塊載入期間持續運作。

## 3. 資料中心指令

主控台出現 `dc>` 時可使用：

```text
nodes
info 3
status 3
update 3
start 3
stop 3
restart 3
status 4
update 4
start 4
```

`nodes`：列出已知電腦，`ONLINE` 表示最近 12 秒內收到代理心跳，**不是 Minecraft 電腦硬體一定關機／開機的證明**。

`info 3`：顯示最後一次心跳的角色、核准執行檔、服務狀態與錯誤。

`status 3`：要求代理立即回報狀態。`update 3`：下載 GitHub 固定檔案 `mek_send.lua`，僅在服務已停止時允許，會保留 `.bak` 舊版。`start`／`stop`／`restart` 只操作已允許的程式；不會操作其他檔案或直接更動核反應爐設定。修改指令要求輸入 `YES` 確認。

核電廠 #3 的 `stop`／`restart` **只有在能讀到 `getStatus() == false` 時才允許**。若反應爐正在運轉或讀不到狀態，會拒絕中斷監控。`stop` 僅停止資料擷取程式，**不會 SCRAM 反應爐**。

首次部署建議順序：

1. 資料中心執行 `nodes`，確認代理 `ONLINE` 與 `Paired=YES`。
2. 核電廠 #3 執行 `update 3`、`start 3`，再用 `info 3` 確認 `RUNNING`。
3. 基地 #4 執行 `update 4`、`start 4`，確認兩面螢幕出現即時資料。
4. 全部觀察正常後才設定開機自動啟動代理，不要在同一台電腦保留其他會重複啟動 `mek_send.lua`／`mek_watch.lua` 的 startup。

## 4. 限制及安全

- **尚未經玩家的 ATM10 8.3 遊戲世界實測**。本次只有 Lua 語法與本地模擬測試，需先驗收再當成正式運作。
- Rednet 訊息**沒有密碼學身分驗證**，電腦 ID 及 `pair` 不能阻止其他玩家偽冒。這套預設只適合單人或完全可信任的私有伺服器；不要用在不可信玩家可放置電腦的伺服器。
- 不提供任意 Shell、Lua `eval`、遠端程式碼／網址參數或直接改寫核反應爐控制值。若要管理其他類型電腦的程式，需先將其加入代理端的明確白名單。
- Modem 不會替遠端區塊載入 Chunk；核電廠、資料中心與基地所在區塊都需要維持載入，才能持續收發訊息。
- 資料中心顯示 `RUNNING` 僅表示代理正在執行被管理的應用程式，不表示反應爐發電正常；需搭配原本 `mek_send.lua` 的設備數據判斷。
- `update` 使用指定 GitHub 公開 `main` 分支的最新內容；建議確認預期版本後再操作。更新失敗應核對 `.bak` 和狀態，不要直接連續重試。

參考：[CC:Tweaked Rednet](https://tweaked.cc/module/rednet.html)、[Multishell](https://tweaked.cc/module/multishell.html)、[Parallel](https://tweaked.cc/module/parallel.html)。

## Pocket #6：隨身連回資料中心 #0（2026-10-24 新增）

這是 **資料中心遠端管理**，不是直接遙控 Mekanism 反應爐。Pocket 透過 Ender Modem 把指令送到資料中心 #0，資料中心再轉送給既有的 `dc_agent.lua`。**核電廠 #3 和基地 #4 的代理程式不必重新安裝或修改。**

### 唯一一次更新資料中心 #0

舊版 `dc_center.lua` 尚未具備 Pocket 請求接收功能，因此第一次必須在 #0 的本機終端更新它。之後用 Pocket 就可管理 #3、#4，而不必在核電廠和基地之間移動。

1. 在資料中心的 `dc>` 輸入 `exit`，離開舊版控制台（不要停止 #3/#4 的代理）。
2. 在資料中心 CraftOS `>` 輸入：

   ```text
   wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/dc_center.lua dc_center_new.lua
   ```

3. 下載成功後，在 CraftOS `>` 依序執行 `move dc_center.lua dc_center_old.lua`、`move dc_center_new.lua dc_center.lua`、`dc_center.lua`。這會保留舊版作為備份；若 `dc_center_old.lua` 已存在，請換用尚未使用的備份名稱。

### Pocket #6 下載管理客戶端

在 Pocket 的 CraftOS `>`（非 `(lua)>`）輸入：

```text
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/dc_remote.lua dc_remote.lua
dc_remote.lua
```

啟動後看到 `pdc>` 即可下指令：

```text
nodes
info 3
status 3
info 4
update 4
start 4
stop 4
restart 4
exit
```

`update`、`start`、`stop`、`restart` 都要求輸入 `YES`（大小寫皆接受）。`status`、`info`、`nodes` 是查詢，不需確認。可管理的節點須已由資料中心配對、最近有心跳並且接受既有固定命令白名單；否則會回覆拒絕。**遠端控制不包含任意 Shell 指令、Lua 執行，亦不會繞過 #3 反應爐運轉中禁止停止監控的安全條件。**

`dc_remote.lua` 只負責管理資料中心，與原本直接查看核電廠數據／核分裂操作的 `mek_pocket.lua` 是不同功能，可以分別在 Pocket 內啟動。Pocket 無須安裝 `dc_agent.lua` 才能遠端管理 #3/#4；資料中心的 `nodes` 若顯示 #2 `OFFLINE`，可能只是 Pocket 沒有啟動管理代理，而不是 Pocket 無法連資料中心。

### 連線與安全限制

- 首次更新 **資料中心 #0 本機** 無法省略：舊版程式沒有接收 Pocket 遠端管理請求的能力；不能只靠 Rednet 搜尋遠端執行任意指令。
- 固定配對關係：資料中心 #0，只接受 Pocket #6 的遠端管理請求；核電廠 #3 與基地 #4 仍由現有資料中心代理接受既有白名單指令。
- Rednet **沒有強式身分驗證或加密**。Pocket ID 白名單不是密碼學安全保證；只適用單人或可信任的私人伺服器。
- 執行命令遇到 `NO ACK`、逾時或連線中斷時，**不能直接認定命令失敗或成功**，應先用 `info <id>` 確認狀態再決定是否重試。
- 資料中心、核電廠、基地電腦所在區塊仍須載入；Ender Modem 不會強制載入區塊。

> 2026-10-24 平板更換：舊 Pocket #2 已遺失，新 Pocket #6 取代其遠端管理權限。新程式必須更新並重新啟動在資料中心 #0 的 `dc_center.lua` 才會生效；要從 Pocket 直接操作核分裂反應爐，還須於安全條件允許時更新核電廠 #3 的 `mek_send.lua`。GitHub 原始碼更新不等於遊戲內正在執行的程式已更新。

## 開機自動恢復（選用）

資料中心 #0、核電廠 #3、基地 #4 可使用更新後的 `ty.lua boot on` 各自啟用開機服務。此指令不會在安裝當下中斷現有監控，也不會啟動或停止核分裂反應爐。#3、#4 的代理需支援新的持久化設定；安裝器會明確提示是否只更新代理程式的磁碟檔案。舊代理的目前執行實例不會被即時替換，要待下次重開機才能開始保留 `start`／`stop` 的意圖。首次仍需要在各台電腦本機啟用一次，不能透過尚未安裝此功能的舊代理遠端寫入開機腳本。完整指令與安全限制見 [INSTALLER.md](INSTALLER.md#開機自動恢復opt-in不會自動啟動反應爐)。
