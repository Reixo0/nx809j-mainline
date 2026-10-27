package de.robv.android.xposed;

import java.lang.reflect.Member;

/** Compile-time stub of the Xposed API (the framework provides the real one). */
public abstract class XC_MethodHook {
    protected void beforeHookedMethod(MethodHookParam param) throws Throwable {}
    protected void afterHookedMethod(MethodHookParam param) throws Throwable {}

    public static final class MethodHookParam {
        public Member method;
        public Object thisObject;
        public Object[] args;
        public void setResult(Object result) { throw new UnsupportedOperationException(); }
    }

    public class Unhook {}
}
