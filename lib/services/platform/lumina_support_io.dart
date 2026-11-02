import 'dart:ffi';
import 'dart:io';

bool get luminaSupported =>
    (Platform.isAndroid &&
        [Abi.androidArm64, Abi.androidX64].contains(Abi.current())) ||
    (Platform.isWindows && Abi.current() == Abi.windowsX64);
