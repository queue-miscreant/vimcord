import asyncio
from functools import lru_cache, partial
from http.client import HTTPException    #for catching IncompleteRead
from urllib.error import HTTPError, URLError
from html import unescape
from lxml.html import fromstring as html_parse
from lxml.etree import HTMLParser #pylint: disable=no-name-in-module
import re
import logging

requests = None

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

try:
    import requests
except ImportError:
    from urllib.request import urlopen, Request
    log.error("Could not import requests! implementing fallback.")

    class RequestsMock:
        def __init__(self, response):
            self.content = response.read()
            self.headers = response.headers

        @classmethod
        def get(cls, url, data=None, **params):
            '''
            Minimal `requests.get` implementation.
            Used here as a drop-in replacement with fewer features.
            '''
            request = Request(url, **params, method="GET")
            if data is None:
                return cls(urlopen(request))
            return cls(urlopen(request, data))

        @classmethod
        def head(cls, url, data=None, **params):
            '''
            Minimal `requests.head` implementation.
            Used here as a drop-in replacement with fewer features.
            '''
            if "allow_redirects" in params:
                del params["allow_redirects"]
            request = Request(url, **params, method="HEAD")
            if data is None:
                return cls(urlopen(request))
            return cls(urlopen(request, data))

    requests = RequestsMock

DEFAULT_ENCODING = "utf-8"
LINK_RE = re.compile("(https?://.+?\\.[^`\\s]+)")

class LinkEmptyException(Exception):
    '''vimcord.links exception for catching empty curl results'''

def open_and_parse_meta(link, encoding, user_agent):
    '''Collect a list of all meta tags from the page at a URL'''
    if user_agent is None:
        response = requests.get(link, headers={ "User-Agent": "curl" })
    else:
        response = requests.get(link, headers={ "User-Agent": user_agent })

    if not response.content:
        raise LinkEmptyException(
            f"Curl failed for {link}"
        )

    full = []
    parser = HTMLParser(encoding=encoding)
    for meta_tag in html_parse(response.content, parser=parser).iterfind(".//meta"):
        full.append(meta_tag.attrib)

    return full

def get_content_type(link, user_agent):
    if user_agent is None:
        response = requests.head(link, headers={ "User-Agent": "curl" }, allow_redirects=1)
    else:
        response = requests.head(link, headers={ "User-Agent": user_agent }, allow_redirects=1)

    encoding = DEFAULT_ENCODING
    content_type_data = response.headers.get("Content-Type", "text/html").split(";")
    charset = next(
        filter(lambda x: x.find("charset=") != -1, content_type_data),
        None
    )
    if charset is not None:
        encoding = charset.split("=")[1]

    return content_type_data[0], encoding

#TODO: mediawiki
@lru_cache(maxsize=128)
def _get_opengraph(link, *args, user_agent=None):
    '''`get_opengraph` backend. Handles extra caching, but is intended to be run in a thread pool'''
    full = {}

    content_type, encoding = get_content_type(link, user_agent)
    url = link

    if content_type == "text/html":
        for meta_tag in open_and_parse_meta(link, encoding, user_agent):
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
    # MIME-based pseudo-opengraph
    elif content_type.startswith("image/"):
        full["image"] = url
    elif content_type.startswith("video/"):
        full["video"] = url
    elif content_type.startswith("audio/"):
        full["audio"] = url

    log.info("Got opengraph: %s", full)
    if not args:
        return full
    if len(args) == 1:
        return full[args[0]]        #never try 1-tuple assignment
    return [full[i] if i in full else None for i in args]    #tuple unpacking

async def get_opengraph(link, *args, user_agent=None, loop=None):
    '''
    Awaitable OpenGraph data, with HTML5 entities converted into unicode.
    If a tag repeats (like image), the value will be a list. Returns dict if no
    extra args supplied. Otherwise, for each in `*args`, return is such that
    `value1[, value2] = get_opengraph(..., key1[, key2])` formats correctly.
    '''
    if loop is None:
        loop = asyncio.get_event_loop()
    return await loop.run_in_executor(None, lambda: _get_opengraph(link, *args, user_agent=None))

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
        "musk_twitter": re.compile(r"x\.com/.+/status"),
        "tenor": re.compile("tenor.com/(view)?"),
        "discord": re.compile("discord.com/channels"),
    }

    @classmethod
    def attempt(cls, link):
        for opener, regex in cls.OPENERS.items():
            log.info("Trying opener %s", opener)
            if regex.search(link):
                return getattr(cls, opener)(link)
        return None

    @staticmethod
    async def title_and_description(link):
        # TODO: whitelist/blacklist links
        log.info("Using default opener!")
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
        if isinstance(description, str):
            description = description.split("\n")
        if isinstance(description, list):
            ret.extend([
                [[
                    i.strip().rstrip(),
                    "VimcordOGDescription"
                ]]
            for i in description])
        # media content
        return ret, unwrap_media([image, video])

    @classmethod
    async def musk_twitter(cls, link):
        await cls.twitter(link.replace("x.com", "twitter.com"))

    @staticmethod
    async def twitter(link):
        # open through vxtwitter for opengraph
        link = re.sub("(https?://)(www.|mobile.|vx)?(twitter)", "\\1fx\\3", link)

        # title, image, video, desc
        title, description, images, video = await get_opengraph(
            link,
            "title",
            "description",
            "image",
            "video",
            user_agent="Twitterbot"
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

def _dummy_notify(message, level):
    pass

async def get_link_content(link, notify_func=_dummy_notify):
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
