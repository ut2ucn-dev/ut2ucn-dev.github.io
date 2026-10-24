package studio.stemik.app;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.MediaStore;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.io.File;

/**
 * The whole app: a full-screen WebView over the Stemik site on GitHub Pages.
 * The site itself is the source of truth, so every deploy reaches the app
 * without a new APK.
 */
public class MainActivity extends Activity {

    private static final String START_URL = "https://ut2ucn-dev.github.io/";
    private static final String APP_HOST = "ut2ucn-dev.github.io";
    private static final int REQUEST_FILE = 1;

    // Keeps the system bars in the same colour as the page's own theme toggle.
    private static final String THEME_HOOK_JS =
            "(function(){if(window.__stemikThemeHook)return;window.__stemikThemeHook=1;"
            + "var r=document.documentElement;"
            + "function s(){StemikAndroid.setDarkTheme(r.classList.contains('theme-dark'));}"
            + "new MutationObserver(s).observe(r,{attributes:true,attributeFilter:['class']});s();})();";

    private FrameLayout root;
    private WebView webView;
    private ProgressBar progress;
    private View offlineView;
    private boolean mainFrameFailed;

    private ValueCallback<Uri[]> fileCallback;
    private File cameraFile;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        clearOldCameraFiles();

        root = new FrameLayout(this);
        setContentView(root);
        setupEdgeToEdge();
        applyBarColors(isSystemDark());

