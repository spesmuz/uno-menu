package uz.uno.airways;

import android.app.Activity;
import android.app.ActivityManager;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.IntentFilter;
import android.content.pm.ResolveInfo;
import android.os.Build;
import android.provider.Settings;
import java.util.List;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.view.View;
import android.view.WindowManager;
import android.webkit.*;
import java.util.ArrayList;

public class MainActivity extends Activity {
  static final String URL = "__SITE_URL__";
  static final int PICK = 7;
  WebView web;
  ValueCallback<Uri[]> fileCb;
  final Handler h = new Handler();
  boolean failed = false;
  boolean loading = false;
  static final String DEFAULT_PIN = "0000";

  /* kiosk is off by default; the admin turns it on only on the restaurant's own tablets */
  boolean kioskOn() { return getSharedPreferences("uno", MODE_PRIVATE).getBoolean("kiosk", false); }
  void homeAlias(boolean on) {
    try {
      getPackageManager().setComponentEnabledSetting(new ComponentName(this, getPackageName() + ".HomeAlias"),
        on ? android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED : android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
        android.content.pm.PackageManager.DONT_KILL_APP);
    } catch (Exception e) { }
  }
  void setKioskNow(boolean on) {
    getSharedPreferences("uno", MODE_PRIVATE).edit().putBoolean("kiosk", on).commit();
    homeAlias(on);
    if (on) { exiting = false; lastPin = 0; setupOwner(); pin(); }
    else {
      if (owner()) {
        try { dpm.clearPackagePersistentPreferredActivities(admin, getPackageName()); } catch (Exception e) { }
        try { dpm.setStatusBarDisabled(admin, false); } catch (Exception e) { }
      }
      try { stopLockTask(); } catch (Exception e) { }
    }
  }

  String exitPin() { return getSharedPreferences("uno", MODE_PRIVATE).getString("exit_pin", DEFAULT_PIN); }

  /* the page did not finish in 20 s (e.g. Wi-Fi without internet): show the waiting screen */
  final Runnable watchdog = new Runnable() { public void run() {
    if (loading) { loading = false; try { web.stopLoading(); } catch (Exception e) { } failed = true; showOffline(); }
  } };
  boolean exiting = false;

  DevicePolicyManager dpm;
  ComponentName admin;
  long lastPin = 0;

  boolean owner() {
    try { return dpm != null && dpm.isDeviceOwnerApp(getPackageName()); } catch (Exception e) { return false; }
  }

  /* full kiosk (device owner): nothing can leave the app, status bar off, app is the home screen */
  void setupOwner() {
    if (!owner() || !kioskOn()) return;
    try { dpm.setLockTaskPackages(admin, new String[]{ getPackageName() }); } catch (Exception e) { }
    try { if (Build.VERSION.SDK_INT >= 28) dpm.setLockTaskFeatures(admin, DevicePolicyManager.LOCK_TASK_FEATURE_NONE); } catch (Exception e) { }
    try {
      IntentFilter f = new IntentFilter(Intent.ACTION_MAIN);
      f.addCategory(Intent.CATEGORY_HOME); f.addCategory(Intent.CATEGORY_DEFAULT);
      dpm.addPersistentPreferredActivity(admin, f, new ComponentName(this, MainActivity.class));
    } catch (Exception e) { }
    try { dpm.setStatusBarDisabled(admin, true); } catch (Exception e) { }
  }

  /* pin the app (screen pinning; silent and unbreakable in device-owner mode) */
  void pin() {
    if (exiting || !kioskOn()) return;
    long now = System.currentTimeMillis();
    if (now - lastPin < 4000) return;
    lastPin = now;
    try {
      ActivityManager am = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
      if (am.getLockTaskModeState() == ActivityManager.LOCK_TASK_MODE_NONE) startLockTask();
    } catch (Exception e) { }
  }

