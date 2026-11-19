package uz.uno.ofitsiant;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.MediaPlayer;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.VibrationEffect;
import android.os.Vibrator;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.TimeZone;
import org.json.JSONArray;
import org.json.JSONObject;

/* Runs in the background, checks the restaurant's calls every 3 s and rings like an alarm clock
   until every new call has been accepted. */
public class WatchService extends Service {
  static final String SB_URL = "__SB_URL__";
  static final String SB_KEY = "__SB_KEY__";
  static final String CH_WATCH = "watch", CH_CALLS = "calls_alarm";
  static final int ID_WATCH = 1, ID_CALL = 2;

  volatile boolean running = true;
  Thread worker;
  MediaPlayer player;
  Vibrator vib;
  PowerManager.WakeLock wake;
  int savedVolume = -1;
  final Set<Long> muted = new HashSet<Long>();
  Set<Long> lastIds = new HashSet<Long>();

  public static void start(Context c, String action) {
    Intent i = new Intent(c, WatchService.class);
    if (action != null) i.setAction(action);
    try {
      if (Build.VERSION.SDK_INT >= 26) c.startForegroundService(i); else c.startService(i);
    } catch (Exception e) { }
  }

  @Override public IBinder onBind(Intent i) { return null; }

  @Override public void onCreate() {
    super.onCreate();
    channels();
    startForeground(ID_WATCH, build(CH_WATCH, "UNO Ofitsiant ishlamoqda", "Chaqiruvlar kutilmoqda", false));
    vib = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
    try {
      PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
      wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "uno:watch");
      wake.acquire();
    } catch (Exception e) { }
    worker = new Thread(new Runnable() { public void run() { loop(); } });
    worker.start();
  }

  @Override public int onStartCommand(Intent intent, int flags, int startId) {
    String a = intent != null ? intent.getAction() : null;
    if ("mute".equals(a)) { synchronized (muted) { muted.addAll(lastIds); } stopAlarm(); }
    if (("poll".equals(a) || "mute".equals(a)) && worker != null) worker.interrupt();
    return START_STICKY;
  }

  @Override public void onDestroy() {
    running = false;
    if (worker != null) worker.interrupt();
    stopAlarm();
    try { if (wake != null && wake.isHeld()) wake.release(); } catch (Exception e) { }
    super.onDestroy();
  }

  void loop() {
    while (running) {
      try { handle(new JSONArray(fetch())); } catch (Exception e) { }
      try { Thread.sleep(3000); } catch (InterruptedException e) { }
    }
  }

  String fetch() throws Exception {
    SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US);
    f.setTimeZone(TimeZone.getTimeZone("UTC"));
    String since = f.format(new Date(System.currentTimeMillis() - 45L * 60 * 1000));
    URL u = new URL(SB_URL + "/rest/v1/uno_calls?select=id,table_no,kind,total&status=eq.new&created_at=gt." + since + "&order=created_at.asc");
    HttpURLConnection c = (HttpURLConnection) u.openConnection();
    c.setConnectTimeout(8000); c.setReadTimeout(8000);
    c.setRequestProperty("apikey", SB_KEY);
    c.setRequestProperty("Accept", "application/json");
    try {
      if (c.getResponseCode() != 200) throw new Exception("http " + c.getResponseCode());
      BufferedReader r = new BufferedReader(new InputStreamReader(c.getInputStream(), "UTF-8"));
      StringBuilder sb = new StringBuilder(); String line;
      while ((line = r.readLine()) != null) sb.append(line);
      r.close();
      return sb.toString();
    } finally { c.disconnect(); }
  }

  static String money(double v) {
    String s = String.valueOf(Math.round(v)), o = "";
    for (int i = 0; i < s.length(); i++) { if (i > 0 && (s.length() - i) % 3 == 0) o += " "; o += s.charAt(i); }
    return o + " so'm";
  }

  void handle(JSONArray a) throws Exception {
    Set<Long> ids = new HashSet<Long>();
    StringBuilder text = new StringBuilder();
    String title = null;
    boolean fresh = false;
    for (int i = 0; i < a.length(); i++) {
      JSONObject o = a.getJSONObject(i);
      long id = o.getLong("id"); ids.add(id);
      synchronized (muted) { if (!muted.contains(id)) fresh = true; }
      String line = o.optString("table_no") + "-stol: " + ("bill".equals(o.optString("kind")) ? "hisob so'rayapti" : "ofitsiant chaqiryapti");
      if ("bill".equals(o.optString("kind")) && !o.isNull("total")) line += " (" + money(o.optDouble("total", 0)) + ")";
      if (title == null) title = line;
      if (text.length() > 0) text.append("\n");
      text.append(line);
    }
    synchronized (muted) { muted.retainAll(ids); }
    lastIds = ids;
    NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
    if (ids.isEmpty()) { stopAlarm(); nm.cancel(ID_CALL); return; }
    String head = ids.size() == 1 ? title : ids.size() + " ta chaqiruv";
    nm.notify(ID_CALL, build(CH_CALLS, head, text.toString(), true));
    if (fresh) startAlarm(); else stopAlarm();
  }

  void startAlarm() {
    if (player != null) return;
    try {
      AudioManager am = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
      savedVolume = am.getStreamVolume(AudioManager.STREAM_ALARM);
      am.setStreamVolume(AudioManager.STREAM_ALARM, am.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0);
    } catch (Exception e) { savedVolume = -1; }
    try {
      Uri u = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
      if (u == null) u = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
      if (u == null) u = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
      MediaPlayer p = new MediaPlayer();
      p.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build());
      p.setDataSource(this, u);
      p.setLooping(true);
      p.prepare();
      p.start();
      player = p;
    } catch (Exception e) { player = null; }
    try {
      long[] pattern = new long[]{ 0, 900, 500 };
      if (Build.VERSION.SDK_INT >= 26) vib.vibrate(VibrationEffect.createWaveform(pattern, 0));
      else vib.vibrate(pattern, 0);
    } catch (Exception e) { }
  }

  void stopAlarm() {
    try { if (player != null) { player.stop(); player.release(); } } catch (Exception e) { }
    player = null;
    try { if (vib != null) vib.cancel(); } catch (Exception e) { }
    if (savedVolume >= 0) {
      try { ((AudioManager) getSystemService(Context.AUDIO_SERVICE)).setStreamVolume(AudioManager.STREAM_ALARM, savedVolume, 0); } catch (Exception e) { }
      savedVolume = -1;
    }
  }

  void channels() {
    if (Build.VERSION.SDK_INT < 26) return;
    NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
    NotificationChannel w = new NotificationChannel(CH_WATCH, "Fon xizmati", NotificationManager.IMPORTANCE_MIN);
    w.setShowBadge(false);
    nm.createNotificationChannel(w);
    NotificationChannel c = new NotificationChannel(CH_CALLS, "Mijoz chaqiruvlari", NotificationManager.IMPORTANCE_HIGH);
    c.setSound(null, null);
    c.enableVibration(false);
    c.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
    c.setBypassDnd(true);
    nm.createNotificationChannel(c);
  }

  @SuppressWarnings("deprecation")
  Notification build(String ch, String title, String text, boolean alert) {
    Intent open = new Intent(this, MainActivity.class);
    open.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
    int fl = PendingIntent.FLAG_UPDATE_CURRENT | (Build.VERSION.SDK_INT >= 23 ? PendingIntent.FLAG_IMMUTABLE : 0);
    PendingIntent pi = PendingIntent.getActivity(this, alert ? 2 : 1, open, fl);
    Notification.Builder b = Build.VERSION.SDK_INT >= 26 ? new Notification.Builder(this, ch) : new Notification.Builder(this);
    b.setSmallIcon(android.R.drawable.ic_popup_reminder)
     .setContentTitle(title)
     .setContentText(text)
     .setStyle(new Notification.BigTextStyle().bigText(text))
     .setContentIntent(pi)
     .setOngoing(true)
     .setShowWhen(alert);
    if (alert) {
      b.setCategory(Notification.CATEGORY_ALARM)
       .setPriority(Notification.PRIORITY_MAX)
       .setVisibility(Notification.VISIBILITY_PUBLIC)
       .setFullScreenIntent(pi, true);
      Intent mute = new Intent(this, WatchService.class).setAction("mute");
      PendingIntent mp = PendingIntent.getService(this, 3, mute, fl);
      b.addAction(new Notification.Action.Builder(null, "Ovozni o'chirish", mp).build());
    } else {
      b.setPriority(Notification.PRIORITY_MIN);
    }
    return b.build();
  }
}
