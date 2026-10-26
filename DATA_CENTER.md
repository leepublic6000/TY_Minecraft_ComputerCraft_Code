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

## 資料中心 #0 上方 Advanced Monitor 狀態看板（2026-10-26）

已直接擴充原有 `dc_center.lua`（搭配 `dc_auth.lua` 的唯讀工作階段查核）：資料中心 #0 的 Advanced Monitor 將顯示已知電腦 #0、#3、#4、#6 狀態，**不必安裝或另開顯示程式**，管理主控台原有 `dc>`、玩家登入、平板解鎖等功能保留。

| 顯示項目 | 資料來源與精確意義 |
| --- | --- |
| `#0 CENTRE ONLINE` | 資料中心目前的程式正在執行（螢幕本身無法在 #0 斷電時持續更新） |
| `#3 NUCLEAR` | 每約 3 秒收到的 `dc_agent.lua` 心跳；距離上次心跳超過 12 秒顯示 `OFFLINE`，同時標示最後回報的 `APP RUNNING/STOPPED/ERROR` |
| `#3 TELEMETRY LIVE/STALE/NO DATA` | **另外追蹤** `mek_send.lua` 的 `ty_mek_control_v1:data` 廣播；超過 5 秒沒有新資料顯示 `STALE`。管理代理 `RUNNING` 不等於監控資料有送達 |
| `#4 BASE` | #4 管理代理的心跳連線及 `mek_watch.lua` 服務狀態 |
| `#6 POCKET PDC LIVE/AGENT LIVE/STALE/NO SIGNAL` | 優先使用已登入的 #6 `dc_remote.lua` 活動心跳，若另有配對中的 `dc_agent.lua` 可改用其心跳；超過 12 秒沒有新訊號顯示 `STALE`／`NO SIGNAL`。**這是軟體心跳，不等同於平板硬體開關狀態** |

### 在遊戲中套用

1. 把上方 **Advanced Monitor 接到資料中心 Computer #0**；若緊貼電腦上方，可由 `top` 周邊直接存取；不相鄰時需以 Wired Modem/網路線連接。程式優先選擇 `top`，否則選取面積最大的已連線顯示器。
2. 在 #0 的 **CraftOS `>` 分頁**依序執行 `ty.lua update dc_auth.lua`、`ty.lua update dc_center.lua`，只更新資料中心的兩個磁碟檔案。從原本的 `dc>` 主控台輸入 `exit` 後，回到 Shell 執行 `bg dc_center.lua` 讓新版生效，**不要保留兩份中心程式**。這會短暫中斷資料中心管理通訊，但不會直接重啟核電廠 #3 或基地 #4。兩者須搭配更新，否則 Pocket 心跳不會被辨識，但舊版 `dc_auth.lua` 不會讓新版資料中心整個崩潰。
3. 更新並重新啟動 Pocket #6 的 `dc_remote.lua`（`ty.lua update dc_remote.lua`）；完成管理員登入後，平板管理程式會每約 3 秒傳送活動心跳。當 Pocket 改用 `mek_pocket.lua`、Lua 或關閉 `dc_remote.lua`，看板上的 `PDC` 心跳會到期，即使平板本身仍在使用。顯示器心跳不會自動延長原本 30 分鐘的登入閒置期限，認證過期需自行重新登入。
4. 在 #0 的 `dc>` 可用 `monitor` 查詢目前偵測到的顯示器名稱與字元尺寸；若看板仍是黑色，先確認連接、`monitor` 指令結果及 #0 是否確實重新載入了新版。顯示器可依可用字元自動調整文字大小；斷線時會定期嘗試重新偵測。

看板只是唯讀狀態顯示，不會啟停反應爐或解除控制面板權限。Rednet 心跳只能判定「指定時間內是否收到訊息」，不是設備硬體健康、反應爐狀態或強式身分認證的證明。

**版本界線**：GitHub 修改及靜態程式檢查不等於已在你的 ATM10 8.3 遊戲畫面驗證；使用者仍需按上述步驟在 #0/#6 載入新版才會顯示資訊。不需要修改 #3 的 `mek_send.lua` 或 #4 的 `mek_watch.lua`。

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

