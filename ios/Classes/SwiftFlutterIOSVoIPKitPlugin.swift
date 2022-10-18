import Flutter
import UIKit
import UserNotifications

public class SwiftFlutterIOSVoIPKitPlugin: NSObject {

    private static var flutterPluginRegistrantCallback: FlutterPluginRegistrantCallback?

    private var _registrar: FlutterPluginRegistrar
    public static var dispatcherInitialized: Bool = false
    private static var backgroundIsolateRun: Bool = false
    
    private var _flutterEngine: FlutterEngine

    private var _backgroundMethodChannel: FlutterMethodChannel

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: FlutterPluginChannelType.method.name,  binaryMessenger: registrar.messenger())
        let plugin = SwiftFlutterIOSVoIPKitPlugin(messenger: registrar.messenger(), registrar: registrar)
        registrar.addMethodCallDelegate(plugin, channel: channel)
        registrar.addApplicationDelegate(plugin)
    }

    init(messenger: FlutterBinaryMessenger, registrar: FlutterPluginRegistrar) {

        _flutterEngine = FlutterEngine(
            name: "FIVKIsolate",
            project: nil,
            allowHeadlessExecution: true
        )

        _backgroundMethodChannel = FlutterMethodChannel(
            name: FlutterPluginChannelType.backgroundMethod.name,
            binaryMessenger: _flutterEngine.binaryMessenger
        )

        self.voIPCenter = VoIPCenter(
            bgMethodChannel: _backgroundMethodChannel,
            eventChannel: FlutterEventChannel(name: FlutterPluginChannelType.event.name, binaryMessenger: messenger
            ))
        self._registrar = registrar;
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

    public func getCallbackHandle() -> Int64 {
        let userDefaults = UserDefaults.standard;
        let handle = userDefaults.integer(forKey: "fivk_callback_handle")
        return handle;
    }

    private func setCallbackHandle(_ handle: Int64) {
        let userDefaults = UserDefaults.standard;
        userDefaults.setInteger(handle, forKey: "fivk_callback_handle");
    }

    public func startBackgroundService(_ handle: Int64) {
        print("[fivk]: callback handle received \(handle)")

        let info: FlutterCallbackInformation? = FlutterCallbackCache.lookupCallbackInformation(handle)
        assert(info != nil, "[fivk] ERROR: failed to find the callback");

        let entrypoint: String = info!.callbackName;
        let uri: String =  info!.callbackLibraryPath;

        print("[fivk]: callback found : \(entrypoint) with uri: \(uri)");


        _flutterEngine.run(withEntrypoint: entrypoint, libraryURI: uri)
        print("[fivk]: flutter engine is running...");

        if(!SwiftFlutterIOSVoIPKitPlugin.backgroundIsolateRun) {
            SwiftFlutterIOSVoIPKitPlugin.flutterPluginRegistrantCallback?(_flutterEngine)
            print("[fivk]: flutter engine is registered...");
        }

        _backgroundMethodChannel.setMethodCallHandler{(call, result) in 
            print("[fivk]: method handler called")
            switch call.method {
                case "dispatcherInitialized":
                    result(true)
                    print("[fivk]: Displatcher initialized")
                default:
                    print("[fivk]: background method channel called")
            }
        }

        // _registrar.addMethodCallDelegate(self, channel: backgroundMethodChannel);

        SwiftFlutterIOSVoIPKitPlugin.backgroundIsolateRun = true;

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
        
        case initialize
        case dispatcherInitialized
    }

    @objc
    public static func setPluginRegistrantCallback(_ callback: @escaping FlutterPluginRegistrantCallback) {
        flutterPluginRegistrantCallback = callback
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
            case .initialize:
                print("[fivk]: initialize calling...")
                let args = call.arguments as! [Any]
                let callbackHandle = args[0] as! Int64
                self.setCallbackHandle(callbackHandle)
                self.startBackgroundService(callbackHandle)
                result(true)
            case .dispatcherInitialized:
                print("[fivk]: Dispatcher initialized")
                SwiftFlutterIOSVoIPKitPlugin.dispatcherInitialized = true
                result(true)
        }
    }
}
