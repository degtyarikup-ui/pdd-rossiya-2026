"""Real Android Parcel regression; opt in with PDD_ANDROID_DEVICE_TESTS=1.

Builds an isolated, temporary instrumentation APK. Does not launch/change the
PDD app or send reports. Requires one adb-connected Android device and JDK/SDK.
"""
import os
from pathlib import Path
import secrets
import struct
import shutil
import subprocess
import tempfile
import unittest
from zipfile import ZipFile

from environment import ROOT, android_sdk

PACKAGE = 'ru.pdd.reportreceivercheck'
HARNESS = r"""
package ru.pdd.reportreceivercheck;
import android.app.Instrumentation;
import android.os.BadParcelableException;
import android.os.Bundle;
import android.os.Parcel;
import android.os.ResultReceiver;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import ru.pdd.pdd_app.GodotReportReceiver;

public class Probe extends Instrumentation {
    public void onCreate(Bundle args) { super.onCreate(args); start(); }
    @SuppressWarnings("deprecation")
    private static ResultReceiver decode(ResultReceiver receiver) {
        Bundle bundle = new Bundle();
        bundle.putParcelable("reply", receiver);
        Parcel parcel = Parcel.obtain();
        try {
            parcel.writeBundle(bundle);
            parcel.setDataPosition(0);
            Bundle received = parcel.readBundle(null);
            received.setClassLoader(null); // ResultReceiver's framework IPC path.
            return received.getParcelable("reply");
        } finally { parcel.recycle(); }
    }
    public void onStart() {
        Bundle result = new Bundle();
        try {
            boolean reproduced = false;
            try { decode(new ResultReceiver(null) {}); }
            catch (BadParcelableException expected) { reproduced = true; }
            if (!reproduced) throw new AssertionError("Original anonymous receiver must fail with boot loader");
            for (int code : new int[]{0, 1}) {
                AtomicInteger actual = new AtomicInteger(-1);
                CountDownLatch delivered = new CountDownLatch(1);
                ResultReceiver local = new ResultReceiver(null) {
                    protected void onReceiveResult(int value, Bundle data) {
                        if ("probe".equals(data.getString("marker"))) actual.set(value);
                        delivered.countDown();
                    }
                };
                ResultReceiver remote = decode(GodotReportReceiver.remote(local));
                if (remote.getClass() != ResultReceiver.class) throw new AssertionError("Must use framework class");
                // Also flatten the Intent/outer-receiver path, then the nested reply path.
                remote = decode(GodotReportReceiver.remote(remote));
                Bundle data = new Bundle();
                data.putString("marker", "probe");
                remote.send(code, data);
                if (!delivered.await(3, TimeUnit.SECONDS) || actual.get() != code)
                    throw new AssertionError("Missing IPC callback: " + code);
            }
            result.putString("result", "PASS: original crash reproduced; wrapped success/failure callbacks delivered");
            finish(-1, result);
        } catch (Throwable error) {
            result.putString("result", "FAIL: " + error);
            finish(0, result);
        }
    }
}
"""


