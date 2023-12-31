import asyncio
import logging
import re

# from vimcord.discord import errors as discord_errors
from vimcord.formatting import format_channel
from vimcord.pickle_pipe import ForwardedException

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

def parse_mentions(text, server):
    '''Convert all literal @s into semantic ones for discord'''
    if server is None:
        return text
    for i in sorted(server.members, key=lambda x: len(str(x)), reverse=True):
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
        '''
        Send a Discord message to a channel.

        `message_data` is a dict containing data sent with Discord posts to the message buffer.
        It must contain the field "channel_id", which is the target channel.
        It can also contain "is_reply" and "message_id", which indicates the message is a reply
        referencing that message.

        `content` is a dict containing the fields "content" and (optionally) "filenames".
        The former value is a string containing the message to send to Discord.
        The latter value is a list of filenames to send along with the message.
        Only the first entry is actually sent, due to library limitations.
        '''
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
        '''
        Request to edit a Discord message.

        `message_data` is a dict containing data sent with Discord posts to the message buffer.
        It must contain the fields "message_id" and "channel_id", which are the the ID of the
        Discord message being edited and the channel it belongs to.

        If the message can be found, this sends the message contents to vim, which are
        replaced in the reply buffer. When submitted, `do_edit` should be called.
        '''
        message_id = message_data.get("message_id")

        if (message := self.bridge.all_messages.get(message_id)) is None:
            self.plugin.notify("Cannot edit: could not find message")
            return

        if self.bridge._user.id != message.author.id:
            self.plugin.notify("Cannot edit: not the author of this message")
            return

        self.plugin.nvim.async_call(
            self.plugin.nvim.api.call_function,
            "vimcord#discord#action#do_edit",
             [str(message.content), message_data]
         )

    async def do_edit(self, message_data, content):
        '''
        Submit an edit to a Discord message.

        `message_data` is a dict containing data sent with Discord posts to the message buffer.
        It must contain the fields "message_id" and "channel_id", which are the the ID of the
        Discord message being edited and the channel it belongs to.

        `content` is a dict containing the field "content", which is a string containing
        the edited message contents to send to Discord.
        '''
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

    async def delete(self, message_data):
        '''
        Delete a Discord message.

        `message_data` is a dict containing data sent with Discord posts to the message buffer.
        It must contain the fields "message_id" and "channel_id", which are the the ID of the
        Discord message being edited and the channel it belongs to.
        '''
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")

        if message_id is None:
            self.plugin.notify("Cannot delete message: line has no message ID!")
            return

        channel = await self.discord.awaitable.get_channel(channel_id)
        if channel is None:
            self.plugin.notify("Cannot delete message: unknown message channel!")
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            self.plugin.notify("Cannot delete message: unknown message ID!")
            return

        try:
            await self.discord.awaitable.delete_message(message)
        except ForwardedException as e:
            log.error(e)
            self.plugin.notify(f"Cannot delete message: {e.args[1]}")

    async def try_direct_message(self, message_data):
        if isinstance(message_data, dict) and "message_id" in message_data is not None:
            message_id = message_data["message_id"]
        elif isinstance(message_data, int):
            message_id = message_data
        else:
            self.plugin.notify("Cannot direct message: received bad message data!")
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            self.plugin.notify("Cannot direct message: unknown message ID!")
            return

        try:
            channel_id = await self.bridge.resolve_author_dm(message)
        except ForwardedException as e:
            # If the target user doesn't allow messages from strangers, we get a 403
            self.plugin.notify(f"Discord responded: {e.args[1]}")
            return
            # if isinstance(e.args[0], discord_errors.Forbidden):

        if channel_id == -1:
            self.plugin.notify("Cannot direct message yourself!")
            return
        if channel_id is None:
            self.plugin.notify("Cannot direct message: failed to resolve target!")
            return

        self.plugin.nvim.async_call(
            self.plugin.nvim.api.call_function,
            "vimcord#discord#action#simple_reply",
            [{"channel_id": channel_id}]
         )

    async def try_reconnect(self):
        client_closed = await self.discord.awaitable.http.session.closed()
        if client_closed:
            self.plugin.notify("Session was closed! Trying to reconnect...", 0)
            self.discord.task.http.recreate()
            await asyncio.sleep(1)
        self.plugin.notify("Reconnecting to websocket...", 0)
        await self.discord.awaitable.connect()

    def get_channel_members(self, channel_id):
        if (channel := self.bridge.get_channel(channel_id)) is None:
            return []
        return self.bridge.all_members.get(channel.server.id, [])

    def get_channel_names(self, channel_id=None):
        if channel_id is None:
            return self.bridge.all_channel_names
        return self.bridge.all_channel_names.get(channel_id, "")

    def get_unmuted_channel_names(self):
        return self.bridge.unmuted_channel_names

    async def get_connection_state(self):
        daemon_conneceted = self.discord.transport is not None
        try:
            is_not_connected = await self.discord.awaitable.is_closed()
            is_logged_in = await self.discord.awaitable.is_logged_in()
            session_closed = await self.discord.awaitable.http.session.closed()
        except:
            is_not_connected = True
            is_logged_in = False
            session_closed = True

        self.plugin.nvim.async_call(
            self.plugin.nvim.api.call_function,
            "vimcord#discord#local#set_connection_state",
            [daemon_conneceted, is_not_connected or session_closed, is_logged_in]
        )
