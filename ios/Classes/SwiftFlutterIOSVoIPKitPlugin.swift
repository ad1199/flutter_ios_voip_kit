import Flutter
import PushKit
import CallKit
import UIKit
import UserNotifications
import AVFoundation

public class SwiftFlutterIOSVoIPKitPlugin: NSObject {

    static var _instance: SwiftFlutterIOSVoIPKitPlugin?
    private static var flutterPluginRegistrantCallback: FlutterPluginRegistrantCallback?

    private var _registrar: FlutterPluginRegistrar
    private var dispatcherInitialized: Bool = false
    private var backgroundIsolateRun: Bool = false
    
    private let _eventChannel: FlutterEventChannel

    private let didUpdateTokenKey = "Did_Update_VoIP_Device_Token"
    private let pushRegistry: PKPushRegistry
    var flutterEngine: FlutterEngine?
    var backgroundMethodChannel: FlutterMethodChannel?

    private var eventSink: FlutterEventSink?
    private enum EventChannel: String {
        case onDidReceiveIncomingPush
        
        case onDidUpdatePushToken
    }

    let callKitCenter: CallKitCenter

    let app: UIApplication

    private var callEndedBySystem: Bool = false

    var token: String? {
        if let didUpdateDeviceToken = UserDefaults.standard.data(forKey: didUpdateTokenKey) {
            let token = String(deviceToken: didUpdateDeviceToken)
            print("🎈 VoIP didUpdateDeviceToken: \(token)")
            return token
        }

        guard let cacheDeviceToken = self.pushRegistry.pushToken(for: .voIP) else {
            return nil
        }

        let token = String(deviceToken: cacheDeviceToken)
        print("🎈 VoIP cacheDeviceToken: \(token)")
        return token
    }


    public static func register(with registrar: FlutterPluginRegistrar) {
        if(_instance == nil) {
            let channel = FlutterMethodChannel(name: FlutterPluginChannelType.method.name,  binaryMessenger: registrar.messenger())
            _instance = SwiftFlutterIOSVoIPKitPlugin(messenger: registrar.messenger(), registrar: registrar)
            registrar.addMethodCallDelegate(_instance!, channel: channel)
            registrar.addApplicationDelegate(_instance!)
        }
    }

    init(messenger: FlutterBinaryMessenger, registrar: FlutterPluginRegistrar) {

        self._eventChannel = FlutterEventChannel(name: FlutterPluginChannelType.event.name, binaryMessenger: messenger);

        self.app = UIApplication.shared;
        self._registrar = registrar;
        self.callKitCenter = CallKitCenter()
        print("[fivk]: Callkitcenter initialized")
        self.pushRegistry = PKPushRegistry(queue: .main)
        self.pushRegistry.desiredPushTypes = [.voIP]

        super.init()
        self.notificationCenter.delegate = self
        self.pushRegistry.delegate = self
        self.callKitCenter.setup(delegate: self)
        self._eventChannel.setStreamHandler(self)

    }

    // MARK: - VoIPCenter

    // private let voIPCenter: VoIPCenter

    // MARK: - Local Notification

    private let notificationCenter = UNUserNotificationCenter.current()
    private let options: UNAuthorizationOptions = [.alert]

    // MARK: - method channel

    private func getVoIPToken(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        result(self.token)
    }

    // private func getIncomingCallerName(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     result(self.voIPCenter.callKitCenter.incomingCallerName)
    // }

    // private func startCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     guard let args = call.arguments as? [String: Any],
    //         let uuid = args["uuid"] as? String,
    //         let targetName = args["targetName"] as? String else {
    //             result(FlutterError(code: "InvalidArguments startCall", message: nil, details: nil))
    //             return
    //     }
    //     self.voIPCenter.callKitCenter.startCall(uuidString: uuid, targetName: targetName)
    //     result(nil)
    // }

    // private func endCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     self.voIPCenter.callKitCenter.endCall()
    //     result(nil)
    // }

    // private func acceptIncomingCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     guard let args = call.arguments as? [String: Any],
    //         let callerState = args["callerState"] as? String else {
    //             result(FlutterError(code: "InvalidArguments acceptIncomingCall", message: nil, details: nil))
    //             return
    //     }
    //     self.voIPCenter.callKitCenter.acceptIncomingCall(alreadyEndCallerReason: callerState == "calling" ? nil : .failed)
    //     result(nil)
    // }

    // private func unansweredIncomingCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     guard let args = call.arguments as? [String: Any],
    //         let skipLocalNotification = args["skipLocalNotification"] as? Bool else {
    //             result(FlutterError(code: "InvalidArguments unansweredIncomingCall", message: nil, details: nil))
    //             return
    //     }

    //     self.voIPCenter.callKitCenter.unansweredIncomingCall()

