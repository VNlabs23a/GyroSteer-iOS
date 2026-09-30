# GyroSteer PC receiver

The iPhone app sends steering, touch pedals, and buttons to this Windows
receiver over WebSocket. The receiver maps them to a virtual Xbox 360
controller. The same script still accepts the Android app's original binary
UDP packets on port 8080.

## Windows setup

1. Install the **ViGEmBus** driver so Windows can create a virtual Xbox
   controller.
2. Install Python 3.10 or newer if it is not already installed.
3. Open PowerShell in the `support` folder and install the Python libraries:

   ```powershell
   python -m pip install -r requirements-pc.txt
   ```

4. Start the receiver:

   ```powershell
   python gyrosteer_pc_receiver.py
   ```

5. Copy the PC address printed by the receiver into GyroSteer on the iPhone.
   Both devices must be on the same Wi-Fi network. Allow Python through
   Windows Firewall for **private networks** if Windows asks.

The receiver uses both TCP/WebSocket and UDP port `8080`; Windows permits both
protocols to use the same port number. If your network blocks device-to-device
traffic, use a shared non-guest Wi-Fi network.

If real pedals are connected to the PC, the receiver uses their input. Without
them, the on-screen iPhone pedals control the virtual Xbox triggers.