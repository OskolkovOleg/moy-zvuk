package com.ryanheise.audioservice;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Receives only explicit, immutable notification PendingIntents. */
public class CustomActionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent != null && AudioService.instance != null) {
            AudioService.instance.handleCustomNotificationAction(intent.getAction(), intent.getExtras());
        }
    }
}
