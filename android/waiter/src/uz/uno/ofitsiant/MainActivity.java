package uz.uno.ofitsiant;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.PowerManager;
import android.provider.Settings;
import android.view.View;
import android.view.WindowManager;
import android.webkit.*;

public class MainActivity extends Activity {
  static final String URL = "__SITE_URL__ofitsiant.html";
  WebView web;
  final Handler h = new Handler();
  boolean failed = false, askedBattery = false;

  public class Waiter {
    @JavascriptInterface public boolean isApp() { return true; }
    @JavascriptInterface public void poll() { WatchService.start(MainActivity.this, "poll"); }
    @JavascriptInterface public void mute() { WatchService.start(MainActivity.this, "mute"); }
  }

  @SuppressWarnings("deprecation")
  @Override public void onCreate(Bundle b) {
    super.onCreate(b);
    getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);
    web = new WebView(this);
    web.setBackgroundColor(Color.parseColor("#0A0908"));
    setContentView(web);
    WebSettings s = web.getSettings();
    s.setJavaScriptEnabled(true);
    s.setDomStorageEnabled(true);
    s.setMediaPlaybackRequiresUserGesture(false);
    s.setAllowFileAccess(false);
    s.setTextZoom(100);
    web.setWebViewClient(new WebViewClient() {
      @Override public void onReceivedError(WebView v, WebResourceRequest r, WebResourceError e) {
        if (r.isForMainFrame()) { failed = true; offline(); }
      }
      @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
        return !r.getUrl().toString().startsWith("__SITE_URL__");
      }
    });
    web.setWebChromeClient(new WebChromeClient());
    web.addJavascriptInterface(new Waiter(), "UnoWaiter");
    web.loadUrl(URL);
    WatchService.start(this, null);
  }

  void offline() {
    web.loadDataWithBaseURL(null, "<html><body style='margin:0;background:#0A0908;color:#E8B04B;font-family:sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;text-align:center'><div><div style='font-size:24px;margin-bottom:10px'>UNO Ofitsiant</div><div style='color:#bbb;font-size:16px'>Internetga ulanish kutilmoqda…</div></div></body></html>", "text/html", "utf-8", null);
    h.postDelayed(new Runnable() { public void run() { if (failed) { failed = false; web.loadUrl(URL); } } }, 8000);
  }

  void askBattery() {
    if (askedBattery || Build.VERSION.SDK_INT < 23) return;
    askedBattery = true;
    try {
      PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
      if (!pm.isIgnoringBatteryOptimizations(getPackageName())) {
        Intent i = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
        i.setData(Uri.parse("package:" + getPackageName()));
        startActivity(i);
      }
    } catch (Exception e) { }
  }

  @Override protected void onResume() {
    super.onResume(); web.onResume();
    WatchService.start(this, "poll");
    h.postDelayed(new Runnable() { public void run() { askBattery(); } }, 1500);
  }
  @Override protected void onPause() { web.onPause(); super.onPause(); }
  @Override public void onBackPressed() { if (web.canGoBack()) web.goBack(); else moveTaskToBack(true); }
}
