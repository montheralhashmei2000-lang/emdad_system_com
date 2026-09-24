package com.imdad.supply;

import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.appcompat.app.AppCompatActivity;
import com.getcapacitor.Bridge;
import com.getcapacitor.PluginHandle;
import com.getcapacitor.CapacitorWebView;
import androidx.activity.OnBackPressedCallback;
import android.app.AlertDialog;

public class MainActivity extends AppCompatActivity {
  @Override
  public void onCreate(Bundle savedInstanceState){
    super.onCreate(savedInstanceState);
    setContentView(R.layout.activity_main);
    getOnBackPressedDispatcher().addCallback(this,new OnBackPressedCallback(true){
      @Override public void handleOnBackPressed(){
        AlertDialog d=new AlertDialog.Builder(MainActivity.this)
          .setTitle("تأكيد الخروج")
          .setMessage("هل تريد الخروج من نظام الإمداد والتموين؟")
          .setPositiveButton("نعم، خروج",(di,w)->finishAffinity())
          .setNegativeButton("إلغاء",(di,w)->di.dismiss())
          .setCancelable(true)
          .create();
        d.show();
      }
    });
  }
}
