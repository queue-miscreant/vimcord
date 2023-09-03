import asyncio
from http.client import HTTPException    #for catching IncompleteRead
from urllib.error import HTTPError
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

async def urlopen_async(link, loop=None):
    '''Awaitable urllib.request.urlopen; run in a thread pool executor'''
    if loop is None:
        loop = asyncio.get_event_loop()
    try:
        ret = await loop.run_in_executor(None, urlopen, link)
        return ret
    except (HTTPError, HTTPException):
        return ""

async def open_and_parse_meta(link, loop=None):
    '''Collect a list of all meta tags from the page at a URL'''
    html = await urlopen_async(link, loop=loop)
    if not html:
        raise Exception(f"Curl failed for {repr(link)}")

    full = []
    for meta_tag in html_parse(html, parser=UTF8_PARSER).iterfind(".//meta"):
        full.append(meta_tag.attrib)
    return full

async def get_opengraph(link, *args, loop=None):
    '''
    Awaitable OpenGraph data, with HTML5 entities converted into unicode.
    If a tag repeats (like image), the value will be a list. Returns dict if no
    extra args supplied. Otherwise, for each in `*args`, return is such that
    `value1[, value2] = get_opengraph(..., key1[, key2])` formats correctly.
    '''
    full = {}
    no_head = False
    if isinstance(link, str):
        request = Request(link, method="HEAD", headers={ "User-Agent": "curl" })
        response = await urlopen_async(request, loop=loop)
        if not response:
            no_head = True
        else:
            # don't bother curling again if this isn't an html page
            content = response.headers.get("Content-Type")
            no_head = content.find("text/html") == -1

    if not no_head:
        for meta_tag in (await open_and_parse_meta(link, loop=loop)):
            prop = meta_tag.get("property")
            if not prop or not prop.startswith("og:"):
                continue
            prop = prop[3:]
            content = meta_tag["content"]
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

class SpecialOpeners:
    OPENERS = {
        "twitter": re.compile(r"twitter\.com/.+/status"),
        "tenor": re.compile("tenor.com/view"),
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

        site_name, title, description = await get_opengraph(
            link,
            "site_name",
            "title",
            "description"
        )
        if title is not None:
            if site_name is not None:
                ret.append([
                    [site_name + ": ", "VimcordOGDefault"],
                    [title, "VimcordOGTitle"]
                ])
            else:
                ret.append([[title, "VimcordOGTitle"]])
        if description is not None:
            ret.append([[description, "VimcordOGDescription"]])
        return ret

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
            *[[[i, "VimcordOGDescription"]]
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

        return disp

    @staticmethod
    async def tenor(link):
        return []

async def get_link_content(link):
    if (coro := SpecialOpeners.attempt(link)) is not None:
        return await coro
    return await SpecialOpeners.title_and_description(link)

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
