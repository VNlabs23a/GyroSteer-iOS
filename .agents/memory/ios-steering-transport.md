---
name: iOS steering transport
description: Transport choice for connecting the Expo iPhone app and existing Android sender to the Windows gamepad receiver.
---

Use WebSocket JSON from the iPhone and retain Android's binary UDP input in the Windows receiver. Both transports can listen on port 8080 because TCP and UDP have separate port spaces.

**Why:** Expo Go does not expose raw UDP sockets, while the Android app and the supplied Windows bridge already use UDP. A WebSocket bridge avoids a custom native module and keeps both phone apps compatible with one receiver.

**How to apply:** Keep the iOS frame fields (`steering`, `angle`, `buttons`, `accel`, and `brake`) aligned with the Windows WebSocket parser. Do not remove the `GW` binary UDP parser when changing the PC bridge.