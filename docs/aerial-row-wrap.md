# Aerial 应用网格：方向键跨行（自打补丁）

> 症状：应用列表里，焦点挪到一行最右边再按 `→` 就卡住不动，不会进下一行。
> 反过来，在最左边按 `←` 也不会回到上一行。

这是 Aerial 自己的焦点逻辑写死的（`rowEnd` 时把 `right` 设成 `Cancel`），
跟电视、遥控器都没关系。官方 issue：[#516](https://github.com/pengchujin/aerial-tv/issues/516)，
我们的 PR：[#522](https://github.com/pengchujin/aerial-tv/pull/522)。

## 改动

两处，一共十几行：

`app/src/main/java/app/orchard/tv/ui/home/AppTile.kt`

```kotlin
// 新增参数
rowStart: Boolean = false,
nextRowFirst: FocusRequester? = null,
prevRowLast: FocusRequester? = null,

// 原来的
// .focusProperties { if (rowEnd) right = FocusRequester.Cancel }
// 改成
.focusProperties {
    if (rowEnd) right = nextRowFirst ?: FocusRequester.Cancel
    if (rowStart && prevRowLast != null) left = prevRowLast
}
```

`app/src/main/java/app/orchard/tv/ui/home/HomeScreen.kt`（`AppTile(...)` 调用处）

```kotlin
rowStart = index % COLUMNS == 0,
nextRowFirst = if (index % COLUMNS == COLUMNS - 1 && index < apps.lastIndex) {
    requester(apps[index + 1].key)
} else null,
prevRowLast = if (index % COLUMNS == 0 && index >= COLUMNS) {
    requester(apps[index - 1].key)
} else null,
```

## 改完的效果

| 位置 | 按键 | 之前 | 之后 |
|---|---|---|---|
| 行末 | `→` | 卡住 | 下一行第一个 |
| 行首 | `←` | 卡住 | 上一行最后一个 |
| 最后一行末尾 | `→` | 卡住 | 卡住（保持原设计，不跳到顶部状态条） |
| 第一行行首 | `←` | — | 保持默认 |

## 自己编译（Windows / WSL 都行）

```bash
git clone https://github.com/pengchujin/aerial-tv.git
cd aerial-tv
git checkout v1.47          # 和你电视上装了哪个版本就用哪个 tag
# 打上面的补丁，然后：
echo "sdk.dir=/path/to/android-sdk" > local.properties
./gradlew :app:assembleStandardRelease
```

产物：`app/build/outputs/apk/standard/release/app-standard-release.apk`

> 没有官方签名密钥，只能用本机 debug key 签。**必须先卸载电视上原有的 Aerial 再装**，
> 代价是壁纸、天气城市、Dock 顺序这些设置会重置。

国内网络提示：

- Gradle 发行包从 `services.gradle.org` 下不动 → 用 `https://mirrors.cloud.tencent.com/gradle/` 手动下
- 依赖很慢 → `settings.gradle.kts` 里把 `maven.aliyun.com` 的镜像放前面
- `compileSdk = 36` → `sdkmanager "platforms;android-36"`

## 实测记录（MiTV-ASTR0，Android 14，5 列）

- 第 1 行第 5 个 → `→` → 第 2 行第 1 个 ✅
- 第 2 行第 1 个 → `←` → 第 1 行第 5 个 ✅（截图逐像素一致）
- 最后一行末尾 → `→` → 不动 ✅（排除状态栏后像素零变化）
