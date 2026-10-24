# 小米电视改造 · 2026-10-25 会话记录

> 记录这一天在电视上做的四件事、踩的坑、留下的资产。给未来的自己（或接手的人）看。

---

## 一、这一轮到底干了啥

| # | 事情 | 结果 |
|---|---|---|
| 1 | 主页替身 APK 出现在电视应用栏 | 去掉多余的 `LEANBACK_LAUNCHER` 过滤器，v102；并把历史遗留的格子从桌面布局里隐藏 |
| 2 | 天气显示东京（代理出口在日本） | 通过 Aerial 自带的手机页面 API 改成上海，`chosen=true` 钉死 |
| 3 | Aerial 应用网格方向键到行末卡住 | 改源码 `AppTile.kt`，行末 `→` 进下一行、行首 `←` 回上一行；装机 + 提 issue #516 / PR #522 |
| 4 | 应用图标要按最近使用排序 | 改 `HomeViewModel` 加 53 行按 `lastTimeUsed` 排序，v56 装机验证 |

---

## 二、逐件事：怎么做的

### 1. 主页替身不该出现在应用栏

**现象**：电视应用栏里多一个「主页替身」格子，点进去黑屏。

**原因**（两层）：
1. `homekey-standin/manifest/AndroidManifest.xml` 里除了 `MAIN + HOME`，还多写了一个
   `MAIN + LEANBACK_LAUNCHER` 过滤器 —— 等于对系统说「我是个可以启动的 App」。
2. 即使删掉它，Aerial 的 `AppCatalog.load()` 里还有一段 `stockLaunchers(pm)`：
   凡是声明了 `CATEGORY_HOME` 的包都会被当成「原桌面」列出来。
   所以第一次装完，Aerial 仍然把它记进了桌面布局。

**做法**：
- 删掉 `LEANBACK_LAUNCHER` 过滤器 → 重编 v102（`versionCode 102`）
- 用 Aerial 手机页面的 `POST /api/layout` 带 `op=hide&key=com.ts.launcher` 把旧格子隐藏

**验证**：
```
cmd package query-activities -a MAIN -c LEANBACK_LAUNCHER | grep com.ts.launcher  → 0 条
cmd package query-activities -a MAIN -c LAUNCHER          | grep com.ts.launcher  → 0 条
Home 键 → app.orchard.tv/.MainActivity                                          → 正常
```

**结论**：HOME 解析只认 `MAIN + HOME`，和 LAUNCHER 无关。替身不需要「可启动」。

---

### 2. 天气改上海（手机不在同一网络）

**原因**：Aerial 默认按出口 IP 定位。电视走代理（出口日本）→ 显示 Tokyo。

**做法**：不扫码，直接调它自带的手机页面接口。

1. 遥控器 `MENU` → 控制中心 → 个性化，右侧出现二维码
2. 截图解码拿 token：
   ```bash
   adb exec-out screencap -p > /tmp/q.png
   # zxing-cpp 解码 → http://<电视IP>:8790/<token>/
   ```
3. 从 **Windows 侧** POST（WSL 直连电视 8790 不通）：
   ```powershell
   curl.exe -s -X POST "http://<电视IP>:8790/<token>/api/weather/city" --data "name=%E4%B8%8A%E6%B5%B7"
   ```
4. 返回 `{"found":true,"weather":{"place":"上海","chosen":true,...}}` 即成

**关键**：`chosen: true` 一旦写上，就不会再被 IP 定位覆盖，换代理也不会跳回东京。

---

### 3. Aerial 方向键跨行

**现象**：应用网格里，焦点在一行最右时按 `→` 不动；最左按 `←` 也不动。

**根因**（源码）：
```kotlin
// AppTile.kt
.focusProperties { if (rowEnd) right = FocusRequester.Cancel }
```
`Cancel` = 没有下一个焦点，所以卡死。不是电视、不是遥控器。

**改法**：
- `AppTile.kt` 增加 `rowStart` 参数
- `rowEnd` 时 `right` 指向下一行第一个；`rowStart` 时 `left` 指向上一行最后一个
- `HomeScreen.kt` 传 `rowStart = index % COLUMNS == 0`
- 最后一行最右仍保持 `Cancel`（不跳到顶部状态胶囊）

**构建踩坑**：
- `./gradlew` 卡在下载 Gradle（`~/.gradle/caches` 停在 461M 不动）→ kill 掉
- 换腾讯镜像下 `gradle-8.14.3-bin.zip`（132M）解压到 `$HOME/tools/gradle-8.14.3`
- 缺少 `platforms;android-36` → `sdkmanager "platforms;android-36"`
- 阿里云 Maven 镜像只用于救急，构建完 `settings.gradle.kts` 已 revert

