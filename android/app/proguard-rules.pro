# The page calls StemikAndroid.setDarkTheme() through the JS bridge.
-keepclassmembers class studio.stemik.app.MainActivity$Bridge {
    @android.webkit.JavascriptInterface <methods>;
}
