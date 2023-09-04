import asyncio
import logging

import vimcord.local_discord_server as local_discord_server
from vimcord.formatting import format_channel, clean_post
from vimcord.links import get_link_content, LINK_RE

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

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

        self._unmuted_channels = []
        self.user = None

        plugin.nvim.loop.create_task(
            self.start_discord_client_server(plugin.socket_path)
        )

    async def start_discord_client_server(self, path):
        '''Spawn a local discord server as a daemon and set the discord pipe object'''
        daemon_created, self.discord_pipe = \
                await local_discord_server.connect_to_daemon(path, log)

        if daemon_created:
            self.discord_pipe.task.start(
                self.plugin.discord_username,
                self.plugin.discord_password
            )
        else:
            await self.on_ready()

        # bind events
        self.discord_pipe.event("servers_ready", self.on_ready)
        self.discord_pipe.event("message", self.on_message)
        self.discord_pipe.event("message_edit", self.on_message_edit)
        self.discord_pipe.event("message_delete", self.on_message_delete)
        self.discord_pipe.event("dm_update", self.on_dm_update)

    @property
    def unmuted_channels(self):
        return [i for server in self._unmuted_channels for i in server[1:]]

    def get_channel_by_name(self, channel_name):
        for channel in self.unmuted_channels:
            if channel_name == format_channel(channel, raw=True):
                return channel
        return None

    def visit_link(self, link):
        log.debug("Visiting link %s", repr(link))

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
        self._unmuted_channels = await self.discord_pipe.awaitable.unmuted_channels()
        self._user = await self.discord_pipe.awaitable.user()
        start_messages = await self.discord_pipe.awaitable.connection.messages()

        # TODO: write prepended messages all at the same time
        def messages():
            for post in start_messages:
                self._on_message(post)

        self.plugin.nvim.async_call(messages)

    async def on_message(self, post):
        self.all_messages[post.id] = post
        self.plugin.nvim.async_call(
            self._on_message,
            post,
        )

    def _on_message(self, post):
        if self._last_channel != post.channel:
            self._last_channel = post.channel
            self.plugin.nvim.lua.vimcord.append_to_buffer(
                self._buffer,
                [format_channel(post.channel)],
                {
                    "channel_id": post.channel.id,
                    "server_id":  (post.server.id if post.server is not None else None),
                }
            )

        links, message = clean_post(self, post)
        self.plugin.nvim.lua.vimcord.append_to_buffer(
            self._buffer,
            message.split("\n"),
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  (post.server.id if post.server is not None else None),
                "raw_message": post.content, # TODO ultimately unnecessary?
            },
        )
        if links:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(post.id, links)
            )

    async def on_message_edit(self, _, post):
        self.plugin.nvim.async_call(
            self._on_message_edit,
            post,
        )

    def _on_message_edit(self, post):
        links, message = clean_post(self, post)
        self.plugin.nvim.lua.vimcord.edit_buffer_message(
            self._buffer,
            message.split("\n"),
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  (post.server.id if post.server is not None else None),
                "raw_message": post.content, # TODO ultimately unnecessary?
            },
        )
        if links:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(post.id, links)
            )

    async def on_message_delete(self, post):
        self.plugin.nvim.async_call(
            lambda x,y: self.plugin.nvim.lua.vimcord.delete_buffer_message(x, y),
            self._buffer,
            post.id,
        )

    async def on_dm_update(self, dm):
        pass
