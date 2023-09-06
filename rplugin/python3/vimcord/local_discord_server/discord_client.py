import asyncio
import logging
import json
import time

import vimcord.discord as discord

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

class VimcordClient(discord.Client):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)

        self._really_connected = False
        self._getting_servers = False
        #keys are server ids, values are dicts of server data
        self._notify = {}
        self._dm_ordering = {}

    async def get_new_servers(self):
        '''Launch request to get new server settings'''
        if self._getting_servers:
            return
        self._getting_servers = True
        log.info("Number servers: %d", len(self.servers))
        log.info("Server list: %s", list(map(str, self.servers)))
        for server in self.servers:
            if server.id in self._notify:
                continue
            settings = await self.http.request(
                discord.http.Route(
                    "PATCH",
                    "/users/@me/guilds/{server_id}/settings",
                    server_id=server.id
                ),
                json={}
            )
            if settings is None:
                settings = {"muted": False}

            settings["channel_overrides"] = {channel["channel_id"]: channel \
                for channel in settings.get("channel_overrides", [])}

            self._notify[server.id] = settings

        self._getting_servers = False
        self.dispatch("servers_ready")

    async def on_socket_raw_receive(self, data):
        '''Get new servers on GUILD_MEMBERS_CHUNK'''
        try:
            if json.loads(data)["t"] != "GUILD_MEMBERS_CHUNK":
                return
        except ValueError:
            return

        self.loop.create_task(self.get_new_servers())

    async def on_ready(self):
        '''Get DM orderings'''
        direct_messages = await self.http.request(
            discord.http.Route("GET", "/users/@me/channels")
        )
        for channel in direct_messages:
            self._dm_ordering[channel["id"]] = channel["last_message_id"]
        self._really_connected = True
        self.dispatch("really_ready")
