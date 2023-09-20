import asyncio
import os
import os.path
import signal
import shlex
import sys
import subprocess
import logging

from vimcord.pickle_pipe import PickleClientProtocol

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

async def connect_to_daemon(path, log):
    '''
    Connect to the daemon connected to Discord.
    Spawn the daemon, if it doesn't exist.

    Returns 2-tuple of whether the daemon had to be started and the
    PickleClientProtocol for communicating with it.
    '''
    server_running = os.path.exists(path) and \
            os.system(f"lsof {shlex.quote(os.path.join(path, 'socket'))}") == 0
    if not server_running:
        log.debug("Spawning daemon...")
        # add the plugin to the python path
        vimcord_dir = os.path.dirname(__file__)
        for _ in range(2):
            vimcord_dir = os.path.dirname(vimcord_dir)
        subprocess.Popen(
            [sys.executable, os.path.dirname(__file__), path],
            env={"PYTHONPATH": vimcord_dir}
        )

    log.debug("Connecting to daemon...")
    ret = None
    while True:
        try:
            _, ret = await asyncio.get_running_loop().create_unix_connection(
                PickleClientProtocol,
                path=os.path.join(path, "socket")
            )
            break
        except (FileNotFoundError, ConnectionRefusedError, NotADirectoryError):
            await asyncio.sleep(1)
    log.debug("Connected to daemon process!")

    return not server_running, ret

def kill_server(path):
    with open(os.path.join(path, "pid")) as pid_file:
        try:
            os.kill(int(pid_file.read()), signal.SIGTERM)
        except ValueError:
            pass
