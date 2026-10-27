#!/bin/sh
# Builds out/reboot-linux-lsposed/reboot-linux-lsposed.apk without Gradle.
# Tools: an AOSP-style tree (EVO default ~/evo12) for the JDK, android.jar,
# aapt2, d8, zipalign and apksigner. The signing key is generated once in
# out/reboot-linux-lsposed/key.p12 (keep it: updates need the same key).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(cd "$here/../../.." && pwd)
evo=${EVO:-$HOME/evo12}
jdk=$evo/prebuilts/jdk/jdk21/linux-x86/bin
tools=$evo/prebuilts/sdk/tools/linux/bin
jar=$evo/prebuilts/sdk/36/public/android.jar
o=$top/out/reboot-linux-lsposed
rm -rf "$o/build"; mkdir -p "$o/build/classes" "$o/build/stubs" "$o/build/dex"

# Xposed API stubs: compile against them, never package them
"$jdk/javac" -nowarn -source 17 -target 17 -cp "$jar" -d "$o/build/stubs" \
	$(find "$here/stubs" -name '*.java')
"$jdk/javac" -source 17 -target 17 -cp "$jar:$o/build/stubs" -d "$o/build/classes" \
	$(find "$here/src" -name '*.java')
"$jdk/java" -cp "$tools/../lib/d8.jar" com.android.tools.r8.D8 --release \
	--min-api 34 --lib "$jar" --classpath "$o/build/stubs" --output "$o/build/dex" \
	$(find "$o/build/classes" -name '*.class')

"$tools/aapt2" compile --dir "$here/res" -o "$o/build/res.zip"
"$tools/aapt2" link -I "$jar" --manifest "$here/AndroidManifest.xml" \
	-A "$here/assets" -o "$o/build/unaligned.apk" "$o/build/res.zip"
(cd "$o/build/dex" && zip -q -X "$o/build/unaligned.apk" classes.dex)
"$tools/zipalign" -f -p 4 "$o/build/unaligned.apk" "$o/build/aligned.apk"

if [ ! -e "$o/key.p12" ]; then
	"$jdk/keytool" -genkeypair -keystore "$o/key.p12" -storetype PKCS12 \
		-storepass nx809j -keypass nx809j -alias key -keyalg RSA -keysize 3072 \
		-validity 10000 -dname "CN=nx809j reboot-linux" >/dev/null 2>&1
fi
"$jdk/java" -jar "$tools/../lib/apksigner.jar" sign --ks "$o/key.p12" \
	--ks-pass pass:nx809j --out "$o/reboot-linux-lsposed.apk" "$o/build/aligned.apk"
ls -l "$o/reboot-linux-lsposed.apk"
