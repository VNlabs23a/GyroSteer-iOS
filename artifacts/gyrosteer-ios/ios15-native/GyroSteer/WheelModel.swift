import Combine
import CoreMotion
import Foundation
import UIKit

private enum PreferenceKey {
    static let host = "gyrosteer.native.host"
    static let port = "gyrosteer.native.port"
    static let maxAngle = "gyrosteer.native.maxAngle"
    static let sensitivity = "gyrosteer.native.sensitivity"
    static let deadzone = "gyrosteer.native.deadzone"
    static let linearity = "gyrosteer.native.linearity"
}

final class WheelModel: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    static let shared = WheelModel()

    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: PreferenceKey.host) }
    }
    @Published var port: String {
        didSet { UserDefaults.standard.set(port, forKey: PreferenceKey.port) }
    }
    @Published var maxAngle: Double {
        didSet {
            UserDefaults.standard.set(maxAngle, forKey: PreferenceKey.maxAngle)
            applyAngle(angle)
        }
    }
    @Published var sensitivity: Double {
        didSet { UserDefaults.standard.set(sensitivity, forKey: PreferenceKey.sensitivity) }
    }
    @Published var deadzone: Double {
        didSet {
            UserDefaults.standard.set(deadzone, forKey: PreferenceKey.deadzone)
            applyAngle(angle)
        }
    }
    @Published var linearity: Double {
        didSet {
            UserDefaults.standard.set(linearity, forKey: PreferenceKey.linearity)
            applyAngle(angle)
        }
    }

    @Published private(set) var angle = 0.0
    @Published private(set) var steering = 0.0
    @Published private(set) var pressedMask = 0
    @Published private(set) var throttlePressed = false
    @Published private(set) var brakePressed = false
    @Published private(set) var isTurning = false
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var packetCount = 0
    @Published private(set) var connectionMessage = "PC not connected"
    @Published private(set) var gyroAvailable = false
    @Published private(set) var gyroActive = false
    @Published private(set) var gyroStatus = "CHECKING GYRO"
    @Published private(set) var gyroRate = 0.0

    private let motionManager = CMMotionManager()
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var sendTimer: Timer?
    private var connectionTimeout: DispatchWorkItem?
    private var rawAngle = 0.0
    private var zeroOffset = 0.0
    private var filteredAngle = 0.0
    private var gyroBias = 0.0
    private var lastSampleTimestamp: TimeInterval = 0
    private var sequence = 0
    private var lockHapticActive = false
    private var activeHost = ""

    private override init() {
        let defaults = UserDefaults.standard
        host = defaults.string(forKey: PreferenceKey.host) ?? ""
        port = defaults.string(forKey: PreferenceKey.port) ?? "8080"
        maxAngle = defaults.object(forKey: PreferenceKey.maxAngle) as? Double ?? 900
        sensitivity = defaults.object(forKey: PreferenceKey.sensitivity) as? Double ?? 4
        deadzone = defaults.object(forKey: PreferenceKey.deadzone) as? Double ?? 2
        linearity = defaults.object(forKey: PreferenceKey.linearity) as? Double ?? 1.2
        super.init()
        gyroAvailable = motionManager.isGyroAvailable
        startGyroscope()
    }

    func toggleConnection() {
        if isConnected || isConnecting {
            stopSession()
        } else {
            connect()
        }
    }

    func connect() {
        let cleanHost = host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: "^wss?://",
                with: "",
                options: .regularExpression
            )
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        let normalizedHost = cleanHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let numericPort = Int(port.trimmingCharacters(in: .whitespacesAndNewlines))

        guard !normalizedHost.isEmpty else {
            connectionMessage = "Enter your PC’s local IP address"
            return
        }
        guard let numericPort, (1...65535).contains(numericPort) else {
            connectionMessage = "Enter a valid port from 1 to 65535"
            return
        }
        guard motionManager.isGyroAvailable else {
            connectionMessage = "This iPhone does not report gyroscope data"
            return
        }

        var components = URLComponents()
        components.scheme = "ws"
        components.host = normalizedHost
        components.port = numericPort
        guard let url = components.url else {
            connectionMessage = "Enter a valid PC address"
            return
        }

        activeHost = normalizedHost
        connectionMessage = "Connecting to \(normalizedHost):\(numericPort)"
        isConnecting = true
        packetCount = 0

        let session = URLSession(
            configuration: .default,
            delegate: self,
            delegateQueue: .main
        )
        let socket = session.webSocketTask(with: url)
        self.session = session
        self.socket = socket
        socket.resume()

        let timeout = DispatchWorkItem { [weak self, weak socket] in
            guard let self, let socket, self.socket === socket, self.isConnecting else { return }
            self.stopSession(message: "Connection timed out — check PC receiver and Wi-Fi")
        }
        connectionTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: timeout)
    }

    func stopSession(message: String = "PC not connected") {
        connectionTimeout?.cancel()
        connectionTimeout = nil
        sendTimer?.invalidate()
        sendTimer = nil

        let oldSocket = socket
        socket = nil
        oldSocket?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
        session = nil

        isConnected = false
        isConnecting = false
        connectionMessage = message
        pressedMask = 0
        throttlePressed = false
        brakePressed = false
        isTurning = false
        rawAngle = 0
        zeroOffset = 0
        filteredAngle = 0
        gyroBias = 0
        lastSampleTimestamp = 0
        lockHapticActive = false
        applyAngle(0)
    }

    func pauseForBackground() {
        if isConnected || isConnecting {
            stopSession(message: "Paused while GyroSteer is in the background")
        }
        motionManager.stopGyroUpdates()
        gyroActive = false
        gyroRate = 0
        gyroStatus = "GYRO PAUSED"
        lastSampleTimestamp = 0
    }

    func resumeFromForeground() {
        startGyroscope()
    }

    func recenter() {
        zeroOffset = rawAngle
        filteredAngle = 0
        applyAngle(0)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func setButton(bit: Int, pressed: Bool) {
        guard (0..<12).contains(bit) else { return }
        let mask = 1 << bit
        if pressed {
            pressedMask |= mask
        } else {
            pressedMask &= ~mask
        }
    }

    func setThrottle(_ pressed: Bool) {
        throttlePressed = pressed
    }

    func setBrake(_ pressed: Bool) {
        brakePressed = pressed
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard socket === webSocketTask else { return }
        connectionTimeout?.cancel()
        connectionTimeout = nil
        isConnecting = false
        isConnected = true
        connectionMessage = "Connected to \(activeHost)"
        sequence = 0
        rawAngle = 0
        zeroOffset = 0
        filteredAngle = 0
        gyroBias = 0
        lastSampleTimestamp = 0
        receiveNextMessage(from: webSocketTask)

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.sendFrame()
        }
        sendTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard socket === webSocketTask else { return }
        stopSession(message: "PC connection closed")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard
            let error,
            let webSocketTask = task as? URLSessionWebSocketTask,
            socket === webSocketTask
        else {
            return
        }
        stopSession(message: "Connection lost — \(error.localizedDescription)")
    }

    private func startGyroscope() {
        guard motionManager.isGyroAvailable else {
            gyroAvailable = false
            gyroActive = false
            gyroStatus = "GYRO UNAVAILABLE"
            return
        }
        gyroAvailable = true
        guard !motionManager.isGyroActive else { return }

        motionManager.gyroUpdateInterval = 1.0 / 60.0
        gyroStatus = "STARTING GYRO"
        motionManager.startGyroUpdates(to: .main) { [weak self] sample, error in
            guard let self else { return }
            if let error {
                self.motionManager.stopGyroUpdates()
                self.gyroActive = false
                self.gyroStatus = "GYRO ERROR"
                return
            }
            guard let sample else { return }
            self.gyroActive = true
            self.gyroStatus = "GYRO ACTIVE"
            self.gyroRate = sample.rotationRate.z
            self.integrateGyroscope(rate: sample.rotationRate.z, timestamp: sample.timestamp)
        }
    }

    private func integrateGyroscope(rate: Double, timestamp: TimeInterval) {
        if lastSampleTimestamp == 0 {
            lastSampleTimestamp = timestamp
            return
        }

        let elapsed = clampValue(timestamp - lastSampleTimestamp, 0, 0.08)
        lastSampleTimestamp = timestamp
        var angularRate = rate - gyroBias
        let turning = abs(angularRate) > 0.025
        if !turning {
            gyroBias += (rate - gyroBias) * 0.02
            angularRate = 0
        }
        isTurning = turning

        rawAngle += angularRate * elapsed * (180.0 / .pi) * sensitivity
        let requestedAngle = rawAngle - zeroOffset
        let halfAngle = maxAngle / 2
        let target = clampValue(requestedAngle, -halfAngle, halfAngle)
        let smoothed = filteredAngle + (target - filteredAngle) * 0.28
        filteredAngle = smoothed
        applyAngle(smoothed)

        let nearLock = abs(smoothed) >= halfAngle - 18
        if nearLock && !lockHapticActive {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        lockHapticActive = nearLock
    }

    private func applyAngle(_ requestedAngle: Double) {
        let halfAngle = maxAngle / 2
        angle = clampValue(requestedAngle, -halfAngle, halfAngle)

        let raw = clampValue(angle / max(halfAngle, 1), -1, 1)
        let deadzoneFraction = clampValue(deadzone / 100, 0, 0.5)
        let magnitude = abs(raw)
        if magnitude <= deadzoneFraction {
            steering = 0
        } else {
            let rescaled = (magnitude - deadzoneFraction) / (1 - deadzoneFraction)
            steering = (raw < 0 ? -1 : 1) * pow(rescaled, linearity)
        }
    }

    private func sendFrame() {
        guard let socket, socket.state == .running else { return }
        sequence = (sequence + 1) & 0xFFFF
        let frame: [String: Any] = [
            "type": "wheel",
            "seq": sequence,
            "steering": steering,
            "axis": steering,
            "angle": angle,
            "buttons": pressedMask,
            "accel": throttlePressed ? 1 : 0,
            "brake": brakePressed ? 1 : 0,
            "isMoving": isTurning
        ]
        guard
            JSONSerialization.isValidJSONObject(frame),
            let data = try? JSONSerialization.data(withJSONObject: frame),
            let message = String(data: data, encoding: .utf8)
        else {
            return
        }

        socket.send(.string(message)) { [weak self, weak socket] error in
            guard let error else { return }
            DispatchQueue.main.async {
                guard let self, let socket, self.socket === socket else { return }
                self.stopSession(message: "Connection lost — \(error.localizedDescription)")
            }
        }
        if sequence % 10 == 0 {
            packetCount += 10
        }
    }

    private func receiveNextMessage(from socket: URLSessionWebSocketTask) {
        socket.receive { [weak self, weak socket] result in
            guard let self, let socket, self.socket === socket else { return }
            switch result {
            case .success:
                self.receiveNextMessage(from: socket)
            case .failure(let error):
                DispatchQueue.main.async {
                    guard self.socket === socket else { return }
                    self.stopSession(message: "Connection lost — \(error.localizedDescription)")
                }
            }
        }
    }
}

func clampValue(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
    min(maximum, max(minimum, value))
}