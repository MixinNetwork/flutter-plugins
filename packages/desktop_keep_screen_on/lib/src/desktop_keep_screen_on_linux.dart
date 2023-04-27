import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';

import 'desktop_keep_screen_on_platform_interface.dart';
import 'util/get_application_id.dart';

enum DbusApi {
  // https://lira.no-ip.org:8443/doc/gnome-session/dbus/gnome-session.html#org.gnome.SessionManager.Inhibit
  gnome(
    serviceName: 'org.gnome.SessionManager',
    interfaceName: 'org.gnome.SessionManager',
    objectPath: '/org/gnome/SessionManager',
  ),
  freedesktopPower(
    serviceName: 'org.freedesktop.PowerManagement',
    interfaceName: 'org.freedesktop.PowerManagement.Inhibit',
    objectPath: '/org/freedesktop/PowerManagement/Inhibit',
  ),
  freedesktopScreenSaver(
    serviceName: 'org.freedesktop.ScreenSaver',
    interfaceName: 'org.freedesktop.ScreenSaver',
    objectPath: '/org/freedesktop/ScreenSaver',
  );

  const DbusApi({
    required this.serviceName,
    required this.interfaceName,
    required this.objectPath,
  });

  final String serviceName;
  final String interfaceName;
  final String objectPath;
}

extension _DbusApiExtension on DbusApi {
  String get unInhibitMethodName {
    switch (this) {
      case DbusApi.gnome:
        return 'Uninhibit';
      case DbusApi.freedesktopPower:
      case DbusApi.freedesktopScreenSaver:
        return 'UnInhibit';
    }
  }
}

enum GnomeAPIInhibitFlags {
  logout(1),
  switchUser(2),
  suspendSession(4),
  markSessionIdle(8);

  const GnomeAPIInhibitFlags(this.value);

  final int value;
}

class InhibitCookie {
  final DbusApi api;
  final int cookie;

  InhibitCookie(this.api, this.cookie);
}

/// https://source.chromium.org/chromium/chromium/src/+/main:services/device/wake_lock/power_save_blocker/power_save_blocker_linux.cc
class DesktopKeepScreenOnLinux extends DesktopKeepScreenOnPlatform {
  static void registerWith() {
    DesktopKeepScreenOnPlatform.instance = DesktopKeepScreenOnLinux();
  }

  final DBusClient dbus = DBusClient.session();

  final List<InhibitCookie> cookies = [];

  final _lock = Lock();

  @override
  Future<void> setPreventSleep(bool preventSleep) =>
      _lock.synchronized(() async {
        if (preventSleep) {
          if (cookies.isNotEmpty) {
            return;
          }
          if (!await _inhibit(DbusApi.gnome)) {
            await _inhibit(DbusApi.freedesktopPower);
            await _inhibit(DbusApi.freedesktopScreenSaver);
          }
        } else {
          for (final cookie in cookies) {
            await _unInhibit(cookie);
          }
        }
      });

  final String _description = 'Prevent the screen from turning off';

  String? _applicationId;

  String _getId() {
    _applicationId ??= getApplicationId();
    return _applicationId ??= 'flutter.keep_screen_on';
  }

  Future<bool> _inhibit(DbusApi api) async {
    if (!await dbus.nameHasOwner(api.serviceName)) {
      debugPrint('warning: inhibit $api service not found');
      return false;
    }

    final values = <DBusValue>[];

    switch (api) {
      case DbusApi.gnome:
        // The arguments of the method are:
        //     app_id:        The application identifier
        //     toplevel_xid:  The toplevel X window identifier
        //     reason:        The reason for the inhibit
        //     flags:         Flags that spefify what should be inhibited
        values.addAll([
          DBusString(_getId()),
          const DBusUint32(0),
          DBusString(_description),
          DBusUint32(
            GnomeAPIInhibitFlags.markSessionIdle.value |
                GnomeAPIInhibitFlags.suspendSession.value,
          ),
        ]);

        break;
      case DbusApi.freedesktopPower:
      case DbusApi.freedesktopScreenSaver:
        // The arguments of the method are:
        //     app_id:        The application identifier
        //     reason:        The reason for the inhibit
        values.addAll([
          DBusString(_getId()),
          DBusString(_description),
        ]);
        break;
    }

    try {
      final response = await dbus.callMethod(
        path: DBusObjectPath(api.objectPath),
        name: 'Inhibit',
        destination: api.serviceName,
        interface: api.interfaceName,
        values: values,
      );
      if (response.values.isEmpty) {
        return false;
      }
      final cookie = response.values[0] as DBusUint32;
      debugPrint('cookie: $api ${cookie.value} ${_getId()}');
      cookies.add(InhibitCookie(api, cookie.value));
    } on DBusMethodResponseException catch (error, stacktrace) {
      debugPrint('error: $error, stacktrace: $stacktrace');
      return false;
    } catch (error, stacktrace) {
      debugPrint('error: $error, stacktrace: $stacktrace');
      return false;
    }

    return true;
  }

  Future<void> _unInhibit(InhibitCookie cookie) async {
    final api = cookie.api;

    assert(await dbus.nameHasOwner(api.serviceName));

    try {
      await dbus.callMethod(
        path: DBusObjectPath(api.objectPath),
        name: api.unInhibitMethodName,
        destination: api.serviceName,
        interface: api.interfaceName,
        values: [
          DBusUint32(cookie.cookie),
        ],
      );
    } on DBusMethodResponseException catch (error, stacktrace) {
      debugPrint('error: $error, stacktrace: $stacktrace');
    }
  }
}
