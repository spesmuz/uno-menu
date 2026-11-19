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
  boolean exiting = false;

  DevicePolicyManager dpm;
  ComponentName admin;
  long lastPin = 0;

  boolean owner() {
    try { return dpm != null && dpm.isDeviceOwnerApp(getPackageName()); } catch (Exception e) { return false; }
  }

  /* full kiosk (device owner): nothing can leave the app, status bar off, app is the home screen */
  void setupOwner() {
    if (!owner()) return;
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
    if (exiting) return;
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
    @JavascriptInterface public String mode() { return owner() ? "owner" : "pin"; }
    @JavascriptInterface public void exitApp() { runOnUiThread(new Runnable() { public void run() { leave(false); } }); }
    @JavascriptInterface public void disableKiosk() { runOnUiThread(new Runnable() { public void run() { leave(true); } }); }
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
    setContentView(web);
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
        if (r.isForMainFrame()) { failed = true; showOffline(); }
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
      @Override public void onPermissionRequest(PermissionRequest r) { r.deny(); }
    });

    web.addJavascriptInterface(new Kiosk(), "UnoKiosk");
    web.loadUrl(URL);
  }

  void showOffline() {
    web.loadDataWithBaseURL(null,
      "<html><body style='margin:0;background:#0A0908;color:#E8B04B;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;text-align:center'>" +
      "<div><div style='font-size:26px;margin-bottom:12px'>UNO Airways Restaurante</div>" +
      "<div style='color:#bbb;font-size:17px'>Internetga ulanish kutilmoqda…<br>Подключение к интернету…</div></div></body></html>",
      "text/html", "utf-8", null);
    h.postDelayed(new Runnable() { public void run() { if (failed) { failed = false; web.loadUrl(URL); } } }, 8000);
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
    if (web.canGoBack()) web.goBack();
    else web.evaluateJavascript("window.unoBack&&window.unoBack()", null);
  }
}
