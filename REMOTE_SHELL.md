# TY 完整遠端 Shell（ATM10 8.3／CC:Tweaked）

本功能針對現有的資料中心 #0、基地 #4、核電廠 #3、Pocket #6。基地 #4 和**已停機**的 #3 提供原本的互動式 CraftOS Shell；**反應爐運轉中的 #3** 在確認 Pocket #6 的管理員登入後，只提供**固定白名單管理終端**，不提供任意 Lua、`edit`、CraftOS Shell 或反應爐控制 API。終端都在獨立分頁中傳輸畫面，不是 Minecraft 畫面截取，也不接管目前的 `mek_send.lua` 監控。

**安全前提：Rednet 沒有加密或密碼學來源驗證，現有登入 Token 亦可被網路內的惡意玩家複製。這裡的「已驗證」僅代表資料中心 #0 的現有遊戲內玩家登入／管理員授權通過，並非抗竊聽的安全 SSH。僅可用於單人世界／完全可信任的私人伺服器；不可信玩家能放置 ComputerCraft 電腦的環境不得啟用。**

## 連線路徑

```text
Pocket #6 － Rednet －> 資料中心 #0 － Rednet －> 基地 #4
                                     \－> 核電廠 #3（RUNNING=受限管理；STOPPED=完整 Shell）
Pocket #6 － Rednet －> 資料中心 #0 本身的獨立 Shell（目標 #0）
```

資料中心 `dc_center.lua` 仍負責已配對節點的 `nodes/info/start/stop/update`。對 #3 終端會先檢查 **#0 已啟用 auth、來源確實是 Pocket #6、當前登入工作階段為 admin、節點在線且已配對**；只將經資料中心核准的旗標轉送給 #3，使用者自行附加的權限欄位不會被轉送。舊 Pocket #2 沒有連線權限。服務端 `dc_shell_host.lua` 由 #3 本機一次性允許，預設關閉；不改動 `dc_agent.lua`、`mek_send.lua`、`mek_watch.lua` 的控制邏輯。

| 檔案 | 安裝在 | 功能 |
| --- | --- | --- |
| `dc_center.lua` | #0 | 新增完整終端訊息轉接；原有管理命令保留 |
| `dc_shell_host.lua` | #0、#4、#3（須本機啟用） | #3 運轉中為受限管理；停機後才是完整 Shell，其他目標不變 |
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

### D. 核電廠 #3（已驗證管理員可於運轉中遠端管理）

**不必為了安裝受限管理而停止反應爐。** 但第一次仍需到 #3 的 CraftOS `>` 啟用 Host；原本的舊代理不能透過 Rednet 隔空安裝任意新程式。

依序部署，不須停止 `mek_send.lua`：

1. **資料中心 #0**：在 Shell 用**支援指定檔名的新版** `ty.lua update dc_center.lua`，只更新磁碟檔案。然後在 #0 的舊 `dc>` 主控台輸入 `exit`，於 Shell 執行 `bg dc_center.lua` 重新載入新版資料中心。不用停止 #3 的監控程式。若 #0 的管理器仍是舊版，先依 [INSTALLER.md](INSTALLER.md#舊版-tylua-升級到選擇更新) 升級，避免舊版忽略檔名。
2. **資料中心 #0 身分驗證**：`dc>` 執行 `auth status`，必須確認 `Auth: ENABLED`，且已完成玩家管理員註冊；否則先依 [AUTH_SYSTEM.md](AUTH_SYSTEM.md) 透過 Chat Box 完成 `auth claim`、`auth confirm`、`auth enable`。**未啟用登入時，#3 連停機的完整 Shell 都會拒絕，不會退回舊版 ID 白名單模式。**
3. **Pocket #6**：更新 `ty.lua update dc_remote.lua` 與 `ty.lua update dc_shell_client.lua`（如有需要先確認 `ty.lua help` 支援單檔選擇）。離開正在執行的舊 `pdc>`，重新執行 `dc_remote.lua`；按原本流程 `login`，或確認信任 Pocket 已恢復管理員工作階段。
4. **核電廠 #3**：獨立切至 CraftOS `>` 分頁，執行下列指令（不要更新 `mek_send.lua` 或執行 `update all`）：

   ```text
   ty.lua update dc_shell_host.lua
   dc_shell_host.lua enable
   bg dc_shell_host.lua
   ```

   `enable` 會先確定可讀到反應爐真實狀態，再要求本機輸入大寫 `PLANT`；運轉中也可啟用**受限**管理 Host。若已有 Host 分頁，**不要再開第二份**，須讓目前 Host 分頁在安全情況下重新載入新版；不要重啟 `mek_send.lua`。
