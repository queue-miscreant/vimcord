import re
import logging

from vimcord.formatting import format_channel

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

LAST_GET_SERVERS = {}

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
        self.discord = self.bridge.discord
        if not hasattr(self, action_name):
            return None

        try:
            self.ret = getattr(self, action_name)(*args)
        except Exception as e:
            log.error(e, stack_info=True)

    def message(self, message_data, content, is_reply):
        log.debug("%s", message_data)
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        if (channel := self.discord.get_channel(channel_id)) is None:
            return

        reference = {
            "channel_id": channel_id,
            "message_id": message_id,
        }

        self.plugin.nvim.loop.create_task(
            self.discord.send_message(
                channel,
                content,
                reference=(reference if is_reply else None)
            )
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
    def delete(self, message_data):
        log.debug("%s", message_data)
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        if self.discord.get_channel(channel_id) is None:
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            return

        log.debug("%s", message)

        self.plugin.nvim.loop.create_task(
            self.discord.delete_message(message)
        )

    def edit(self, message_data, content):
        log.debug("%s", message_data)
        message_id = message_data.get("message_id")
        channel_id = message_data.get("channel_id")
        if self.discord.get_channel(channel_id) is None:
            return

        if (message := self.bridge.all_messages.get(message_id)) is None:
            return

        # TODO: show edit success/failure
        self.plugin.nvim.loop.create_task(
            self.discord.edit_message(
                message,
                content
            )
        )

    def get_servers(self):
        ret = []
        LAST_GET_SERVERS.clear()

        channels = self.discord.unmuted_channels()
        categories = [(i[0], i[1:]) for i in channels if len(i) > 1]

        for (_, entries) in categories:
            for entry in entries:
                ret.append(format_channel(entry, raw=True))
                LAST_GET_SERVERS[format_channel(entry, raw=True)] = entry

        return ret

    def try_post_server(self, channel_name, message):
        channel = LAST_GET_SERVERS[channel_name]
        if channel is None:
            log.debug("Could not find channel named %s", channel_name)
            return
        self.plugin.nvim.loop.create_task(
            self.discord.send_message(
                channel,
                message
            )
        )
