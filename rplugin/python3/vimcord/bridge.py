import asyncio
import logging
import time

import vimcord.discord as discord
import vimcord.local_discord_server as local_discord_server
from vimcord.formatting import format_channel, clean_post, extmark_post
from vimcord.links import get_link_content, LINK_RE

log = logging.getLogger(__name__)
log.setLevel("INFO")

def is_current(timestr):
    '''Retrieves whether the date encoded by the time string is in the future'''
    if isinstance(timestr, int) and timestr < 0 or timestr is None:
        return True
    return time.mktime(time.strptime(timestr.split(".")[0], "%Y-%m-%dT%H:%M:%S")) > time.time()

class DiscordBridge:
    '''
    Manage global state related to things other than discord
    '''
    def __init__(self, plugin):
        self.plugin = plugin
        self.discord_pipe = None

        self._buffer = plugin.nvim.lua.vimcord.init()

        self._last_channel = None
        self.all_messages = {}
        self.visited_links = set()

        # server properties that need refreshed rarely, but get used for unmuted channels/is muted
        self._user = None
        self._dm_ordering = {}
        self._notify = {}
        self._servers = []
        self._private_channels = []

        plugin.nvim.loop.create_task(
            self.start_discord_client_server(plugin.socket_path)
        )

    async def get_remote_attributes(self):
        '''Refresh rarely-updated members from the daemon'''
        self._user = await self.discord_pipe.awaitable.user()
        self._dm_ordering = await self.discord_pipe.awaitable._dm_ordering()
        self._notify = await self.discord_pipe.awaitable._notify()
        self._servers = await self.discord_pipe.awaitable.servers()
        self._private_channels = await self.discord_pipe.awaitable.private_channels()

    async def start_discord_client_server(self, path):
        '''Spawn a local discord server as a daemon and set the discord pipe object'''
        _, self.discord_pipe = await local_discord_server.connect_to_daemon(path, log)

        # bind events
        self.discord_pipe.event("servers_ready", self.on_ready)
        self.discord_pipe.event("message", self.on_message)
        self.discord_pipe.event("message_edit", self.on_message_edit)
        self.discord_pipe.event("message_delete", self.on_message_delete)
        self.discord_pipe.event("dm_update", self.on_dm_update)

        await self.preamble()

    async def preamble(self):
        '''
        When connecting to the daemon, check if the user is logged in and
        whether a connection has been established.
        '''
        is_logged_in = await self.discord_pipe.awaitable.is_logged_in()
        if not is_logged_in:
            log.info("Not logged in! Attempting to login and start discord connection...")
            self.discord_pipe.task.start(
                self.plugin.discord_username,
                self.plugin.discord_password
            )
        else:
            is_not_connected = await self.discord_pipe.awaitable.is_closed()
            if is_not_connected:
                log.info("Not connected to discord! Attempting to reconnect...")
                self.discord_pipe.task.connect()
            else:
                self.plugin.nvim.loop.create_task(self.on_ready())

    @property
    def all_members(self):
        return {server.id: [
                member.display_name for member in server.members
            ]
            for server in self._servers}

    def get_channel_by_name(self, channel_name):
        for channel in self.unmuted_channels:
            if channel_name == format_channel(channel, raw=True):
                return channel
        return None

    def visit_link(self, link):
        '''Add a link to the set of visited links and issue a recolor to the buffer'''
        unvisited = []
        if isinstance(link, str):
            match = LINK_RE.match(link.replace("\n", "").replace("\x1b", ""))
            if not match:
                # TODO: error
                return
            link = [match.group(1)]

        if isinstance(link, list):
            unvisited = [l
                for l in link
                if l not in self.visited_links and LINK_RE.match(l)]
            self.visited_links.union(link)
        else:
            raise ValueError("Can only visit links of type string or list!")

        if unvisited:
            self.plugin.nvim.lua.vimcord.recolor_visited_links(
                self._buffer,
                unvisited
            )

    async def add_link_extmarks(self, message_id, links):
        '''
        Asynchronously generate extmarks to a list of links, then call vim
        function to add them.
        '''
        formatted_opengraph = await asyncio.gather(*[
            get_link_content(link) for link in links
        ])
        # flatten results
        # TODO: intercalate?
        formatted_opengraph = [j for i in formatted_opengraph for j in i]

        if formatted_opengraph:
            self.plugin.nvim.async_call(
                lambda x,y,z: self.plugin.nvim.api.call_function(
                    "vimcord#buffer#add_link_extmarks",
                    [x,y,z]
                ),
                self._buffer,
                message_id,
                formatted_opengraph
            )

    # DISCORD CALLBACKS --------------------------------------------------------
    async def on_ready(self):
        '''Ready callback. Get messages from daemon and add them to the buffer'''
        await self.get_remote_attributes()
        log.info("Retrieving messages from daemon")
        start_messages = await self.discord_pipe.awaitable.connection.messages()
        unmuted_messages = [message
            for message in start_messages
            if not self.is_muted(
                getattr(message, "server", None),
                message.channel
            )]

        # TODO: write prepended messages all at the same time
        def on_ready_callback():
            log.info("Sending data to vim...")
            self.plugin.nvim.api.call_function(
                "vimcord#buffer#add_extra_data",
                [
                    { i.id: format_channel(i, raw=True)
                      for i in self.unmuted_channels },
                    self.all_members,
                    self._user.id
                ]
            )
            for message in unmuted_messages:
                self._on_message(message)

        self.plugin.nvim.async_call(on_ready_callback)

    async def on_message(self, post):
        '''Add message to the buffer if it has not been muted'''
        muted = self.is_muted(getattr(post, "server", None), post.channel)
        if muted:
            return
        self.plugin.nvim.async_call(
            self._on_message,
            post,
        )

    def _on_message(self, post):
        '''On message callback, when vim is available'''
        self.all_messages[post.id] = post
        if self._last_channel != post.channel:
            self._last_channel = post.channel
            self.plugin.nvim.lua.vimcord.append_to_buffer(
                self._buffer,
                [format_channel(post.channel)],
                [],
                {
                    "channel_id": post.channel.id,
                    "server_id":  (post.server.id if post.server is not None else None),
                }
            )

        links, reply, message = clean_post(self, post)
        self.plugin.nvim.lua.vimcord.append_to_buffer(
            self._buffer,
            message.split("\n"),
            reply,
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  (post.server.id if post.server is not None else None),
                "reply_message_id": (post.referenced_message.id if post.referenced_message is not None else None)
            },
        )
        if links:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(post.id, links)
            )

    async def on_message_edit(self, _, post):
        '''If a message was edited, update the buffer'''
        muted = self.is_muted(getattr(post, "server", None), post.channel)
        if muted:
            return
        self.plugin.nvim.async_call(
            self._on_message_edit,
            post,
        )

    def _on_message_edit(self, post):
        '''On message edit callback, when vim is available'''
        links, _, message = clean_post(self, post, no_reply=True)
        as_reply = extmark_post(self, post)
        self.plugin.nvim.lua.vimcord.edit_buffer_message(
            self._buffer,
            message.split("\n"),
            as_reply,
            # TODO: this is immutable data. don't send it down again, because the buffer already has it
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  (post.server.id if post.server is not None else None),
                "reply_message_id": (post.referenced_message.id if post.referenced_message is not None else None)
            },
        )
        if links:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(post.id, links)
            )

    async def on_message_delete(self, post):
        '''If a message was deleted, update the buffer'''
        muted = self.is_muted(getattr(post, "server", None), post.channel)
        if muted:
            return
        self.plugin.nvim.async_call(
            lambda x,y: self.plugin.nvim.lua.vimcord.delete_buffer_message(x, y),
            self._buffer,
            post.id,
        )

    async def on_dm_update(self, dm):
        '''DM discord user status change'''
        #TODO

    #---Check if a channel is muted---------------------------------------------
    def is_muted(self, server, channel):
        '''Check if a channel is muted, per its settings'''
        if server is None:
            return False
        try:
            settings = self._notify[server.id]
            if "channel_overrides" not in settings \
            or channel.id not in settings["channel_overrides"]:
                # this server has no channel overrides, or there are none for this channel
                return settings.get("muted") and (
                    settings.get("mute_config") is None or
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

    def _unmuted_channels(self):
        '''Get a list of channels (and private messages) which are unmuted'''
        ret = [[*sorted(
            self._private_channels,
            key=lambda x: self._dm_ordering.get(x.id, "") or "",
            reverse=True
        )]]
        for server in self._servers:
            me_in_server = server.get_member(self._user.id)
            if me_in_server is None:
                continue
            server_channels = [] # [server.name]
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

    @property
    def unmuted_channels(self):
        return [channel for server in self._unmuted_channels() for channel in server]
