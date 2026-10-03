import SwiftUI
import UIKit

private struct ExtraControl: Identifiable {
    let bit: Int
    let title: String
    let symbol: String

    var id: Int { bit }

    static let all: [ExtraControl] = [
        ExtraControl(bit: 4, title: "DRS", symbol: "arrow.up.right"),
        ExtraControl(bit: 5, title: "HORN", symbol: "speaker.wave.2"),
        ExtraControl(bit: 6, title: "TC +", symbol: "plus"),
        ExtraControl(bit: 7, title: "TC −", symbol: "minus"),
        ExtraControl(bit: 8, title: "ABS +", symbol: "plus"),
        ExtraControl(bit: 9, title: "ABS −", symbol: "minus"),
        ExtraControl(bit: 10, title: "PIT", symbol: "flag"),
        ExtraControl(bit: 11, title: "PAUSE", symbol: "pause")
    ]
}

struct ContentView: View {
    @ObservedObject private var model = WheelModel.shared
    @State private var showingSettings = false
    @State private var showingExtraControls = false

    private let extraColumns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    private let buttonColumns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private var statusColor: Color {
        if model.isConnected { return WheelTheme.primary }
        if model.isConnecting { return WheelTheme.accent }
        return WheelTheme.muted
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - 24)
            let wheelSize = max(
                108,
                min(geometry.size.height * 0.50, contentWidth * 0.36 - 18)
            )
            ZStack {
                WheelTheme.background.ignoresSafeArea()

                VStack(spacing: 6) {
                    cockpitHeader

                    HStack(alignment: .top, spacing: 6) {
                        steeringPanel(wheelSize: wheelSize)
                            .frame(minWidth: contentWidth * 0.36, maxWidth: contentWidth * 0.36)
                            .frame(maxHeight: .infinity)

                        VStack(spacing: 6) {
                            connectionPanel
                            tuningPanel
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }
                        .frame(minWidth: contentWidth * 0.31, maxWidth: contentWidth * 0.31)
                        .frame(maxHeight: .infinity, alignment: .top)

                        buttonsPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: 1200, maxHeight: .infinity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var cockpitHeader: some View {
        HStack(spacing: 7) {
            Image(systemName: "steeringwheel")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(WheelTheme.primary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text("GYROSTEER")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.4)
                    .foregroundColor(WheelTheme.foreground)
                Text("PHONE WHEEL · PC BRIDGE")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundColor(WheelTheme.muted)
            }

            Spacer(minLength: 4)

            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(model.isConnected ? "PC ONLINE" : (model.isConnecting ? "CONNECTING" : "PC OFFLINE"))
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(WheelTheme.foreground)
                    .lineLimit(1)
                if model.isConnected {
                    Text("\(model.packetCount) PKT")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(WheelTheme.muted)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(WheelTheme.card)
            .cornerRadius(8)
        }
        .frame(height: 28)
        .accessibilityElement(children: .combine)
    }

    private func steeringPanel(wheelSize: CGFloat) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                sectionTitle("LIVE STEERING")
                Spacer(minLength: 2)
                Text("\(Int(model.maxAngle))°")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundColor(WheelTheme.primary)
                Button(action: model.recenter) {
                    Image(systemName: "scope")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(WheelTheme.foreground)
                        .frame(width: 22, height: 21)
                        .background(WheelTheme.background)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Recenter steering wheel")
            }

            WheelArtwork(angle: model.angle, size: wheelSize)
                .frame(maxWidth: .infinity)
                .frame(height: wheelSize)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%+.0f°", model.angle))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WheelTheme.foreground)
                Spacer(minLength: 3)
                Text("AXIS")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(WheelTheme.muted)
                Text(String(format: "%+.3f", model.steering))
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WheelTheme.primary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(WheelTheme.wheelRim)
                    Rectangle()
                        .fill(WheelTheme.muted.opacity(0.7))
                        .frame(width: 1, height: 8)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    Circle()
                        .fill(abs(model.steering) > 0.94 ? WheelTheme.accent : WheelTheme.primary)
                        .frame(width: 7, height: 7)
                        .position(
                            x: geometry.size.width * CGFloat(
                                0.5 + clampValue(model.steering, -1, 1) * 0.46
                            ),
                            y: geometry.size.height / 2
                        )
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Circle()
                    .fill(model.gyroActive ? WheelTheme.primary : WheelTheme.accent)
                    .frame(width: 6, height: 6)
                Text(model.gyroStatus)
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .foregroundColor(model.gyroActive ? WheelTheme.primary : WheelTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text(String(format: "Z %+.2f rad/s", model.gyroRate))
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WheelTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(13)
    }

    private var connectionPanel: some View {
        VStack(spacing: 3) {
            HStack {
                sectionTitle("PC CONNECTION")
                Spacer(minLength: 2)
                Text("WI-FI")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(WheelTheme.muted)
            }

            HStack(spacing: 4) {
                TextField("PC IP address", text: $model.host)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(WheelTheme.foreground)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.isConnected || model.isConnecting)
                    .accessibilityLabel("PC IP address")
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(WheelTheme.background)
                    .cornerRadius(7)

                TextField("8080", text: $model.port)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundColor(WheelTheme.foreground)
                    .keyboardType(.numberPad)
                    .disabled(model.isConnected || model.isConnecting)
                    .accessibilityLabel("PC port")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 3)
                    .frame(width: 38)
                    .frame(minHeight: 28)
                    .background(WheelTheme.background)
                    .cornerRadius(7)

                Button(action: model.toggleConnection) {
                    HStack(spacing: 3) {
                        Image(systemName: model.isConnected || model.isConnecting ? "stop.fill" : "wifi")
                            .font(.system(size: 8, weight: .bold))
                        Text(model.isConnected || model.isConnecting ? "STOP" : "GO")
                            .font(.system(size: 7, weight: .heavy, design: .rounded))
                    }
                    .foregroundColor(model.isConnected ? WheelTheme.foreground : WheelTheme.primaryInk)
                    .frame(width: 48, height: 28)
                    .background(model.isConnected ? WheelTheme.cardRaised : WheelTheme.primary)
                    .cornerRadius(7)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(model.isConnected || model.isConnecting ? "Disconnect from PC" : "Connect to PC")
            }

            Text(model.connectionMessage)
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .foregroundColor(statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(6)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var tuningPanel: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                sectionTitle("FINE TUNING")
                Spacer(minLength: 1)
                Button(action: resetTuning) {
                    Text("RESET")
                        .font(.system(size: 7, weight: .heavy, design: .rounded))
                        .tracking(0.3)
                        .foregroundColor(WheelTheme.primary)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(WheelTheme.background)
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Reset wheel tuning to defaults")
            }

            FineTuningRow(
                title: "ROTATION",
                rangeLabel: "180–1080°",
                valueLabel: "\(Int(model.maxAngle))°",
                value: $model.maxAngle,
                bounds: 180...1080,
                step: 10
            )
            FineTuningRow(
                title: "SENSITIVITY",
                rangeLabel: "1–8×",
                valueLabel: String(format: "%.1f×", model.sensitivity),
                value: $model.sensitivity,
                bounds: 1...8,
                step: 0.1
            )
            FineTuningRow(
                title: "DEADZONE",
                rangeLabel: "0–10%",
                valueLabel: String(format: "%.1f%%", model.deadzone),
                value: $model.deadzone,
                bounds: 0...10,
                step: 0.1
            )
            FineTuningRow(
                title: "LINEARITY",
                rangeLabel: "0.6–2.0",
                valueLabel: String(format: "%.2f", model.linearity),
                value: $model.linearity,
                bounds: 0.6...2,
                step: 0.05
            )

            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var buttonsPanel: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                sectionTitle("DRIVING BUTTONS")
                Spacer(minLength: 1)
                Text("HOLD")
                    .font(.system(size: 6, weight: .heavy, design: .rounded))
                    .foregroundColor(WheelTheme.muted)
            }

            LazyVGrid(columns: buttonColumns, spacing: 4) {
                HoldButton(title: "SHIFT DOWN", symbol: "minus", kind: .neutral, height: 25) {
                    model.setButton(bit: 0, pressed: $0)
                }
                HoldButton(title: "SHIFT UP", symbol: "plus", kind: .neutral, height: 25) {
                    model.setButton(bit: 1, pressed: $0)
                }
                HoldButton(title: "BRAKE", symbol: "minus", kind: .brake, height: 25) {
                    model.setBrake($0)
                }
                HoldButton(title: "THROTTLE", symbol: "chevron.up", kind: .throttle, height: 25) {
                    model.setThrottle($0)
                }
                HoldButton(title: "NITRO", symbol: "bolt.fill", kind: .accent, height: 25) {
                    model.setButton(bit: 2, pressed: $0)
                }
                HoldButton(title: "HANDBRAKE", symbol: "hand.raised.fill", kind: .neutral, height: 25) {
                    model.setButton(bit: 3, pressed: $0)
                }
                ForEach(ExtraControl.all) { control in
                    HoldButton(title: control.title, symbol: control.symbol, kind: .neutral, height: 25) {
                        model.setButton(bit: control.bit, pressed: $0)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func resetTuning() {
        model.maxAngle = 900
        model.sensitivity = 4
        model.deadzone = 2
        model.linearity = 1.2
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var portraitLayout: some View {
        VStack(spacing: 12) {
            header
            connectionCard
            steeringCard
            controlsCard
            if showingExtraControls {
                extraControlsCard
            }
            if showingSettings {
                settingsCard
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 10)
        .padding(.bottom, 24)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 8) {
                header
                landscapeSteeringCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            VStack(spacing: 8) {
                connectionCard
                controlsCard
                if showingExtraControls {
                    extraControlsCard
                }
                if showingSettings {
                    settingsCard
                }
            }
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: 1000, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(WheelTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(WheelTheme.border, lineWidth: 1)
                    )
                Image(systemName: "steeringwheel")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(WheelTheme.primary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("GYROSTEER")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .tracking(1.8)
                    .foregroundColor(WheelTheme.foreground)
                Text("PHONE WHEEL · PC BRIDGE")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundColor(WheelTheme.muted)
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSettings.toggle()
                }
            } label: {
                Image(systemName: showingSettings ? "xmark" : "slider.horizontal.3")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(WheelTheme.foreground)
                    .frame(width: 40, height: 40)
                    .background(WheelTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(WheelTheme.border, lineWidth: 1)
                    )
                    .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(showingSettings ? "Hide settings" : "Show settings")
        }
        .frame(minHeight: 44)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(model.isConnected ? "PC LINK ACTIVE" : (model.isConnecting ? "CONNECTING" : "PC LINK"))
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1.1)
                        .foregroundColor(WheelTheme.foreground)
                }
                Spacer(minLength: 8)
                Text(model.isConnected ? "\(model.packetCount) packets" : "WEBSOCKET · WI-FI")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .foregroundColor(WheelTheme.muted)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                connectionField(label: "PC ADDRESS", placeholder: "192.168.1.50", text: $model.host)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(model.isConnected || model.isConnecting)

                connectionField(label: "PORT", placeholder: "8080", text: $model.port)
                    .frame(width: 74)
                    .keyboardType(.numberPad)
                    .disabled(model.isConnected || model.isConnecting)
            }

            Button(action: model.toggleConnection) {
                HStack(spacing: 8) {
                    if model.isConnecting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: WheelTheme.primaryInk))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: model.isConnected ? "stop.fill" : "wifi")
                            .font(.system(size: 13, weight: .bold))
                    }
                    Text(model.isConnected || model.isConnecting ? "STOP" : "CONNECT")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(0.8)
                }
                .foregroundColor(model.isConnected ? WheelTheme.foreground : WheelTheme.primaryInk)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(model.isConnected ? WheelTheme.cardRaised : WheelTheme.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(model.isConnected ? WheelTheme.input : WheelTheme.primary, lineWidth: 1)
                )
                .cornerRadius(10)
            }
            .buttonStyle(PlainButtonStyle())

            Text(model.connectionMessage)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(statusColor)
                .lineLimit(2)
        }
        .padding(13)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private func connectionField(
        label: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundColor(WheelTheme.muted)
            TextField(placeholder, text: text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(WheelTheme.foreground)
                .padding(.horizontal, 10)
                .frame(height: 39)
                .background(WheelTheme.background)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(WheelTheme.input, lineWidth: 1)
                )
                .cornerRadius(10)
        }
    }