5. **Pocket #6** 的 `pdc>` 輸入 `shell 3`：如果驗證及網路、Host 都正常，反應爐運轉時會顯示 `LIVE LIMITED` 與 `plant>`；若反應爐已停止則顯示 `FULL SHELL` 與正常 CraftOS 終端。

#### 核電廠運轉中的 `plant>` 白名單

| 指令 | 允許效果 |
|---|---|
| `status` | 唯讀查詢實際反應爐狀態、溫度與燃燒率 |
| `config` | 唯讀查看磁碟上 `mek_send.lua` 的 `local CFG`；執行中程式可能仍是舊設定 |
| `ls` | 列出指定的受管理檔案及是否存在 |
| `boot status`、`boot on`、`boot off` | 執行現有 `ty.lua` 的開機恢復管理，保留原本確認機制 |
| `check ty.lua`、`check dc_agent.lua`、`check dc_shell_host.lua` | 只檢查指定管理檔案是否需更新 |
| `update ty.lua`、`update dc_agent.lua`、`update dc_shell_host.lua` | **只替換白名單管理檔案的磁碟版本**；需原本更新確認，不會重啟目前的服務 |
| `exit` | 結束管理工作階段 |

所有其他輸入（例如 `lua`、`edit`、`shell`、`wget`、`update mek_send.lua`、`update all`、`restart 3`）**拒絕執行**。不透過受限終端直接啟動、關閉、設定燃燒率或變更安全模式；需要這些功能仍須遵循核電廠既有獨立授權與安全檢查。不能透過登入身分繞過反應爐安全設定。

停止反應爐後，新建立的 `shell 3` 工作階段才可進入完整 CraftOS Shell；若完整 Shell 使用期間反應爐重新運轉，Host 會中斷該 Shell。若開啟時無法確認反應爐狀態，則直接拒絕連線。已有的受限工作階段不會因停機自動升級成完整權限，須先退出再重新連線。

## 停用、錯誤與驗收

- 目標電腦本機 `dc_shell_host.lua status` 可檢查是否啟用。`dc_shell_host.lua disable` 輸入 `DISABLE` 後，會移除本功能自己的開機啟動檔與啟用旗標，不停止既有核電廠／基地監控；現行遠端 Shell 於下一輪事件檢查後停止。
- 若 Pocket 顯示 `TIMEOUT`，先檢查資料中心是否已重新啟動**新版** `dc_center.lua`、目標電腦的 Shell Host 分頁是否正常、Ender Modem 是否可用，以及所在 Chunk 是否有載入。單純從 GitHub 更新磁碟文件不代表已運行的舊版程式自動更新。
- 先驗收 `shell 0`：看到資料中心的 CraftOS 提示符且 `id` 回傳 `0`；再驗收 `shell 4`：使用 `id` 應回傳 `4`，在遠端 `ls` 和 `ty.lua boot status` 應可執行。退出後 #0／#4 原本的管理服務必須維持 `RUNNING`。
- #3 運轉時先驗收 `shell 3` 只顯示 `plant>` 受限終端，`status`、`config` 可讀，`lua`、`edit`、`update mek_send.lua` 被拒絕。未登入、唯讀登入、auth 未啟用都應拒絕；登出或 `$tyrevokeall` 後工作階段應關閉。**不要為了驗證完整 Shell 強制停機或重新啟動反應爐**。
- Rednet 工作階段超過 45 秒沒有資料交換會逾時。重連時應用全新工作階段；不要把 `NO ACK` 當成遠端命令確定沒執行。

## 驗證狀態

原版遠端 Shell 曾進行 Lua 語法及模擬測試；**本次新增的「驗證後運轉中受限管理」仍待 Lua 編譯、協定／輸入回歸與 ATM10 8.3 遊戲實機測試，不等於已在遊戲部署或驗收。** 必須檢查認證拒絕、操作白名單、核心狀態變更時權限仍受限、以及舊監控不中斷。

參考：[CC:Tweaked window](https://tweaked.cc/module/window.html)、[term](https://tweaked.cc/module/term.html)、[multishell](https://tweaked.cc/module/multishell.html)、[rednet](https://tweaked.cc/module/rednet.html)。

## 特別修正：遠端 Shell 不會重新執行開機初始化

遠端 Shell 透過 `os.run({shell=shell, multishell=false}, "/rom/programs/shell.lua")` 啟動，明確繼承當前 CraftOS Shell 環境；這避免把它誤判為最上層 Shell，重跑 `/rom/startup.lua`、`startup/` 自動啟動程式。遠端 Shell 的 `multishell` 分頁控制刻意關閉，防止遠端建立目標電腦的前景分頁。這項設計已加入模擬檢查，但仍需在 ATM10 8.3 現場驗證。
