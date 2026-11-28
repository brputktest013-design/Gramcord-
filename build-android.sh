#!/usr/bin/env bash
# Генерирует Android-проект (WebView-оболочка) вокруг index.html и ключ подписи.
# Запускается из GitHub Actions; сам Gradle вызывается отдельным шагом workflow.
set -euo pipefail
cd "$(dirname "$0")"
[ -f index.html ] || { echo "Не найден index.html рядом со скриптом"; exit 1; }

P=android
rm -rf "$P"
mkdir -p "$P/app/src/main/assets" "$P/app/src/main/java/app/gramcord" \
         "$P/app/src/main/res/values" "$P/app/src/main/res/drawable" "$P/app/src/main/res/mipmap-anydpi-v26"
cp index.html "$P/app/src/main/assets/index.html"

# ключ подписи: создаётся один раз и хранится в (приватном!) репозитории,
# чтобы новые версии APK ставились поверх старых без потери данных
if [ ! -f gramcord.jks ]; then
  keytool -genkeypair -keystore gramcord.jks -alias gramcord -keyalg RSA -keysize 2048 \
    -validity 36500 -storepass gramcord-key -keypass gramcord-key -dname "CN=Gramcord, O=Gramcord"
fi

cat > "$P/settings.gradle" <<'EOF'
pluginManagement {
    repositories { google(); mavenCentral(); gradlePluginPortal() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = 'Gramcord'
include ':app'
EOF

cat > "$P/build.gradle" <<'EOF'
plugins {
    id 'com.android.application' version '8.5.2' apply false
}
EOF

cat > "$P/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
EOF

cat > "$P/app/build.gradle" <<'EOF'
plugins {
    id 'com.android.application'
}

android {
    namespace 'app.gramcord'
    compileSdk 34

    defaultConfig {
        applicationId 'app.gramcord'
        minSdk 26
        targetSdk 34
        versionCode (System.getenv('RUN_NUMBER') ?: '1').toInteger()
        versionName '1.' + (System.getenv('RUN_NUMBER') ?: '0')
    }

    signingConfigs {
        release {
            storeFile rootProject.file('../gramcord.jks')
            storePassword 'gramcord-key'
            keyAlias 'gramcord'
            keyPassword 'gramcord-key'
        }
    }

    buildTypes {
        release {
            minifyEnabled false
            signingConfig signingConfigs.release
        }
    }

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    lint {
        checkReleaseBuilds false
        abortOnError false
    }
}

dependencies {
    implementation 'androidx.webkit:webkit:1.11.0'
}
EOF

cat > "$P/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.microphone" android:required="false" />

    <application
        android:label="Gramcord"
        android:icon="@mipmap/ic_launcher"
        android:theme="@style/AppTheme"
        android:usesCleartextTraffic="false">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTask"
            android:windowSoftInputMode="adjustResize"
            android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|keyboardHidden|keyboard|uiMode|density|fontScale">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

cat > "$P/app/src/main/res/values/styles.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="android:Theme.DeviceDefault.NoActionBar">
        <item name="android:windowBackground">@color/gc_bg</item>
        <item name="android:statusBarColor">@color/gc_bg</item>
        <item name="android:navigationBarColor">@color/gc_nav</item>
    </style>
</resources>
EOF

cat > "$P/app/src/main/res/values/colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="gc_bg">#FF181A1D</color>
    <color name="gc_nav">#FF121416</color>
    <color name="gc_icon_bg">#FF2B7FD6</color>
</resources>
EOF

# иконка приложения: векторная (синий фон, белое облачко с буквой G)
cat > "$P/app/src/main/res/drawable/ic_launcher_fg.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="M38,30H70a8,8 0 0 1 8,8V60a8,8 0 0 1 -8,8H50L36,80V68H38a8,8 0 0 1 -8,-8V38a8,8 0 0 1 8,-8Z" />
    <path
        android:strokeColor="#FF2B7FD6"
        android:strokeWidth="4.4"
        android:strokeLineCap="round"
        android:strokeLineJoin="round"
        android:pathData="M62.4,41.9A11,11 0 1 0 65,49H57" />
</vector>
EOF

cat > "$P/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/gc_icon_bg" />
    <foreground android:drawable="@drawable/ic_launcher_fg" />
</adaptive-icon>
EOF

# логика кнопки «назад» внутри приложения: закрывает оверлеи и возвращается из чата
cat > "$P/app/src/main/assets/back.js" <<'EOF'
(function(){
 try{
  var q=function(s){return document.querySelector(s)},e;
  if((e=q('.cmo.on .cmbk'))){e.click();return 1}
  if((e=q('.cpg.on .cpt button'))){e.click();return 1}
  if(typeof SH!=='undefined'&&SH&&SH.classList.contains('on')){SH.classList.remove('on');return 1}
  var pv=q('.bk.pv.on'),st=q('#set.on'),gs=window.gcSettings&&gcSettings.isOpen&&gcSettings.isOpen();
  if(pv||st||gs){e=q('#bnav .bn-b');if(e){e.click();return 1}}
  var m=q('#main.v'),bk=q('#bk');
  if(m&&bk){bk.click();return 1}
 }catch(x){}
 return 0
})()
EOF

cat > "$P/app/src/main/java/app/gramcord/MainActivity.java" <<'EOF'
package app.gramcord;

import android.Manifest;
import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.webkit.WebViewAssetLoader;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;

public class MainActivity extends Activity {
    private static final String HOST = "appassets.androidplatform.net";
    private static final String HOME = "https://" + HOST + "/assets/index.html";
    private static final int REQ_FILE = 1;
    private static final int REQ_PERM = 2;

    private WebView web;
    private ValueCallback<Uri[]> fileCb;
    private PermissionRequest pendingReq;
    private String backJs = "0";

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        backJs = readAsset("back.js");

        final WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();

        web = new WebView(this);
        web.setBackgroundColor(0xFF181A1D);
        setContentView(web);

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        s.setBuiltInZoomControls(false);
        s.setTextZoom(100);
        CookieManager.getInstance().setAcceptCookie(true);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return loader.shouldInterceptRequest(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                if (HOST.equals(u.getHost())) return false;
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, u));
                } catch (Exception ignored) {
                }
                return true;
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> cb, FileChooserParams params) {
                if (fileCb != null) fileCb.onReceiveValue(null);
                fileCb = cb;
                try {
                    startActivityForResult(params.createIntent(), REQ_FILE);
                } catch (Exception e) {
                    fileCb = null;
                    return false;
                }
                return true;
            }

            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        if (!HOST.equals(request.getOrigin().getHost())) {
                            request.deny();
                            return;
                        }
                        ArrayList<String> need = new ArrayList<String>();
                        for (String res : request.getResources()) {
                            if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(res)
                                    && checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                                need.add(Manifest.permission.CAMERA);
                            }
                            if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(res)
                                    && checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                                need.add(Manifest.permission.RECORD_AUDIO);
                            }
                        }
                        if (need.isEmpty()) {
                            request.grant(request.getResources());
                        } else {
                            if (pendingReq != null) pendingReq.deny();
                            pendingReq = request;
                            requestPermissions(need.toArray(new String[0]), REQ_PERM);
                        }
                    }
                });
            }
        });

        if (state == null || web.restoreState(state) == null) {
            web.loadUrl(HOME);
        }
    }

    private String readAsset(String name) {
        try {
            InputStream in = getAssets().open(name);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[4096];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            in.close();
            return out.toString("UTF-8");
        } catch (Exception e) {
            return "0";
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == REQ_FILE) {
            if (fileCb != null) {
                fileCb.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(resultCode, data));
                fileCb = null;
            }
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] results) {
        if (requestCode == REQ_PERM && pendingReq != null) {
            boolean ok = results.length > 0;
            for (int r : results) if (r != PackageManager.PERMISSION_GRANTED) ok = false;
            if (ok) pendingReq.grant(pendingReq.getResources()); else pendingReq.deny();
            pendingReq = null;
            return;
        }
        super.onRequestPermissionsResult(requestCode, permissions, results);
    }

    @Override
    public void onBackPressed() {
        web.evaluateJavascript(backJs, new ValueCallback<String>() {
            @Override
            public void onReceiveValue(String value) {
                if ("1".equals(value)) return;
                if (web.canGoBack()) web.goBack();
                else moveTaskToBack(true);
            }
        });
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        web.saveState(out);
    }

    @Override
    protected void onDestroy() {
        if (web != null) web.destroy();
        super.onDestroy();
    }
}
EOF

echo "Проект сгенерирован в $P/"