    //     if (skipLocalNotification) {
    //         result(nil)
    //         return
    //     }

    //     let content = UNMutableNotificationContent()
    //     content.title = args["missedCallTitle"] as? String ?? "Missed Call"
    //     content.body = args["missedCallBody"] as? String ?? "There was a call"
    //     let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2,
    //                                                     repeats: false)
    //     let request = UNNotificationRequest(identifier: "unansweredIncomingCall",
    //                                         content: content,
    //                                         trigger: trigger)
    //     self.notificationCenter.add(request) { (error) in
    //         if let error = error {
    //             print("❌ unansweredIncomingCall local notification error: \(error.localizedDescription)")
    //         }
    //     }

    //     result(nil)
    // }

    // private func callConnected(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     self.voIPCenter.callKitCenter.callConnected()
    //     result(nil)
    // }

    // public func requestAuthLocalNotification(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     notificationCenter.requestAuthorization(options: options) { granted, error in
    //         if let error = error {
    //             result(["granted": granted, "error": error.localizedDescription])
    //         } else {
    //             result(["granted": granted])
    //         }
    //     }
    // }
    
    // public func getLocalNotificationsSettings(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     notificationCenter.getNotificationSettings { settings in
    //         result(settings.toMap())
    //     }
    // }
    
    // private func testIncomingCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    //     guard let args = call.arguments as? [String: Any],
    //         let uuid = args["uuid"] as? String,
    //         let callerId = args["callerId"] as? String,
    //         let callerName = args["callerName"] as? String else {
    //             result(FlutterError(code: "InvalidArguments testIncomingCall", message: nil, details: nil))
    //             return
    //     }

    //     self.voIPCenter.callKitCenter.incomingCall(uuidString: uuid,
    //                                                callerId: callerId,
    //                                                callerName: callerName) { (error) in
    //         if let error = error {
    //             print("❌ testIncomingCall error: \(error.localizedDescription)")
    //             result(FlutterError(code: "testIncomingCall",
    //                                 message: error.localizedDescription,
    //                                 details: nil))
    //             return
    //         }
    //         result(nil)
    //     }
    // }

    public func getDispatcherHandle() -> Int64 {
        let userDefaults = UserDefaults.standard;
        let handle = userDefaults.object(forKey: "fivk_dispatcher_handle") as! Int64
        return handle;
    }

    private func setDispatcherHandle(_ handle: Int64) {
        let userDefaults = UserDefaults.standard;
        userDefaults.set(handle, forKey: "fivk_dispatcher_handle");
    }

    public func getCallbackHandle() -> Int64 {
        let userDefaults = UserDefaults.standard;
        let handle = userDefaults.object(forKey: "fivk_callback_handle") as! Int64
        return handle;
    }

    private func setBackgroundCallback(_ call: FlutterMethodCall) {
        let args = call.arguments as! [Any]
        let handle = args[0] as! Int64
        let userDefaults = UserDefaults.standard
        userDefaults.set(handle, forKey: "fivk_callback_handle");
        print("[fivk]: Set background callback done")
    }

    private func isAppActive() -> Bool {
        return self.app.applicationState == UIApplication.State.active
    }

    private func runBackgroundCallback(event: String, data: [String: Any]?, completion: @escaping (Bool) -> Void) {

        var args: [Any] = [
            self.getCallbackHandle(),
            event
        ]

        if(data != nil) {
            args.append(data as Any)
        } 

        backgroundMethodChannel!.invokeMethod("backgroundCallback", arguments: args) { result in
            completion(true)
        }
    }

    private func startBackgroundService(completion: @escaping (Bool) -> Void) {

        if(flutterEngine != nil) {
            completion(true)
            return
        }

        let handle = self.getDispatcherHandle()
        print("[fivk]: callback handle received \(handle)")

        let info: FlutterCallbackInformation? = FlutterCallbackCache.lookupCallbackInformation(handle)
        assert(info != nil, "[fivk] ERROR: failed to find the callback");

        let entrypoint: String = info!.callbackName;
        let uri: String =  info!.callbackLibraryPath;

        print("[fivk]: callback found : \(entrypoint) with uri: \(uri)");

        flutterEngine = FlutterEngine(
            name: "FIVKIsolate",
            project: nil,
            allowHeadlessExecution: true
        )

        flutterEngine!.run(withEntrypoint: entrypoint, libraryURI: uri)
        print("[fivk]: flutter engine is running...");

        print("[fivk]: Calling plugin regstrant callback")
        SwiftFlutterIOSVoIPKitPlugin.flutterPluginRegistrantCallback?(flutterEngine!)
        print("[fivk]: flutter engine is registered...");

        backgroundMethodChannel = FlutterMethodChannel(
            name: FlutterPluginChannelType.backgroundMethod.name,
            binaryMessenger: flutterEngine!.binaryMessenger
        )

        backgroundMethodChannel!.setMethodCallHandler{(call, result) in 
            print("[fivk]: background set method handler called")
            switch call.method {
                case "dispatcherInitialized":
                    self.dispatcherInitialized = true
                    result(true)
                    print("[fivk]: Dispatcher initialized")
                    completion(true)
                default:
                    print("[fivk]: Method not registered")
                    // cleanupFlutterResources()
                    result(true)
                    completion(true)
            }
        }

        self.backgroundIsolateRun = true;

    }

