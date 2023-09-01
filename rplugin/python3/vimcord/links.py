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
            no_head = not content.find("text/html")

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

    if not args:
        return full
    if len(args) == 1:
        return full[args[0]]        #never try 1-tuple assignment
    return [full[i] if i in full else None for i in args]    #tuple unpacking

class SpecialOpeners:
    OPENERS = {
        "twitter": re.compile(r"twitter\.com/.+/status"),
    }

    @classmethod
    def attempt(cls, bridge, link):
        for opener, regex in cls.OPENERS.items():
            log.debug("Trying opener %s", opener)
            if regex.search(link):
                log.debug("Success!")
                return getattr(cls, opener)(bridge, link)
        return None

    @staticmethod
    async def title_and_description(bridge, link):
        # TODO: whitelist/blacklist links
        log.debug("Using default opener!")
        title, description = await get_opengraph(link, "title", "description")
        if title is not None and description is not None:
            if not description:
                return [[[title, "VimcordOGTitle"]]]
            if not title:
                return [[[description, "VimcordOGDescription"]]]
            return [
                [[title, "VimcordOGTitle"]],
                [[description, "VimcordOGDescription"]]
            ]
        return []

    @staticmethod
    async def twitter(bridge, link):
        mobile_link = link.find("mobile.twitter")
        if mobile_link != -1:
            link = link[:mobile_link] + link[mobile_link+7:]

        # title, image, video, desc
        meta_tags = await open_and_parse_meta(
            Request(link, headers={"User-Agent": "Twitterbot"}),
        )
        image = [i["content"] for i in meta_tags if i.get("itemprop") == "contentUrl"]
        title = next(filter(
            lambda x: x.get("property") == "og:title",
            meta_tags
        ), { "content": "" })["content"]
        desc = next(filter(
            lambda x: x.get("property") == "og:description",
            meta_tags
        ), { "content": "" })["content"]
        has_video = any(map(
            lambda x: x == "Embedded video",
            [i["content"] for i in meta_tags if i.get("itemprop") == "description"]
        ))

        #no, I'm not kidding, twitter double-encodes the HTML entities
        #but most parsers are insensitive to this because of the following:
        #"&amp;amp;..." = "(&amp;)..." -> "(&)amp;..." -> "(&amp;)..." -> "&..."
        try:
            who = unescape(title[:title.rfind(" on Twitter")])
            desc = unescape(desc[1:-1]) #remove quotes
        except AttributeError:
            return [[["Curl failed to find tag!", "VimcordError"]]]

        disp = [[[who, "VimcordOGTitle"]], [[desc, "VimcordOGDescription"]]]
        additional = ""
        if has_video:
            additional = "1 video"
        elif len(image) == 1:
            additional = "1 image"
        elif image:
            additional = f"{len(image)} images"

        if additional:
            disp.append([additional, "VimcordAdditional"])

        return disp

async def get_link_content(bridge, link):
    if (coro := SpecialOpeners.attempt(bridge, link)) is not None:
        return await coro
    return await SpecialOpeners.title_and_description(bridge, link)

# for testing purposes
if __name__ == "__main__":
    import sys
    import json
    ret = asyncio.run(get_opengraph(sys.argv[1]), debug=True)
    print(json.dumps(ret))