Pocket #6 不必先安裝代理，`mek_pocket.lua` 仍能直接唯讀監控核電廠。新版資料中心看板會利用已驗證的 `dc_remote.lua` 活動心跳顯示 `PDC LIVE`，無須額外安裝代理；但如果該管理程式沒執行，不能把 `NO PDC` 當成 Pocket 整台電腦離線。

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
monitor
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

## 基地控制面板的 Pocket 授權解鎖

新版 `dc_remote.lua`、`dc_center.lua`、`mek_watch.lua` 支援「#6 授權、#4 操作、#3 保留設備安全限制」；**只更新程式原始碼不會改變目前運作中的分頁**。

### 三台電腦部署（不修改核電廠 #3）

1. **#0 資料中心**：從 CraftOS Shell 執行 `ty.lua update dc_center.lua`（必須是支援單檔的新版 `ty.lua`），成功後退出舊版 `dc>` 並重新從 Shell 啟動 `dc_center.lua`；原本的玩家登入狀態檔不修改，但執行中的工作階段需重新登入/信任裝置恢復。確認 `dc> auth status` 顯示 `Auth: ENABLED`。
2. **#4 基地**：執行 `ty.lua update mek_watch.lua`，只更新監控與面板程式的磁碟版本。若基地目前**確定由 `dc_agent.lua` 管理該程式**，可在資料中心／Pocket 以既有 `restart 4` 重新載入；若目前是獨立 `mek_watch` 分頁，需只關閉舊分頁再執行 `bg mek_watch.lua`，**不得開啟第二份監控程式**。#4 重載只短暫影響基地顯示及控制，不改動核電廠。
3. **#6 Pocket**：從 `pdc>` 退出後執行 `ty.lua update dc_remote.lua`，再重新啟動 `dc_remote.lua` 並確認管理員登入有效。

如版本落後，`ty.lua update` 在新版只列出檔案；舊版忽略檔名可能更新全部，請先用 `ty.lua help` 檢查。不要為這項介面授權功能更新/重啟 `mek_send.lua`、整台核電廠或反應爐。

### Pocket 命令與基地實際執行

```text
pdc> auth          # 確認已登入，且登入角色為 admin
pdc> panel 4       # 預設 Base panel: LOCKED
pdc> unlock 4      # 額外輸入大寫 UNLOCK
pdc> panel 4       # 預期 UNLOCKED，剩餘授權秒數
pdc> lock 4        # 額外輸入大寫 LOCK
pdc> panel 4       # 預期 LOCKED
```

#0 只接受來源電腦 ID 6 且已驗證的 admin，檢查 #4 `ONLINE`、`Paired=YES` 且由 `dc_agent.lua` 回報為 `BASE`/ `mek_watch.lua`。訊息由 #0 轉發至 #4 的獨立 `panel_command` 協定；#4 回覆實際解鎖狀態，並於每次觸控送出前同時檢查**面板授權**與既有**核電廠控制政策**。基地右螢幕標題下方顯示 `P:LOCK` 或 `P:ON`；左側唯讀監控不受影響。

授權只保存在 #4 目前執行中的記憶體，最多 **300 秒（5 分鐘）**，需要延長請重新由 Pocket 解鎖；基地若超過 **12 秒**未收到 #0 的身份驗證服務心跳、#0 重新啟動（服務版本識別碼更換）或 #4 監控程式重新啟動，會拒絕操作並清除未送出的二次確認。管理員發送 `$tyrevokeall`，資料中心會嘗試立即撤銷該管理員授權的面板；即使這個撤銷封包遺失，也仍有心跳超時及最長 300 秒的界線。遇到 `No panel ACK` 不得推定解鎖/上鎖已成功，應先使用 `panel 4` 重新查詢。

**兩道鎖，不得混淆：** #4 面板解鎖本身不會修改 #3 `mek_send.lua` 的 `allow_remote_scram`、`allow_remote_activate`、`allow_remote_logic_mode`、`allow_remote_turbine_mode` 或 `max_allowed_burn_rate`。原本的全部預設限制仍在，必須另外於 #3 安全維護期間確認冷卻/回水/安全聯鎖及實測上限再選擇啟用。GitHub 新版 `mek_send.lua` 已把控制指令來源限為基地 #4，`mek_pocket.lua` 已改成純唯讀；**目前執行中的 #3 若尚未重新載入新版，仍使用舊的權限規則**。Rednet sender ID 白名單無法抵禦能偽冒 ID 的惡意程式。面板遠端 SCRAM 也會隨面板上鎖，不能取代獨立的緊急停機。

