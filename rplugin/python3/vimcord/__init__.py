import logging
import traceback

import pynvim
import vimcord.discord as discord
from vimcord.bridge import DiscordBridge
from vimcord.discord_action import DiscordAction

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
        self.discord_instance = None
        self.bridge = None

    @pynvim.command("Discord", nargs=0)
    def open_discord(self):
        if self.discord_instance is not None:
            #TODO: reopen discord buffer
            return

        self.bridge = DiscordBridge(self)
        # self.discord_instance = DiscordContainer(self)

    @pynvim.command("KillDiscord", nargs=0)
    def kill_discord(self):
        from vimcord.local_discord_server import kill_server
        kill_server(self.socket_path)

        # VERY TODO
        self.nvim.api.command("q")

        if self.discord_instance is not None:
            #TODO: reopen discord buffer
            return

        #TODO: check if server running
        # self.bridge = DiscordBridge(self)
        # self.discord_instance = DiscordContainer(self)

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
        formatted = traceback.format_exception(context["exception"])
        log.error("Error occurred:\n%s", "".join(formatted))

        self.nvim.async_call(
            self.nvim.api.notify,
            "An unknown error occurred!",
            4,
            {}
        )
