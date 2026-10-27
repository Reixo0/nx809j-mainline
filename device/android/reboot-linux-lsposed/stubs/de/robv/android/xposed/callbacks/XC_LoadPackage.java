package de.robv.android.xposed.callbacks;

/** Compile-time stub of the Xposed API (the framework provides the real one). */
public abstract class XC_LoadPackage {
    public static final class LoadPackageParam {
        public String packageName;
        public String processName;
        public ClassLoader classLoader;
        public boolean isFirstApplication;
    }
}
