package uz.uno.airways;

import android.app.AlarmManager;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import java.util.Map;

/* booking reminder: "your table is booked today at 19:00" two hours before, like the iPhone app.
   Reminders are kept in preferences so they come back after the phone restarts. */
public class RemindReceiver extends BroadcastReceiver {
  static final String ACT = "uz.uno.airways.REMIND";
  static final String CH = "uno_remind";

  static SharedPreferences prefs(Context c) { return c.getSharedPreferences("uno_remind", Context.MODE_PRIVATE); }

  static PendingIntent pi(Context c, String id) {
    Intent i = new Intent(c, RemindReceiver.class).setAction(ACT).putExtra("id", id);
    return PendingIntent.getBroadcast(c, id.hashCode(), i, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  static void schedule(Context c, String id, long at, String title, String body) {
    prefs(c).edit().putString(id, at + "\n" + title + "\n" + body).apply();
    alarm(c, id, at);
  }

  static void alarm(Context c, String id, long at) {
    AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
    if (am == null) return;
    try { am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi(c, id)); } catch (Exception e) { try { am.set(AlarmManager.RTC_WAKEUP, at, pi(c, id)); } catch (Exception x) { } }
  }

  static void cancel(Context c, String id) {
    prefs(c).edit().remove(id).apply();
    AlarmManager am = (AlarmManager) c.getSystemService(Context.ALARM_SERVICE);
    try { if (am != null) am.cancel(pi(c, id)); } catch (Exception e) { }
  }

  @Override public void onReceive(Context c, Intent i) {
    String a = i.getAction();
    if (ACT.equals(a)) { String id = i.getStringExtra("id"); if (id != null) show(c, id); return; }
    if (Intent.ACTION_BOOT_COMPLETED.equals(a) || Intent.ACTION_MY_PACKAGE_REPLACED.equals(a)) {
      long now = System.currentTimeMillis();
      for (Map.Entry<String, ?> e : prefs(c).getAll().entrySet()) {
        String[] p = String.valueOf(e.getValue()).split("\n", 3);
        long at; try { at = Long.parseLong(p[0]); } catch (Exception x) { continue; }
        if (at > now) alarm(c, e.getKey(), at); else prefs(c).edit().remove(e.getKey()).apply();
      }
    }
  }

  static void show(Context c, String id) {
    String v = prefs(c).getString(id, null);
    prefs(c).edit().remove(id).apply();
    if (v == null) return;
    String[] p = v.split("\n", 3);
    String title = p.length > 1 ? p[1] : "UNO Airways", body = p.length > 2 ? p[2] : "";
    NotificationManager nm = (NotificationManager) c.getSystemService(Context.NOTIFICATION_SERVICE);
    if (nm == null) return;
    Notification.Builder b;
    if (Build.VERSION.SDK_INT >= 26) {
      NotificationChannel ch = new NotificationChannel(CH, "Bron eslatmalari", NotificationManager.IMPORTANCE_HIGH);
      nm.createNotificationChannel(ch);
      b = new Notification.Builder(c, CH);
    } else {
      b = new Notification.Builder(c).setPriority(Notification.PRIORITY_HIGH).setDefaults(Notification.DEFAULT_ALL);
    }
    Intent open = new Intent(c, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
    PendingIntent tap = PendingIntent.getActivity(c, 7, open, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    b.setSmallIcon(android.R.drawable.ic_popup_reminder).setContentTitle(title).setContentText(body)
     .setStyle(new Notification.BigTextStyle().bigText(body)).setAutoCancel(true).setContentIntent(tap);
    try { nm.notify(id.hashCode(), b.build()); } catch (Exception e) { }
  }
}
