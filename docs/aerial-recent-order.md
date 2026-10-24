# Aerial：应用按「最近使用」排序（自打补丁）

## 效果

桌面图标从上到下、从左到右，按**最后一次打开的时间**排，最近用过的排最前面。
每次从应用回到桌面、重启电视后重新读一次使用记录。

- 没用过的应用：排在用过的后面，保持原来的手工顺序
- 文件夹：位置不动（里面的应用换了不算文件夹被用过）
- 信号源等输入：位置不动
- **没有授权使用记录时**：完全退回手工排序，不会乱

## 为什么 Aerial 原来不这么做

它把顺序存在 `LayoutStore` 里，只认「用户手动排的结果」。翻遍 `AppCatalog` 没有任何
按使用频率或时间排序的代码——只有 `HomeGuardService` 用了 `UsageStatsManager`，
但那是用来判断「哪个 App 在前台」的，跟排序无关。

## 改动（两个文件）

`app/src/main/java/app/orchard/tv/HomeViewModel.kt`

```kotlin
// arrange() 里，排完手工布局之后过一道最近使用排序
apps = inRecentOrder(arrangement.home, recentUse())
AppCatalog.home = apps
```

```kotlin
/** 最近使用在前；没打开过的保持原相对顺序排后面；输入源和文件夹占原来的坑。 */
private fun inRecentOrder(home: List<AppEntry>, used: Map<String, Long>): List<AppEntry> {
    if (used.isEmpty()) return home
    val slots = home.indices.filter { home[it].source == null && home[it].folder == null }
    if (slots.size < 2) return home
    val sorted = slots.map { home[it] }
        .withIndex()
        .sortedWith(
            compareByDescending<IndexedValue<AppEntry>> { used[it.value.packageName] ?: 0L }
                .thenBy { it.index },
        )
        .map { it.value }
    val out = home.toMutableList()
    slots.forEachIndexed { i, slot -> out[slot] = sorted[i] }
    return out
}

/** 包名 → 最后一次在前台的时间；两秒内重复调用走缓存。 */
private fun recentUse(): Map<String, Long> { /* queryUsageStats(INTERVAL_WEEKLY, now-30d, now) */ }

/** 从应用回到桌面时刷新一次。 */
fun refreshRecentOrder() { lastUsedAt = 0L; if (loaded) arrange() }
```

`MainActivity.kt` 的 `resumeWork()` 加一行 `vm.refreshRecentOrder()`。

版本号 `versionCode 55 → 56`，否则装不上（同签名的增量更新要求更高版本）。

## 必须授权「使用记录」，否则排序不生效

App 声明了 `PACKAGE_USAGE_STATS`，但这权限只能由用户/ADB 给：

```bash
adb shell appops set app.orchard.tv GET_USAGE_STATS allow
```

没给的话 `queryUsageStats` 返回空 → 代码里 `if (used.isEmpty()) return home` 直接
保持手工顺序，不报错、不卡。

## 构建

```bash
$HOME/tools/gradle-8.14.3/bin/gradle :app:assembleStandardRelease -x lint --no-daemon
# 产出 app/build/outputs/apk/standard/release/app-standard-release.apk
```

装之前不用卸载（同一个 debug 签名，直接 `adb install -r`），数据不丢。

## 实测

| 操作 | 桌面第一个图标 |
|---|---|
| 打开「影视仓」，回桌面 | 影视仓 ✅（长按菜单标题显示「影视」）|
| 打开 SmartTube，回桌面 | SmartTube ✅ |
| 未授权使用记录 | 顺序与手工排列完全一致，像素级无变化 ✅ |

## 已知取舍

图标会**跳**：点过的应用移到最前面，其余整体后移。找东西靠「最近用过的在前面」，
不靠固定位置。想固定位置就撤掉这个补丁、回到手工排序。