    private var steeringCard: some View {
        VStack(spacing: 9) {
            HStack {
                sectionTitle("STEERING INPUT")
                Spacer()
                Text("\(Int(model.maxAngle))° TOTAL")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .tracking(0.3)
                    .foregroundColor(WheelTheme.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(WheelTheme.background)
                    .cornerRadius(10)
            }

            WheelArtwork(angle: model.angle, size: 156)
                .frame(maxWidth: .infinity)
                .frame(height: 164)

            HStack(alignment: .lastTextBaseline) {
                Text(String(format: "%+.1f°", model.angle))
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WheelTheme.foreground)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("AXIS X")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundColor(WheelTheme.muted)
                    Text(String(format: "%+.3f", model.steering))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(WheelTheme.primary)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(WheelTheme.wheelRim)
                    Rectangle()
                        .fill(WheelTheme.muted.opacity(0.7))
                        .frame(width: 1, height: 12)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    Circle()
                        .fill(abs(model.steering) > 0.94 ? WheelTheme.accent : WheelTheme.primary)
                        .frame(width: 9, height: 9)
                        .position(
                            x: geometry.size.width * CGFloat(0.5 + clampValue(model.steering, -1, 1) * 0.46),
                            y: geometry.size.height / 2
                        )
                }
            }
            .frame(height: 12)

            HStack {
                Text("−\(Int(model.maxAngle / 2))°")
                Spacer()
                Text(model.isTurning ? "TURNING" : "CENTERED")
                Spacer()
                Text("+\(Int(model.maxAngle / 2))°")
            }
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundColor(WheelTheme.muted)
        }
        .padding(14)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private var landscapeSteeringCard: some View {
        VStack(spacing: 6) {
            HStack {
                sectionTitle("STEERING")
                Spacer(minLength: 4)
                Text("\(Int(model.maxAngle))°")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundColor(WheelTheme.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(WheelTheme.background)
                    .cornerRadius(8)
            }

            HStack(spacing: 6) {
                WheelArtwork(angle: model.angle, size: 112)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: "%+.0f°", model.angle))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(WheelTheme.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    HStack(spacing: 4) {
                        Text("AXIS")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(WheelTheme.muted)
                        Text(String(format: "%+.2f", model.steering))
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(WheelTheme.primary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(WheelTheme.wheelRim)
                            Rectangle()
                                .fill(WheelTheme.muted)
                                .frame(width: 1, height: 10)
                                .position(
                                    x: geometry.size.width / 2,
                                    y: geometry.size.height / 2
                                )
                            Circle()
                                .fill(WheelTheme.primary)
                                .frame(width: 8, height: 8)
                                .position(
                                    x: geometry.size.width * CGFloat(
                                        0.5 + clampValue(model.steering, -1, 1) * 0.46
                                    ),
                                    y: geometry.size.height / 2
                                )
                        }
                    }
                    .frame(height: 10)

                    HStack(spacing: 4) {
                        Circle()
                            .fill(model.gyroActive ? WheelTheme.primary : WheelTheme.accent)
                            .frame(width: 6, height: 6)
                        Text(model.gyroStatus)
                            .font(.system(size: 7, weight: .heavy, design: .rounded))
                            .tracking(0.3)
                            .foregroundColor(model.gyroActive ? WheelTheme.primary : WheelTheme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Text(String(format: "Z %+.3f rad/s", model.gyroRate))
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(WheelTheme.muted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(14)
    }

    private var controlsCard: some View {
        VStack(spacing: 10) {
            HStack {
                sectionTitle("DRIVING CONTROLS")
                Spacer()
                Button(action: model.recenter) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text("RECENTER")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                    }
                    .foregroundColor(WheelTheme.primary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(WheelTheme.background)
                    .cornerRadius(9)
                }
                .buttonStyle(PlainButtonStyle())
            }

            HStack(spacing: 8) {
                HoldButton(title: "SHIFT DOWN", symbol: "minus", kind: .neutral, height: 62) {
                    model.setButton(bit: 0, pressed: $0)
                }
                HoldButton(title: "SHIFT UP", symbol: "plus", kind: .neutral, height: 62) {
                    model.setButton(bit: 1, pressed: $0)
                }
            }

            HStack(spacing: 8) {
                HoldButton(title: "BRAKE", symbol: "minus", kind: .brake, height: 68) {
                    model.setBrake($0)
                }
                HoldButton(title: "THROTTLE", symbol: "chevron.up", kind: .throttle, height: 68) {
                    model.setThrottle($0)
                }
            }

            HStack(spacing: 8) {
                HoldButton(title: "NITRO", symbol: "bolt.fill", kind: .accent, height: 48) {
                    model.setButton(bit: 2, pressed: $0)
                }
                HoldButton(title: "HANDBRAKE", symbol: "hand.raised.fill", kind: .neutral, height: 48) {
                    model.setButton(bit: 3, pressed: $0)
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingExtraControls.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Text(showingExtraControls ? "FEWER BUTTONS" : "MORE BUTTONS")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                    Image(systemName: showingExtraControls ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(WheelTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(14)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private var extraControlsCard: some View {
        LazyVGrid(columns: extraColumns, spacing: 8) {
            ForEach(ExtraControl.all) { control in
                HoldButton(title: control.title, symbol: control.symbol, kind: .neutral, height: 48) {
                    model.setButton(bit: control.bit, pressed: $0)
                }
            }
        }
        .padding(12)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("WHEEL SETUP")
            TuningRow(title: "Rotation", value: "\(Int(model.maxAngle))°") {
                Slider(value: $model.maxAngle, in: 180...1080, step: 30)
            }
            TuningRow(title: "Sensitivity", value: String(format: "%.1f×", model.sensitivity)) {
                Slider(value: $model.sensitivity, in: 1...8, step: 0.5)
            }
            TuningRow(title: "Deadzone", value: String(format: "%.1f%%", model.deadzone)) {
                Slider(value: $model.deadzone, in: 0...10, step: 0.5)
            }
            TuningRow(title: "Linearity", value: String(format: "%.1f", model.linearity)) {
                Slider(value: $model.linearity, in: 0.6...2, step: 0.1)
            }
        }
        .padding(14)
        .background(WheelTheme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(WheelTheme.border, lineWidth: 1)
        )
        .cornerRadius(16)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(1)
            .foregroundColor(WheelTheme.muted)
    }
}

private struct WheelArtwork: View {
    let angle: Double
    let size: CGFloat

    private var scale: CGFloat { size / 156 }

    var body: some View {
        ZStack {
            Circle()
                .fill(WheelTheme.wheelFace)
                .overlay(Circle().stroke(WheelTheme.wheelRim, lineWidth: 10 * scale))
            Capsule()
                .fill(WheelTheme.wheelSpoke)
                .frame(width: 118 * scale, height: 13 * scale)
            Capsule()
                .fill(WheelTheme.wheelSpoke)
                .frame(width: 13 * scale, height: 118 * scale)
            Circle()
                .fill(WheelTheme.wheelHub)
                .frame(width: 55 * scale, height: 55 * scale)
                .overlay(
                    Circle().stroke(WheelTheme.primary.opacity(0.9), lineWidth: 2 * scale)
                )
            VStack(spacing: 1) {
                Image(systemName: "scope")
                    .font(.system(size: 19 * scale, weight: .semibold))
                    .foregroundColor(WheelTheme.primary)
                Text("GS")
                    .font(.system(size: 8 * scale, weight: .heavy, design: .rounded))
                    .tracking(1 * scale)
                    .foregroundColor(WheelTheme.primary)
            }
            VStack {
                Capsule()
                    .fill(WheelTheme.accent)
                    .frame(width: 11 * scale, height: 7 * scale)
                    .offset(y: 4 * scale)
                Spacer()
            }
            .frame(height: 146 * scale)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(angle))
        .animation(.linear(duration: 0.025), value: angle)
    }
}

private enum HoldButtonKind: Equatable {
    case neutral
    case brake
    case throttle
    case accent
}

private struct HoldButton: View {
    let title: String
    let symbol: String
    let kind: HoldButtonKind
    let height: CGFloat
    let onPressChange: (Bool) -> Void
    @State private var isPressed = false

    init(
        title: String,
        symbol: String,
        kind: HoldButtonKind,
        height: CGFloat,
        onPressChange: @escaping (Bool) -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.kind = kind
        self.height = height
        self.onPressChange = onPressChange
    }

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .heavy))
                Text(title)
                    .font(.system(size: 7, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(isPressed ? activeFill : WheelTheme.cardRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in setPressed(true) }
                .onEnded { _ in setPressed(false) }
        )
        .accessibilityLabel(title)
        .accessibilityValue(isPressed ? "Pressed" : "Not pressed")
        .accessibilityAction {
            pulseForAccessibility()
        }
        .onDisappear { setPressed(false) }
    }

    private var borderColor: Color {
        switch kind {
        case .neutral: return WheelTheme.border
        case .brake: return WheelTheme.brakeBorder
        case .throttle: return WheelTheme.throttleBorder
        case .accent: return WheelTheme.accent.opacity(0.5)
        }
    }

    private var activeFill: Color {
        switch kind {
        case .neutral: return WheelTheme.primary.opacity(0.24)
        case .brake, .accent: return WheelTheme.accent
        case .throttle: return WheelTheme.primary
        }
    }

    private var foregroundColor: Color {
        if isPressed && kind == .throttle {
            return WheelTheme.primaryInk
        }
        if isPressed && (kind == .brake || kind == .accent) {
            return WheelTheme.foreground
        }
        if kind == .brake { return WheelTheme.accent }
        if kind == .throttle { return WheelTheme.primary }
        if kind == .accent { return WheelTheme.accent }
        return WheelTheme.foreground
    }

    private func setPressed(_ pressed: Bool) {
        guard pressed != isPressed else { return }
        isPressed = pressed
        onPressChange(pressed)
        if pressed {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func pulseForAccessibility() {
        setPressed(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            setPressed(false)
        }
    }
}

private struct TuningRow<Control: View>: View {
    let title: String
    let value: String
    let control: Control

    init(
        title: String,
        value: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.value = value
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(WheelTheme.foreground)
                Spacer()
                Text(value)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WheelTheme.primary)
            }
            control
                .accentColor(WheelTheme.primary)
                .frame(height: 24)
        }
    }
}

private struct FineTuningRow: View {
    let title: String
    let rangeLabel: String
    let valueLabel: String
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text("\(title) · \(rangeLabel)")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundColor(WheelTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 1)

                Text(valueLabel)
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(WheelTheme.primary)
            }

            HStack(spacing: 3) {
                nudgeButton(symbol: "minus", label: "Decrease \(title)", direction: -1)

                Slider(value: $value, in: bounds, step: step)
                    .accentColor(WheelTheme.primary)
                    .frame(height: 18)
                    .accessibilityLabel(title)

                nudgeButton(symbol: "plus", label: "Increase \(title)", direction: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func nudgeButton(
        symbol: String,
        label: String,
        direction: Double
    ) -> some View {
        Button {
            let currentStep = ((value - bounds.lowerBound) / step).rounded()
            let nextValue = bounds.lowerBound + (currentStep + direction) * step
            value = min(max(nextValue, bounds.lowerBound), bounds.upperBound)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(WheelTheme.foreground)
                .frame(width: 22, height: 21)
                .background(WheelTheme.cardRaised)
                .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
        .accessibilityHint("Adjust by \(step)")
    }
}