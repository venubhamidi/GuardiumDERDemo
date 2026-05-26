#!/usr/bin/env python3
"""
Send keystrokes to a VNC server (VMware Fusion VM console).
Used for automating MokManager during boot - no pip dependencies needed.

Usage:
    python3 vnc_keys.py <host> <port> key <key1> [key2] ...
    python3 vnc_keys.py <host> <port> type <text>
    python3 vnc_keys.py <host> <port> sleep <seconds>

Keys: return, space, up, down, left, right, escape, tab, backspace
      Or any single character (a-z, 0-9, etc.)

Examples:
    python3 vnc_keys.py localhost 5901 key space
    python3 vnc_keys.py localhost 5901 key down return
    python3 vnc_keys.py localhost 5901 type Demo1234
"""

import socket
import struct
import sys
import time

# X11 keysyms
KEYSYMS = {
    'return': 0xff0d, 'enter': 0xff0d, 'ret': 0xff0d,
    'space': 0x0020, 'spc': 0x0020,
    'up': 0xff52, 'down': 0xff54,
    'left': 0xff51, 'right': 0xff53,
    'escape': 0xff1b, 'esc': 0xff1b,
    'tab': 0xff09,
    'backspace': 0xff08,
    'shift': 0xffe1, 'shift_l': 0xffe1,
    'ctrl': 0xffe3, 'ctrl_l': 0xffe3,
    'alt': 0xffe9, 'alt_l': 0xffe9,
    'f1': 0xffbe, 'f2': 0xffbf, 'f3': 0xffc0, 'f4': 0xffc1,
    'f5': 0xffc2, 'f6': 0xffc3, 'f7': 0xffc4, 'f8': 0xffc5,
    'delete': 0xffff,
}


def vnc_connect(host, port):
    """Connect to VNC server and complete handshake."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(3)
    sock.connect((host, port))

    # Server version
    version = sock.recv(12)

    # Send version (3.8)
    sock.send(b'RFB 003.008\n')

    # Security types
    num_types = struct.unpack('B', sock.recv(1))[0]
    if num_types == 0:
        # Error
        err_len = struct.unpack('>I', sock.recv(4))[0]
        err_msg = sock.recv(err_len).decode()
        raise Exception(f"VNC error: {err_msg}")

    types = list(sock.recv(num_types))

    # Prefer None (1), then VNC Auth (2)
    if 1 in types:
        sock.send(struct.pack('B', 1))  # None
    else:
        raise Exception(f"VNC requires authentication (types: {types})")

    # Security result
    result = struct.unpack('>I', sock.recv(4))[0]
    if result != 0:
        raise Exception("VNC security handshake failed")

    # ClientInit (shared=1)
    sock.send(struct.pack('B', 1))

    # ServerInit
    header = sock.recv(24)
    name_len = struct.unpack('>I', header[20:24])[0]
    if name_len > 0:
        sock.recv(name_len)

    return sock


def send_key_event(sock, keysym, down):
    """Send a single key event (press or release)."""
    msg = struct.pack('>BBxxI', 4, 1 if down else 0, keysym)
    sock.send(msg)


def press_key(sock, key_name, delay=0.05):
    """Press and release a key."""
    if key_name in KEYSYMS:
        keysym = KEYSYMS[key_name]
    elif len(key_name) == 1:
        keysym = ord(key_name)
    else:
        raise ValueError(f"Unknown key: {key_name}")

    send_key_event(sock, keysym, True)
    time.sleep(delay)
    send_key_event(sock, keysym, False)
    time.sleep(delay)


SHIFT_CHARS = {
    '_': '-', '!': '1', '@': '2', '#': '3', '$': '4',
    '%': '5', '^': '6', '&': '7', '*': '8', '(': '9',
    ')': '0', '+': '=', '{': '[', '}': ']', '|': '\\',
    ':': ';', '"': "'", '<': ',', '>': '.', '?': '/',
    '~': '`',
}


def type_string(sock, text, delay=0.1):
    """Type a string, handling uppercase and shifted characters."""
    for char in text:
        if char.isupper() or char in SHIFT_CHARS:
            send_key_event(sock, KEYSYMS['shift'], True)
            time.sleep(0.05)
            base = SHIFT_CHARS[char] if char in SHIFT_CHARS else char.lower()
            press_key(sock, base, delay)
            send_key_event(sock, KEYSYMS['shift'], False)
            time.sleep(0.05)
        elif char == ' ':
            press_key(sock, 'space', delay)
        else:
            press_key(sock, char, delay)
        time.sleep(delay)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)

    host = sys.argv[1]
    port = int(sys.argv[2])
    cmd = sys.argv[3]

    sock = vnc_connect(host, port)

    try:
        if cmd == 'key':
            for key_name in sys.argv[4:]:
                press_key(sock, key_name)
                time.sleep(0.15)
        elif cmd == 'type':
            text = ' '.join(sys.argv[4:])
            type_string(sock, text)
        elif cmd == 'sleep':
            time.sleep(float(sys.argv[4]))
        else:
            print(f"Unknown command: {cmd}")
            sys.exit(1)
    finally:
        sock.close()


if __name__ == '__main__':
    main()