**網路風險：** Rednet 身分來自電腦 ID 和 #0 的現有登入 token，並無端對端加密或可靠的防偽來源驗證。只適合單人/完全可信任的私人世界。實機需驗證未登入、viewer、#4 離線、心跳中斷、授權到期/重啟與二次確認清除等情境，未經 ATM10 8.3 現場測試不應宣稱安全或完整驗收。

## 下一階段：核電廠 #3 基地專屬控制指令

已提交 GitHub：

- `mek_send.lua`：`processCommand()` 僅處理基地 Computer #4 發出的控制指令；`controlPolicy.controllerIds` 僅列出 #4。Pocket #6 的監控資料接收不受影響。
- `mek_pocket.lua`：第六頁從直接反應爐控制改成唯讀 `ACCESS` 說明，前五頁監控資料保留。平板管理員仍在 `dc_remote.lua` 使用 `unlock 4`／`lock 4`。
- 安全預設仍是 `allow_remote_scram=false`、`allow_remote_activate=false`、`allow_remote_logic_mode=false`、`allow_remote_turbine_mode=false`、`max_allowed_burn_rate=nil`。更新本身不會授權任何操作。

**部署界線**：#3 反應爐運轉時，既有 `ty.lua update mek_send.lua` 會拒絕更新。等待既定安全停機時，先保留本機 `mek_send.lua` 的自訂安全 CFG，再於 #3 本機更新，重新檢查/設定安全上限後，才在監控可安全中斷時重新載入程式。GitHub 預設設定是全鎖定，更新會覆蓋手動修改的 CFG，切勿不核對現場就複製舊的燃燒率上限。Pocket #6 可先執行 `ty.lua update mek_pocket.lua`，並重新載入純唯讀監控介面，與核電廠運作互不干擾。

**遠端反應爐控制仍非端對端強式認證**：#3 只檢查 Rednet 來源電腦 ID #4，不能抵禦能偽冒該 ID 的不可信玩家；基地面板上鎖也會停用螢幕上的 SCRAM，仍應保有獨立硬體/紅石停機措施。

## 開機自動恢復（選用）

資料中心 #0、核電廠 #3、基地 #4 可使用更新後的 `ty.lua boot on` 各自啟用開機服務。此指令不會在安裝當下中斷現有監控，也不會啟動或停止核分裂反應爐。#3、#4 的代理需支援新的持久化設定；安裝器會明確提示是否只更新代理程式的磁碟檔案。舊代理的目前執行實例不會被即時替換，要待下次重開機才能開始保留 `start`／`stop` 的意圖。首次仍需要在各台電腦本機啟用一次，不能透過尚未安裝此功能的舊代理遠端寫入開機腳本。完整指令與安全限制見 [INSTALLER.md](INSTALLER.md#開機自動恢復opt-in不會自動啟動反應爐)。

## 完整遠端 CraftOS Shell（新增、須本機授權）

此功能與原有 `nodes/info/update/start/stop/restart` 管理協定並行，不取代 `dc_agent.lua`。Private-world Remote Shell 已加入 `dc_shell_host.lua`、`dc_shell_client.lua`，由新版 `dc_center.lua` 轉送 Pocket #6 的遠端工作階段。先更新資料中心 #0，再由 Pocket #6 使用 `shell 4` 連線基地 #4；首次在基地 #4 必須於本機執行 `dc_shell_host.lua enable`，不能靠舊代理憑空遠端安裝。核電廠 #3 運轉期間不開放完整 Shell。`ty.lua install` 只安裝檔案，不會自動開放完整 Shell 權限。**Rednet 缺乏加密身分驗證；僅供完全可信任的私人伺服器使用。** 詳見 [REMOTE_SHELL.md](REMOTE_SHELL.md)。
