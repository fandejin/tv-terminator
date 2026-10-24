# Home 键替身 · HomeKey Stand-in

> 按 Home 键直接回到你想用的桌面——中间那一帧"原厂桌面"不会再出现。

一个 **2KB、零界面** 的 Android 小 App。装上它、设成默认桌面，它就安安静静待在那里；
每次系统要显示桌面时，它瞬间把请求转交给真正的桌面 App，自己不画一个像素。

---

## 它解决什么问题

很多国产电视（尤其是小米）上会出现这种情况：

1. 你装了个第三方桌面，比如 Aerial、当贝、Emotn
2. 你执行 `adb shell cmd package set-home-activity ...`，系统回 `Success`
3. 但按 Home 键，**回来的还是原厂桌面**，然后第三方桌面自己的守护服务再抢回来
4. 于是每次按 Home，中间都会闪一下

原因：**这些 ROM 会忽略标准的"默认桌面"设置**。Aerial 官方文档就写着：

> 默认桌面（只有 standard 版；**小米会忽略**）

它们绕开的办法是——用一个无障碍服务监控前台窗口，看到原厂桌面冒头就切回来。
代价就是那一下闪烁。

---

## 原理

小米 ROM 虽然忽略"默认桌面"设置，但会**按包名**决定认不认一个桌面 App。
所以换个思路：**别让目标桌面去当桌面，让一个"替身"去当。**

```
按 Home
  └→ 系统把 HOME 交给替身（因为它的包名被系统认可）
       └→ 替身 onCreate 里立刻 startActivity(真正的桌面)
            └→ 替身 finish()，全程不渲染任何像素
```

关键在于替身的 Activity 用了 `@android:style/Theme.NoDisplay`——它没有窗口，所以用户看不到中间帧。

实测（小米电视，Aerial 桌面，用 ADB 连续截帧比对）：

```
按 Home 后 t0  2,753,684 bytes
按 Home 后 t1  2,753,684 bytes   ← 三帧完全一致
按 Home 后 t2  2,753,684 bytes
```

三帧全是 Aerial，**一帧原厂桌面都没抓到**。

---

## 包名为什么这么讲究

同一段代码，只改包名，系统的态度完全不同（小米电视实测）：

| 替身包名 | 能不能被系统当成桌面 |
|---|---|
| `com.ts.launcher` | ✅ 可以 |
| `app.orchard.tv`（Aerial 自己） | ❌ 退回 FallbackHome |
| `com.finn.homebridge`（随便起的） | ❌ 退回 FallbackHome |

所以我们沿用了这台电视上**曾经被认可过的桌面包名** `com.ts.launcher`。
包名可在 `--pkg` 里改，换电视时建议先做这个小实验确定哪个包名被认。

---

## 快速上手

### 1. 构建

需要：JDK 8+、Android SDK（build-tools + 任意 platform）。**不需要 Gradle。**

```bash
./build.sh \
  --pkg com.ts.launcher \
  --target-pkg app.orchard.tv \
  --target-class app.orchard.tv.MainActivity
```

想直接覆盖电视上已装的版本，加 `--version-code 100`（要 ≥ 对方版本号）。

仓库里 `dist/` 那份预编译 APK 是在小米电视上实测通过的版本（组件名 `com.gathin.tvhome.MainActivity`，目标 Aerial），详见 [dist/README.md](dist/README.md)。

### 2. 安装

```bash
adb connect <电视IP>:5555      # 换成你电视的 IP
adb install -r dist/homekey-standin-com_ts_launcher.apk
```

### 3. 设为默认桌面

```bash
adb shell cmd package set-home-activity --user 0 \
  com.ts.launcher/com.homekey.standin.MainActivity
```

> 注意 Activity 名要和构建时一致。构建脚本默认用 `com.homekey.standin.MainActivity`；
> 如果你的目标是复用旧桌面的组件名，用 `--activity` 指定。

### 4. 验证

```bash
# 看系统解析到哪个桌面
adb shell cmd package resolve-activity --brief \
  -a android.intent.action.MAIN -c android.intent.category.HOME

# 实际按一次 Home，看前台是谁
adb shell input keyevent 3
adb shell dumpsys activity activities | grep -m1 topResumedActivity
```

---

## 可选：顺手把原厂桌面停掉

替身拿到 HOME 之后，原厂桌面就可以停了（不影响）：

```bash
adb shell pm disable-user --user 0 com.mitv.tvhome
```

⚠️ **顺序很重要**：先确认替身已经生效，再停原厂桌面。
反过来的话，中间会掉进 `FallbackHome` 黑屏。

---

## 换一台电视 / 换一个桌面

```bash
./build.sh \
  --pkg <被系统认可的包名> \
  --activity <替身的组件名> \
  --target-pkg <目标桌面包名> \
  --target-class <目标桌面 Activity 全名>
```

目标的 Activity 全名可以这样查：

```bash
adb shell cmd package resolve-activity --brief -a android.intent.action.MAIN \
  -c android.intent.category.LAUNCHER <包名>
```

---

## 已知边界

- **只解决"闪一下"，不解决"系统不认第三方桌面"本身**。系统层面上，真正的桌面还是原厂那个包名。
- **包名白名单是经验规律**，不同 ROM / 不同版本可能不一样，换机请先做上面的包名实验。
- 替身**没有任何 UI**：如果目标桌面被卸载或崩溃，按 Home 会得到黑屏。删掉替身即可恢复。
- 替身不处理开机自启——那是目标桌面自己的事（Aerial 有通知监听复活机制）。
- 不适合当"多桌面切换器"：它只认一个写死的目标。

## 回退

```bash
# 1. 先恢复原厂桌面
adb shell pm enable com.mitv.tvhome
adb shell cmd package set-home-activity --user 0 \
  com.mitv.tvhome/com.mitv.tvhome.MainActivityUserMode

# 2. 再删替身
adb shell pm uninstall --user 0 com.ts.launcher
```

---

## 目录结构

```
homekey-standin/
├── build.sh                    # 一键构建（javac + d8 + aapt2 + zipalign + apksigner）
├── manifest/AndroidManifest.xml # 模板，占位符由 build.sh 替换
├── src/com/homekey/standin/
│   └── MainActivity.java       # 全部逻辑就这 60 行
└── dist/                       # 构建产物
```

## 许可

代码随便用。注意 `--pkg com.ts.launcher` 是借用旧桌面的包名，只适合在自己设备上折腾，
不要拿去做任何冒充别人的事。
