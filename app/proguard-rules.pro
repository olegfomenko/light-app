# --- JNA (used by the UniFFI-generated bindings to load liblightcore.so) ---
# JNA resolves methods and struct fields reflectively; R8 must not rename or
# strip anything it touches.
-keep class com.sun.jna.** { *; }
-keep class * extends com.sun.jna.Structure { *; }
-keep class * implements com.sun.jna.Library { *; }
-keep class * implements com.sun.jna.Callback { *; }
-dontwarn java.awt.**

# --- UniFFI-generated bindings for the Rust core ---
# The generated code registers JNA callbacks and looks up types by name.
-keep class app.light.wallet.core.** { *; }

# Kotlin coroutines debug metadata (safe to drop warnings)
-dontwarn kotlinx.coroutines.debug.**