        createWebView();
        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(100);
        progress.setProgressTintList(android.content.res.ColorStateList.valueOf(getColor(R.color.brand)));
        root.addView(progress, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(3), Gravity.TOP));
        offlineView = createOfflineView();
        offlineView.setVisibility(View.GONE);
        root.addView(offlineView, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        if (savedInstanceState == null || webView.restoreState(savedInstanceState) == null) {
            webView.loadUrl(START_URL);
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void createWebView() {
        webView = new WebView(this);
        webView.setBackgroundColor(getColor(R.color.screen));
        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        s.setUserAgentString(s.getUserAgentString() + " StemikApp/" + BuildConfig.VERSION_NAME);

        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);

        webView.addJavascriptInterface(new Bridge(), "StemikAndroid");
        webView.setWebViewClient(new AppWebViewClient());
        webView.setWebChromeClient(new AppChromeClient());
        webView.setDownloadListener((url, userAgent, contentDisposition, mimeType, length) -> openExternal(Uri.parse(url)));
        root.addView(webView, 0, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    }

    private View createOfflineView() {
        boolean dark = isSystemDark();
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER);
        box.setPadding(dp(32), dp(32), dp(32), dp(32));
        box.setBackgroundColor(getColor(R.color.screen));
        box.setClickable(true);

        TextView title = new TextView(this);
        title.setText(R.string.offline_title);
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 20);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(getColor(dark ? R.color.ink_dark : R.color.ink));
        title.setGravity(Gravity.CENTER);
        box.addView(title);

        TextView text = new TextView(this);
        text.setText(R.string.offline_text);
        text.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        text.setTextColor(getColor(dark ? R.color.ink_dark : R.color.ink));
        text.setAlpha(0.7f);
        text.setGravity(Gravity.CENTER);
        text.setPadding(0, dp(8), 0, dp(24));
        box.addView(text);

        Button retry = new Button(this);
        retry.setText(R.string.retry);
        retry.setTextColor(Color.WHITE);
        retry.setBackgroundTintList(android.content.res.ColorStateList.valueOf(getColor(R.color.brand)));
        retry.setOnClickListener(v -> {
            mainFrameFailed = false;
            offlineView.setVisibility(View.GONE);
            String url = webView.getUrl();
            if (url == null || url.startsWith("about:")) webView.loadUrl(START_URL);
            else webView.reload();
        });
        box.addView(retry, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        return box;
    }

    // Android 15 forces edge-to-edge for targetSdk 35, so from Android 11 on we
    // opt in everywhere and pad the content by the system bars and keyboard.
    private void setupEdgeToEdge() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return;
        getWindow().setDecorFitsSystemWindows(false);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
            v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            return WindowInsets.CONSUMED;
        });
    }

    private void applyBarColors(boolean dark) {
        int color = getColor(dark ? R.color.paper_dark : R.color.paper);
        root.setBackgroundColor(color);
        Window window = getWindow();
        window.setStatusBarColor(color);
        window.setNavigationBarColor(color);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            WindowInsetsController c = window.getInsetsController();
            if (c != null) {
                int light = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                        | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                c.setSystemBarsAppearance(dark ? 0 : light, light);
            }
        } else {
            int flags = window.getDecorView().getSystemUiVisibility();
            int light = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) light |= View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR;
            window.getDecorView().setSystemUiVisibility(dark ? flags & ~light : flags | light);
        }
    }

    private boolean isSystemDark() {
        return (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
    }

    private static boolean isAppUrl(Uri uri) {
        return "https".equals(uri.getScheme()) && APP_HOST.equals(uri.getHost());
    }

    private void openExternal(Uri uri) {
        Intent intent = "tel".equals(uri.getScheme())
                ? new Intent(Intent.ACTION_DIAL, uri)
                : new Intent(Intent.ACTION_VIEW, uri);
        try {
            startActivity(intent);
        } catch (ActivityNotFoundException e) {
            Toast.makeText(this, R.string.no_app, Toast.LENGTH_SHORT).show();
        }
    }

    private class Bridge {
        @JavascriptInterface
        public void setDarkTheme(boolean dark) {
            runOnUiThread(() -> applyBarColors(dark));
        }
    }

    private class AppWebViewClient extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if (isAppUrl(uri)) return false;
            openExternal(uri);
            return true;
        }

        @Override
        public void onPageFinished(WebView view, String url) {
            if (!mainFrameFailed) offlineView.setVisibility(View.GONE);
            view.evaluateJavascript(THEME_HOOK_JS, null);
            CookieManager.getInstance().flush();
        }

        @Override
        public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
            if (request.isForMainFrame()) {
                mainFrameFailed = true;
                offlineView.setVisibility(View.VISIBLE);
            }
        }

        @Override
        public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
            // The renderer crashed or was killed for memory: start over cleanly.
            root.removeView(webView);
            webView.destroy();
            createWebView();
            webView.loadUrl(START_URL);
            return true;
        }
    }

    private class AppChromeClient extends WebChromeClient {
        @Override
        public void onProgressChanged(WebView view, int newProgress) {
            progress.setProgress(newProgress);
            progress.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
        }

        @Override
        public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
            if (fileCallback != null) fileCallback.onReceiveValue(null);
            fileCallback = callback;

            Intent pick = params.createIntent();
            pick.addCategory(Intent.CATEGORY_OPENABLE);
            if (params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE) {
                pick.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
            }
            Intent chooser = Intent.createChooser(pick, getString(R.string.choose_photo));
            Intent camera = acceptsImages(params) ? cameraIntent() : null;
            if (camera != null) chooser.putExtra(Intent.EXTRA_INITIAL_INTENTS, new Intent[]{camera});

            try {
                startActivityForResult(chooser, REQUEST_FILE);
                return true;
            } catch (ActivityNotFoundException e) {
                fileCallback = null;
                cameraFile = null;
                return false;
            }
        }
    }

    private static boolean acceptsImages(WebChromeClient.FileChooserParams params) {
        String[] types = params.getAcceptTypes();
        if (types == null || types.length == 0) return true;
        for (String t : types) {
            if (t.isEmpty() || t.startsWith("image/")) return true;
        }
        return false;
    }

    private Intent cameraIntent() {
        Intent intent = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
        if (intent.resolveActivity(getPackageManager()) == null) return null;
        cameraFile = new File(CameraFileProvider.dir(this), "photo-" + System.currentTimeMillis() + ".jpg");
        Uri uri = CameraFileProvider.uriFor(this, cameraFile);
        intent.putExtra(MediaStore.EXTRA_OUTPUT, uri);
        intent.setClipData(ClipData.newRawUri("", uri));
        intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
        return intent;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_FILE) {
            super.onActivityResult(requestCode, resultCode, data);
            return;
        }
        Uri[] result = null;
        if (resultCode == RESULT_OK) {
            if (data != null && data.getClipData() != null && data.getClipData().getItemCount() > 0
                    && data.getData() == null) {
                ClipData clip = data.getClipData();
                result = new Uri[clip.getItemCount()];
                for (int i = 0; i < clip.getItemCount(); i++) result[i] = clip.getItemAt(i).getUri();
            } else if (data != null && data.getData() != null) {
                result = new Uri[]{data.getData()};
            } else if (cameraFile != null && cameraFile.length() > 0) {
                result = new Uri[]{CameraFileProvider.uriFor(this, cameraFile)};
            }
        }
        if (fileCallback != null) fileCallback.onReceiveValue(result);
        fileCallback = null;
        cameraFile = null;
    }

    private void clearOldCameraFiles() {
        File[] files = CameraFileProvider.dir(this).listFiles();
        if (files == null) return;
        long cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000;
        for (File f : files) {
            //noinspection ResultOfMethodCallIgnored
            if (f.lastModified() < cutoff) f.delete();
        }
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (webView.canGoBack()) webView.goBack();
        else super.onBackPressed();
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        webView.saveState(outState);
    }

    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
    }

    @Override
    protected void onDestroy() {
        webView.destroy();
        super.onDestroy();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
