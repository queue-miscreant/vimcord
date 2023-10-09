import base64
import logging
import sys
import traceback

import pynvim
import vimcord.discord as discord
from vimcord.bridge import DiscordBridge
from vimcord.discord_action import DiscordAction
from vimcord.local_discord_server import kill_server as kill_discord_server

log = logging.getLogger("vimcord")
log.setLevel(logging.ERROR)

def unb64(string, initial="b64:"):
    '''If a string begins with the provided `initial` contents, decode the rest as base64'''
    if string.startswith(initial):
        string = base64.b64decode(string[len(initial):].encode()).decode()
    return string

@pynvim.plugin
class Vimcord:
    def __init__(self, nvim):
        self.nvim = nvim
        self.socket_path = "/tmp/vimcord_server"
        self.do_link_previews = bool(nvim.api.get_var("vimcord_show_link_previews"))

        nvim.loop.set_exception_handler(self.handle_exception)
        self.bridge = None

    @pynvim.command("Discord", nargs=0, bang=True, sync=True)
    def open_discord(self, bang):
        '''
        Get Discord credentials from global variables and attempt to log in.
        If either the username or password is unset or empty, the user will be prompted.
        '''
        try:
            discord_username = self.nvim.api.get_var("vimcord_discord_username")
            discord_password = self.nvim.api.get_var("vimcord_discord_password")
        except pynvim.NvimError:
            discord_username = ""
            discord_password = ""

        # get login from user input
        if not bang:
            if not (discord_username and discord_password):
                self.nvim.api.command("DiscordLogin")
                return

            # base64 decode, if possible
            discord_username = unb64(discord_username)
            discord_password = unb64(discord_password)

        self.nvim.lua.vimcord.discord.create_window()

        if self.bridge is None:
            self.bridge = DiscordBridge(self)
            log.info("Inited")

        self.nvim.loop.create_task(
            self.bridge.start_discord_client_server(
                self.socket_path,
                discord_username,
                discord_password
            )
        )


    @pynvim.command("KillDiscord", nargs=0)
    def kill_discord(self):
        '''Close the daemon, all Discord windows, and the socket connection to the daemon.'''
        kill_discord_server(self.socket_path)
        self.nvim.api.call_function("vimcord#close_all", [])
        self.bridge.close()
        self.bridge = None

    @pynvim.function("VimcordInvokeDiscordAction", sync=True)
    def invoke_discord_action(self, args):
        '''Receive data from vim and call out to DiscordAction, should a suitable one exist'''
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
        if (exception := context.get("exception")) is None or not isinstance(exception, Exception):
            message = context.get("message")
            log.error("Handler got non-exception: %s", message)
            self.notify(message, level=0)
            return
        if sys.version_info >= (3, 10):
            formatted = traceback.format_exception(exception)
        elif hasattr(exception, "__traceback__"):
            formatted = traceback.format_exception(
                type(exception),
                exception,
                exception.__traceback__
            )
        else:
            formatted = "(Could not get stack trace)"

        error_text = f"Error occurred:\n{''.join(formatted)}"
        log.error(error_text)
        self.notify(error_text)

    def notify(self, msg, level=4):
        self.nvim.async_call(self.nvim.api.notify, msg, level, {})
