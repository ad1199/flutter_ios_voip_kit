import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ios_voip_kit/call_state_type.dart';
import 'package:flutter_ios_voip_kit/channel_type.dart';

import 'notifications_settings.dart';

final MethodChannel _channel = MethodChannel(ChannelType.method.name);

typedef IncomingPush = Future<void> Function(String, Map?);
typedef IncomingAction = void Function(String uuid, String callerId);
typedef OnUpdatePushToken = void Function(String token);
typedef OnAudioSessionStateChanged = void Function(bool active);

Future<void> fivkCallDispatcher() async {
  MethodChannel _backgroundChannel =
      MethodChannel(ChannelType.backgroundMethod.name);
  WidgetsFlutterBinding.ensureInitialized();

  _backgroundChannel.setMethodCallHandler((call) async {
    print("[fivk]: setMethodCallHandler invoked in dispatcher");
    final List<dynamic> args = call.arguments;
    final Function? callback = PluginUtilities.getCallbackFromHandle(
        CallbackHandle.fromRawHandle(args[0]));
    assert(callback != null);

    String event = args[1];
    Map? data;
    if (args.length > 2) data = args[2];
    await callback!(event, data);
  });

  _backgroundChannel.invokeMethod("dispatcherInitialized");
}

class FlutterIOSVoIPKit {
  static FlutterIOSVoIPKit get instance => _getInstance();
  static FlutterIOSVoIPKit? _instance;
  static FlutterIOSVoIPKit _getInstance() {
    if (_instance == null) {
      _instance = FlutterIOSVoIPKit._internal();
    }

    return _instance!;
  }

  factory FlutterIOSVoIPKit() => _getInstance();

  FlutterIOSVoIPKit._internal() {
    if (Platform.isAndroid) {
      return;
    }

    _eventSubscription = EventChannel(ChannelType.event.name)
        .receiveBroadcastStream()
        .listen(_eventListener, onError: _errorListener);
  }

  /// [onDidReceiveIncomingPush] is not called when the app is not running, because app is not yet running when didReceiveIncomingPushWith is called.
  IncomingPush? onDidReceiveIncomingPush;

  OnUpdatePushToken? onDidUpdatePushToken;

  StreamSubscription<dynamic>? _eventSubscription;

  Future<void> dispose() async {
    print('🎈 dispose');

    await _eventSubscription?.cancel();
  }

  Future<void> initialize() async {
    final CallbackHandle? callback =
        PluginUtilities.getCallbackHandle(fivkCallDispatcher);
    print('[fivk]: initializing through channel');
    await _channel
        .invokeMethod('initialize', <dynamic>[callback!.toRawHandle()]);
  }

  /// method channel

  Future<void> setBackgroundCallback(
      Future<void> Function(String, Map?) backgroundCallback) async {
    final CallbackHandle? callback =
        PluginUtilities.getCallbackHandle(backgroundCallback);
    print('[fivk]: set on background callback');
    await _channel.invokeMethod(
        'setBackgroundCallback', <dynamic>[callback!.toRawHandle()]);
  }

  Future<String?> getVoIPToken() async {
    print('🎈 getVoIPToken');

    if (Platform.isAndroid) {
      return null;
    }

    return await _channel.invokeMethod('getVoIPToken');
  }

  Future<String?> getIncomingCallerName() async {
    print('🎈 getIncomingCallerName');

    if (Platform.isAndroid) {
      return null;
    }

    return await _channel.invokeMethod('getIncomingCallerName');
  }

  Future<String?> startCall({
    required String uuid,
    required String targetName,
  }) async {
    print('🎈 startCall');

    if (Platform.isAndroid) {
      return null;
    }

    return await _channel.invokeMethod('startCall', {
      'uuid': uuid,
      'targetName': targetName,
    });
  }

  Future<void> endCall() async {
    print('🎈 endCall');

    if (Platform.isAndroid) {
      return null;
    }

    return await _channel.invokeMethod('endCall');
  }

