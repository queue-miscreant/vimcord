import asyncio
import re
import logging

from vimcord.formatting import format_channel

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

def parse_mentions(text, channel):
    '''Convert all literal @s into semantic ones for discord'''
    def replace_fn(string):
        member = next(filter(lambda x: str(x) == string.group(1), channel.server.members), None)
        return member.mention if member else ""
    return re.sub("@([^#]+?#\\d{4})", replace_fn, text, 0, re.UNICODE)

class DiscordAction:
    '''Discord actions which can be invoked by the nvim client.'''
    def __init__(self, plugin, action_name, *args):
        self.plugin = plugin
        self.bridge = plugin.bridge
        self.discord = self.bridge.discord_pipe
        if not hasattr(self, action_name):
            return None

        try:
            ret = getattr(self, action_name)(*args)
            if asyncio.iscoroutine(ret):
                self.ret = None
                self.plugin.nvim.loop.create_task(ret)
                return
            self.ret = ret
        except Exception as e:
            log.error("Error occurred in DiscordAction %s", e, stack_info=True)
            self.plugin.nvim.api.notify(
                f"Error occurred when running action {action_name}",
                4,
                {}
            )

    async def message(self, message_data, content, is_reply):
        log.debug("%s", message_data)
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        # if (channel := self.discord.get_channel(channel_id)) is None:
        channel = await self.discord.wait_for("discord.get_channel", channel_id)

        reference = {
            "channel_id": channel_id,
            "message_id": message_id,
        }

        log.debug("FUCKING HERE %s %s %s", channel, content, reference)

        if channel is None:
            return

        # self.plugin.nvim.loop.create_task(
        #     self.discord.send_message(
        #         channel,
        #         content,
        #         reference=(reference if is_reply else None)
        #     )
        # )

        self.discord.create_remote_task(
            "discord.send_message",
            channel,
            content,
            reference=(reference if is_reply else None)
        )

        # if self._channel is not None and text or self._has_file:
        #     self.last_notified_channel = self._channel
        #     text = self.parse_mentions(text,  self._channel)
        #     if self._has_file:
        #         self._has_file = False
        #         coro = self.send_file(self._channel, "/tmp/discordfile.png", content=text, **kwargs)
        #     else:
        #         coro = self.send_message(self._channel, text, **kwargs)
        #     ret = True

    # TODO: show deletion success/failure
    async def delete(self, message_data):
        log.debug("%s", message_data)
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        # if self.discord.get_channel(channel_id) is None:
        #     return
        channel = await self.discord.wait_for("discord.get_channel", channel_id)
        if channel is None:
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            return

        log.debug("%s", message)

        # self.plugin.nvim.loop.create_task(
        #     self.discord.delete_message(message)
        # )
        self.discord.create_remote_task("discord.delete_message", message)

    async def edit(self, message_data, content):
        log.debug("%s", message_data)
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        # if self.discord.get_channel(channel_id) is None:
        #     return
        channel = await self.discord.wait_for("discord.get_channel", channel_id)
        if channel is None:
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            return

        # TODO: show edit success/failure
        # self.plugin.nvim.loop.create_task(
        #     self.discord.edit_message(
        #         message,
        #         content
        #     )
        # )
        self.discord.create_remote_task("discord.edit_message", message, content)

    def get_servers(self):
        return [format_channel(channel, raw=True) for channel in self.bridge.unmuted_channels]

    async def try_post_server(self, channel_name, message):
        channel = self.bridge.get_channel_by_name(channel_name)
        if channel is None:
            log.debug("Could not find channel named %s", channel_name)
            return

        # self.plugin.nvim.loop.create_task(
        #     self.discord.send_message(
        #         channel,
        #         message
        #     )
        # )
        self.discord.create_remote_task("discord.send_message", channel, message)

    async def try_reconnect(self):
        # self.plugin.nvim.loop.create_task(
        #     self.discord.send_message(
        #         channel,
        #         message
        #     )
        # )
        self.discord.create_remote_task("discord.connect")
