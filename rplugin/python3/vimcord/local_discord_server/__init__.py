import asyncio
import os
import os.path
import logging
import signal

from vimcord.pickle_pipe import PickleServerProtocol
from vimcord.local_discord_server.discord_client import VimcordClient

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

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

def bind_discord_pickle(discord_client, log):
    protocol = PickleServerProtocol(discord_client, log)

    for e in DISCORD_EVENT_NAMES:
        if isinstance(e, tuple):
            event_name, discord_event_name = e
        else:
            event_name, discord_event_name = e, "on_" + e
        handler = protocol.get_event_handler(event_name)
        handler.__name__ = discord_event_name
        discord_client.event(handler)

    return protocol

async def start_server(log, pipe_file):
    client = VimcordClient()
    server = await asyncio.get_event_loop().create_unix_server(
        lambda: bind_discord_pickle(client, log),
        path=pipe_file
    )

    async with server:
        log.debug("Server created. Serving!")
        await server.serve_forever()

def spawn_daemon(pipe_file):
    '''Spawn a daemon process running start_server'''
    pid = os.fork()
    if pid > 0:
        return pid

    # in first child
    os.setsid()
    pid = os.fork()
    if pid > 0:
        log.debug("Child pid: %d", pid)
        os._exit(0)

    # in second child
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    try:
        loop.run_until_complete(start_server(log, pipe_file))
    except Exception as e:
        log.error("Daemon exited: %s", e)
    finally:
        if os.path.exists(pipe_file):
            os.remove(pipe_file)
        os._exit(0)
