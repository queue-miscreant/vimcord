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

        self._logger = log
        self._really_connected = False
        self._getting_servers = False
        self._need_servers = True
        #keys are server ids, values are dicts of server data
        self._notify = {}
        self._dm_ordering = {}

        setattr(self.connection, "parse_guild_members_chunk", self.parse_guild_members_chunk)
        setattr(self.connection, "parse_user_guild_settings_update", self.parse_user_guild_settings_update)

    async def get_new_servers(self):
        '''Launch request to get new server settings'''
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

            # dictify by channel id
            settings["channel_overrides"] = {channel["channel_id"]: channel \
                for channel in settings.get("channel_overrides", [])}

            self._notify[server.id] = settings

        self._getting_servers = False
        self._need_servers = False
        self.dispatch("servers_ready")

    # TODO:
    # discord handles after nuking discriminators
    # log.debug(data)

    def parse_guild_members_chunk(self, data):
        '''Get new servers on GUILD_MEMBERS_CHUNK'''
        if not self._getting_servers and self._need_servers:
            log.debug("Got first GUILD_MEMBERS_CHUNK; retrieving server data")
            self._getting_servers = True
            self.loop.create_task(self.get_new_servers())
        # pseudo-bound method
        type(self.connection).parse_guild_members_chunk(self.connection, data)

    def parse_user_guild_settings_update(self, data):
        '''Get new mute/notification data'''
        log.debug("Got guild user settings")
        guild_id = data.get("guild_id")

        # dictify by channel id
        data["channel_overrides"] = {channel["channel_id"]: channel \
            for channel in data.get("channel_overrides", [])}

        self._notify[guild_id] = data
        self.dispatch("remote_update")

    async def on_ready(self):
        '''Get DM orderings'''
        direct_messages = await self.http.request(
            discord.http.Route("GET", "/users/@me/channels")
        )
        for channel in direct_messages:
            self._dm_ordering[channel["id"]] = channel["last_message_id"]
        self._really_connected = True
        self.dispatch("really_ready")

    def set_logging_level(self, level):
        '''Method to set the logging levels (for exmample, from a client to the daemon)'''
        if isinstance(logging.getLevelName(level), int):
            self._logger.setLevel(level)
            discord.client.log.setLevel(level)
            return True
        return False
