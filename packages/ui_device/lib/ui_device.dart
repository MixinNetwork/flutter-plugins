import 'dart:ffi';

import 'src/ui_device_bindings_generated.dart' as binding;

export 'src/ui_device_bindings_generated.dart'
    show UIUserInterfaceIdiom, UIDeviceBatteryState, UIDeviceOrientation;

final binding.UIDeviceBindings _bindings = binding.UIDeviceBindings(_dylib);

final DynamicLibrary _dylib = DynamicLibrary.process();

binding.UIDevice get current => binding.UIDevice.getCurrentDevice(_bindings)!;
