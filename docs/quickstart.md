# 小白导引：30 分钟改造你的小米电视

> 照着一步步打勾就行。**每一步只做一件事**，做完确认「✅ 正常现象」再往下走。
>
> 详细原理和完整参数 → [完整版文档](xiaomi-tv.md)

---

## 开前安心话

- 全程**不用 root**
- **不卸载**任何系统应用，只是「停用」，一条命令就能开回来
- 最坏的结果是回到原样，**不会变砖**

---

## ✅ 第 1 步：打开 ADB

**在电视上操作：**

1. `设置` → `账号与安全` → `ADB 调试` → 打开
2. 记下电视 IP：`设置` → `网络` → 当前网络（例如 `<电视IP>`）

**在电脑上操作：**

```
adb connect <电视IP>:5555
adb devices
```

> 把 `<电视IP>` 换成你自己的电视 IP

**✅ 正常现象**：出现一行 `<你的电视IP>:5555    device`

**❌ 不对就：**
- 显示 `offline` → 运行 `adb kill-server`，再执行一次 `adb connect`
- 连不上 → 电视 ADB 没开好，或电脑和电视不在同一个 WiFi

---

## ✅ 第 2 步：看你的电视是 32 位还是 64 位

```
adb shell getprop ro.product.cpu.abilist
```

**✅ 怎么判断：**

| 看到什么 | 结论 |
|---|---|
| 只有 `armeabi-v7a` | 32 位 → **下载名里带 v7a 的包** |
| 有 `arm64-v8a` | 64 位 → 普通包就行 |

> 这一步千万别跳过。装错包会报 `INSTALL_FAILED_NO_MATCHING_ABIS`，新手完全看不懂。

---

## ✅ 第 3 步：装干净桌面

```
adb install -r CleanyourTV.apk
adb shell cmd package set-home-activity --user 0 com.ts.launcher/com.gathin.tvhome.MainActivity
```

**✅ 正常现象**：按遥控器 Home 键，出现一个新的 App 网格桌面（带天气）

**❌ 白屏/黑屏** → 说明默认桌面没设成功，重跑第二行命令

> ⚠️ **先别急着删原桌面**，先做第 4 步

---

## ✅ 第 4 步：修 Home 键（小米电视必做）

**为什么会坏**：小米遥控器的 Home 键发的不是标准键值，系统只把它交给小米原桌面。换了桌面后，这个键就没人接了。

**先看看你现在有什么无障碍服务：**

```
adb shell settings get secure enabled_accessibility_services
```

**把桌面自带的服务追加进去**（注意保留原来的服务，用 `:` 隔开）：

```
adb shell settings put secure enabled_accessibility_services "原有服务:com.ts.launcher/com.gathin.tvhome.HomeKeyService"
adb shell settings put secure accessibility_enabled 1
```

举个真实例子（原来只有小爱同学）：

```
adb shell settings put secure enabled_accessibility_services "com.xiaomi.voicecontrol/.VoiceAccessibilityService:com.ts.launcher/com.gathin.tvhome.HomeKeyService"
adb shell settings put secure accessibility_enabled 1
```

**✅ 正常现象**：遥控器按 Home，回到新桌面；按设置键，能打开系统设置

**❌ 还是没反应** → 检查有没有写错包名（是 `com.ts.launcher`，不是 `com.gathin.tvhome`）

---

## ✅ 第 5 步：停用小米广告桌面（可选）

```
adb shell pm disable-user --user 0 com.mitv.tvhome
```

**✅ 正常现象**：按 Home 还是进新桌面

**❌ 白屏了** → 立刻执行这条救回来：
```
adb shell pm enable com.mitv.tvhome
```

---

## ✅ 第 6 步：装三个 App

```
adb install -r SmartTube-v7a.apk
adb install -r FongMi-v7a.apk
adb install -r TVBro.apk
```

- **SmartTube** = 电视版 YouTube（无广告）
- **FongMi** = 影视聚合（需要自己找接口源）
- **TVBro** = 浏览器（用来看抖音）

> 32 位电视请务必用 `v7a` 版本

---

## ✅ 第 7 步：让电视能上 YouTube（不需要看 YouTube 就整步跳过）

> 跳过不影响前面和后面的任何步骤。要看 YouTube 才需要往下做。

1. 电脑上的代理软件打开 **「允许局域网连接 / Allow LAN」**
2. 查出电脑的局域网 IP（`ipconfig` 里的 IPv4 地址，比如 `<电脑IP>`）
3. 在电脑上执行：

```
adb shell settings put global http_proxy <电脑IP>:7897
```

> 端口 `7897` 换成你代理软件的实际端口

**✅ 正常现象**：打开 SmartTube，能刷出视频列表

**❌ 一直转圈** → IP 填错了，必须是**电脑的局域网 IP**（不是 WSL 的、不是 127.0.0.1）

**取消代理：**
```
adb shell settings put global http_proxy :0
```

> 记住：**电脑关机/睡眠，电视就上不了 YouTube**

---

## ✅ 第 8 步：电视看抖音

1. 打开 **TVBro**
2. 按返回键呼出工具栏 → 点齿轮（设置）
3. 找到 **主页** → 选 **自定义**
4. 输入（**必须带 https://**）：

```
https://www.douyin.com
```

5. 返回，重启 TVBro 验证

**遥控器怎么操作：**

| 按键 | 作用 |
|---|---|
| 短按方向键 | 移动光标 |
| **长按方向键** | **滚动页面 / 换视频** |
| OK | 打开光标处的视频 |
| 返回 | 呼出/收起工具栏 |

光标太慢 → 设置里把 **虚拟光标最大速度** 拉到 150%~200%

---

## 🎉 搞定

到这里你就有了：

- 没有广告的干净桌面
- 能看 YouTube（走电脑代理）
- 能看影视聚合（自己加源）
- 能刷抖音网页版

出问题先翻 → [完整版文档的踩坑清单](xiaomi-tv.md#十踩坑清单)
