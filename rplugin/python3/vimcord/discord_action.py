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
            self.plugin.notify(f"Error occurred when running action {action_name}")

    async def message(self, message_data, content):
        channel_id = message_data.get("channel_id")
        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            self.plugin.notify("Cannot send message: could not find channel")
            return

        # look for current servers
        server = next(
            filter(lambda x: x.id == channel.server.id, self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            self.plugin.notify("Cannot send message: could not find matching server")
            return
        if server == "DM":
            server = None

        # make sure we have a reference prepared
        is_reply = message_data.get("is_reply", False)
        message_id = message_data.get("message_id")
        reference = {
            "channel_id": channel_id,
            "message_id": message_id,
        } if is_reply else None

        # format the contents and send
        message_content = parse_mentions(content.get("content", ""), server)
        filenames = content.get("filenames", [])
        if filenames:
            self.discord.task.send_file(
                channel,
                fp=filenames[0],
                content=message_content,
                reference=reference
            )
            # warn about more than one file
            if len(filenames) > 1:
                self.plugin.nvim.async_call(
                    self.plugin.nvim.notify,
                    "Warning: multiple files uploaded, but only one sent",
                    3,
                    {}
                )
        # make sure we actually have content
        elif message_content.strip():
            self.discord.task.send_message(
                channel,
                message_content,
                reference=reference
            )

    async def try_edit(self, message_data):
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")

        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            return
        if (message := self.bridge.all_messages.get(message_id)) is None:
            self.plugin.notify("Cannot edit: could not find message")
            return

        if self.bridge._user.id != message.author.id:
            self.plugin.notify("Cannot edit: not the author of this message")
            return

        self.plugin.nvim.async_call(
            self.plugin.nvim.api.call_function,
            "vimcord#action#do_edit",
             [str(message.content), message_data]
         )

    async def do_edit(self, message_data, content):
        channel_id = message_data.get("channel_id")
        message_id = message_data.get("message_id")
        # we already checked this in "tryedit" according to the normal flow,
        # so this shouldn't happen
        if (message := self.bridge.all_messages.get(message_id)) is None:
            return

        # delete the message if the buffer was empty
        message_content = content.get("content", "")
        if message_content.strip() == "":
            self.discord.task.delete_message(message)
            return

        # make sure we have a target channel...
        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            self.plugin.notify("Cannot edit message: could not find channel")
            return

        # ...and server
        server = next(
            filter(lambda x: x.id == message_data["server_id"], self.bridge._servers),
            None
        ) if getattr(channel, "server", None) is not None else "DM"
        if server is None:
            self.plugin.notify("Cannot send message: could not find matching server")
            return
        if server == "DM":
            server = None

        message_content = parse_mentions(message_content, server)
        self.discord.task.edit_message(message, message_content)

    # TODO: show deletion success/failure
    async def delete(self, message_data):
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        # if self.discord.get_channel(channel_id) is None:
        #     return
        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            return

        blah = await self.discord.awaitable.delete_message(message)
        log.debug(blah)

    async def try_reconnect(self):
        self.discord.task.connect()
