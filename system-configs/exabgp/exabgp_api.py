#!/usr/bin/env python3
"""ExaBGP API helper - reads commands from FIFO and writes to stdout."""
import os
import sys
import select
import time

FIFO = '/opt/exabgp/exabgp.cmd'

# Open FIFO for reading (non-blocking to avoid deadlock)
# We need to also open write end to prevent EOF when no writer
fd = os.open(FIFO, os.O_RDONLY | os.O_NONBLOCK)
# Keep a write fd open so the pipe doesn't get EOF
wfd = os.open(FIFO, os.O_WRONLY | os.O_NONBLOCK)

buf = b''
while True:
    try:
        r, _, _ = select.select([fd], [], [], 1.0)
        if r:
            data = os.read(fd, 65536)
            if data:
                buf += data
                while b'\n' in buf:
                    line, buf = buf.split(b'\n', 1)
                    cmd = line.decode('utf-8', errors='replace').strip()
                    if cmd:
                        print(cmd, flush=True)
    except (IOError, OSError):
        time.sleep(0.1)
