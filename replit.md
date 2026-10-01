# GyroSteer iOS

GyroSteer turns an iPhone into an adjustable gyro steering wheel and sends its inputs to a Windows PC gamepad receiver.

## Run & Operate

- `pnpm --filter @workspace/gyrosteer-ios run dev` — run the Expo app preview
- `pnpm --filter @workspace/gyrosteer-ios run typecheck` — typecheck the mobile app
- Native iOS 15 Xcode project: `artifacts/gyrosteer-ios/ios15-native/README.md`
- Windows receiver setup and firewall notes: `artifacts/gyrosteer-ios/PC_RECEIVER.md`
- Keep the iPhone and PC on the same Wi-Fi; the receiver defaults to port 8080.
- Build and sign the native iOS 15 project on macOS with Xcode; Windows and this Linux workspace cannot produce an IPA.

## Stack

- pnpm workspace, Expo SDK 57, React Native, TypeScript
- Separate SwiftUI/Xcode target for iOS 15 devices; it does not downgrade or replace the Expo app
- iPhone gyro input: `expo-sensors`
- Local preferences: AsyncStorage
- PC bridge: Python WebSocket + UDP server, ViGEm virtual Xbox 360 controller

## Where things live
- `artifacts/gyrosteer-ios/app/index.tsx` — steering screen, motion sensor, WebSocket sender, and controls
- `artifacts/gyrosteer-ios/ios15-native/GyroSteer.xcodeproj` — native iOS 15 app project and shared Xcode scheme
- `artifacts/gyrosteer-ios/ios15-native/GyroSteer/` — SwiftUI interface, gyro/WebSocket model, and iOS permissions
- `artifacts/gyrosteer-ios/constants/colors.ts` — cockpit theme tokens
- `artifacts/gyrosteer-ios/support/gyrosteer_pc_receiver.py` — iOS and Android-compatible PC receiver
- `artifacts/gyrosteer-ios/PC_RECEIVER.md` — Windows setup instructions

## Architecture decisions

- iOS uses WebSocket JSON; Android's existing binary UDP packets remain supported by the same receiver.
- Wheel preferences stay on the iPhone; no account or hosted service is needed.

## Product

- Adjustable steering range, sensitivity, deadzone, linearity, and recentering
- On-screen shifters, throttle, brake, and mapped gamepad buttons

## User preferences

No cross-project preferences recorded.

## Gotchas

- iOS uses WebSocket because Expo Go does not expose raw UDP sockets.
- If Windows Firewall prompts, allow Python on private networks.

## Pointers

- See `artifacts/gyrosteer-ios/PC_RECEIVER.md` for Windows receiver setup.
- See the `pnpm-workspace` skill for workspace structure and package management.
