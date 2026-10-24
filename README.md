# TY Minecraft ComputerCraft Code

ATM10 8.3（Minecraft / Mekanism / CC:Tweaked）核分裂反應爐與工業渦輪機的 **完整可讀資料監控 + 經授權的手動遠端控制**。

> **狀態**：已核對 Mekanism 10.7 與 CC:Tweaked 官方 API；三個 Lua 檔案通過 Lua 語法檢查及模擬周邊／Rednet 整合測試。**尚未在玩家的 ATM10 8.3 遊戲世界中實際部署或測試所有操作。**

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
| `mek_pocket.lua` | Pocket #6 | 隨身完整資料分頁、狀態總覽及手動控制（鍵盤與部分螢幕觸控） |

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
trusted_base_id = 4,
trusted_pocket_id = 6,
max_allowed_burn_rate = nil,
allow_remote_scram = false,
allow_remote_activate = false,
allow_remote_logic_mode = false,
allow_remote_turbine_mode = false,
```

要開放哪一種手動操作，必須由你在核電廠 #3 的 `mek_send.lua` 中**逐項明確開啟**，並重啟該程式：

- `allow_remote_scram = true`：允許 #4、#6 發出 SCRAM 停機指令；基地紅色按鈕點一次，Pocket 必須鍵入 `SCRAM` 確認。
- `max_allowed_burn_rate = <已實測安全上限>`：才允許 `setBurnRate(rate)`，且程式會再與 `getMaxBurnRate()` 的結構上限比較。**不可以把結構最高燃燒速率當成安全設定值**。
- `allow_remote_activate = true`：允許人工遠端啟動；使用前必須確認冷卻／水回收及獨立安全停機機制正常。
- `allow_remote_turbine_mode = true`：允許切換 `IDLE`／`DUMPING_EXCESS`／`DUMPING`；排出的蒸氣無法回收到閉環水冷系統。
- `allow_remote_logic_mode = true`：允許切換 Logic Adapter 的 `DISABLED`、`TEMPERATURE`、`CRITICAL_WASTE_LEVEL`、`DAMAGED`、`DEPLETED`、`ACTIVATION`。變更安全邏輯可能停用原有聯鎖，**不建議在未了解當前紅石保護時開啟**。

**兩點保護**：基地會在重要操作前要求重複點按確認（SCRAM 例外），Pocket 會要求輸入 `YES` 或 `SCRAM`；核電廠端仍會獨立檢查合法指令、來源電腦 ID、安全上限、設備結構與實際讀回。收到 `NO ACK`／逾時**不代表設備沒動作**，務必重新查詢狀態。

## 操作介面

**基地左螢幕**：`OVERVIEW`（總覽）／`REACTOR`（所有讀值）／`TURBINE`（所有讀值）／`ERRORS`（查詢失敗）／`METHODS`（方法名稱），底部可翻頁。`mek_latest.json` 是約每 10 秒更新的最新快照，不是長期歷史資料庫。

**基地右螢幕**：反應爐燃燒速率 `±10`、`±1`、`±0.1` mB/t、套用、ACTIVATE、SCRAM、Logic Mode 選取；渦輪蒸氣排放模式。尚未由核電廠授權的按鈕會顯示為不可用。

**Pocket**：上方點選 `1～6` 分頁，或按數字鍵；`P/N` 往上／往下、`Q` 結束。進入 `6:CTRL` 後，按 **R** 設定燃燒速率、**A** 啟動、**S** SCRAM、**D** 渦輪模式、**L** 反應爐 Logic Mode；可點擊畫面上相應的操作文字。需要輸入設定值及文字確認時，使用 CraftOS 鍵盤輸入。任何控制都必須先由核電廠端開放對應權限。

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