**上游**：
- issue https://github.com/pengchujin/aerial-tv/issues/516
- PR https://github.com/pengchujin/aerial-tv/pull/522
- 分支 `fix/grid-row-wrap`，commit `df386a8`

---

### 4. 按最近使用排序

**Aerial 原生没有**：`AppCatalog` 里完全没有按使用时间排序的逻辑，
顺序只保存在 `LayoutStore` 里（手工排列的结果）。
`UsageStatsManager` 只在 `HomeGuardService` 里用过，那是判断前台的，跟排序无关。

**改法**（`HomeViewModel.kt` +53 行）：
```kotlin
// arrange() 末尾
apps = inRecentOrder(arrangement.home, recentUse())
```
- 只重排「真应用」（`source == null && folder == null`）
- 按 `lastTimeUsed` 倒序，占回原来那些坑位
- **输入源和文件夹不动**（文件夹里的应用被使用不算文件夹被用过）
- 没用过的应用保持原相对顺序、排在用过的后面
- `recentUse()` 用 `queryUsageStats(INTERVAL_WEEKLY, now-30d, now)`，2 秒缓存
- **拿不到数据直接返回原顺序**，不报错不卡
- `MainActivity.resumeWork()` 加 `vm.refreshRecentOrder()`

**必须授权**（特殊权限，`pm grant` 给不了）：
```bash
adb shell appops set app.orchard.tv GET_USAGE_STATS allow
```

**版本号必须 +1**（55 → 56），否则 `install -r` 装不上（同签名更新要求更高版本）。

**实测**：
| 操作 | 桌面第一个图标 |
|---|---|
| 打开「影视仓」→ Home | 影视仓 ✅ |
| 打开「SmartTube」→ Home | SmartTube ✅ |

验证手法：回桌面后长按第一个图标，弹窗标题就是当前应用名。

---

## 三、踩过的坑（按疼的程度排序）

1. **`adb install -r` 报 Success 但装的是旧包**
   原因：`cp 源 'C:\Users\<你>\hks.apk'` 在 WSL 里会把 `C:\...` 当**文件名**，
   复制到当前目录下一个叫 `C:\Users\<你>\hks.apk` 的怪文件里；`adb.exe` 装的是 Windows
   上那个没更新的旧文件。
   → 用 `/mnt/c/...` 复制，再 `md5sum` 对比两边，确认一致再装。

2. **adb.exe 不认识 `/mnt/c/` 路径**
   WSL 路径喂给 Windows 版 adb 会 `failed to stat`。安装时用 `C:\Users\...\x.apk`，
   复制时用 `/mnt/c/Users/...`。两个方向别搞反。

3. **WSL 连不上电视的 8790 端口**（`curl` 直接超时/拒连）
   → 改用 `/mnt/c/Windows/System32/curl.exe`，走 Windows 网络栈才行。

4. **WSL 里 curl 还会被 `http_proxy` 劫持**
   访问内网 IP 要加 `--noproxy '*'`，否则请求被送去代理。

5. **phone server 的 token 每次 App 重启都变**
   只能重新 `MENU → 个性化` 截图 → 解码二维码。没有持久化。

6. **`MENU` 键行为取决于焦点**
   焦点在应用图标上时，`MENU` = 应用菜单（移到文件夹/隐藏/卸载…）；
   焦点不在图标上时，`MENU` = 控制中心。想开控制中心先把焦点移开。

7. **uiautomator 抓不到 Compose 的图标文字**
   `uiautomator dump` 只给 `10月25日 / 1:43 / 上海 · 雨` 这些，图标的 caption 抓不到。
   → 靠「长按弹菜单标题」或截图像素差来判断顺序。

8. **Aerial 重装后设置全丢**
   自签名版和官方版签名不同，`pm uninstall` 才能装 → 壁纸、Dock 顺序、天气城市全重置。
   `adb install -r` 只在**同签名**（都是我们自己的 debug key）时才保留数据。

9. **Gradle 首次构建卡死 4~5 分钟以上**
   网络问题，不是死锁。用国内镜像 + 本地 gradle 二进制。构建一次约 4m50s。

10. **`android.intent.category.HOME` 的包不一定能当默认桌面**
    小米按**包名白名单**放行：`com.ts.launcher` 能设成 HOME，
    `app.orchard.tv`、`com.finn.homebridge` 全被退回 `FallbackHome`。
    → 主页替身必须伪装 `com.ts.launcher`（这是前一轮的结论，这轮仍在用）。

---

## 四、留下的资产

### 仓库 `tv-terminator`（https://github.com/fadnejin/tv-terminator）

