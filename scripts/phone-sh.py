#!/usr/bin/env python3
"""Run a shell command on the phone's mainline initramfs.

The initramfs serves a raw shell with `nc -lk -p 23 -e sh` on 172.16.42.1
(USB NCM); telnet negotiation is handled too, in case a real telnetd is used.
This sends one command, waits for it to finish and prints its output.

Usage: scripts/phone-sh.py 'dmesg | tail' [--timeout SECONDS]
Host side needs 172.16.42.2/24 on the USB interface (see README).
"""
import argparse
import re
import socket
import sys
import time

IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240
MARK = "__NX809J_DONE__"


def strip_telnet(sock, data: bytes) -> bytes:
    """Drop telnet negotiation, refusing every option the server asks for."""
    out, i = bytearray(), 0
    while i < len(data):
        b = data[i]
        if b != IAC:
            out.append(b); i += 1; continue
        if i + 1 >= len(data):
            break
        cmd = data[i + 1]
        if cmd in (DO, DONT, WILL, WONT) and i + 2 < len(data):
            opt = data[i + 2]
            if cmd == DO:
                sock.sendall(bytes([IAC, WONT, opt]))
            elif cmd == WILL:
                sock.sendall(bytes([IAC, DONT, opt]))
            i += 3
        elif cmd == SB:
            end = data.find(bytes([IAC, SE]), i)
            i = len(data) if end < 0 else end + 2
        else:
            i += 2
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("command")
    ap.add_argument("--host", default="172.16.42.1")
    ap.add_argument("--port", type=int, default=23)
    ap.add_argument("--timeout", type=float, default=30)
    args = ap.parse_args()

    sock = socket.create_connection((args.host, args.port), timeout=5)
    sock.settimeout(0.3)
    # Echo the marker via printf so the echoed command line doesn't match it
    cmd = f"{{ {args.command} ; }} 2>&1; printf '%s\\n' '{MARK[:6]}''{MARK[6:]}'\n"
    time.sleep(0.5)
    sock.sendall(cmd.encode())

    buf, deadline = b"", time.time() + args.timeout
    while time.time() < deadline:
        try:
            chunk = sock.recv(65536)
        except socket.timeout:
            continue
        if not chunk:
            break
        buf += strip_telnet(sock, chunk)
        if MARK.encode() in buf:
            break
    else:
        print("[phone-sh] timed out", file=sys.stderr)
    sock.close()

    text = buf.decode(errors="replace").replace("\r", "")
    text = re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", text)  # terminal escapes
    lines = text.split("\n")
    # Drop the echoed command line(s) and everything from the marker on
    try:
        end = next(i for i, l in enumerate(lines) if l.strip() == MARK)
    except StopIteration:
        end = len(lines)
    start = next((i + 1 for i, l in enumerate(lines[:end]) if MARK[:6] in l), 0)
    print("\n".join(lines[start:end]).rstrip())


main()
