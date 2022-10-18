import Flutter
import UIKit
import UserNotifications

public class SwiftFlutterIOSVoIPKitPlugin: NSObject {

    let _headlessRunner: FlutterEngine;
    static let backgroundIsolateRun: Bool = false;
    static var registerPlugins: FlutterPluginRegistrantCallback? = nil;
    let _registrar: FlutterPluginRegistrar;
    let _bgMethodChannel: FlutterMethodChannel;

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: FlutterPluginChannelType.method.name,  binaryMessenger: registrar.messenger())
        let plugin = SwiftFlutterIOSVoIPKitPlugin(messenger: registrar.messenger(), registrar: registrar)
        registrar.addMethodCallDelegate(plugin, channel: channel)
    }

    public static func setPluginRegistrantCallback(callback: @escaping FlutterPluginRegistrantCallback) {
        registerPlugins = callback;
    }

    init(messenger: FlutterBinaryMessenger, registrar: FlutterPluginRegistrar) {

        _registrar = registrar;
        _headlessRunner = FlutterEngine(name: "FIVKIsolate", project: nil, allowHeadlessExecution: true);
        _bgMethodChannel = FlutterMethodChannel(name: "\(FlutterPluginChannelType.method.name)/background", binaryMessenger: _headlessRunner);

        self.voIPCenter = VoIPCenter(
            bgMethodChannel: _bgMethodChannel,
            eventChannel: FlutterEventChannel(name: FlutterPluginChannelType.event.name, binaryMessenger: messenger)
            )
        super.init()
        self.notificationCenter.delegate = self
    }

    // MARK: - VoIPCenter

    private let voIPCenter: VoIPCenter

    // MARK: - Local Notification

    private let notificationCenter = UNUserNotificationCenter.current()
    private let options: UNAuthorizationOptions = [.alert]

    // MARK: - method channel

    private func getVoIPToken(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(self.voIPCenter.token)
    }

    private func getIncomingCallerName(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(self.voIPCenter.callKitCenter.incomingCallerName)
    }

    private func startCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let uuid = args["uuid"] as? String,
            let targetName = args["targetName"] as? String else {
                result(FlutterError(code: "InvalidArguments startCall", message: nil, details: nil))
                return
        }
        self.voIPCenter.callKitCenter.startCall(uuidString: uuid, targetName: targetName)
        result(nil)
    }

    private func endCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        self.voIPCenter.callKitCenter.endCall()
        result(nil)
    }

    private func acceptIncomingCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let callerState = args["callerState"] as? String else {
                result(FlutterError(code: "InvalidArguments acceptIncomingCall", message: nil, details: nil))
                return
        }
        self.voIPCenter.callKitCenter.acceptIncomingCall(alreadyEndCallerReason: callerState == "calling" ? nil : .failed)
        result(nil)
    }

    private func unansweredIncomingCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let skipLocalNotification = args["skipLocalNotification"] as? Bool else {
                result(FlutterError(code: "InvalidArguments unansweredIncomingCall", message: nil, details: nil))
                return
        }

        self.voIPCenter.callKitCenter.unansweredIncomingCall()

        if (skipLocalNotification) {
            result(nil)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = args["missedCallTitle"] as? String ?? "Missed Call"
        content.body = args["missedCallBody"] as? String ?? "There was a call"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2,
                                                        repeats: false)
        let request = UNNotificationRequest(identifier: "unansweredIncomingCall",
                                            content: content,
                                            trigger: trigger)
        self.notificationCenter.add(request) { (error) in
            if let error = error {
                print("❌ unansweredIncomingCall local notification error: \(error.localizedDescription)")
            }
        }

        result(nil)
    }

    private func callConnected(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        self.voIPCenter.callKitCenter.callConnected()
        result(nil)
    }

    public func requestAuthLocalNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        notificationCenter.requestAuthorization(options: options) { granted, error in
            if let error = error {
                result(["granted": granted, "error": error.localizedDescription])
            } else {
                result(["granted": granted])
            }
        }
    }
    
    public func getLocalNotificationsSettings(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        notificationCenter.getNotificationSettings { settings in
            result(settings.toMap())
        }
    }
    
    private func testIncomingCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
            let uuid = args["uuid"] as? String,
            let callerId = args["callerId"] as? String,
            let callerName = args["callerName"] as? String else {
                result(FlutterError(code: "InvalidArguments testIncomingCall", message: nil, details: nil))
                return
        }

        self.voIPCenter.callKitCenter.incomingCall(uuidString: uuid,
                                                   callerId: callerId,
                                                   callerName: callerName) { (error) in
            if let error = error {
                print("❌ testIncomingCall error: \(error.localizedDescription)")
                result(FlutterError(code: "testIncomingCall",
                                    message: error.localizedDescription,
                                    details: nil))
                return
            }
            result(nil)
        }
    }

    private func setOnBackgroundIncomingPush(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let defaults = UserDefaults.standard
        let callbackHandle = call.arguments as? Int;
        print("[VoIP kit]: Got the callback handle : \(callbackHandle!)")

        defaults.setInteger(callbackHandle, forKey: "voip_on_background_incoming_push_handle")
        result(true)
    }

    private func startBackgroundService(handle: Int) {
        let info: FlutterCallbackInformation = FlutterCallbackInformation(lookupCallbackInformation: handle)
        if(info == nil) {
            // throw exception
            print("[VoIP kit]: Cannot get the callback information");
        } else {

            let entrypoint: String = info.callbackName
            let uri: String = info.callbackLibraryPath
            _headlessRunner.run(withEntrypoint: entrypoint, libraryURI: uri )

            assert(registerPlugins != nil, "[VoIP kit]: registerPlugins callback not set.");

            if(!backgroundIsolateRun) {
                registerPlugins(_headlessRunner)
            }

            _registrar.addMethodCallDelegate(self, channel: _bgMethodChannel)
            backgroundIsolateRun = true;

        }
        
    }
}

extension SwiftFlutterIOSVoIPKitPlugin: UNUserNotificationCenterDelegate {

    // MARK: - Local Notification

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // notify when foreground
        completionHandler([.alert])
    }
}

extension SwiftFlutterIOSVoIPKitPlugin: FlutterPlugin {

    private enum MethodChannel: String {
        case getVoIPToken
        case getIncomingCallerName
        case startCall
        case endCall
        case acceptIncomingCall
        case unansweredIncomingCall
        case callConnected
        case requestAuthLocalNotification
        case getLocalNotificationsSettings
        case testIncomingCall
        case setOnBackgroundIncomingPush
        case initializeService
    }

    // MARK: - FlutterPlugin（method channel）

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let method = MethodChannel(rawValue: call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        switch method {
            case .getVoIPToken:
                self.getVoIPToken(call, result: result)
            case .getIncomingCallerName:
                self.getIncomingCallerName(call, result: result)
            case .startCall:
                self.startCall(call, result: result)
            case .endCall:
                self.endCall(call, result: result)
            case .acceptIncomingCall:
                self.acceptIncomingCall(call, result: result)
            case .unansweredIncomingCall:
                self.unansweredIncomingCall(call, result: result)
            case .callConnected:
                self.callConnected(call, result: result)
            case .requestAuthLocalNotification:
                self.requestAuthLocalNotification(call, result: result)
            case .getLocalNotificationsSettings:
                self.getLocalNotificationsSettings(call, result: result)
            case .testIncomingCall:
                self.testIncomingCall(call, result: result)
            case .setOnBackgroundIncomingPush:
                self.setOnBackgroundIncomingPush(call, result: result)
            case .initializeService:
                self.startBackgroundService(handle: call.arguments)
                result(true)
        }
    }
}