  Future<void> acceptIncomingCall({
    required CallStateType callerState,
  }) async {
    print('🎈 acceptIncomingCall');

    if (Platform.isAndroid) {
      return null;
    }

    return await _channel.invokeMethod('acceptIncomingCall', {
      'callerState': callerState.value,
    });
  }

  Future<void> unansweredIncomingCall({
    bool skipLocalNotification = false,
    required String missedCallTitle,
    required String missedCallBody,
  }) async {
    print(
      '🎈 unansweredIncomingCall $skipLocalNotification, $missedCallTitle, $missedCallBody',
    );

    if (Platform.isAndroid) {
      return;
    }

    return await _channel.invokeMethod('unansweredIncomingCall', {
      'skipLocalNotification': skipLocalNotification,
      'missedCallTitle': missedCallTitle,
      'missedCallBody': missedCallBody,
    });
  }

  Future<void> callConnected() async {
    print('🎈 callConnected');

    if (Platform.isAndroid) {
      return;
    }

    return await _channel.invokeMethod('callConnected');
  }

  Future<bool> requestAuthLocalNotification() async {
    print('🎈 requestAuthLocalNotification');

    if (Platform.isAndroid) {
      throw PlatformException(code: 'android-not-supported');
    }

    final result = await _channel.invokeMethod('requestAuthLocalNotification');
    return result['granted'];
  }

  Future<NotificationSettings> getLocalNotificationsSettings() async {
    print('🎈 getLocalNotificationsSettings');

    if (Platform.isAndroid) {
      throw PlatformException(code: 'android-not-supported');
    }

    final result = await _channel.invokeMethod('getLocalNotificationsSettings');
    return NotificationSettings.createFromMap(result);
  }

  Future<void> testIncomingCall({
    required String uuid,
    required String callerId,
    required String callerName,
  }) async {
    print('🎈 testIncomingCall: $uuid, $callerId, $callerName');

    final isRelease = const bool.fromEnvironment('dart.vm.product');
    if (Platform.isAndroid || isRelease) {
      return null;
    }

    return await _channel.invokeMethod('testIncomingCall', {
      'uuid': uuid,
      'callerId': callerId,
      'callerName': callerName,
    });
  }

  Future<void> setOnBackgroundIncomingPush(
      Function(Map<String, dynamic>) callback) async {
    int? callbackHandler =
        PluginUtilities.getCallbackHandle(callback)?.toRawHandle();

    if (callbackHandler == null) {
      print('[VoIP kit]: ERROR: Failed to get the callback id');
    } else {
      print(
          '[VoIP kit] : Got the call handler : ' + callbackHandler.toString());
    }

    var args = callbackHandler;
    try {
      dynamic success =
          await _channel.invokeMethod('setOnBackgroundIncomingPush', args);
      print('[VoIP kit]: Background incoming push set. ' + success.toString());
    } catch (e) {
      String message = e.toString();
      print('[VoIp kit]: setOnBackgroundIncomingPush $message');
    }
  }

  /// event channel

  void _eventListener(dynamic event) {
    print('🎈 _eventListener');

    final Map<dynamic, dynamic> map = event;
    switch (map['event']) {
      case 'onDidReceiveIncomingPush':
        print('🎈 onDidReceiveIncomingPush($onDidReceiveIncomingPush): $map');

        if (onDidReceiveIncomingPush == null) {
          return;
        }

        Map payload = map['payload'] as Map;
        String e = payload['event'];
        Map? data;
        if (payload['data'] != null) data = payload['data'] as Map;
        onDidReceiveIncomingPush!(e, data);
        break;

      case 'onDidUpdatePushToken':
        final String token = map['token'];
        print('🎈 onDidUpdatePushToken $token');

        if (onDidUpdatePushToken == null) {
          return;
        }

        onDidUpdatePushToken!(token);
        break;
    }
  }

  void _errorListener(Object obj) {
    print('🎈 onError: $obj');
  }
}
