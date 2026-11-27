package uz.uno.airways;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.job.JobInfo;
import android.app.job.JobParameters;
import android.app.job.JobScheduler;
import android.app.job.JobService;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.text.SimpleDateFormat;
import java.util.Locale;
import java.util.TimeZone;
import org.json.JSONArray;
import org.json.JSONObject;

/* News the admin marked "send to phones" appear as a notification. No Firebase: the system wakes this job
   about every 30 minutes (when there is internet), it reads the public news list once and goes back to sleep. */
public class NewsJob extends JobService {
  static final int ID = 1001;
  static final String CH = "uno_news";
  static final String URL_NEWS = "https://eaxavnixuqgwashplnhz.supabase.co/rest/v1/uno_docs?select=path,data&path=like.news/*";
  static final String KEY = "sb_publishable_gILXDU_L8vepyEbsF87Tcg_hYyMpril";

  static void schedule(Context c) {
    try {
      JobScheduler js = (JobScheduler) c.getSystemService(Context.JOB_SCHEDULER_SERVICE);
      if (js == null) return;
      for (JobInfo j : js.getAllPendingJobs()) if (j.getId() == ID) return;
      JobInfo info = new JobInfo.Builder(ID, new ComponentName(c, NewsJob.class))
        .setPeriodic(30L * 60 * 1000)
        .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
        .setPersisted(true)
        .build();
      js.schedule(info);
    } catch (Exception e) { }
  }

  static void cancel(Context c) {
    try { JobScheduler js = (JobScheduler) c.getSystemService(Context.JOB_SCHEDULER_SERVICE); if (js != null) js.cancel(ID); } catch (Exception e) { }
  }

  @Override public boolean onStartJob(final JobParameters params) {
    new Thread(new Runnable() { public void run() {
      try { check(NewsJob.this); } catch (Exception e) { }
      jobFinished(params, false);
    } }).start();
    return true;
  }

  @Override public boolean onStopJob(JobParameters params) { return true; }

  static long parseAt(String s) {
    if (s == null) return 0;
    String[] fmts = { "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'" };
    for (String f : fmts) {
      try { SimpleDateFormat d = new SimpleDateFormat(f, Locale.US); d.setTimeZone(TimeZone.getTimeZone("UTC")); return d.parse(s).getTime(); } catch (Exception e) { }
    }
    return 0;
  }

  static void check(Context c) throws Exception {
    SharedPreferences p = c.getSharedPreferences("uno_news", Context.MODE_PRIVATE);
    long seen = p.getLong("seen", 0);
    HttpURLConnection h = (HttpURLConnection) new URL(URL_NEWS).openConnection();
    h.setConnectTimeout(15000); h.setReadTimeout(15000);
    h.setRequestProperty("apikey", KEY); h.setRequestProperty("Authorization", "Bearer " + KEY);
    if (h.getResponseCode() != 200) { h.disconnect(); return; }
    InputStream in = h.getInputStream(); ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] buf = new byte[8192]; int n;
    while ((n = in.read(buf)) > 0) { out.write(buf, 0, n); if (out.size() > 2000000) break; }
    in.close(); h.disconnect();
    JSONArray rows = new JSONArray(out.toString("UTF-8"));
    long now = System.currentTimeMillis(), newest = seen; JSONObject pick = null; long pickAt = 0;
    for (int i = 0; i < rows.length(); i++) {
      JSONObject d = rows.getJSONObject(i).optJSONObject("data"); if (d == null) continue;
      if (!d.optBoolean("push", false) || d.optBoolean("hidden", false)) continue;
      long at = parseAt(d.optString("at", null)); if (at <= 0 || at > now + 3600000) continue;
      if (at > newest) newest = at;
      if (seen > 0 && at > seen && at > pickAt) { pick = d; pickAt = at; }
    }
    /* the very first check only remembers where we are: no flood of old news after installing */
    if (seen == 0) { p.edit().putLong("seen", Math.max(newest, now)).apply(); return; }
    if (newest > seen) p.edit().putLong("seen", newest).apply();
    if (pick == null) return;
    String lang = Locale.getDefault().getLanguage();
    String title = pick.optString("title_" + lang, ""); if (title.isEmpty() || "uz".equals(lang)) title = pick.optString("title", "");
    String text = pick.optString("text_" + lang, ""); if (text.isEmpty() || "uz".equals(lang)) text = pick.optString("text", "");
    if (title.isEmpty()) title = "UNO Airways";
    show(c, title, text);
  }

  static void show(Context c, String title, String text) {
    NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    if (nm == null) return;
    Notification.Builder b;
    if (Build.VERSION.SDK_INT >= 26) {
      nm.createNotificationChannel(new NotificationChannel(CH, "Yangiliklar va aksiyalar", NotificationManager.IMPORTANCE_DEFAULT));
      b = new Notification.Builder(c, CH);
    } else b = new Notification.Builder(c);
    Intent open = new Intent(c, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP).putExtra("tab", "profile");
    PendingIntent tap = PendingIntent.getActivity(c, 8, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    b.setSmallIcon(android.R.drawable.ic_popup_reminder).setContentTitle(title).setContentText(text)
     .setStyle(new Notification.BigTextStyle().bigText(text)).setAutoCancel(true).setContentIntent(tap);
    try { nm.notify(5000 + (int) (System.currentTimeMillis() % 1000), b.build()); } catch (Exception e) { }
  }
}
