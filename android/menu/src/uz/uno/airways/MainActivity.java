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
  boolean repin = false;            /* came back from a dock app: lock again */
  final Runnable pinLater = new Runnable() { public void run() { lastPin = 0; pin(); } };

  DevicePolicyManager dpm;
  ComponentName admin;
  long lastPin = 0;

  boolean owner() {
    try { return dpm != null && dpm.isDeviceOwnerApp(getPackageName()); } catch (Exception e) { return false; }
  }

  /* full kiosk (device owner): nothing can leave the app, status bar off, app is the home screen */
  void setupOwner() {
    if (!owner() || !kioskOn()) return;
    /* incoming calls must still ring and be answerable: allow the phone app inside the locked mode */
    String dialer = null;
    try { dialer = ((android.telecom.TelecomManager) getSystemService(Context.TELECOM_SERVICE)).getDefaultDialerPackage(); } catch (Exception e) { }
    try { dpm.setLockTaskPackages(admin, dialer == null ? new String[]{ getPackageName() } : new String[]{ getPackageName(), dialer }); } catch (Exception e) { }
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
    /* door terminal dock: open the phone, SMS or another work app (e.g. Plus) even while the kiosk is on */
    @JavascriptInterface public String openApp(final String what) {
      try {
        Intent i;
        String pkg = null;
        if ("dial".equals(what)) i = new Intent(Intent.ACTION_DIAL);
        else if ("sms".equals(what)) {
          try { pkg = android.provider.Telephony.Sms.getDefaultSmsPackage(MainActivity.this); } catch (Exception e) { }
          i = pkg != null ? getPackageManager().getLaunchIntentForPackage(pkg) : null;
          if (i == null) { i = new Intent(Intent.ACTION_MAIN); i.addCategory(Intent.CATEGORY_APP_MESSAGING); }
        } else {
          if (what == null || !what.matches("[A-Za-z0-9_.]{3,120}")) return "err";
          pkg = what; i = getPackageManager().getLaunchIntentForPackage(pkg);
          if (i == null) return "none";
        }
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        final Intent go = i; final String target = pkg;
        runOnUiThread(new Runnable() { public void run() {
          if (kioskOn()) {
            if (owner()) {
              /* full kiosk: let this app run inside the locked mode */
              java.util.ArrayList<String> l = new java.util.ArrayList<String>();
              l.add(getPackageName());
              try { String d = ((android.telecom.TelecomManager) getSystemService(Context.TELECOM_SERVICE)).getDefaultDialerPackage(); if (d != null) l.add(d); } catch (Exception e) { }
              try { String sm = android.provider.Telephony.Sms.getDefaultSmsPackage(MainActivity.this); if (sm != null) l.add(sm); } catch (Exception e) { }
              if (target != null) l.add(target);
              try { ResolveInfo ri = getPackageManager().resolveActivity(go, 0); if (ri != null && ri.activityInfo != null) l.add(ri.activityInfo.packageName); } catch (Exception e) { }
              try { dpm.setLockTaskPackages(admin, l.toArray(new String[0])); } catch (Exception e) { }
            } else {
              /* screen pinning: unpin while the other app is open; it pins again when the user comes back */
              try { stopLockTask(); } catch (Exception e) { }
              lastPin = 0; repin = true;
            }
          }
          try { startActivity(go); } catch (Exception e) { }
        } });
        return "ok";
      } catch (Exception e) { return "err"; }
    }
    /* installed apps that can be opened (for choosing the third dock button) */
    @JavascriptInterface public String apps() {
      try {
        Intent m = new Intent(Intent.ACTION_MAIN); m.addCategory(Intent.CATEGORY_LAUNCHER);
        List<ResolveInfo> l = getPackageManager().queryIntentActivities(m, 0);
        StringBuilder b = new StringBuilder("[");
        java.util.HashSet<String> seen = new java.util.HashSet<String>();
        for (ResolveInfo ri : l) {
          if (ri.activityInfo == null) continue;
          String p = ri.activityInfo.packageName; if (p.equals(getPackageName()) || !seen.add(p)) continue;
          String n = String.valueOf(ri.loadLabel(getPackageManager())).replace("\\", "").replace("\"", "'");
          if (b.length() > 1) b.append(',');
          b.append("{\"n\":\"").append(n).append("\",\"p\":\"").append(p).append("\"}");
        }
        return b.append(']').toString();
      } catch (Exception e) { return "[]"; }
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

  /* camera (staff attendance) and microphone (UNO AI voice commands): only our own site */
  PermissionRequest camReq;
  String[] camGrant;
  static final int CAM = 9;
  boolean has(String p) { return Build.VERSION.SDK_INT < 23 || checkSelfPermission(p) == android.content.pm.PackageManager.PERMISSION_GRANTED; }
  void askCamera(PermissionRequest r) {
    String origin = r.getOrigin() == null ? "" : r.getOrigin().toString();
    if (!URL.startsWith(origin.endsWith("/") ? origin : origin + "/")) { r.deny(); return; }
    java.util.ArrayList<String> grant = new java.util.ArrayList<String>(), need = new java.util.ArrayList<String>();
    for (String res : r.getResources()) {
      if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(res)) { grant.add(res); if (!has(android.Manifest.permission.CAMERA)) need.add(android.Manifest.permission.CAMERA); }
      if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(res)) { grant.add(res); if (!has(android.Manifest.permission.RECORD_AUDIO)) need.add(android.Manifest.permission.RECORD_AUDIO); }
    }
    if (grant.isEmpty()) { r.deny(); return; }
    String[] g = grant.toArray(new String[0]);
    if (need.isEmpty()) { r.grant(g); return; }
    try {
      if (dpm != null && dpm.isDeviceOwnerApp(getPackageName())) {
        for (String p : need) dpm.setPermissionGrantState(admin, getPackageName(), p, DevicePolicyManager.PERMISSION_GRANT_STATE_GRANTED);
        boolean all = true; for (String p : need) if (!has(p)) all = false;
        if (all) { r.grant(g); return; }
      }
    } catch (Exception e) { }
    if (camReq != null) camReq.deny();
    camReq = r; camGrant = g;
    requestPermissions(need.toArray(new String[0]), CAM);
  }

  @Override public void onRequestPermissionsResult(int rq, String[] perms, int[] res) {
    if (rq == CAM && camReq != null) {
      boolean ok = res.length > 0;
      for (int x : res) if (x != android.content.pm.PackageManager.PERMISSION_GRANTED) ok = false;
      if (ok) camReq.grant(camGrant); else camReq.deny();
      camReq = null; camGrant = null;
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

  @Override public void onWindowFocusChanged(boolean f) { super.onWindowFocusChanged(f); if (f) { immersive(); if (kioskOn()) { lastPin = 0; pin(); } } }
  @Override protected void onResume() {
    super.onResume(); web.onResume(); immersive(); pin();
    /* the lock can only start once the window is really in front: try again shortly after returning */
    if (kioskOn()) { h.removeCallbacks(pinLater); h.postDelayed(pinLater, 700); if (repin) { h.postDelayed(pinLater, 1800); repin = false; } }
  }
  @Override protected void onPause() { web.onPause(); super.onPause(); }

  @Override public void onBackPressed() {
    String cur = web.getUrl();
    /* attendance terminal: Back does nothing (no way to the admin login) */
    if (cur != null && cur.contains("davomat.html")) return;
    if (web.canGoBack()) { web.goBack(); return; }
    web.evaluateJavascript("(window.unoBack&&window.unoBack())?1:0", new ValueCallback<String>() {
      public void onReceiveValue(String r) {
        /* nothing left to close inside the page: an ordinary (non-kiosk) app goes to the background */
        if (!"1".equals(r) && !kioskOn()) moveTaskToBack(true);
      }
    });
  }
}
