"""
GyroSteer Windows receiver

Listens for the iPhone app over WebSocket and keeps the Android app's binary
UDP protocol working on the same port. Maps both inputs to a ViGEm virtual
Xbox 360 controller.

Requirements:
    Windows 10/11
    ViGEmBus driver
    python -m pip install vgamepad pygame websockets

Run:
    python gyrosteer_pc_receiver.py
"""

import asyncio
import json
import socket
import struct
import time

import pygame
import vgamepad as vg
import websockets

PORT = 8080
BUFFER_SIZE = 1024

BUTTON_MAP = (
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


def get_local_ip():
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        probe.connect(("8.8.8.8", 80))
        return probe.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        probe.close()


pygame.init()
pygame.joystick.init()
pedal_device = None
for device_index in range(pygame.joystick.get_count()):
    candidate = pygame.joystick.Joystick(device_index)
    if "Xbox" not in candidate.get_name():
        candidate.init()
        pedal_device = candidate
        print(f"Physical pedals/controller: {candidate.get_name()}")
        break

print("Starting virtual Xbox 360 controller...")
try:
    gamepad = vg.VX360Gamepad()
    print("Virtual Xbox controller ready.")
except Exception as error:
    print("Could not create the virtual controller.")
    print("Install ViGEmBus, then restart Windows and run this script again.")
    raise SystemExit(1) from error

last_log_time = 0.0


def clamp(value, low, high):
    return max(low, min(high, value))


def update_gamepad(steering, angle, mask, accel, brake, source):
    global last_log_time

    steering = clamp(float(steering), -1.0, 1.0)
    angle = float(angle)
    mask = int(mask)
    accel = clamp(float(accel), 0.0, 1.0)
    brake = clamp(float(brake), 0.0, 1.0)

    # A real pedal set takes precedence; otherwise use the phone's touch pedals.
    if pedal_device is not None:
        pygame.event.pump()
        axis_count = pedal_device.get_numaxes()
        raw_accel = pedal_device.get_axis(4) if axis_count > 4 else -1.0
        raw_brake = pedal_device.get_axis(5) if axis_count > 5 else -1.0
        accel = clamp((raw_accel + 1.0) * 0.5, 0.0, 1.0)
        brake = clamp((raw_brake + 1.0) * 0.5, 0.0, 1.0)

    # Match the original receiver's steering inversion.
    gamepad.left_joystick_float(x_value_float=-steering, y_value_float=0.0)
    gamepad.right_trigger_float(value_float=accel)
    gamepad.left_trigger_float(value_float=brake)

    for bit_index, xbox_button in BUTTON_MAP:
        if mask & (1 << bit_index):
            gamepad.press_button(button=xbox_button)
        else:
            gamepad.release_button(button=xbox_button)

    gamepad.update()

    now = time.monotonic()
    if now - last_log_time > 0.15:
        print(
            f"\r{source:4} | angle {angle:+7.1f}°"
            f" | steer {-steering:+.3f} | accel {accel:.2f}"
            f" | brake {brake:.2f} | buttons 0x{mask:03X}",
            end="",
            flush=True,
        )
        last_log_time = now


def release_gamepad():
    gamepad.left_joystick_float(x_value_float=0.0, y_value_float=0.0)
    gamepad.right_trigger_float(value_float=0.0)
    gamepad.left_trigger_float(value_float=0.0)
    for _, xbox_button in BUTTON_MAP:
        gamepad.release_button(button=xbox_button)
    gamepad.update()


def decode_android_packet(data):
    if len(data) < 16 or data[:2] != b"GW":
        return None
    sequence, steering, angle, mask = struct.unpack("<Hffi", data[2:16])
    accel = 0.0
    brake = 0.0
    if len(data) >= 24:
        accel, brake = struct.unpack("<ff", data[16:24])
    return sequence, steering, angle, mask, accel, brake


class AndroidUdpReceiver(asyncio.DatagramProtocol):
    def datagram_received(self, data, address):
        try:
            packet = decode_android_packet(data)
            if packet is None:
                return
            _, steering, angle, mask, accel, brake = packet
            update_gamepad(steering, angle, mask, accel, brake, "UDP")
        except (ValueError, struct.error, TypeError) as error:
            print(f"\nIgnored invalid Android packet from {address}: {error}")


def parse_button_mask(value):
    if isinstance(value, int):
        return value
    if isinstance(value, list):
        names = {button[0]: button[1] for button in (
            ("SHIFT_DOWN", 1 << 0),
            ("SHIFT_UP", 1 << 1),
            ("NITRO", 1 << 2),
            ("HANDBRAKE", 1 << 3),
            ("DRS", 1 << 4),
            ("HORN", 1 << 5),
            ("TC_PLUS", 1 << 6),
            ("TC_MINUS", 1 << 7),
            ("ABS_PLUS", 1 << 8),
            ("ABS_MINUS", 1 << 9),
            ("PIT", 1 << 10),
            ("PAUSE", 1 << 11),
        )}
        result = 0
        for name in value:
            result |= names.get(str(name), 0)
        return result
    if isinstance(value, str):
        try:
            return int(value, 0)
        except ValueError:
            return parse_button_mask(
                [part.strip() for part in value.split(",") if part.strip()]
            )
    return 0


async def handle_iphone_client(websocket, path=None):
    remote = getattr(websocket, "remote_address", "unknown")
    print(f"\n iPhone connected: {remote}")
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                steering = data.get("steering", data.get("axis", 0.0))
                angle = data.get("angle", 0.0)
                mask = parse_button_mask(data.get("buttons", data.get("mask", 0)))
                accel = data.get("accel", data.get("throttle", 0.0))
                brake = data.get("brake", 0.0)
                update_gamepad(steering, angle, mask, accel, brake, "iOS")
            except (json.JSONDecodeError, ValueError, TypeError) as error:
                print(f"\n Ignored invalid iPhone packet: {error}")
    except websockets.ConnectionClosed:
        pass
    finally:
        release_gamepad()
        print("\n iPhone disconnected; controller inputs released.")


async def main():
    loop = asyncio.get_running_loop()
    udp_transport, _ = await loop.create_datagram_endpoint(
        AndroidUdpReceiver,
        local_addr=("0.0.0.0", PORT),
    )

    local_ip = get_local_ip()
    print("=" * 64)
    print("GYROSTEER PC RECEIVER")
    print(f"PC address for the iPhone app: {local_ip}")
    print(f"WebSocket (iPhone): ws://{local_ip}:{PORT}")
    print(f"UDP (Android):      {local_ip}:{PORT}")
    print("Keep this window open. Both devices must use the same Wi-Fi.")
    print("=" * 64)

    try:
        async with websockets.serve(
            handle_iphone_client,
            "0.0.0.0",
            PORT,
            ping_interval=15,
            ping_timeout=15,
            max_size=2048,
        ):
            await asyncio.Future()
    finally:
        udp_transport.close()
        release_gamepad()
        pygame.quit()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nReceiver stopped.")