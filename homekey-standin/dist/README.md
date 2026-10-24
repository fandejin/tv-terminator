# dist/

`homekey-standin-com_ts_launcher.apk` —— 在小米电视 MiTV-ASTR0 上实测通过的构建产物。

- 包名：`com.ts.launcher`
- Activity：`com.gathin.tvhome.MainActivity`（沿用旧桌面组件名，与实测环境一致）
- 跳转目标：`app.orchard.tv/.MainActivity`（Aerial）
- 版本号：100

自己重新构建时 Activity 名默认是 `com.homekey.standin.MainActivity`，
别忘了设成对应的组件：

```bash
adb shell cmd package set-home-activity --user 0 \
  com.ts.launcher/com.gathin.tvhome.MainActivity
```
