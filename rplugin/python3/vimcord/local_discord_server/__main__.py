import asynci
import os
import os.path
import logging
import logging.handlers
import sys
import traceback

import vimcord.pickle_pipe as pickle_pipe
from vimcord.local_discord_server.discord_client import VimcordClient

log = logging.getLogger(__package__)
log.setLevel("ERROR")
pickle_pipe.log.setLevel("ERROR")

CREATED_PROTOCOLS = []

def _handle_exception(loop, context):
    exception = context.get("exception")
    if sys.version_info >= (3, 10):
        formatted = traceback.format_exception(exception)
        log.error("Error occurred:\n%s", "".join(formatted))
    elif hasattr(exception, "__traceback__"):
        formatted = traceback.format_exception(
            type(exception),
            exception,
            exception.__traceback__
        )
    else:
        formatted = "(Could not get stack trace)"
    # broadcast the error to clients (i.e., so they can tell it to reconnect)
    deletions = []
    for i, protocol in enumerate(CREATED_PROTOCOLS):
        if protocol.transport is None or protocol.transport.is_closing():
            deletions.append(i)
            continue
        if (exc := context.get("exception")) is not None:
            protocol.write_error(exc)

    for deletion in reversed(deletions):
        del CREATED_PROTOCOLS[deletion]

DISCORD_EVENT_NAMES = [
    "call",
    "call_remove",
    "call_update",
    "channel_create",
    "channel_delete",
    "channel_update",
    "dm_update",
    "group_join",
    "group_remove",
    "member_ban",
    "member_join",
    "member_remove",
    "member_unban",
    "member_update",
    "message",
    "message_delete",
    "message_edit",
    "reaction_add",
    "reaction_clear",
    "reaction_remove",
    ("really_ready", "ready"),
    "remote_update", # not a Discord event; used to send daemon data to clients
    "resumed",
    "servers_ready",
    "server_available",
    "server_emojis_update",
    "server_join",
    "server_remove",
    "server_role_create",
    "server_role_delete",
    "server_role_update",
    "server_unavailable",
    "server_update",
    "typing",
    "voice_state_update",
]

def bind_discord_pickle(discord_client):
    protocol = pickle_pipe.PickleServerProtocol(discord_client)

    for e in DISCORD_EVENT_NAMES:
        if isinstance(e, tuple):
            event_name, discord_event_name = e
        else:
            event_name, discord_event_name = e, "on_" + e
        handler = protocol.get_event_handler(event_name)
        handler.__name__ = discord_event_name
        discord_client.event(handler)

    CREATED_PROTOCOLS.append(protocol)
    return protocol

async def _start_server(pipe_file):
    client = VimcordClient()
    server = await asyncio.get_event_loop().create_unix_server(
        lambda: bind_discord_pickle(client),
        path=os.path.join(pipe_file, "socket")
    )

    async with server:
        log.debug("Server created. Serving!")
        await server.serve_forever()

def start_server(pipe_file_dir):
    '''Spawn a daemon process running start_server'''
    # need to make the directory
    if not os.path.isdir(pipe_file_dir):
        # remove a file if it's there already
        if os.path.exists(pipe_file_dir):
            os.remove(pipe_file_dir)
        os.mkdir(pipe_file_dir)

    handler = logging.handlers.RotatingFileHandler(
        filename=os.path.join(pipe_file_dir, "daemon.log"),
        maxBytes=2**16,
        backupCount=1
    )
    handler.setFormatter(
        logging.Formatter("%(asctime)s " + logging.BASIC_FORMAT)
    )
    logging.basicConfig(handlers=[handler], force=True)

    # dinner time
    pid = os.fork()
    if pid > 0:
        return

    # in first child
    os.setsid()
    pid = os.fork()
    if pid > 0:
        os._exit(0)

    # in second child
    loop = asyncio.get_event_loop()
    loop.set_exception_handler(_handle_exception)

    with open(os.path.join(pipe_file_dir, "pid"), "w") as pid_file:
        pid_file.write(str(os.getpid()))

    try:
        loop.run_until_complete(_start_server(pipe_file_dir))
    except Exception as e:
        log.error("Daemon exiting: %s", e)
    finally:
        # remove the pid file
        pid_file = os.path.join(pipe_file_dir, "pid")
        if os.path.exists(pid_file):
            os.remove(pid_file)
        os._exit(0)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        start_server(sys.argv[1])
    else:
        print("Could not start daemon!")
