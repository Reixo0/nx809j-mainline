package org.nx809j.rebootlinux;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.Toast;

import java.io.BufferedReader;
import java.io.InputStreamReader;

/**
 * Arms the Canoe boot-once record for Linux with the Reboot to Linux
 * KernelSU module's action.sh (root), then reboots normally.
 */
public class RebootReceiver extends BroadcastReceiver {
    static final String PACKAGE = "org.nx809j.rebootlinux";
    static final String ACTION = PACKAGE + ".REBOOT_LINUX";
    private static final String TAG = "nx809j-reboot-linux";
    private static final String COMMAND =
            "sh /data/adb/modules/nx809j_reboot_linux/action.sh arm && svc power reboot";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!ACTION.equals(intent.getAction())) {
            return;
        }
        Log.i(TAG, "arming boot-once and rebooting");
        final PendingResult pending = goAsync();
        final Context app = context.getApplicationContext();
        new Thread(() -> {
            String error = null;
            try {
                Process p = new ProcessBuilder("su", "-c", COMMAND)
                        .redirectErrorStream(true).start();
                StringBuilder out = new StringBuilder();
                try (BufferedReader r = new BufferedReader(
                        new InputStreamReader(p.getInputStream()))) {
                    String line;
                    while ((line = r.readLine()) != null) {
                        out.append(line).append('\n');
                    }
                }
                if (p.waitFor() != 0) {
                    error = out.toString().trim();
                }
            } catch (Exception e) {
                error = e.toString();
            }
            if (error != null) {
                Log.e(TAG, "reboot to Linux failed: " + error);
                final String msg = "Reboot to Linux failed (root for this app?): " + error;
                new Handler(Looper.getMainLooper()).post(
                        () -> Toast.makeText(app, msg, Toast.LENGTH_LONG).show());
            }
            pending.finish();
        }).start();
    }
}