  void openOtherHome() {
    try {
      Intent h = new Intent(Intent.ACTION_MAIN); h.addCategory(Intent.CATEGORY_HOME);
      List<ResolveInfo> l = getPackageManager().queryIntentActivities(h, 0);
      for (ResolveInfo ri : l) {
        if (ri.activityInfo == null || getPackageName().equals(ri.activityInfo.packageName)) continue;
        Intent i = new Intent(Intent.ACTION_MAIN); i.addCategory(Intent.CATEGORY_HOME);
        i.setClassName(ri.activityInfo.packageName, ri.activityInfo.name);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(i); return;
      }
    } catch (Exception e) { }
    try { startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); } catch (Exception e) { }
  }

  void leave(boolean full) {
    exiting = true;
    if (owner()) {
      try { dpm.clearPackagePersistentPreferredActivities(admin, getPackageName()); } catch (Exception e) { }
      try { dpm.setStatusBarDisabled(admin, false); } catch (Exception e) { }
    }
    try { stopLockTask(); } catch (Exception e) { }
    if (full) {
      if (owner()) { try { dpm.clearDeviceOwnerApp(getPackageName()); } catch (Exception e) { } }
      try { startActivity(new Intent(Settings.ACTION_HOME_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); }
      catch (Exception e) { openOtherHome(); }
    } else openOtherHome();
    finishAndRemoveTask();
  }

  /* called from the admin panel (only after admin login) */
  public class Kiosk {
    @JavascriptInterface public boolean isApp() { return true; }
    @JavascriptInterface public String mode() { return !kioskOn() ? "off" : owner() ? "owner" : "pin"; }
    @JavascriptInterface public boolean kioskOn() { return MainActivity.this.kioskOn(); }
    @JavascriptInterface public void setKiosk(final boolean on) { runOnUiThread(new Runnable() { public void run() { setKioskNow(on); } }); }
    @JavascriptInterface public void exitApp() { runOnUiThread(new Runnable() { public void run() { leave(false); } }); }
    @JavascriptInterface public void disableKiosk() { runOnUiThread(new Runnable() { public void run() { leave(true); } }); }
    /* offline exit: PIN kept on this tablet, set from the admin panel */
    @JavascriptInterface public boolean hasPin() { return !DEFAULT_PIN.equals(exitPin()); }
    @JavascriptInterface public boolean setPin(String p) {
      if (p == null || !p.matches("\\d{4,8}")) return false;
      return getSharedPreferences("uno", MODE_PRIVATE).edit().putString("exit_pin", p).commit();
    }
    @JavascriptInterface public boolean exitWithPin(String p) {
      if (p == null || !p.equals(exitPin())) return false;
      runOnUiThread(new Runnable() { public void run() { leave(false); } });
      return true;
    }
    /* save a PNG (base64) into the phone gallery: Pictures/UNO. Returns "ok", "perm" (permission asked) or "err" */
    @JavascriptInterface public String saveImage(String name, String b64) {
      try {
        if (name == null || !name.matches("[A-Za-z0-9_.-]{1,80}")) return "err";
        int c = b64.indexOf(','); if (c >= 0) b64 = b64.substring(c + 1);
        byte[] data = android.util.Base64.decode(b64, android.util.Base64.DEFAULT);
        if (Build.VERSION.SDK_INT >= 29) {
          android.content.ContentValues v = new android.content.ContentValues();
          v.put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name);
          v.put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "image/png");
          v.put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Pictures/UNO");
          Uri u = getContentResolver().insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI, v);
          if (u == null) return "err";
          java.io.OutputStream o = getContentResolver().openOutputStream(u);
          o.write(data); o.close();
          return "ok";
        }
        if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
          runOnUiThread(new Runnable() { public void run() { requestPermissions(new String[] { android.Manifest.permission.WRITE_EXTERNAL_STORAGE }, 11); } });
          return "perm";
        }
        java.io.File dir = new java.io.File(android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_PICTURES), "UNO");
        dir.mkdirs();
        java.io.File f = new java.io.File(dir, name);
        java.io.FileOutputStream o = new java.io.FileOutputStream(f);
        o.write(data); o.close();
        android.media.MediaScannerConnection.scanFile(MainActivity.this, new String[] { f.getAbsolutePath() }, new String[] { "image/png" }, null);
        return "ok";
      } catch (Exception e) { return "err"; }
    }
    /* save any file (base64) into Downloads/UNO, e.g. a ZIP of QR cards */
    @JavascriptInterface public String saveFile(String name, String b64, String mime) {
      try {
        if (name == null || !name.matches("[A-Za-z0-9_.-]{1,80}")) return "err";
        if (mime == null || mime.length() == 0) mime = "application/octet-stream";
        int c = b64.indexOf(','); if (c >= 0) b64 = b64.substring(c + 1);
        byte[] data = android.util.Base64.decode(b64, android.util.Base64.DEFAULT);
        if (Build.VERSION.SDK_INT >= 29) {
          android.content.ContentValues v = new android.content.ContentValues();
          v.put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, name);
          v.put(android.provider.MediaStore.MediaColumns.MIME_TYPE, mime);
          v.put(android.provider.MediaStore.MediaColumns.RELATIVE_PATH, "Download/UNO");
          Uri u = getContentResolver().insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
          if (u == null) return "err";
          java.io.OutputStream o = getContentResolver().openOutputStream(u);
          o.write(data); o.close();
          return "ok";
        }
        if (checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
          runOnUiThread(new Runnable() { public void run() { requestPermissions(new String[] { android.Manifest.permission.WRITE_EXTERNAL_STORAGE }, 11); } });
          return "perm";
        }
        java.io.File dir = new java.io.File(android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS), "UNO");
        dir.mkdirs();
        java.io.File f = new java.io.File(dir, name);
        java.io.FileOutputStream o = new java.io.FileOutputStream(f);
        o.write(data); o.close();
        android.media.MediaScannerConnection.scanFile(MainActivity.this, new String[] { f.getAbsolutePath() }, new String[] { mime }, null);
        return "ok";
      } catch (Exception e) { return "err"; }
    }
    @JavascriptInterface public void retry() { runOnUiThread(new Runnable() { public void run() { failed = false; web.loadUrl(URL); } }); }
  }

  void immersive() {
    getWindow().getDecorView().setSystemUiVisibility(
      View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION |
      View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION |
      View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
  }

  @Override public void onCreate(Bundle b) {
    super.onCreate(b);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    dpm = (DevicePolicyManager) getSystemService(Context.DEVICE_POLICY_SERVICE);
    admin = new ComponentName(this, AdminReceiver.class);
    setupOwner();
    immersive();
    web = new WebView(this);
    web.setBackgroundColor(Color.parseColor("#0A0908"));
    final android.widget.FrameLayout root = new android.widget.FrameLayout(this);
    root.setBackgroundColor(Color.parseColor("#0A0908"));
    root.addView(web, new android.widget.FrameLayout.LayoutParams(-1, -1));
    setContentView(root);
    /* Android 15+ draws apps edge-to-edge: keep the page clear of the keyboard */
    if (Build.VERSION.SDK_INT >= 30) {
      root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
        public android.view.WindowInsets onApplyWindowInsets(View v, android.view.WindowInsets in) {
          android.graphics.Insets i = in.getInsets(android.view.WindowInsets.Type.ime());
          v.setPadding(i.left, i.top, i.right, i.bottom);
          return android.view.WindowInsets.CONSUMED;
        }
      });
    }
    WebSettings s = web.getSettings();
    s.setJavaScriptEnabled(true);
    s.setDomStorageEnabled(true);
    s.setDatabaseEnabled(true);
    s.setMediaPlaybackRequiresUserGesture(false);
    s.setAllowFileAccess(false);
    s.setAllowContentAccess(true);
    s.setCacheMode(WebSettings.LOAD_DEFAULT);
    s.setTextZoom(100);
    s.setSupportZoom(false);
    web.setOverScrollMode(View.OVER_SCROLL_NEVER);

    web.setWebViewClient(new WebViewClient() {
      @Override public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
        if (r.isForMainFrame()) { loading = false; h.removeCallbacks(watchdog); failed = true; showOffline(); }
      }
      @Override public void onPageStarted(WebView v, String url, android.graphics.Bitmap icon) {
        if (url != null && url.startsWith(URL)) { loading = true; h.removeCallbacks(watchdog); h.postDelayed(watchdog, 20000); }
      }
      @Override public void onPageFinished(WebView v, String url) {
        if (url != null && url.startsWith(URL)) { loading = false; h.removeCallbacks(watchdog); }
      }
      @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
        String u = r.getUrl().toString();
        return !(u.startsWith(URL) || u.startsWith("about:"));
      }
    });

    web.setWebChromeClient(new WebChromeClient() {
      @Override public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
        if (fileCb != null) fileCb.onReceiveValue(null);
        fileCb = cb;
        ArrayList<String> types = new ArrayList<String>();
        for (String a : p.getAcceptTypes()) for (String t : a.split(",")) { t = t.trim(); if (t.contains("/")) types.add(t); }
        Intent i = new Intent(Intent.ACTION_GET_CONTENT);
        i.addCategory(Intent.CATEGORY_OPENABLE);
        i.setType(types.size() == 1 ? types.get(0) : "*/*");
        if (types.size() > 1) i.putExtra(Intent.EXTRA_MIME_TYPES, types.toArray(new String[0]));
        try { startActivityForResult(Intent.createChooser(i, "Fayl tanlang"), PICK); }
        catch (Exception e) { fileCb = null; return false; }
        return true;
      }
      @Override public void onPermissionRequest(final PermissionRequest r) {
        runOnUiThread(new Runnable() { public void run() { askCamera(r); } });
      }
    });

    web.addJavascriptInterface(new Kiosk(), "UnoKiosk");
    web.loadUrl(URL);
  }

  /* camera for the staff attendance screen (davomat.html): only our own site, only video */
  PermissionRequest camReq;
  static final int CAM = 9;
  void askCamera(PermissionRequest r) {
    boolean video = false;
    for (String res : r.getResources()) if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(res)) video = true;
    String origin = r.getOrigin() == null ? "" : r.getOrigin().toString();
    if (!video || !URL.startsWith(origin.endsWith("/") ? origin : origin + "/")) { r.deny(); return; }
    String[] grant = new String[] { PermissionRequest.RESOURCE_VIDEO_CAPTURE };
    if (Build.VERSION.SDK_INT < 23 || checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) { r.grant(grant); return; }
    try {
      if (dpm != null && dpm.isDeviceOwnerApp(getPackageName())) {
        dpm.setPermissionGrantState(admin, getPackageName(), android.Manifest.permission.CAMERA, DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED);
        if (checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) { r.grant(grant); return; }
      }
    } catch (Exception e) { }
    if (camReq != null) camReq.deny();
    camReq = r;
    requestPermissions(new String[] { android.Manifest.permission.CAMERA }, CAM);
  }

  @Override public void onRequestPermissionsResult(int rq, String[] perms, int[] res) {
    if (rq == CAM && camReq != null) {
      if (res.length > 0 && res[0] == android.content.pm.PackageManager.PERMISSION_GRANTED) camReq.grant(new String[] { PermissionRequest.RESOURCE_VIDEO_CAPTURE });
      else camReq.deny();
      camReq = null;
    } else super.onRequestPermissionsResult(rq, perms, res);
  }

  void showOffline() {
    web.loadDataWithBaseURL(null,
      "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>" +
      "body{margin:0;background:#0A0908;color:#E8B04B;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;text-align:center;-webkit-user-select:none;user-select:none}" +
      "h1{font-size:26px;letter-spacing:.12em;margin:0 0 14px;font-weight:700}p{color:#bbb;font-size:17px;line-height:1.5;margin:0 0 22px}" +
      "button{height:52px;padding:0 28px;border-radius:16px;border:0;background:#E8B04B;color:#1a1306;font-size:17px;font-weight:700}" +
      "#pin{display:none;margin-top:26px}#pin input{height:48px;width:160px;border-radius:12px;border:1px solid #5a4a2a;background:#16140f;color:#fff;font-size:22px;text-align:center;letter-spacing:.3em}" +
      "#pin button{background:#3a1d1a;color:#ff9a8a;margin-left:8px}#m{color:#ff9a8a;font-size:14px;margin-top:10px;min-height:18px}</style></head><body><div>" +
      "<h1 id='t'>UNO AIRWAYS</h1><p>Internetga ulanish kutilmoqda…<br>Подключение к интернету…</p>" +
      "<button onclick='UnoKiosk.retry()'>Qayta urinish</button>" +
      "<div id='pin'><input id='v' type='password' inputmode='numeric' maxlength='8' placeholder='PIN'><button onclick=\"if(!UnoKiosk.exitWithPin(document.getElementById('v').value)){document.getElementById('m').textContent='PIN noto\\'g\\'ri';document.getElementById('v').value='';}\">Chiqish</button><div id='m'></div></div>" +
      "</div><script>var n=0,tt=null,open=false;document.getElementById('t').addEventListener('click',function(){n++;clearTimeout(tt);tt=setTimeout(function(){n=0},1500);if(n>=7){open=true;document.getElementById('pin').style.display='block';document.getElementById('v').focus();}});" +
      "setInterval(function(){if(!open)UnoKiosk.retry();},15000);</script></body></html>",
      "text/html", "utf-8", null);
  }

  @Override protected void onActivityResult(int rq, int rc, Intent data) {
    if (rq == PICK && fileCb != null) {
      fileCb.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(rc, data));
      fileCb = null;
    } else super.onActivityResult(rq, rc, data);
  }

  @Override public void onWindowFocusChanged(boolean f) { super.onWindowFocusChanged(f); if (f) immersive(); }
  @Override protected void onResume() { super.onResume(); web.onResume(); immersive(); pin(); }
  @Override protected void onPause() { web.onPause(); super.onPause(); }

  @Override public void onBackPressed() {
    if (web.canGoBack()) { web.goBack(); return; }
    web.evaluateJavascript("(window.unoBack&&window.unoBack())?1:0", new ValueCallback<String>() {
      public void onReceiveValue(String r) {
        /* nothing left to close inside the page: an ordinary (non-kiosk) app goes to the background */
        if (!"1".equals(r) && !kioskOn()) moveTaskToBack(true);
      }
    });
  }
}
