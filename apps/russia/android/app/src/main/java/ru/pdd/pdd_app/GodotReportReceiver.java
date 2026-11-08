package ru.pdd.pdd_app;

import android.os.Parcel;
import android.os.ResultReceiver;

/** Flatten anonymous receivers before framework-created IPC Bundles read them with the boot loader. */
public final class GodotReportReceiver {
    private GodotReportReceiver() {}

    public static ResultReceiver remote(ResultReceiver receiver) {
        Parcel parcel = Parcel.obtain();
        try {
            receiver.writeToParcel(parcel, 0);
            parcel.setDataPosition(0);
            return ResultReceiver.CREATOR.createFromParcel(parcel);
        } finally {
            parcel.recycle();
        }
    }
}