```
README.md                      项目总表（5 个项目行）
docs/xiaomi-tv.md              改造全流程
docs/quickstart.md             快速上手
docs/aerial-row-wrap.md        方向键补丁：根因/diff/自编译步骤
docs/aerial-recent-order.md    最近使用排序：diff/授权/实测
docs/session-log-2026-10-25.md 本文件
homekey-standin/               Home 键替身项目
  ├─ src/…/MainActivity.java   64 行，无界面
  ├─ manifest/AndroidManifest.xml  模板（__PKG__/__ACTIVITY__ 占位）
  ├─ build.sh                  115 行，纯 aapt2/d8/apksigner
  ├─ dist/…-com_ts_launcher.apk  v102 预编译
  └─ README.md                 原理 + 包名实验表 + 坑
skills/xiaomi-tv-setup/SKILL.md  操作手册（与本地 skill 同步）
```

提交链：
```
60b3387 最近使用排序补丁（docs + skill 2.2D）
7e4bd5b skill 2.4 远程改天气 + 主页替身 v102 说明
024572b 主页替身 v102：去掉 LEANBACK_LAUNCHER
0030497 清理 dist 里的 .idsig
33f5e96 skill 2.2C 方向键补丁
aab4607 方向键补丁说明 + 项目索引
```

### 本地 skill
`~/.hermes/skills/devops/xiaomi-tv-setup/SKILL.md`
- 2.2A 两条路（忍闪 / 零闪主页桥）
- 2.2A-补 小米白名单包名 → 主页桥做法
- 2.2C 方向键跨行补丁 + 自编译三提醒
- 2.2D 最近使用排序 + `appops` 授权
- 2.4 远程改天气城市
- 故障速查新增两条（行末按→不动 / 应用栏多出主页替身）

### Aerial 源码与构建环境
```
$HOME/build/aerial-tv         源码（tag v1.47）
  分支 fix/grid-row-wrap   df386a8  方向键补丁（已 push 到 fork，PR #522）
  分支 local/recent-order  53ecd83  最近使用排序（本地，未提 PR）
$HOME/tools/gradle-8.14.3     Gradle 8.14.3（腾讯镜像下的）
$HOME/android-sdk/platforms/android-36
构建：gradle :app:assembleStandardRelease -x lint --no-daemon   （约 4m50s）
```

### APK 备份
```
~/hermes-workspace/tv-apks/aerial-1.47-v56-rowwrap-recent.apk   2.89 MB  ← 当前装机版
~/hermes-workspace/tv-apks/aerial-1.47-rowwrap-debugsigned.apk  2.89 MB  ← 只有方向键补丁
~/hermes-workspace/tv-apks/aerial-standard-v1.46.apk            2.88 MB  ← 更早的官方版
/mnt/c/Users/<你>/aerial-recent.apk                                装机用副本
/mnt/c/Users/<你>/hks.apk                                          主页替身 v102
/mnt/c/Users/<你>/hb2.apk                                          救砖用主页桥（第一版）
~/hermes-workspace/tv-backup/cleanyourtv-v2.6-installed.apk      老桌面备份
/mnt/c/Users/<你>/hermes-tv-backup/                                 备份副本
```

### 电视上的当前状态
```
默认 HOME   com.ts.launcher/com.gathin.tvhome.MainActivity（主页替身 v102）
桌面        Aerial v1.47 / versionCode 56（方向键 + 最近使用 两个补丁）
授权        WRITE_SECURE_SETTINGS / 通知监听 / SYSTEM_ALERT_WINDOW
            appops GET_USAGE_STATS = allow   ← 最近使用排序靠它
无障碍      小爱语音 + Aerial 桌面守护
天气        上海（chosen=true 钉死，不受代理影响）
停用        小米桌面 + 8 个系统服务
值守 cron   4f558c50df37，每 15 分钟静默检查（~/.hermes/scripts/tv_watch.sh）
```

---

## 五、下次要注意

1. **换官方 Aerial 版本**：自签版必须先 `pm uninstall --user 0 app.orchard.tv` 才能装官方包，
   装完三授权 + `appops GET_USAGE_STATS` 全要重给。
2. **PR #522 合入后**：方向键补丁可以弃用，直接装官方版；但最近使用排序仍是我们自己的补丁。
3. **恢复出厂/重装替身**：应用栏会再冒出「原桌面」格子（Aerial 的 `stockLaunchers` 会列 HOME 包），
   需要再用 `POST /api/layout` 的 `op=hide` 隐藏一次。
4. **主页替身永远别加 LAUNCHER 类目**——加了就会出现在应用栏。
