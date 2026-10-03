# GyroSteer for iOS 15

This is a separate, landscape-only native Swift/Xcode version of GyroSteer for older iPhones.
It leaves the Expo app in the parent directory unchanged and sets its iOS
deployment target to **iOS 15.0**.
The landscape UI uses a top switcher to open four non-scrolling layouts: a full
wheel visualizer, settings, driving buttons, and a combined wheel-and-buttons
view. This keeps the driving screen focused without removing access to setup.

It uses only Apple frameworks: CoreMotion for gyro steering, SwiftUI for the
controls, and URLSession WebSocket for the PC connection. The gyro readout and
wheel respond even before the PC connects. The JSON packet fields and button
bits match `../support/gyrosteer_pc_receiver.py`, so the Windows receiver does
not need a second protocol.

## Build on macOS

Windows cannot compile or sign an iOS app. On your macOS 15 machine:

1. Install Xcode 16 or later and open `GyroSteer.xcodeproj`.
2. Select the **GyroSteer** target and choose your Apple development team under
   **Signing & Capabilities**. If Xcode says the bundle identifier is already
   in use, change `PRODUCT_BUNDLE_IDENTIFIER` to one you control.
3. To test directly, connect the iPhone SE, select it as the run destination,
   and use **Product → Run**. The first connection asks for local-network
   permission.
4. To export an IPA, select **Any iOS Device (arm64)** as the destination and
   choose **Product → Archive**. In Organizer, choose **Distribute App** and
   select **Development** or **Ad Hoc** if your signing team offers it; export
   the resulting IPA. The signing profile must allow installation on your
   device, and its expiration depends on the signing method and account.

The Windows receiver still listens on port `8080`. Put the phone and PC on the
same Wi-Fi, allow Python through Windows Firewall on private networks, start
the receiver, then enter the PC's local IP address in GyroSteer.

## Project contents

- `GyroSteer.xcodeproj` — Xcode project and shared build scheme
- `GyroSteer/ContentView.swift` — landscape mode switcher, visualizer, settings, and control layouts
- `GyroSteer/WheelModel.swift` — gyro integration, settings, and WebSocket sender
- `GyroSteer/Info.plist` — iOS 15 deployment permissions and scene configuration

This workspace runs on Linux and has no Xcode toolchain, so the Xcode build and
device installation must be verified on the macOS machine.

push