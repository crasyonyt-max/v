package com.novasystems.bruh;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Bundle;
import android.widget.ImageView;

import java.io.InputStream;

public class MainActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        ImageView view = new ImageView(this);
        view.setBackgroundColor(0xFF000000);
        view.setScaleType(ImageView.ScaleType.FIT_CENTER);
        try {
            InputStream in = getAssets().open("bruh.png");
            Bitmap bitmap = BitmapFactory.decodeStream(in);
            in.close();
            view.setImageBitmap(bitmap);
        } catch (Exception e) {
            // nothing else to show
        }
        setContentView(view);
    }
}
