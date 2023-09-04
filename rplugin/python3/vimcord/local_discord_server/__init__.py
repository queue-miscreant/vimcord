import asyncio
import os
import os.path
import shlex

from vimcord.pickle_pipe import PickleClientProtocol
from vimcord.local_discord_server.server import start_server

def spawn_daemon(func, *args):
    '''Spawn a daemon process running start_server'''
    pid = os.fork()
    if pid > 0:
        return

    # in first child
    os.setsid()
    pid = os.fork()
    if pid > 0:
        os._exit(0)

    # in second child
    func(*args)

async def connect_to_daemon(path, log):
    '''
    Connect to the daemon connected to Discord.
    Spawn the daemon, if it doesn't exist.

    Returns 2-tuple of whether the daemon had to be started and the
    PickleClientProtocol for communicating with it.
    '''
    server_running = os.path.exists(path) and os.system(f"lsof {shlex.quote(path)}") == 0
    if not server_running:
        log.debug("Spawning daemon...")
        spawn_daemon(start_server, path)

    log.debug("Connecting to daemon...")
    ret = None
    while True:
        try:
            _, ret = await asyncio.get_running_loop().create_unix_connection(
                PickleClientProtocol,
                path=path
            )
            break
        except (FileNotFoundError, ConnectionRefusedError):
            await asyncio.sleep(1)
    log.debug("Connected to daemon process!")

    return not server_running, ret

# TODO: save the pid in a file next to the socket
# TODO: don't use sigkill
def kill_server(path):
    os.system(f"lsof {shlex.quote(path)} | tail -1 | cut -d' ' -f 2 | xargs kill -s SIGKILL")
