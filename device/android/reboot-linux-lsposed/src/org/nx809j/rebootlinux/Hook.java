package org.nx809j.rebootlinux;

import android.content.Context;
import android.content.Intent;
import android.graphics.drawable.Drawable;
import android.util.Log;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;

import de.robv.android.xposed.IXposedHookLoadPackage;
import de.robv.android.xposed.XC_MethodHook;
import de.robv.android.xposed.XposedBridge;
import de.robv.android.xposed.XposedHelpers;
import de.robv.android.xposed.callbacks.XC_LoadPackage;

/**
 * Adds "Linux" after "Bootloader" in the advanced restart menu of
 * GlobalActionsDialogLite (EvolutionX / LineageOS SystemUI). The new item
 * is built like the Bootloader item (whose class R8 may have merged with
 * the other reboot-reason items, e.g. RestartDownloadAction(dialog, icon,
 * label, classId) in SystemUIGoogle) and gets its own label. Pressing it
 * goes through the dialog's own rebootAction() with a private reason, so a
 * secure keyguard is dismissed first as for the other items; at the end of
 * that path, GlobalActionsComponent.reboot() sends RebootReceiver a
 * broadcast for that reason instead of rebooting.
 */
public class Hook implements IXposedHookLoadPackage {
    private static final String TAG = "nx809j-reboot-linux: ";
    private static final String LOG = "nx809j-reboot-linux";
    private static final String DIALOG =
            "com.android.systemui.globalactions.GlobalActionsDialogLite";
    private static final String COMPONENT =
            "com.android.systemui.globalactions.GlobalActionsComponent";
    private static final String BOOTLOADER_LABEL = "global_action_restart_bootloader";
    private static final String REASON = "nx809j-linux";
    private static volatile Context sContext;
    private static final Map<Object, Boolean> LINUX_ITEMS =
            Collections.synchronizedMap(new WeakHashMap<>());
    private static final Map<Class<?>, Boolean> HOOKED = new WeakHashMap<>();

