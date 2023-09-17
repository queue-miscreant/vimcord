import logging
import traceback

import pynvim
import vimcord.discord as discord
from vimcord.bridge import DiscordBridge
from vimcord.discord_action import DiscordAction
from vimcord.local_discord_server import kill_server as kill_discord_server

log = logging.getLogger("vimcord")
log.setLevel(logging.ERROR)

@pynvim.plugin
class Vimcord:
    def __init__(self, nvim):
        self.nvim = nvim
        self.discord_username = nvim.api.get_var("vimcord_discord_username")
        self.discord_password = nvim.api.get_var("vimcord_discord_password")

        self.socket_path = "/tmp/vimcord_server"

        nvim.loop.set_exception_handler(self.handle_exception)
        self.bridge = None

    @pynvim.command("Discord", nargs=0)
    def open_discord(self):
        if self.bridge is not None:
            self.nvim.lua.vimcord.create_window(False, self.bridge._buffer)
            return

        self.open_bridge()

    @pynvim.command("KillDiscord", nargs=0)
    def kill_discord(self):
        kill_discord_server(self.socket_path)
        self.nvim.api.call_function("vimcord#close_all", self.bridge._buffer)

        if self.bridge is not None:
            async def reopen_bridge():
                buffer = self.bridge._buffer
                await self.bridge.close()
                self.nvim.async_call(self.open_bridge, buffer)

            self.nvim.loop.create_task(reopen_bridge())
            return

        self.nvim.async_call(self.open_bridge)

    @pynvim.function("VimcordInvokeDiscordAction", sync=True)
    def invoke_discord_action(self, args):
        if self.bridge is None or self.bridge.discord_pipe is None:
            self.nvim.api.notify(
                "No running discord detected",
                4,
                {}
            )
            return

        return DiscordAction(self, *args).ret

    @pynvim.function("VimcordVisitLink")
    def visit_link(self, args):
        if len(args) == 1:
            link, = args
        else:
            raise ValueError(f"Expected 1 argument, received {len(args)}")

        self.bridge.visit_link(link)

    def handle_exception(self, loop, context):
        if (message := context.get("exception")) is None:
            log.debug("%s", message)
            return
        formatted = traceback.format_exception(context["exception"])
        log.error("Error occurred:\n%s", "".join(formatted))

        self.nvim.async_call(
            self.nvim.api.notify,
            # "An unknown error occurred!",
            "Error occurred:\n%s" % "".join(formatted),
            4,
            {}
        )

    def open_bridge(self, buffer=None):
        self.bridge = DiscordBridge(self, buffer)

    def notify(self, msg, level=4):
        self.nvim.async_call(self.nvim.api.notify, msg, level, {})
