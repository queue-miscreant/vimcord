import asyncio
from functools import lru_cache
from http.client import HTTPException    #for catching IncompleteRead
from urllib.error import HTTPError, URLError
from urllib.request import urlopen, Request
from html import unescape
from lxml.html import parse as html_parse
from lxml.etree import HTMLParser #pylint: disable=no-name-in-module
import re
import logging

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

LINK_RE = re.compile("(https?://.+?\\.[^`\\s]+)")
UTF8_PARSER = HTMLParser(encoding='utf-8')

class LinkEmptyException(Exception):
    '''vimcord.links exception for catching empty curl results'''

def open_and_parse_meta(link):
    '''Collect a list of all meta tags from the page at a URL'''
    html = urlopen(link)
    if not html:
        raise LinkEmptyException(
            f"Curl failed for {link.full_url if isinstance(link, Request) else link}"
        )

    full = []
    for meta_tag in html_parse(html, parser=UTF8_PARSER).iterfind(".//meta"):
        full.append(meta_tag.attrib)
    return full

@lru_cache(maxsize=128)
def _get_opengraph(link, *args):
    '''`get_opengraph` backend. Handles extra caching, but is intended to be run in a thread pool'''
    full = {}
    no_head = False
    if isinstance(link, str):
        request = Request(link, method="HEAD", headers={ "User-Agent": "curl" })
        response = urlopen(request)
        if not response:
            no_head = True
        else:
            # don't bother curling again if this isn't an html page
            content = response.headers.get("Content-Type")
            no_head = content.find("text/html") == -1

    if not no_head:
        for meta_tag in open_and_parse_meta(link):
            prop = meta_tag.get("property")
            if not prop or not prop.startswith("og:"):
                continue
            prop = prop[3:]
            content = meta_tag.get("content")
            if content is None:
                continue
            prev = full.get(prop)
            if prev is None:
                full[prop] = content
                continue
            if not isinstance(prev, list):
                full[prop] = [prev]
            full[prop].append(content)

    log.debug("Got opengraph: %s", full)
    if not args:
        return full
    if len(args) == 1:
        return full[args[0]]        #never try 1-tuple assignment
    return [full[i] if i in full else None for i in args]    #tuple unpacking

async def get_opengraph(link, *args, loop=None):
    '''
    Awaitable OpenGraph data, with HTML5 entities converted into unicode.
    If a tag repeats (like image), the value will be a list. Returns dict if no
    extra args supplied. Otherwise, for each in `*args`, return is such that
    `value1[, value2] = get_opengraph(..., key1[, key2])` formats correctly.
    '''
    if loop is None:
        loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, _get_opengraph, link, *args)

def unwrap_media(media_list):
    ret = []
    for i in media_list:
        if isinstance(i, list):
            ret.extend(i)
        elif i is not None:
            ret.append(i)
    return ret

class SpecialOpeners:
    OPENERS = {
        "twitter": re.compile(r"twitter\.com/.+/status"),
        "tenor": re.compile("tenor.com/(view)?"),
        "discord": re.compile("discord.com/channels"),
    }

    @classmethod
    def attempt(cls, link):
        for opener, regex in cls.OPENERS.items():
            log.debug("Trying opener %s", opener)
            if regex.search(link):
                return getattr(cls, opener)(link)
        return None

    @staticmethod
    async def title_and_description(link):
        # TODO: whitelist/blacklist links
        log.debug("Using default opener!")
        ret = []

        site_name, title, description, image, video = await get_opengraph(
            link,
            "site_name",
            "title",
            "description",
            "image",
            "video"
        )
        if title is not None:
            if site_name is not None:
                ret.append([
                    [
                        (site_name if isinstance(site_name, str) else site_name[0]) + ": ",
                        "VimcordOGSiteName"
                    ],
                    [title if isinstance(title, str) else title[0], "VimcordOGTitle"]
                ])
            else:
                ret.append([[
                    title if isinstance(title, str) else title[0],
                    "VimcordOGTitle"
                ]])
        if description is not None:
            ret.append([[
                description if isinstance(title, str) else title[0],
                "VimcordOGDescription"
            ]])
        # media content
        return ret, unwrap_media([image, video])

    @staticmethod
    async def twitter(link):
        # open through vxtwitter for opengraph
        re.sub("(https?://)(www.|mobile.|vx)?(twitter)", "\\1fx\\2", link)

        # title, image, video, desc
        title, description, images, video = await get_opengraph(
            Request(link, headers={"User-Agent": "Twitterbot"}),
            "title",
            "description",
            "image",
            "video"
        )

        who = re.sub("on (Twitter|X)", "", title or "")

        disp = [
                [["Twitter: ", "VimcordOGDefault"], [who, "VimcordOGTitle"]],
            *[[[i + ' ', "VimcordOGDescription"]]
              for i in description.split("\n") if i.rstrip()]
        ]
        additional = ""
        if video is not None:
            additional = "1 video"
        elif images:
            if isinstance(images, str):
                additional = "1 image"
            else:
                additional = f"{len(images)} images"

        if additional:
            disp.append([[additional, "VimcordAdditional"]])

        return disp, unwrap_media([images, video])

    @staticmethod
    async def tenor(link):
        image, video = await get_opengraph(link, "image", "video")
        return [], [unwrap_media([image, video])[0]]

    @staticmethod
    async def discord(link):
        return [], []

async def get_link_content(link, notify_func=lambda x: None):
    try:
        if (coro := SpecialOpeners.attempt(link)) is not None:
            return await coro
        return await SpecialOpeners.title_and_description(link)
    except LinkEmptyException:
        pass
    except (HTTPError, HTTPException, URLError) as e:
        notify_func("Error when curling link!", level=3)
        log.error("Error when curling link %s: %s", link, e, stack_info=True)
    return [], []

# for testing purposes
if __name__ == "__main__":
    import sys
    import json
    handler = logging.StreamHandler(sys.stdout)
    handler.setLevel(logging.DEBUG)
    log.addHandler(handler)

    # ret = asyncio.run(get_opengraph(sys.argv[1]), debug=True)
    ret = asyncio.run(get_link_content(sys.argv[1]), debug=True)
    print(json.dumps(ret))
