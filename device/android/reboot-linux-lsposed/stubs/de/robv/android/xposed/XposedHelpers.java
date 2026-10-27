package de.robv.android.xposed;

/** Compile-time stub of the Xposed API (the framework provides the real one). */
public final class XposedHelpers {
    public static Class<?> findClass(String className, ClassLoader classLoader) { throw new UnsupportedOperationException(); }
    public static XC_MethodHook.Unhook findAndHookMethod(String className, ClassLoader classLoader, String methodName, Object... parameterTypesAndCallback) { throw new UnsupportedOperationException(); }
    public static Object newInstance(Class<?> clazz, Object... args) { throw new UnsupportedOperationException(); }
    public static Object getObjectField(Object obj, String fieldName) { throw new UnsupportedOperationException(); }
    public static void setObjectField(Object obj, String fieldName, Object value) { throw new UnsupportedOperationException(); }
    public static int getIntField(Object obj, String fieldName) { throw new UnsupportedOperationException(); }
    public static Object getSurroundingThis(Object obj) { throw new UnsupportedOperationException(); }
    public static Object callMethod(Object obj, String methodName, Object... args) { throw new UnsupportedOperationException(); }
}
