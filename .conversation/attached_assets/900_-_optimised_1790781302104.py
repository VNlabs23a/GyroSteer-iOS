# =========================================================
# 900° GYRO WHEEL + PHYSICAL PEDALS MERGED XBOX CONTROLLER
# =========================================================

import socket
import struct
import sys
import vgamepad as vg
import pygame

UDP_PORT = 8080
BUFFER_SIZE = 1024

# --- 1. INITIALIZE PHYSICAL WHEEL/PEDALS FIRST ---
pygame.init()
pygame.joystick.init()

pedal_device = None
num_joysticks = pygame.joystick.get_count()

# Find the physical controller/pedals (skip virtual Xbox controllers)
for i in range(num_joysticks):
    temp_joy = pygame.joystick.Joystick(i)
    device_name = temp_joy.get_name()
    
    if "Xbox" not in device_name:
        pedal_device = temp_joy
        pedal_device.init()
        print(f"✓ Found Physical Device: {device_name} (ID: {i})")
        break

if not pedal_device:
    print("! Physical wheel not detected. Falling back to phone screen pedals.")

# --- 2. INITIALIZE VIRTUAL XBOX CONTROLLER ---
print("Initializing Virtual Xbox Controller...")
try:
    gamepad = vg.VX360Gamepad()
    print("✓ Virtual Xbox 360 Controller connected!")
except Exception as e:
    print("X Error creating virtual controller. Ensure ViGEmBus driver is installed.")
    print(e)
    sys.exit(1)

# --- 3. UDP NETWORK SOCKET ---
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("0.0.0.0", UDP_PORT))

print(f"Server listening for 900° Gyro Wheel packets on UDP port {UDP_PORT}...\n")

# Button Mappings (Bit index -> Xbox Button)
XBOX_BUTTON_MAP = (
    (0, vg.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_SHOULDER),
    (1, vg.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_SHOULDER),
    (2, vg.XUSB_BUTTON.XUSB_GAMEPAD_A),
    (3, vg.XUSB_BUTTON.XUSB_GAMEPAD_B),
    (4, vg.XUSB_BUTTON.XUSB_GAMEPAD_Y),
    (5, vg.XUSB_BUTTON.XUSB_GAMEPAD_X),
    (6, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_UP),
    (7, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_DOWN),
    (8, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_RIGHT),
    (9, vg.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_LEFT),
    (10, vg.XUSB_BUTTON.XUSB_GAMEPAD_BACK),
    (11, vg.XUSB_BUTTON.XUSB_GAMEPAD_START),
)

try:
    while True:
        data, _ = sock.recvfrom(BUFFER_SIZE)
        
        # Validate header and minimum packet length
        if len(data) >= 16 and data[:2] == b'GW':
            # Unpack binary packet from phone
            seq, steering, angle, mask = struct.unpack('<Hffi', data[2:16])
            
            # 1. Map Steering (-1.0 to 1.0) to Xbox Left Stick X
            # Clamp to [-1.0, 1.0] to avoid potential overflow issues
            inverted_steering = max(-1.0, min(1.0, -steering))
            gamepad.left_joystick_float(x_value_float=inverted_steering, y_value_float=0.0)

            # 2. Read Pedals
            if pedal_device:
                pygame.event.pump()  # Refresh hardware input state
                
                num_axes = pedal_device.get_numaxes()
                raw_accel = pedal_device.get_axis(4) if num_axes > 4 else -1.0
                raw_brake = pedal_device.get_axis(5) if num_axes > 5 else -1.0

                # Convert range [-1.0, 1.0] to trigger range [0.0, 1.0]
                accel_val = max(0.0, min(1.0, (raw_accel + 1.0) * 0.5))
                brake_val = max(0.0, min(1.0, (raw_brake + 1.0) * 0.5))

                gamepad.right_trigger_float(value_float=accel_val)
                gamepad.left_trigger_float(value_float=brake_val)
            elif len(data) >= 24:
                # Fallback to phone screen pedals if physical hardware isn't connected
                accel, brake = struct.unpack('<ff', data[16:24])
                gamepad.right_trigger_float(value_float=max(0.0, min(1.0, accel)))
                gamepad.left_trigger_float(value_float=max(0.0, min(1.0, brake)))

            # 3. Process Buttons from Bitmask
            for bit_index, xbox_btn in XBOX_BUTTON_MAP:
                if mask & (1 << bit_index):
                    gamepad.press_button(button=xbox_btn)
                else:
                    gamepad.release_button(button=xbox_btn)

            # Send combined frame state to OS
            gamepad.update()

            print(f"\rAngle: {angle:6.1f}° | Steering Float: {inverted_steering:6.2f} | Seq: {seq}", end="", flush=True)

except KeyboardInterrupt:
    print("\nShutting down server gracefully...")
finally:
    sock.close()
    pygame.quit()