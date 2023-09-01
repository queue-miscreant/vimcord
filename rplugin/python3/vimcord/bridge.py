import asyncio
import logging

from vimcord.client import VimcordClient
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
        self.discord = VimcordClient(self)

        self._buffer = plugin.nvim.lua.vimcord.init()

        self._last_channel = None
        self.all_messages = {}
        self.visited_links = set()

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
            get_link_content(self, link) for link in links
        ])
        # flatten results
        # TODO: intercalate?
        formatted_opengraph = [j for i in formatted_opengraph for j in i]

        self.plugin.nvim.async_call(
            lambda x,y,z: self.plugin.nvim.lua.vimcord.add_link_extmarks(x,y,z),
            self._buffer,
            message_id,
            formatted_opengraph
        )

    # DISCORD CALLBACKS --------------------------------------------------------
    def on_discord_connected(self):
        self.plugin.nvim.async_call(
            lambda x,y,z: self.plugin.nvim.lua.vimcord.append_to_buffer(x,y,z),
            self._buffer,
            ["Connected to Discord!"],
            {}
        )


    def on_message(self, post):
        self.all_messages[post.id] = post

        if self._last_channel != post.channel:
            self._last_channel = post.channel
            self.plugin.nvim.async_call(
                lambda x,y,z: self.plugin.nvim.lua.vimcord.append_to_buffer(x,y,z),
                self._buffer,
                [format_channel(post.channel)],
                {
                    "channel_id": post.channel.id,
                    "server_id":  post.server.id,
                }
            )

        links, message = clean_post(self, post)
        self.plugin.nvim.async_call(
            lambda x,y,z: self.plugin.nvim.lua.vimcord.append_to_buffer(x,y,z),
            self._buffer,
            message.split("\n"),
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  post.server.id,
                "raw_message": post.content, # TODO ultimately unnecessary?
            }
        )
        if links:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(post.id, links)
            )

    def on_message_edit(self, post):
        links, message = clean_post(self, post)
        self.plugin.nvim.async_call(
            lambda x,y,z: self.plugin.nvim.lua.vimcord.edit_buffer_message(x,y,z),
            self._buffer,
            message.split("\n"),
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  post.server.id,
                "raw_message": post.content, # TODO ultimately unnecessary?
            }
        )
        if links:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(post.id, links)
            )

    def on_message_delete(self, post):
        self.plugin.nvim.async_call(
            lambda x,y: self.plugin.nvim.lua.vimcord.delete_buffer_message(x, y),
            self._buffer,
            post.id,
        )

    def on_dm_update(self, dm):
        pass
