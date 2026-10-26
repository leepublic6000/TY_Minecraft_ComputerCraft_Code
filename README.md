# TY Minecraft ComputerCraft Code

ATM10 8.3（Minecraft / Mekanism / CC:Tweaked）核分裂反應爐與工業渦輪機的 **完整可讀資料監控 + 經授權的手動遠端控制**。

> **狀態**：已核對 Mekanism 10.7 與 CC:Tweaked 官方 API；三個 Lua 檔案通過 Lua 語法檢查及模擬周邊／Rednet 整合測試。**尚未在玩家的 ATM10 8.3 遊戲世界中實際部署或測試所有操作。**

## 統一安裝與更新（ty.lua）

日後不需要每次手動貼 GitHub 長網址。使用一份 [`ty.lua`](ty.lua) 腳本，自動依電腦 ID 選取程式：資料中心 **#0**、核電廠 **#3**、基地 **#4**、Pocket **#6**。

- 第一次安裝：從 [Raw ty.lua](https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/ty.lua) 下載檔案並拖進 CraftOS，輸入 `ty.lua install`。
- 選擇程式更新：`ty.lua update` **只列出可選檔案**；使用 `ty.lua update ty.lua`、`ty.lua update dc_agent.lua` 等指令，只更新指定的本機檔案。可先用 `ty.lua check ty.lua` 比對版本。
- 全部更新：明確輸入 `ty.lua update all`，才會更新這台電腦所有受管理檔案；下載驗證、`.tybak` 備份與失敗回復機制不變，**不會自動重啟背景程式**。
- 資料中心集中更新：在 **#0** 輸入 `ty.lua all`，更新資料中心本身，並透過既有管理代理遠端更新基地 **#4**；這與單機 `ty.lua update all` 不同。
- 核電廠 **#3**：運轉中只允許在本機選擇更新**不涉及反應爐控制程式的磁碟檔案**（如 `ty.lua`、`dc_agent.lua`）；`mek_send.lua` 或全部更新仍須確認反應爐安全停止，原本安全參數不會默默被保留或猜測。舊版 `ty.lua` 不支援選擇更新，請先依 [升級步驟](INSTALLER.md#舊版-tylua-升級到選擇更新) 取得新管理器。

[完整安裝說明與安全限制](INSTALLER.md)。現有 `dc_center.lua`、`dc_agent.lua` 的通訊協定與 Mekanism 監控程式未因這次新增安裝器而改動。

## 你的遊戲配置

| 裝置 | 電腦 ID | 已確認接線／周邊 |
| --- | ---: | --- |
| 核電廠 Advanced Computer | **3** | `back` = `fissionReactorLogicAdapter`；`turbineValve_0` = `turbineValve`；`top` = Ender Modem（使用者表示） |
| 基地 Advanced Computer | **4** | `left` = 71×33 唯讀 Monitor；`right` = 29×33 控制 Monitor；`top` = Ender Modem |
| 隨身 Pocket Computer | **6** | `back` = Modem 升級模組 |

核電廠已實測反應爐與渦輪都 `isFormed() = true`，渦輪 `getProductionRate()` 曾回傳 `62`（發電能源單位需依遊戲設定核實）。舊 Pocket #2（已遺失）與基地 #4 曾分別使用 `rednet.lookup()` 找到核電廠 #3；新 Pocket #6 的通訊仍待遊戲內驗證。這些測試**不等於新監控程式已在遊戲中跑通**。

## 檔案用途

| 檔案 | 安裝在 | 用途 |
| --- | --- | --- |
| `mek_send.lua` | 核電廠 #3 | 動態擷取反應爐／渦輪所有公開、免參數、唯讀 `get*`／`is*`／`has*`／`can*` 方法；每秒廣播資料；對允許的手動指令檢查參數與權限並讀回結果 |
| `mek_watch.lua` | 基地 #4 | 左側 71×33 唯讀完整資料分頁；右側 29×33 觸控控制；輸出最新完整快照 `mek_latest.json` |
| `mek_pocket.lua` | Pocket #6 | 唯讀監控反應爐／渦輪所有資料；第六頁 `ACCESS` 提示使用 `dc_remote.lua` 在平板授權基地 #4 |

