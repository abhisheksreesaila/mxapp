// The one Java file in mojo-ui. It belongs to the framework, never to an app: Android only
// calls Java objects back (listeners, adapters, frame callbacks), so this Activity forwards
// every callback to Mojo (libmojoui.so, mojoui/hosts/android.mojo), which builds the views.
package dev.mojoui;

import android.app.Activity;
import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.*;
import android.widget.*;

public final class MojoActivity extends Activity implements View.OnClickListener, View.OnTouchListener,
        CompoundButton.OnCheckedChangeListener, RadioGroup.OnCheckedChangeListener, SeekBar.OnSeekBarChangeListener,
        AdapterView.OnItemSelectedListener, AdapterView.OnItemClickListener, TextView.OnEditorActionListener,
        Choreographer.FrameCallback {
    static { System.loadLibrary("mojoui"); }

    public boolean quiet;  // true while Mojo changes the views itself: their callbacks aren't the user
    private long host;

    static native long create(MojoActivity activity);
    static native void event(long host, int view, int kind, String text, int number);
    static native void touch(long host, int view, int action, float x, float y, float x2, float y2, int pointers);
    static native void frame(long host, long nanos);
    static native String row(long host, int view, int index);
    static native void destroy(long host);

    @Override protected void onCreate(Bundle state) { super.onCreate(state); host = create(this); }
    @Override protected void onDestroy() { destroy(host); host = 0; super.onDestroy(); }

    // kind: 0 tap, 1 on/off, 2 choice, 3 slider, 4 row tap, 5 Return, 6 typing
    public void onClick(View v) { if (!quiet) event(host, v.getId(), 0, null, 0); }
    public void onCheckedChanged(CompoundButton v, boolean on) { if (!quiet) event(host, v.getId(), 1, null, on ? 1 : 0); }
    public void onCheckedChanged(RadioGroup g, int id) {
        if (!quiet && id != View.NO_ID) event(host, g.getId(), 2, null, g.indexOfChild(g.findViewById(id)));
    }
    public void onProgressChanged(SeekBar s, int value, boolean user) { if (!quiet && user) event(host, s.getId(), 3, null, value); }
    public void onStartTrackingTouch(SeekBar s) {}
    public void onStopTrackingTouch(SeekBar s) {}
    public void onItemSelected(AdapterView<?> a, View v, int at, long id) { if (!quiet) event(host, a.getId(), 2, null, at); }
    public void onNothingSelected(AdapterView<?> a) {}
    public void onItemClick(AdapterView<?> a, View v, int at, long id) { if (!quiet) event(host, a.getId(), 4, null, at); }
    public boolean onEditorAction(TextView v, int action, KeyEvent e) {
        if (!quiet && (e == null || e.getAction() == KeyEvent.ACTION_DOWN)) event(host, v.getId(), 5, v.getText().toString(), 0);
        return true;
    }
    public boolean onTouch(View v, MotionEvent e) {  // a canvas owns its gestures (no scrolling parent steals them)
        if (e.getActionMasked() == MotionEvent.ACTION_DOWN) v.getParent().requestDisallowInterceptTouchEvent(true);
        boolean two = e.getPointerCount() > 1;
        touch(host, v.getId(), e.getActionMasked(), e.getX(0), e.getY(0), two ? e.getX(1) : 0, two ? e.getY(1) : 0, e.getPointerCount());
        return true;
    }
    public void doFrame(long nanos) { frame(host, nanos); }

    public TextWatcher typing(final int view) {
        return new TextWatcher() {
            public void beforeTextChanged(CharSequence s, int a, int b, int c) {}
            public void onTextChanged(CharSequence s, int a, int b, int c) {}
            public void afterTextChanged(Editable s) { if (!quiet) event(host, view, 6, s.toString(), 0); }
        };
    }

    public BaseAdapter rows(final int view, final int count) {  // a long list asks Mojo only for rows on screen
        return new BaseAdapter() {
            public int getCount() { return count; }
            public Object getItem(int i) { return null; }
            public long getItemId(int i) { return i; }
            public View getView(int i, View old, ViewGroup parent) {
                TextView t = old instanceof TextView ? (TextView) old : new TextView(MojoActivity.this);
                int pad = (int) (14 * getResources().getDisplayMetrics().density);
                t.setPadding(pad, pad, pad, pad);
                t.setText(row(host, view, i));
                return t;
            }
        };
    }
}