    @Override
    public void handleLoadPackage(XC_LoadPackage.LoadPackageParam lpparam) {
        if (!"com.android.systemui".equals(lpparam.packageName)) {
            return;
        }
        // SystemUI's process also loads code without the dialog class.
        try {
            lpparam.classLoader.loadClass(DIALOG);
        } catch (ClassNotFoundException e) {
            return;
        }
        XposedHelpers.findAndHookMethod(DIALOG, lpparam.classLoader, "createActionItems",
                new XC_MethodHook() {
            @Override
            protected void afterHookedMethod(MethodHookParam param) {
                try {
                    addLinuxItem(param.thisObject);
                } catch (Throwable t) {
                    XposedBridge.log(TAG + "adding the menu item failed");
                    XposedBridge.log(t);
                }
            }
        });
        XposedHelpers.findAndHookMethod(COMPONENT, lpparam.classLoader, "reboot",
                boolean.class, String.class, new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                if (REASON.equals(param.args[1]) && sContext != null) {
                    Log.i(LOG, "reboot(" + REASON + "): asking RebootReceiver");
                    param.setResult(null);
                    sContext.sendBroadcast(new Intent(RebootReceiver.ACTION)
                            .setPackage(RebootReceiver.PACKAGE)
                            .addFlags(Intent.FLAG_INCLUDE_STOPPED_PACKAGES
                                    | Intent.FLAG_RECEIVER_FOREGROUND));
                }
            }
        });
    }

    private static void addLinuxItem(Object dialog) throws Exception {
        Context context = (Context) XposedHelpers.getObjectField(dialog, "mContext");
        @SuppressWarnings("unchecked")
        List<Object> items = (List<Object>) XposedHelpers.getObjectField(dialog, "mRestartItems");
        int at = -1;
        for (int i = 0; i < items.size(); i++) {
            Object item = items.get(i);
            int label = messageResId(item);
            if (label != 0 && BOOTLOADER_LABEL.equals(
                    context.getResources().getResourceEntryName(label))) {
                at = i;
            }
        }
        if (at < 0) {
            return; // no advanced restart menu, or no Bootloader item
        }
        Object bootloader = items.get(at);
        Object linux = copyOf(dialog, bootloader);
        XposedHelpers.setObjectField(linux, "mMessage", "Linux");
        Drawable tux = tuxIcon(context);
        if (tux != null) {
            XposedHelpers.setObjectField(linux, "mIcon", tux);
        }
        LINUX_ITEMS.put(linux, Boolean.TRUE);
        hookOnPress(linux.getClass());
        items.add(at + 1, linux);
        Log.i(LOG, "added Linux after item " + at + " (" + linux.getClass().getSimpleName() + ")");
    }

    /** Tux from this module's resources (res/drawable/ic_tux.xml). */
    private static Drawable tuxIcon(Context context) {
        try {
            Context module = context.createPackageContext(RebootReceiver.PACKAGE, 0);
            int id = module.getResources().getIdentifier("ic_tux", "drawable",
                    RebootReceiver.PACKAGE);
            return id == 0 ? null : module.getDrawable(id);
        } catch (Throwable t) {
            Log.w(LOG, "no Tux icon", t);
            return null;
        }
    }

    private static int messageResId(Object item) {
        try {
            return XposedHelpers.getIntField(item, "mMessageResId");
        } catch (Throwable t) {
            return 0;
        }
    }

    /** A new action of the same class, built with the original's arguments. */
    private static Object copyOf(Object dialog, Object item) throws Exception {
        Class<?> c = item.getClass();
        int icon = XposedHelpers.getIntField(item, "mIconResId");
        int label = XposedHelpers.getIntField(item, "mMessageResId");
        for (Constructor<?> k : c.getDeclaredConstructors()) {
            Class<?>[] p = k.getParameterTypes();
            k.setAccessible(true);
            if (p.length == 1) {
                return k.newInstance(dialog);
            }
            if (p.length == 4 && p[1] == int.class && p[2] == int.class && p[3] == int.class) {
                // R8-merged class: (dialog, icon, label, classId)
                return k.newInstance(dialog, icon, label,
                        XposedHelpers.getIntField(item, "$r8$classId"));
            }
        }
        throw new NoSuchMethodException("no usable constructor in " + c);
    }

    private static synchronized void hookOnPress(Class<?> c) {
        if (HOOKED.containsKey(c)) {
            return;
        }
        Method onPress = null;
        for (Class<?> k = c; k != null && onPress == null; k = k.getSuperclass()) {
            try {
                onPress = k.getDeclaredMethod("onPress");
            } catch (NoSuchMethodException e) {
                // look further up
            }
        }
        if (onPress == null) {
            throw new IllegalStateException("no onPress in " + c);
        }
        XposedBridge.hookMethod(onPress, new XC_MethodHook() {
            @Override
            protected void beforeHookedMethod(MethodHookParam param) {
                if (!LINUX_ITEMS.containsKey(param.thisObject)) {
                    return;
                }
                // Never fall through to the Bootloader action (Xposed runs the
                // original method when a callback throws).
                param.setResult(null);
                Log.i(LOG, "Linux pressed");
                try {
                    requestReboot(XposedHelpers.getSurroundingThis(param.thisObject));
                } catch (Throwable t) {
                    XposedBridge.log(TAG + "reboot request failed");
                    XposedBridge.log(t);
                }
            }
        });
        HOOKED.put(c, Boolean.TRUE);
    }

    private static void requestReboot(Object dialog) {
        sContext = (Context) XposedHelpers.getObjectField(dialog, "mContext");
        // rebootAction(String reason, boolean safeMode) in SystemUIGoogle (R8
        // reordered it), rebootAction(boolean safeMode, String reason) in AOSP
        try {
            XposedHelpers.callMethod(dialog, "rebootAction", REASON, false);
        } catch (NoSuchMethodError e) {
            XposedHelpers.callMethod(dialog, "rebootAction", false, REASON);
        }
    }
}
