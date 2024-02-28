import asyncio
import datetime
import logging
import time

import vimcord.discord as discord
import vimcord.local_discord_server as local_discord_server
from vimcord.formatting import format_channel, clean_post, extmark_post
from vimcord.links import get_link_content, LINK_RE

log = logging.getLogger(__name__)
log.setLevel("INFO")

def utc_timestamp_to_iso(timestamp):
    # iso_format = timestamp.astimezone(datetime.UTC).isoformat(' ', timespec="seconds")
    current_timezone = datetime.datetime.now(datetime.timezone.utc).astimezone().tzinfo
    local_time = datetime.datetime(*timestamp.timetuple()[:-2], datetime.timezone.utc).astimezone(current_timezone)
    iso_format = local_time.isoformat(" ", timespec="seconds").split(" ")
    # remove timezone
    iso_format[1] = iso_format[1].split("+")[0].split("-")[0]
    return " ".join(iso_format)

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

        self._last_post = None
        # Map from post id to post object
        # `...last_author` author is a map from post id to the last author at the time the post was made,
        # which is obviously inefficient and terrible, but doesn't mess with all_messages
        self.all_messages = {}
        self.all_messages_last_author = {}
        self.visited_links = set()

        # server properties that need refreshed rarely, but get used for unmuted channels/is muted
        self._user = None
        self._dm_ordering = {}
        self._notify = {}
        self._servers = []
        self._private_channels = []

    async def get_remote_attributes(self):
        '''Refresh rarely-updated members from the daemon'''
        self._user = await self.discord_pipe.awaitable.user()
        self._dm_ordering = await self.discord_pipe.awaitable._dm_ordering()
        self._notify = await self.discord_pipe.awaitable._notify()
        self._servers = await self.discord_pipe.awaitable.servers()
        self._private_channels = await self.discord_pipe.awaitable.private_channels()

    async def resolve_author_dm(self, post):
        if not isinstance(post, discord.Message):
            return None
        if post.author == self._user:
            return -1
        channel_id, _ = await self.discord_pipe.awaitable._resolve_destination(post.author)
        # fetch the new private channel if we don't have it
        if not any(i.id == channel_id for i in self._private_channels):
            self._private_channels = await self.discord_pipe.awaitable.private_channels()
        return channel_id

    async def start_discord_client_server(self, path, discord_token):
        '''Spawn a local discord server as a daemon and set the discord pipe object'''
        if self.discord_pipe is None:
            log.info("Starting client %s", path)
            # TODO: set discord_ready here
            _, self.discord_pipe = await local_discord_server.connect_to_daemon(path, log)

            # bind events
            self.discord_pipe.event("remote_update", self.on_remote_update)
            self.discord_pipe.event("servers_ready", self.on_ready)
            self.discord_pipe.event("message", self.on_message)
            self.discord_pipe.event("message_edit", self.on_message_edit)
            self.discord_pipe.event("message_delete", self.on_message_delete)
            self.discord_pipe.event("dm_update", self.on_dm_update)
            self.discord_pipe.event("error", self.on_error)
        else:
            log.info("Using existing client")

        await self.preamble(discord_token)

    async def preamble(self, discord_token):
        '''
        When connecting to the daemon, check if the user is logged in and
        whether a connection has been established.
        '''
        is_logged_in = await self.discord_pipe.awaitable.is_logged_in()
        is_not_connected = await self.discord_pipe.awaitable.is_closed()
        if not is_logged_in:
            log.info("Not logged in! Attempting to login and start discord connection...")
            self.discord_pipe.task.start(discord_token)
        else:
            if is_not_connected:
                log.info("Not connected to discord! Attempting to reconnect...")
                self.discord_pipe.task.connect()
            else:
                self.plugin.nvim.loop.create_task(self.on_ready())

        self.plugin.nvim.async_call(
            self.plugin.nvim.api.call_function,
            "vimcord#discord#local#set_connection_state",
            [True, is_not_connected, is_logged_in]
        )

    async def close(self):
        self.discord_pipe.transport.close()

    @property
    def all_members(self):
        return {server.id: [
                member.display_name for member in server.members
            ]
            for server in self._servers}

    @property
    def all_channel_names(self):
        return { i.id: format_channel(i, raw=True) for i in self.all_channels }

    @property
    def unmuted_channel_names(self):
        return { i.id: format_channel(i, raw=True) for i in self.unmuted_channels }

    @property
    def extra_data(self):
        '''Data to set in g:vimcord'''
        return {
            "discord_user_id": self._user.id,
        }

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
                return
            link = [match.group(1)]

        if isinstance(link, list):
            unvisited = [l
                for l in link
                if l not in self.visited_links and LINK_RE.match(l)]
            self.visited_links.update(link)
        else:
            raise ValueError("Can only visit links from type string or list!")

        if unvisited:
            self.plugin.nvim.async_call(
                self.plugin.nvim.api.call_function,
                "vimcord#link#color_links_in_buffer",
                link
            )

    async def add_link_extmarks(self, message_id, links):
        '''
        Asynchronously generate extmarks to a list of links, then call vim
        function to add them.
        '''
        formatted_opengraph = await asyncio.gather(*[
            get_link_content(link, notify_func=self.plugin.notify) for link in links
        ])
        # flatten results
        # TODO: intercalate?
        extmark_content = [j for i in formatted_opengraph if i for j in i[0]]
        media_links = [j for i in formatted_opengraph if i for j in i[1]]

        self.plugin.nvim.async_call(
            lambda x,y,z,w: self.plugin.nvim.lua.vimcord.discord.add_link_extmarks(x,y,z,w),
            message_id,
            extmark_content,
            media_links,
            [link for link in links if link in self.visited_links]
        )

    # DISCORD CALLBACKS --------------------------------------------------------
    async def on_remote_update(self):
        log.info("Getting new remote")
        await self.get_remote_attributes()

    async def on_ready(self):
        '''Ready callback. Get messages from daemon and add them to the buffer'''
        # TODO: seems to fail when sent over again
        await self.get_remote_attributes()
        log.info("Retrieving messages from daemon")
        start_messages = await self.discord_pipe.awaitable.connection.messages()
        unmuted_messages = [message
            for message in start_messages
            if not self.is_muted(
                getattr(message, "server", None),
                message.channel
            )]

        links_and_messages = [
            self._prepare_post_for_buffer(message)
            for message in unmuted_messages
        ]

        is_logged_in = await self.discord_pipe.awaitable.is_logged_in()
        is_not_connected = await self.discord_pipe.awaitable.is_closed()

        def on_ready_callback():
            log.info("Sending data to vim...")
            self.plugin.nvim.api.call_function(
                "vimcord#discord#local#add_extra_data",
                [self.extra_data]
            )

            self.plugin.nvim.async_call(
                self.plugin.nvim.api.call_function,
                "vimcord#discord#local#set_connection_state",
                [True, is_not_connected, is_logged_in]
            )

            if not links_and_messages:
                return

            id_and_links, unflat_messages = zip(*links_and_messages)
            # send messages to vim
            self.plugin.nvim.lua.vimcord.discord.append_messages_to_buffer(
                [message for i in unflat_messages for message in i]
            )

            # start link fetches
            if not self.plugin.do_link_previews:
                return

            for message_id, links in id_and_links:
                if not links:
                    continue
                self.plugin.nvim.loop.create_task(
                    self.add_link_extmarks(message_id, links)
                )


        self.plugin.nvim.async_call(on_ready_callback)

    async def on_message(self, post):
        '''Add message to the buffer if it has not been muted'''
        muted = self.is_muted(getattr(post, "server", None), post.channel)
        if muted or post.id in self.all_messages:
            return
        self.plugin.nvim.async_call(
            self._append_messages_to_buffer,
            *self._prepare_post_for_buffer(post)
        )

    def _append_messages_to_buffer(self, links_and_id, messages):
        self.plugin.nvim.lua.vimcord.discord.append_messages_to_buffer(messages)

        message_id, links = links_and_id
        if links and self.plugin.do_link_previews:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(message_id, links)
            )

    def _prepare_post_for_buffer(self, post):
        '''On message callback, when vim is available'''
        ret = []
        if self._last_post is not None and self._last_post.channel != post.channel:
            ret.append((
                [format_channel(post.channel)],
                [],
                {
                    "channel_id": post.channel.id,
                    "server_id":  (post.server.id if post.server is not None else None),
                },
                False,
            ))
        last_author = None if self._last_post is None or self._last_post.channel != post.channel else self._last_post.author

        links, reply, message = clean_post(self, post, last_author=last_author)
        if message.split("\n") == []:
            log.debug("DETECTED BAD MESSAGE CONTENTS: %s in channel %s", repr(post.content), str(post.channel))

        ret.append((
            message.split("\n") or [""],
            reply,
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  (post.server.id if post.server is not None else None),
                "reply_message_id": (post.referenced_message.id if post.referenced_message is not None else None),
                "timestamp": utc_timestamp_to_iso(post.timestamp)
            },
            self._user.id in [i.id for i in post.mentions],
        ))
        self._last_post = post
        self.all_messages[post.id] = post
        self.all_messages_last_author[post.id] = last_author

        return (post.id, links), ret

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
        last_author = self.all_messages_last_author.get(post.id)
        links, _, message = clean_post(self, post, no_reply=True, last_author=last_author)
        as_reply = extmark_post(self, post)
        self.plugin.nvim.lua.vimcord.discord.edit_buffer_message(
            post.id,
            as_reply,
            message.split("\n"),
            # this is immutable data, but it's (marginally) easier to send it again
            {
                "message_id": post.id,
                "channel_id": post.channel.id,
                "server_id":  (post.server.id if post.server is not None else None),
                "reply_message_id": (post.referenced_message.id if post.referenced_message is not None else None),
            },
            self._user.id in [i.id for i in post.mentions],
        )
        self.all_messages[post.id] = post

        if links and self.plugin.do_link_previews:
            self.plugin.nvim.loop.create_task(
                self.add_link_extmarks(post.id, links)
            )

    async def on_message_delete(self, post):
        '''If a message was deleted, update the buffer'''
        muted = self.is_muted(getattr(post, "server", None), post.channel)
        if muted:
            return
        self.plugin.nvim.async_call(
            lambda x: self.plugin.nvim.lua.vimcord.discord.delete_buffer_message(x),
            post.id,
        )

    async def on_dm_update(self, dm):
        '''DM discord user status change'''
        #TODO: private channel status updates

    async def on_error(self, exc_type, exc_message):
        '''On error received from server'''
        if isinstance(exc_type, RuntimeError) and "already waiting for the next message" in exc_message:
            self.plugin.notify(f"Server attempted waiting for the next message twice", 3)
            return
        self.plugin.notify(f"Server encountered error: {exc_message}")
        log.info(f"Server encountered error of type {exc_type!r} with message {exc_message!r}")

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
        return [
            [channel
                for channel in server if not hasattr(channel, "server") or \
                        not self.is_muted(channel.server, channel)]
            for server in self._all_channels()]

    def _all_channels(self):
        '''Get a list of channels (and private messages)'''
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
                    or not visible:
                        continue
                except KeyError:
                    pass
                server_channels.append(channel)
            ret.append(server_channels)
        return ret

    @property
    def unmuted_channels(self):
        return [channel for server in self._unmuted_channels() for channel in server]

    @property
    def all_channels(self):
        return [channel for server in self._all_channels() for channel in server]

    def get_channel(self, channel_id):
        return next((channel for channel in self.all_channels if str(channel.id) == str(channel_id)), None)