**資料範圍**：只包含 `Fission Reactor Logic Adapter` / `Industrial Turbine Valve` 透過 CC:Tweaked **實際公開**的免參數查詢方法；查詢失敗保留在 `errors`，所有方法名稱（含不能直接呼叫的 setter）保留在 `methods`。不會假裝取得其他設備（例如鍋爐、儲能矩陣）的數據。溫度 `getTemperature` 從 Kelvin 轉成攝氏（畫面使用 `C` 字元）；熱容量／溫差類數值不做錯誤換算。

## 從 GitHub 安裝：請按順序

先在每一台電腦的 `(lua)>` 輸入 `exit()` 回到 CraftOS 命令列，**不要在互動式 Lua 提示符直接貼 `wget`**。

**第一台：核電廠 #3**

```text
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/mek_send.lua mek_send.lua
mek_send.lua
```

**第二台：基地 #4**

```text
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/mek_watch.lua mek_watch.lua
mek_watch.lua
```

**第三台：Pocket #6**

```text
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/mek_pocket.lua mek_pocket.lua
mek_pocket.lua
```

首次安裝不要先設定 `startup.lua`。先依序確認 #3 的主控台看見反應爐和渦輪、#4 左畫面出現 `LIVE` 且所有資料可瀏覽，最後才開啟 Pocket。若下載失敗，檢查遊戲／伺服器的 CC:Tweaked HTTP 設定與 GitHub Raw 網址是否可用。

### 更新既有檔案

在程式**已停止**之後，先備份再下載，例如核電廠：

```text
copy mek_send.lua mek_send.bak
delete mek_send.lua
wget https://raw.githubusercontent.com/leepublic6000/TY_Minecraft_ComputerCraft_Code/main/mek_send.lua mek_send.lua
```

基地、Pocket 依相同方式替換檔案名稱。**更新 `mek_send.lua` 會覆蓋檔案內手動修改的安全設定**；更新前記下原有設定，更新後確認並重新設定，切勿直接複製舊的上限值而不核對現場冷卻系統。不要用自動更新來默默改變反應爐控制邏輯。

## 目前安全預設：所有遠端操作鎖定

核電廠端程式開頭 `CFG` 已設定合法電腦 ID，但下面的功能預設**全部禁用**：

```lua
trusted_base_id = 4, -- 唯一反應爐控制指令來源：基地 #4
max_allowed_burn_rate = nil,
allow_remote_scram = false,
allow_remote_activate = false,
allow_remote_logic_mode = false,
allow_remote_turbine_mode = false,
```

要開放哪一種手動操作，必須由你在核電廠 #3 的 `mek_send.lua` 中**逐項明確開啟**，並重啟該程式：

- `allow_remote_scram = true`：只允許基地 #4 發出 SCRAM 停機指令；基地紅色按鈕點一次，Pocket #6 不再直接操作反應爐。
- `max_allowed_burn_rate = <已實測安全上限>`：才允許 `setBurnRate(rate)`，且程式會再與 `getMaxBurnRate()` 的結構上限比較。**不可以把結構最高燃燒速率當成安全設定值**。
- `allow_remote_activate = true`：允許人工遠端啟動；使用前必須確認冷卻／水回收及獨立安全停機機制正常。
- `allow_remote_turbine_mode = true`：允許切換 `IDLE`／`DUMPING_EXCESS`／`DUMPING`；排出的蒸氣無法回收到閉環水冷系統。
- `allow_remote_logic_mode = true`：允許切換 Logic Adapter 的 `DISABLED`、`TEMPERATURE`、`CRITICAL_WASTE_LEVEL`、`DAMAGED`、`DEPLETED`、`ACTIVATION`。變更安全邏輯可能停用原有聯鎖，**不建議在未了解當前紅石保護時開啟**。

**兩道限制**：基地先檢查 Pocket #6 管理員核准的五分鐘面板授權，重要操作再要求兩次點按（SCRAM 例外）；核電廠端只接受來源 #4，仍獨立檢查合法指令、安全上限、設備結構與結果讀回。收到 `NO ACK`／逾時**不代表設備沒動作**，務必重新查詢狀態。

## 操作介面

