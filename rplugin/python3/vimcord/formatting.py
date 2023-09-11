import logging

import vimcord.discord as discord
from vimcord.links import LINK_RE

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

MAX_REPLY_WIDTH = 100

def syntax_color(color, text, literal=False):
    '''This is how the syntax plugin expects colors'''
    if literal:
        return f"\x1b{color} {text} \x1b"
    return f"\x1b{two56(color):02x} {text} \x1b"

def ellipsize(string, width):
    if len(string) > width:
        return string[:width-1] + "…"
    return string

def color_visited_link(bridge, match):
    color = "100"
    link = match.group(1)
    if link in bridge.visited_links:
        color = "VL"
    return syntax_color(color, link, literal=True)

def clean_post(bridge, post: discord.Message, no_reply=False):
    embeds = [i["url"] for i in post.attachments]
    links = LINK_RE.findall(post.clean_content) + embeds
    #pre-visit all links made by me
    if post.author == bridge._user:
        bridge.visited_links.union(links)

    # clean up post content
    content = post.clean_content + ' ' + ' '.join(embeds)
    content = LINK_RE.sub(
        lambda x: color_visited_link(bridge, x),
        content
    )

    author = post.author.display_name
    if hasattr(post.author, "color"):
        author = syntax_color(str(post.author.color), author)

    reply = []
    if not no_reply and post.referenced_message is not None:
        reply = extmark_post(bridge, post.referenced_message)

    return links, reply, author + ": " + content

def extmark_post(bridge, post: discord.Message):
    embeds = [i["url"] for i in post.attachments]
    content = post.clean_content + ' ' + ' '.join(embeds)
    color_number = "Default"
    if hasattr(post.author, "color"):
        color_number = two56(str(post.author.color))

    lines = content.split("\n")
    ellipsize = False
    if len(lines) > 1:
        content = lines[0]
        ellipsize = True
    if len(content) > 80:
        content = content[:MAX_REPLY_WIDTH]
        ellipsize = True
    if ellipsize:
        content = content[:-1] + "…"

    return [
        [post.author.display_name, f"discordColor{color_number}"],
        [f": {content}", "discordReply"]
    ]

def format_channel(channel, width=80, raw=False):
    '''Consistent way to format channels'''
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
    if too_black < sum(color)/3 < too_white:
        return color
    return None

def two56(color, reweight=_too_extreme):
    '''
    Convert general colors to 256 terminal colors.
    Extreme colors are rounded with `reweight`.
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
        stdev = sum((i - avg)**2 for i in rgbf)**0.5
        if stdev < 0.05:
            return 232 + int(avg*24)

        # weighted sum
        return 16 + sum(map(lambda x, y: int(x * 5) * y, rgbf, [36, 6, 1]))
    except (AttributeError, TypeError, ValueError):
        return 256