@unittest.skipUnless(os.environ.get('PDD_ANDROID_DEVICE_TESTS') == '1', 'opt-in Android device check')
class ReportReceiverDeviceTests(unittest.TestCase):
    def test_boot_loader_can_decode_both_remote_receivers_and_deliver_results(self):
        sdk = android_sdk()
        version = lambda p: tuple(int(x) for x in p.name.split('.') if x.isdigit())
        build_tools = max((sdk / 'build-tools').iterdir(), key=version)
        platform = max((sdk / 'platforms').glob('android-*'), key=lambda p: int(p.name.split('-')[1]))
        android_jar = platform / 'android.jar'
        jdk = Path('/opt/homebrew/opt/openjdk@17/bin')
        tool = lambda name: str(jdk / name) if (jdk / name).exists() else shutil.which(name)
        env = dict(os.environ, PDD_PROBE_KEY_PASSWORD=secrets.token_hex(16))
        env['JAVA_HOME'] = str(jdk.parent) if jdk.exists() else env.get('JAVA_HOME', '')
        run = lambda args: subprocess.run(list(map(str, args)), env=env, check=True,
                                          capture_output=True, text=True, timeout=60)
        scratch = ROOT / 'scratch'
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='report-receiver-', dir=scratch) as folder:
            tmp = Path(folder)
            (tmp / 'Probe.java').write_text(HARNESS)
            (tmp / 'AndroidManifest.xml').write_text(f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="{PACKAGE}">
<uses-sdk android:minSdkVersion="24" android:targetSdkVersion="35"/>
<application android:label="Report IPC Check"/>
<instrumentation android:name=".Probe" android:targetPackage="{PACKAGE}"/>
</manifest>''')
            classes = tmp / 'classes'
            classes.mkdir()
            run([tool('javac'), '--release', '8', '-cp', android_jar, '-d', classes,
                 ROOT / 'android/app/src/main/java/ru/pdd/pdd_app/GodotReportReceiver.java', tmp / 'Probe.java'])
            dex = tmp / 'dex'
            dex.mkdir()
            run([build_tools / 'd8', '--min-api', '24', '--lib', android_jar,
                 '--output', dex, *classes.rglob('*.class')])
            apk = tmp / 'probe.apk'
            run([build_tools / 'aapt2', 'link', '-I', android_jar, '--manifest', tmp / 'AndroidManifest.xml', '-o', apk])
            with ZipFile(apk, 'a') as zipped:
                zipped.write(dex / 'classes.dex', 'classes.dex')
            key = tmp / 'key.p12'
            run([tool('keytool'), '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
                 '-keyalg', 'RSA', '-keysize', '2048', '-dname', 'CN=ReportReceiverCheck',
                 '-validity', '1', '-noprompt', '-storepass:env', 'PDD_PROBE_KEY_PASSWORD'])
            run([build_tools / 'apksigner', 'sign', '--ks', key,
                 '--ks-pass', 'env:PDD_PROBE_KEY_PASSWORD', apk])
            run(['adb', 'install', '-t', apk])
            try:
                output = run(['adb', 'shell', 'am', 'instrument', '-w', f'{PACKAGE}/.Probe']).stdout
                self.assertIn('PASS: original crash reproduced', output, output)
                print(output.strip())
            finally:
                run(['adb', 'uninstall', PACKAGE])


@unittest.skipUnless(os.environ.get('PDD_VERIFY_DEV_APK') == '1', 'opt-in assembled APK check')
class ReportReceiverApkTests(unittest.TestCase):
    def test_receiver_is_in_the_actual_application_dex(self):
        apk = ROOT / 'build/app/outputs/flutter-apk/app-ru-release.apk'
        with ZipFile(apk) as zipped:
            dex = [zipped.read(name) for name in zipped.namelist()
                   if name.startswith('classes') and name.endswith('.dex')]
        def defines_receiver(data):
            strings = struct.unpack_from('<I', data, 60)[0]
            types = struct.unpack_from('<I', data, 68)[0]
            count, classes = struct.unpack_from('<II', data, 96)
            for i in range(count):
                class_index = struct.unpack_from('<I', data, classes + i * 32)[0]
                string_index = struct.unpack_from('<I', data, types + class_index * 4)[0]
                offset = struct.unpack_from('<I', data, strings + string_index * 4)[0]
                while data[offset] & 0x80: offset += 1
                offset += 1
                if data[offset:data.index(b'\0', offset)] == b'Lru/pdd/pdd_app/GodotReportReceiver;':
                    return True
            return False
        self.assertTrue(any(defines_receiver(data) for data in dex),
                        'GodotReportReceiver must be compiled into the app, not only visible to Kotlin')


if __name__ == '__main__':
    unittest.main()
