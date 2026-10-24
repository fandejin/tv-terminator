package com.homekey.standin;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.os.Bundle;

/**
 * HomeKey Stand-in —— 主页替身
 *
 * 一个没有任何界面的“中转站”：
 *  1. 系统把 HOME 请求交给它（因为它占着一个被系统认可的包名）
 *  2. 它立刻把请求转交给真正的桌面 App
 *  3. 它自己 finish()，不渲染任何像素
 *
 * 结果：用户按 Home 时看不到中间那一帧系统桌面。
 *
 * 构建时由 build.sh 替换 __TARGET_PKG__ / __TARGET_CLS__ 两个占位符。
 */
public class MainActivity extends Activity {

    private static final String TARGET_PKG = "__TARGET_PKG__";
    private static final String TARGET_CLS = "__TARGET_CLS__";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        forward();
        finish();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        forward();
        finish();
    }

    private void forward() {
        // 防止把自己当成目标 → 无限递归
        if (TARGET_PKG.equals(getPackageName())) {
            return;
        }
        try {
            Intent i = new Intent(Intent.ACTION_MAIN);
            i.addCategory(Intent.CATEGORY_LAUNCHER);
            i.setComponent(new ComponentName(TARGET_PKG, TARGET_CLS));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
            startActivity(i);
        } catch (Throwable t) {
            // 目标桌面没装/被停用：尝试用包名启动一次，再失败就静默
            try {
                Intent i = getPackageManager().getLaunchIntentForPackage(TARGET_PKG);
                if (i != null) {
                    i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                    startActivity(i);
                }
            } catch (Throwable ignored) {
            }
        }
    }
}
