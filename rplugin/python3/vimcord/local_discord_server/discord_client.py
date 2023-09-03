import asyncio
import logging
import json
import time

import vimcord.discord as discord

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

def is_current(timestr):
    '''Retrieves whether the date encoded by the time string is in the future'''
    if isinstance(timestr, int) and timestr < 0 or timestr is None:
        return True
    return time.mktime(time.strptime(timestr.split(".")[0], "%Y-%m-%dT%H:%M:%S")) > time.time()

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
                break

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
        log.debug("REALLY READY")
        self.dispatch("really_ready")

    def is_muted(self, server, channel):
        '''Check if a channel is muted, per its settings'''
        try:
            settings = self._notify[server.id]
            if "channel_overrides" not in settings \
            or channel.id not in settings["channel_overrides"]:
                # this server has no channel overrides, or there are none for this channel
                return settings["muted"] and (
                    settings["mute_config"] is None or
                    is_current(settings["mute_config"]["end_time"])
                )

            # defer to channel overrides
            local_settings = settings["channel_overrides"][channel.id]
            return local_settings["muted"] and (
                local_settings["mute_config"] is None or
                is_current(local_settings["mute_config"]["end_time"])
            )
        except KeyError:
            return True

    def unmuted_channels(self):
        '''Get a list of channels (and private messages) which are unmuted'''
        ret = [["Private Messages", *sorted(
            self.private_channels,
            key=lambda x: self._dm_ordering.get(x.id, "") or "",
            reverse=True
        )]]
        for server in self.servers:
            me_in_server = server.get_member(self.user.id)
            if me_in_server is None:
                continue
            server_channels = [server.name]
            # settings = self._notify[server.id] \
            #     if server.id in self._notify else {"muted": False}
            for channel in server.channels:
                visible = channel.permissions_for(me_in_server).read_messages \
                    if channel.server.owner is not None else False
                try:
                    if channel.type != discord.ChannelType.text \
                    or not visible \
                    or self.is_muted(server, channel):
                        continue
                except KeyError:
                    pass
                server_channels.append(channel)
            ret.append(server_channels)
        return ret
