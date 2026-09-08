#!/usr/bin/env python3
"""Run on MiSTer with the diagnostic echo ROM and Serial CTS: Host RTS.
Restores tty settings and modem-control outputs on exit. Does not start services.
"""
import array
import fcntl
import os
import select
import termios
import time
import tty

fd = os.open('/dev/ttyS1', os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
original = termios.tcgetattr(fd)
modem = array.array('i', [0])
fcntl.ioctl(fd, termios.TIOCMGET, modem, True)
original_modem = modem[0]

def set_modem(bits):
    fcntl.ioctl(fd, termios.TIOCMSET, array.array('i', [bits]))

def receive(count, timeout=3):
    result = bytearray()
    deadline = time.monotonic() + timeout
    while len(result) < count and time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], max(0, deadline-time.monotonic()))
        if ready:
            result.extend(os.read(fd, count-len(result)))
    return bytes(result)

def send(data):
    pending = memoryview(data)
    while pending:
        _, ready, _ = select.select([], [fd], [], 3)
        if not ready:
            raise TimeoutError('UART write timeout')
        pending = pending[os.write(fd, pending):]
    termios.tcdrain(fd)

try:
    tty.setraw(fd, termios.TCSANOW)
    settings = termios.tcgetattr(fd)
    settings[2] = (settings[2] & ~(termios.PARENB | termios.CSTOPB | termios.CSIZE | termios.CRTSCTS)) | termios.CS8 | termios.CLOCAL | termios.CREAD
    settings[4] = settings[5] = termios.B19200
    termios.tcsetattr(fd, termios.TCSANOW, settings)
    set_modem(original_modem | termios.TIOCM_RTS | termios.TIOCM_DTR)
    termios.tcflush(fd, termios.TCIOFLUSH)
    time.sleep(0.1)
    total = 0
    for repeat in range(16):
        for start in range(0, 256, 64):
            payload = bytes(range(start, start+64))
            send(payload)
            actual = receive(len(payload))
            if actual != payload:
                raise RuntimeError(f'echo mismatch at {total}: expected {payload.hex()}, received {actual.hex()}')
            total += len(payload)
    print(f'PASS MiSTer HPS UART -> 6551 -> T65 IRQ handler -> 6551 -> HPS: {total} bytes, all 256 values, 19200 8N1', flush=True)
    # Deassert HPS RTS, which is the FPGA's active-low CTS input.
    set_modem((original_modem | termios.TIOCM_DTR) & ~termios.TIOCM_RTS)
    time.sleep(0.02)
    payload = bytes(range(64))
    send(payload)
    actual = receive(1, 0.1)
    if actual:
        raise RuntimeError(f'CTS backpressure failed: {actual.hex()}')
    set_modem(original_modem | termios.TIOCM_RTS | termios.TIOCM_DTR)
    actual = receive(len(payload))
    if actual != payload:
        raise RuntimeError(f'CTS resume mismatch: {actual.hex()}')
    print('PASS MiSTer RTS/FPGA CTS: transmission pauses and resumes all 64 queued bytes', flush=True)
finally:
    termios.tcsetattr(fd, termios.TCSANOW, original)
    set_modem(original_modem)
    os.close(fd)