**基地左螢幕（新版比例縮放）**：依螢幕字元容量選擇可用的最大 0.5 級距文字倍率（目前 71×33@0.5 的大螢幕預期約改成 35×16@1.0），總覽改成「反應爐／渦輪與槽量」雙欄資訊卡，顯示燃燒、溫度、發電、燃料、冷卻、蒸氣與廢料的數值及比例條。原本 `OVERVIEW`／`REACTOR`／`TURBINE`／`ERRORS`／`METHODS` 分頁與所有完整值、查詢錯誤、方法名稱仍保留；完整資料頁底部可翻頁。`mek_latest.json` 仍約每 10 秒儲存最新完整快照，不是長期歷史資料庫。

**基地右螢幕（新版比例縮放）**：原本 29×33@0.5 的控制螢幕預期約改成 14×16@1.0，按實際尺寸等比切分觸控區。上方可切換 `CORE`（狀態／ACTIVATE／SCRAM）、`BURN`（±10、±1、±0.1 mB/t／套用）、`LOGIC`（邏輯模式選擇／套用）、`TURB`（渦輪排放模式）；指令確認與權限鎖定維持不變：**除 SCRAM 為單次點擊，其餘變更須在 8 秒內點擊同一操作兩次**。渦輪排放頁保留失去回收水的警告。每次 `monitor_resize` 都會重新計算倍率與觸控位置；原有監控協定和反應爐安全參數不受影響。

### Pocket #6 授權基地 #4 控制面板（預設鎖定）

透過資料中心 #0 的既有 Chat Box 登入驗證，**只有已登入 admin 的 Pocket #6** 可執行 `pdc> unlock 4`；#4 `mek_watch.lua` 收到授權後，才允許基地的觸控按鈕呼叫原有的反應爐控制協定。Pocket 只核准/撤回基地面板授權，不會藉此執行反應爐操作；基地監控數據和左螢幕始終可讀。

```text
pdc> panel 4     -- 唯讀查詢鎖定狀態與剩餘秒數
pdc> unlock 4    -- 輸入大寫 UNLOCK；授權有效 5 分鐘
pdc> lock 4      -- 輸入大寫 LOCK；立即撤銷
```

基地右螢幕顯示 `P:LOCK`（未授權）或 `P:ON`（已授權）。新開機、基地監控程式重啟、五分鐘授權到期、資料中心心跳中斷逾 12 秒或資料中心重新啟動後，面板會**自動重新上鎖**，取消尚未完成的二次點擊確認。已經送往反應爐的指令不會因事後上鎖而撤銷。程式不持久化解鎖狀態。

**面板解鎖是額外一層鎖，不是取代核電廠 #3 的安全設定。** `mek_send.lua` 中 `allow_remote_*` 預設仍關閉、`max_allowed_burn_rate` 預設 `nil`；即使面板已授權，未經核電廠安全維護設定的按鈕仍呈灰色。GitHub 新版 `mek_send.lua` 僅接受 #4 控制指令，`mek_pocket.lua` 已改為唯讀；但**#3 本機未重新載入新版前，舊版權限規則仍在執行**。Rednet 電腦 ID 也不是密碼學防偽授權。基地面板上鎖時連遠端 SCRAM 按鈕也會禁用，**必須保有獨立的實體/紅石安全停機方式**。詳見 [DATA_CENTER.md](DATA_CENTER.md#基地控制面板的-pocket-授權解鎖)。

**更新基地畫面（#4 本機）**：使用支援選擇更新的新版 `ty.lua update mek_watch.lua`，只替換基地磁碟上的 `mek_watch.lua` 並保留備份；程式不會自動重啟，需在確認由 `dc_agent.lua` 管理時才從資料中心／Pocket `restart 4`，或手動關閉舊的 `mek_watch` 分頁再啟動新版本。**不要在 #3 更新 `mek_send.lua` 或重啟反應爐**。舊版 `ty.lua` 若不支援單檔參數，先依 [新版管理器升級步驟](INSTALLER.md#舊版-tylua-升級到選擇更新) 取得新版，避免舊版忽略檔名而更新所有程式。

**Pocket**：`mek_pocket.lua` 前五頁維持完整唯讀資料顯示，第六頁為 `ACCESS` 說明；Pocket #6 在 `dc_remote.lua` 經管理員驗證後使用 `panel 4`、`unlock 4`、`lock 4`。反應爐實際操作只在基地 #4 的觸控控制台執行，並受 #3 安全設定限制。

## 重要限制