    private func cleanupFlutterResources() {

        if(flutterEngine == nil) {
            return
        }

        flutterEngine!.destroyContext()
        backgroundMethodChannel = nil
        flutterEngine = nil
    }

    private func setOnBackgroundIncomingPush(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let defaults = UserDefaults.standard
        let callbackHandle = call.arguments as? Int;
        print("[VoIP kit]: Got the callback handle : \(callbackHandle!)")

        defaults.setInteger(callbackHandle!, forKey: "voip_on_background_incoming_push_handle")
        result(true)
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
        // case getIncomingCallerName
        // case startCall
        // case endCall
        // case acceptIncomingCall
        // case unansweredIncomingCall
        // case callConnected
        // case requestAuthLocalNotification
        // case getLocalNotificationsSettings
        // case testIncomingCall
        
        case initialize
        case setBackgroundCallback
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
            // case .getIncomingCallerName:
            //     self.getIncomingCallerName(call, result: result)
            // case .startCall:
            //     self.startCall(call, result: result)
            // case .endCall:
            //     self.endCall(call, result: result)
            // case .acceptIncomingCall:
            //     self.acceptIncomingCall(call, result: result)
            // case .unansweredIncomingCall:
            //     self.unansweredIncomingCall(call, result: result)
            // case .callConnected:
            //     self.callConnected(call, result: result)
            // case .requestAuthLocalNotification:
            //     self.requestAuthLocalNotification(call, result: result)
            // case .getLocalNotificationsSettings:
            //     self.getLocalNotificationsSettings(call, result: result)
            // case .testIncomingCall:
            //     self.testIncomingCall(call, result: result)
            case .initialize:
                let args = call.arguments as! [Any]
                let handle = args[0] as! Int64
                self.setDispatcherHandle(handle)
                //self.startBackgroundService()
                result(true)
            case .setBackgroundCallback:
                print("[fivk]: Set background callback")
                self.setBackgroundCallback(call)
                result(true)
        }
    }
}

extension SwiftFlutterIOSVoIPKitPlugin: PKPushRegistryDelegate {

    // MARK: - PKPushRegistryDelegate

    public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        print("🎈 VoIP didUpdate pushCredentials")
        UserDefaults.standard.set(pushCredentials.token, forKey: didUpdateTokenKey)
        
