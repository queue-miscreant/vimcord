import logging

import vimcord.discord as discord
from vimcord.links import LINK_RE

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

INDENT_SIZE = 3
MAX_REPLY_WIDTH = 100

def syntax_color(color, text):
    '''
    Format some `text` using the dynamic colors provided by `discordColor` syntax.
    `color` is any color format supported by `two56()`.
    '''
    return f"\x1b{two56(color):02x} {text} \x1b"

def ellipsize(string, width):
    if len(string) > width:
        return string[:width-1] + "…"
    return string

def clean_post(bridge, post: discord.Message, no_reply=False, last_author=None):
    '''
    Convert a `discord.Message` object into a form suitable for display in a text buffer.
    Returns a triple of:
        - A list of links found when parsing the post
        - A virt_lines extmark argument
        - A string with newlines to be inserted into the buffer

    If no_reply is true, the second return value is an empty list.
    If last_author is not None, the author is omitted if post.author and last_author match.
    '''
    embeds = [i["url"] for i in post.attachments]
    links = LINK_RE.findall(post.clean_content) + embeds
    #pre-visit all links made by me
    if post.author == bridge._user:
        bridge.visited_links.union(links)

    # clean up post content
    content = (post.clean_content + '\n' + ' '.join(embeds)).strip()

    author = post.author.display_name
    if hasattr(post.author, "color"):
        author = syntax_color(str(post.author.color), author)

    reply = []
    if not no_reply and post.referenced_message is not None:
        reply = extmark_post(bridge, post.referenced_message)

    if not content:
        return links, reply, f" {author}: {post.system_content}"

    if post.author == last_author and not reply:
        return links, reply, f" \n{content}"
    return links, reply, f" {author}:\n{content}"

def extmark_post(bridge, post: discord.Message):
    '''
    Convert a `discord.Message` object into a single-line extmark.
    The author is rendered in color, but message body is rendered
    with the "discordReply" highlight.
    '''
    embeds = [i["url"] for i in post.attachments]
    content = post.clean_content + ' ' + ' '.join(embeds)
    color_number = "Default"
    if hasattr(post.author, "color"):
        color_number = two56(str(post.author.color))

    content = content.replace("\n", " ")
    if len(content) > MAX_REPLY_WIDTH:
        content = content[:MAX_REPLY_WIDTH - 1] + "…"

    return [
        [post.author.display_name, f"discordColor{color_number}"],
        [f": {content.strip()}", "discordReply"]
    ]

def format_channel(channel, width=80, raw=False):
    '''
    Format a discord.Channel object as a string.
    Private messages are rendrered as "Direct message with...", while
    general text channels are rendered as "{server name} # {channel name}".
    '''
    # private channels are serverless
    if isinstance(channel, discord.PrivateChannel):
        if raw:
            return str(channel)
        channel_name = ellipsize(str(channel), width - 1)
        return f"#{channel_name}"
    # want both server and channel names
    server_name = ellipsize(str(channel.server), width // 2)
    channel_name = ellipsize(str(channel), width - width // 2 - 3)
    if raw:
        return f"{server_name}#{channel_name}"
    return f"{server_name} # {channel_name}"

# 256-color helper----------------------------------------------------------------------------------

def _too_extreme(color, too_black=0.1, too_white=0.9):
    '''
    If a triple of numbers has an average which is too low (`too_black`)
    or too high (`too_white`), signal that the triple is invalid with None.
    '''
    if too_black < sum(color)/3 < too_white:
        return color
    return None

def two56(color, reweight=_too_extreme):
    '''
    Convert general colors to 256 terminal colors.
    Extreme colors are rounded with `reweight`.

    `color` can be any of:
        - A hex code (#FFF or #FFFFFF)
        - A triple of values ([255, 255, 255])
        - A literal number 0-255, matching terminal 256 colors
    '''
    if isinstance(color, int):
        return color
    if isinstance(color, float):
        raise TypeError("cannot interpret float as color number")

    if isinstance(color, str):
        if color.startswith("#"):
            color = color[1:]
        # attempt to convert string to hex
        try:
            int(color, 16)
        except ValueError:
            return 256
        parts_len = len(color) // 3
        rgbf = [
            int(color[i * parts_len:(i+1) * parts_len], 16) / ((16**parts_len) - 1)
            for i in range(3)
        ]
    else:
        rgbf = [i/255 for i in color]

    try:
        avg = sum(rgbf)/3
        if callable(reweight):
            rgbf = reweight(rgbf)
            if rgbf is None:
                raise ValueError
            avg = sum(rgbf)/3

        # if the standard deviation is small enough, this is just a tone of gray
        variance = sum((i - avg)**2 for i in rgbf)
        if variance < 0.0025:
            return 232 + int(avg*24)

        # weighted sum
        return 16 + sum(map(lambda x, y: int(x * 5) * y, rgbf, [36, 6, 1]))
    except (AttributeError, TypeError, ValueError):
        return 256
