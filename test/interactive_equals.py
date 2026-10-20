#!/usr/bin/env python3
"""Exercise Readline insertion through a real interactive Bash pseudo-terminal."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import sys
import termios
import time

ROOT = Path(__file__).resolve().parent.parent
BASH = shutil.which("bash")
PROMPT = b"BETTEROPTS_PTY> "
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "dumb"
    os.execv(BASH, [BASH, "--noprofile", "--norc", "-i"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 240, 0, 0))


def read_until(marker, timeout=10):
    data = b""
    deadline = time.monotonic() + timeout
    while not data.endswith(marker):
        if time.monotonic() > deadline:
            raise AssertionError(f"Timed out waiting for {marker!r}: {data!r}")
        if select.select([fd], [], [], 0.1)[0]:
            try:
                chunk = os.read(fd, 65536)
            except OSError as exc:
                if exc.errno == errno.EIO:
                    chunk = b""
                else:
                    raise
            if not chunk:
                raise AssertionError(f"Bash exited: {data!r}")
            data += chunk
    return data


def send(text):
    os.write(fd, text.encode())


def check(arguments, expected):
    send(f'{ROOT}/test/fixtures/equals_fields {arguments}\n')
    output = read_until(PROMPT).decode(errors="replace").replace("\r", "")
    assert "count=1\n" in output, output
    assert f"value={expected}\n" in output, output
    print(f"ok: {arguments!r} -> {expected!r}")


try:
    read_until(b"$ ")
    send(f"PS1='{PROMPT.decode()}'; source '{ROOT}/betteropts.sh'; "
         f"complete -F _bo_bash_completion -o nosort '{ROOT}/test/fixtures/equals_fields'\n")
    read_until(PROMPT)
    check("--set k\tto\t", "topic")
    check("--set kind=to\t", "topic")
    check("-s kind=to\t", "topic")
    check("--set=kind=to\t", "topic")
    check("--set kind=with=\t", "with=equals")
    check("--set kind==le\t", "=leading")
    check("--set kind=value\t", "value with spaces")
    check("--set kind=sh\t", "shell;$(false)*")
    # Readline still uses the same whole-token contract without '=' word breaks.
    send("saved_breaks=$COMP_WORDBREAKS; COMP_WORDBREAKS=${COMP_WORDBREAKS//=}\n")
    read_until(PROMPT)
    check("--set=kind=to\t", "topic")
    send("COMP_WORDBREAKS=$saved_breaks\n")
    read_until(PROMPT)
    send("dump_line() { printf '\\nCURRENT:%s\\n' \"$READLINE_LINE\"; READLINE_LINE=; READLINE_POINT=0; }; "
         "bind -x '\"\\C-x!\":dump_line'\n")
    read_until(PROMPT)
    for partial in ['--set "ki', '--set kind="to', r'--set kind=value\ w', '--set kind=scheme:va']:
        original = f"{ROOT}/test/fixtures/equals_fields {partial}"
        send(original + "\t\x18!")
        output = read_until(PROMPT)
        assert ("CURRENT:" + original + "\r\n").encode() in output, output
        print(f"observed unchanged unsupported prefix: {partial!r}")
    print("Interactive equals completion passed.")
finally:
    os.kill(pid, signal.SIGTERM)
    os.close(fd)
    os.waitpid(pid, 0)