        // self.eventSink?(["event": EventChannel.onDidUpdatePushToken.rawValue,
        //                  "token": pushCredentials.token.hexString])
    }

    // NOTE: iOS11 or more support

    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        print("🎈 VoIP didReceiveIncomingPushWith completion: \(payload.dictionaryPayload)")

        handlePushEvent(payload)

        completion()
        
    }

    // NOTE: iOS10 support

    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType) {
        print("🎈 VoIP didReceiveIncomingPushWith: \(payload.dictionaryPayload)")

        let info = self.parse(payload: payload)
        let callerName = info!["incoming_caller_name"] as! String
        self.callKitCenter.incomingCall(uuidString: info!["uuid"] as! String,
                                        callerId: info!["incoming_caller_id"] as! String,
                                        callerName: callerName) { error in
            if let error = error {
                print("❌ reportNewIncomingCall error: \(error.localizedDescription)")
                return
            }
            // self.eventSink?(["event": EventChannel.onDidReceiveIncomingPush.rawValue,
            //                  "payload": info as Any,
            //                  "incoming_caller_name": callerName])
        }
    }

    private func parse(payload: PKPushPayload) -> [String: Any]? {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload.dictionaryPayload, options: .prettyPrinted)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            let aps = json?["aps"] as? [String: Any]
            return aps?["alert"] as? [String: Any]
        } catch let error as NSError {
            print("❌ VoIP parsePayload: \(error.localizedDescription)")
            return nil
        }
    }

    private func handlePushEvent(_ payload: PKPushPayload) {

        let info = self.parse(payload: payload)
        let event = info!["event"] as! String;

        if(event == "invite") {
            callEndedBySystem = false
            let caller = info!["caller"] as! [String: Any]
            let callerName = caller["name"] as! String
            self.callKitCenter.incomingCall(uuidString: info!["uuid"] as! String,
                                            callerId: info!["session_id"] as! String,
                                            callerName: callerName) { error in
                if let error = error {
                    print("❌ reportNewIncomingCall error: \(error.localizedDescription)")
                    return
                }
            }

            // Close incoming callkit ui if the invitation is expired
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'"
            dateFormatter.timeZone = TimeZone(abbreviation: "UTC") // set timezone to utc
            let calledUtcDate = dateFormatter.date(from: info!["called_at"] as! String)

            let currentDate = Date()
            let difference = currentDate.timeIntervalSinceReferenceDate - calledUtcDate!.timeIntervalSinceReferenceDate

            let currentDateString = dateFormatter.string(from: currentDate)
            print("[fivk]: Current date: \(currentDateString)")
            print("[fivk]: Difference in called date: \(difference)")

            if(difference > 30) {
                callEndedBySystem = true
                self.callKitCenter.endCall()
            }

        }

        if(event == "cancel") {

            let caller = info!["caller"] as! [String: Any]
            let callerName = caller["name"] as! String

            // Show callkit if it is not already displayed as not showing it may crash the app
            if(!self.callKitCenter.isCalling()) {
                self.callKitCenter.incomingCall(uuidString: info!["uuid"] as! String,
                                            callerId: info!["session_id"] as! String,
                                            callerName: callerName) { error in
                    if let error = error {
                        print("❌ reportNewIncomingCall error: \(error.localizedDescription)")
                        return
                    }
                }
            }

            callEndedBySystem = true
            self.callKitCenter.endCall()
        }

        if(self.isAppActive()) {
            print("[fivk]: Application is active")
            self.eventSink?(["event": EventChannel.onDidReceiveIncomingPush.rawValue,
                             "payload": [
                                "event": event,
                                "data": info as Any
                             ]])
        } else {
            print("[fivk]: Application is inactive")
            self.startBackgroundService() { result in
                self.runBackgroundCallback(event: event, data: info!) { result in
                    if(event == "cancel") {
                        self.cleanupFlutterResources()
                    }
                }
            }
        }

    }
}

extension SwiftFlutterIOSVoIPKitPlugin: CXProviderDelegate {

    // MARK:  - CXProviderDelegate

    public func providerDidReset(_ provider: CXProvider) {
        print("🚫 VoIP providerDidReset")
    }

    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        print("🤙 VoIP CXStartCallAction")
        // self.callKitCenter.connectingOutgoingCall()
        action.fulfill()
    }

    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        print("✅ VoIP CXAnswerCallAction")
        self.callKitCenter.answerCallAction = action
        // self.configureAudioSession()
        // self.eventSink?(["event": EventChannel.onDidAcceptIncomingCall.rawValue,
        //                  "uuid": self.callKitCenter.uuidString as Any,
        //                  "incoming_caller_id": self.callKitCenter.incomingCallerId as Any])

        callEndedBySystem = true;
        print("[fivk]: Accept call action")
        if(self.isAppActive() ) {
            self.eventSink?(["event": EventChannel.onDidReceiveIncomingPush.rawValue,
                             "payload": [
                                "event": "accept",
                             ]])
            self.callKitCenter.endCall();
        } else {
            self.startBackgroundService() { result in
                self.runBackgroundCallback(event: "accept", data: nil) { result in
                    self.cleanupFlutterResources()
                    self.callKitCenter.endCall();
                }
            }   
        }
    }

    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        print("❎ VoIP CXEndCallAction")
        // if (self.callKitCenter.isCalleeBeforeAcceptIncomingCall) {
        //     self.eventSink?(["event": EventChannel.onDidRejectIncomingCall.rawValue,
        //                      "uuid": self.callKitCenter.uuidString as Any,
        //                      "incoming_caller_id": self.callKitCenter.incomingCallerId as Any])
        // }
        self.callKitCenter.disconnected(reason: .remoteEnded)
        action.fulfill()

        print("[fivk]: End call action")

        if(callEndedBySystem) {
            return
        }
        if(self.isAppActive() ) {
            self.eventSink?(["event": EventChannel.onDidReceiveIncomingPush.rawValue,
                             "payload": [
                                "event": "reject",
                             ]])
        } else {
            self.startBackgroundService() { result in
                self.runBackgroundCallback(event: "reject", data: nil) { result in
                    self.cleanupFlutterResources()
                }
            }   
        }
    }
    
    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        print("🔈 VoIP didActivate audioSession")
        // self.eventSink?(["event": EventChannel.onDidActivateAudioSession.rawValue])
    }

    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        print("🔇 VoIP didDeactivate audioSession")
        // self.eventSink?(["event": EventChannel.onDidDeactivateAudioSession.rawValue])
    }
    
}

extension SwiftFlutterIOSVoIPKitPlugin: FlutterStreamHandler {

    // MARK: - FlutterStreamHandler（event channel）

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
