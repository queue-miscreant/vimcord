import asyncio
import logging
import re

from vimcord.formatting import format_channel

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

def parse_mentions(text, server):
    '''Convert all literal @s into semantic ones for discord'''
    if server is None:
        return text
    for i in server.members:
        text = text.replace(f"@{i.display_name}", i.mention)
    return text

class DiscordAction:
    '''Discord actions which can be invoked by the nvim client'''
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
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")

        reference = {
            "channel_id": channel_id,
            "message_id": message_id,
        }

        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            return

        server = next(
            filter(lambda x: x.id == message_data["server_id"], self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            return
        if server == "DM":
            server = None

        content = parse_mentions(content, server)
        self.discord.task.send_message(
            channel,
            content,
            reference=(reference if is_reply else None)
        )

    # TODO: show deletion success/failure
    async def delete(self, message_data):
        log.debug("%s", message_data)
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        # if self.discord.get_channel(channel_id) is None:
        #     return
        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            return

        self.discord.task.delete_message(message)

    async def tryedit(self, message_data):
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")

        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            return
        if (message := self.bridge.all_messages.get(message_id)) is None:
            self.plugin.nvim.async_call(
                self.plugin.nvim.api.notify,
                "Cannot edit: could not find message",
                4,
                {}
            )
            return

        if self.bridge._user.id != message.author.id:
            self.plugin.nvim.async_call(
                self.plugin.nvim.api.notify,
                "Cannot edit: not the author of this message",
                4,
                {}
            )
            return

        self.plugin.nvim.async_call(
            self.plugin.nvim.api.call_function,
            "vimcord#action#edit_end",
             [str(message.content), message_data]
         )

    async def edit(self, message_data, content):
        if (message := self.bridge.all_messages.get(message_data["message_id"])) is None:
            return

        channel = await self.discord.awaitable.get_channel(message_data["channel_id"])
        if channel is None:
            return

        server = next(
            filter(lambda x: x.id == message_data["server_id"], self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            return
        if server == "DM":
            server = None

        content = parse_mentions(content, server)
        self.discord.task.edit_message(message, content)

    def get_servers(self):
        return [format_channel(channel, raw=True) for channel in self.bridge.unmuted_channels()]

    async def try_post_channel(self, message_data, content):
        channel = await self.discord.awaitable.get_channel(message_data["channel_id"])
        if channel is None:
            log.debug("Could not find channel %s", message_data["channel_id"])
            return

        server = next(
            filter(lambda x: x.id == message_data["server_id"], self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            return
        if server == "DM":
            server = None

        content = parse_mentions(content, server)
        self.discord.task.send_message(channel, content)

    async def try_reconnect(self):
        self.discord.task.connect()

    async def new_reply(self, message_data, content):
        log.debug("%s %s", message_data, content)

        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        is_reply = message_data.get("is_reply", False)

        reference = {
            "channel_id": channel_id,
            "message_id": message_id,
        }

        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            return

        server = next(
            filter(lambda x: x.id == message_data["server_id"], self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            return
        if server == "DM":
            server = None

        content = parse_mentions(content, server)
        self.discord.task.send_message(
            channel,
            content,
            reference=(reference if is_reply else None)
        )

    async def new_edit(self, message_data, content):
        log.debug("%s %s", message_data, content)

        if (message := self.bridge.all_messages.get(message_data["message_id"])) is None:
            return

        if content.strip() == "":
            self.discord.task.delete_message(message)
            return

        channel = await self.discord.awaitable.get_channel(message_data["channel_id"])
        if channel is None:
            return

        server = next(
            filter(lambda x: x.id == message_data["server_id"], self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            return
        if server == "DM":
            server = None

        content = parse_mentions(content, server)
        self.discord.task.edit_message(message, content)

    async def new_try_post_channel(self, message_data, content):
        channel = await self.discord.awaitable.get_channel(message_data["channel_id"])
        if channel is None:
            log.debug("Could not find channel %s", message_data["channel_id"])
            return

        server = next(
            filter(lambda x: x.id == channel.server.id, self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            return
        if server == "DM":
            server = None

        content = parse_mentions(content, server)
        self.discord.task.send_message(channel, content)

