# --- Razorpay SDK ---
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**

# --- Ignore/keep ProGuard annotation types referenced by some SDKs ---
-keep class proguard.annotation.** { *; }
-keep @interface proguard.annotation.Keep
-keep @interface proguard.annotation.KeepClassMembers
-dontwarn proguard.annotation.**

# Some SDKs also use AndroidX Keep annotations
-keep class androidx.annotation.Keep
-keep @interface androidx.annotation.Keep

# Keep annotation metadata (safe and useful)
-keepattributes *Annotation*