- CC:Tweaked `rednet` **沒有可靠的訊息身分認證**。僅限可信任的私人世界／伺服器環境，不能把電腦 ID 白名單當成安全加密。多人不可信環境需要額外的訊息認證設計。
- Ender Modem 支援跨距／維度通信，但**不會自動載入區塊**。反應爐、渦輪、核電廠電腦所在區塊仍須載入。
- 本方案為監視及人工操作的便利介面，不可取代 Mekanism 或獨立紅石安全停機、供水、冷卻與蒸氣回收。
- 只有具體公開 API 的控制（啟動、SCRAM、燃燒速率、Logic Mode、渦輪 Dumping Mode）；**不能直接設定渦輪轉速或 FE/t**。

## 官方 API 參考

- [Mekanism 10.7 Computer Methods](https://mekanism.github.io/computer_data/10.7.0.html)：Fission Reactor Logic Adapter、Fission Reactor Multiblock、Industrial Turbine Multiblock、Fixed String Values。
- [CC:Tweaked peripheral API](https://tweaked.cc/module/peripheral.html)
- [CC:Tweaked rednet API](https://tweaked.cc/module/rednet.html)
- [CC:Tweaked Pocket API](https://tweaked.cc/module/pocket.html)

## 集中式資料中心（新增）

資料中心的 Advanced Computer 可以使用 `dc_center.lua` 管理節點，並以 `dc_agent.lua` 在核電廠 #3、基地 #4 回報狀態與接收允許的啟動、停止、重啟及 GitHub 更新命令。這是固定白名單管理，不是任意遠端 Shell。首次安裝代理及本機配對仍須在目標電腦進行。

完整部署方式與安全限制請見 [DATA_CENTER.md](DATA_CENTER.md)。

Pocket #6 也可以使用 [`dc_remote.lua`](dc_remote.lua) 連回資料中心 #0，直接執行 `nodes`、`info 3`、`update 3`、`start 3` 等管理命令。資料中心僅需一次更新 `dc_center.lua`，既有 #3、#4 代理不需重裝；詳見 [DATA_CENTER.md](DATA_CENTER.md)。

### 電腦開機自動恢復（需手動啟用一次）

最新版 `ty.lua` 新增 `ty.lua boot status`、`ty.lua boot on`、`ty.lua boot off`。在資料中心 #0、核電廠 #3、基地 #4 各自啟用後，往後重開機會開啟管理程式；#3/#4 的新版代理會記錄最後一次 `start`／`stop` 意圖並恢復監控。這**不會啟動核分裂反應爐、不會解除任何安全鎖**，核電廠程式更新仍需獨立確認。使用方法、安全檢查及實測界線見 [INSTALLER.md 的開機自動恢復](INSTALLER.md#開機自動恢復opt-in不會自動啟動反應爐)。

## 完整遠端 CraftOS Shell（僅限可信任的私人伺服器）

已加入 [`dc_shell_host.lua`](dc_shell_host.lua)（目標電腦端）、[`dc_shell_client.lua`](dc_shell_client.lua)（Pocket #6 端），並擴充 `dc_center.lua`、`dc_remote.lua`。從 Pocket #6 的 `pdc>` 可使用 `shell 4` 操作基地 #4；核電廠 #3 則有兩種模式：

- **運轉中 #3：** #0 必須啟用玩家登入驗證，Pocket #6 必須為已登入的 admin，且 #3 已在本機啟用新版 Host。此時 `shell 3` 只進入 `plant>` 受限管理終端，支援 `status`、`config`、`boot status/on/off` 及指定管理檔案的 `check`／`update`，**不允許任意 Lua、`edit`、修改 `mek_send.lua`、重啟監控或直接控制反應爐**。
- **停機中 #3：** 同樣需要驗證管理員身分與本機 Host，`shell 3` 才提供完整 CraftOS Shell；完整 Shell 期間反應爐若開始運轉，工作階段就會被關閉。

**驗證登入不是加密 SSH。** 現有 Rednet 沒有加密、可靠的密碼學來源驗證或抗重放保證，僅限完全可信任的私人世界。首次仍須在目標電腦本機執行 `dc_shell_host.lua enable` 並啟動 Host，不能單靠新版程式隔空安裝；此步驟可在 #3 反應爐運轉中執行，且不會中斷 `mek_send.lua`。詳細部署、白名單與驗收見 [REMOTE_SHELL.md](REMOTE_SHELL.md)。
