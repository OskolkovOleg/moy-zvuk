# ML Kit discovers these classes by manifest name and invokes their no-arg
# constructors through reflection. R8 full mode otherwise removes constructors.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    public <init>();
}
