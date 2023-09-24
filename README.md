neovimpv
========

vimcord: a Vim plugin for discord


Feature List
------------

- Messages from unmuted channels displayed in buffer with appropriate name coloring
- Direct replies
- Member @ completion when writing replies
- Drag-and-drop image uploads
- Link previews from OpenGraph
- Intelligent link openers depending on media content
- Airline integration


Installation
------------

### Vundle

Place the following in `~/.config/nvim/init.vim`:
```vim
Plugin 'queue-miscreant/vimcord'  {'do': 'UpdateRemotePlugins'}
```
Make sure the file is sourced and run `:PluginInstall`.


Dependencies
------------

Requires the following Python packages:

- pynvim
- aiohttp
- websockets


### Optional Dependencies

The following programs are the default openers for media content.
Different ones can be used by the user, so they are not strictly required.

- Python:
    - requests
- mpv
- feh


### Disclaimer

The plugin comes with an older version of [Rapptz's discord library](https://github.com/Rapptz/discord.py),
with some minor modifications. It includes some small compatibility fixes to
work with later versions of asyncio (probably destroying what little
compatibility it implemented at the time) as well as implementing message
references.
It's supplied here because it still supports logging in via username and password
and it's what I'm most familiar with.


Commands
--------

### :Discord

The main command. Attempts to use credentials in global variables
(`g:vimcord_discord_username`, `g:vimcord_discord_password`) to log in. If
these variables are empty or not set, the user is prompted for them before
initiating the connection; afterward, the values are destroyed.

When a connection is made, two windows will be opened: one containing a
Discord buffer and a buffer for composing messages (the "reply buffer").

The Discord buffer contains all messages received from unmuted channels from
Discord. At this point, there isn't a way to show the contents of muted
channels. This may change in the future, but it's done to keep the amount of
noise in the window to a minimum. See "keybinds" for more.

The reply buffer is normally unenterable. Bindings from the Discord buffer will
place the cursor within its window in order to type a message.


### :KillDiscord

Kills the Discord daemon and closes Discord windows. At the moment, this
isn't supported very well. Use this at your own caution.


Keys
----

### Message buffer

| Key(s)    | Mnemonic          | Explanation
|-----------|-------------------|-------------------------------------------------------------
| `i`       | `i`nsert message  | Enters the reply buffer, targeting the channel of the message currently under the cursor
| `I`       | `I`nsert reply    | Like `i`, but marks the message under the cursor as a reference (i.e., a discord reply)
| `r`, `R`  | `r`eplace message | Attempts to retrieve the message under the cursor for editing and enters the reply buffer. Does not work if you are not the author of the post.
| `X`, `D`  | `D`elete message  | Attempts to delete the message under the cursor. These are shifted characters to unintentional deletions.
| `C`       | `C`end DM         | Enter the reply buffer, targetting a direct message with the post's author
| `<c-t>`   | (ctrl-t)          | Prompts the user for a channel name, as in the webapp's ctrl-t shortcut. When an existing channel is selected, enters the reply buffer targeting the channel.
| `A`       | `A`ppend message  | Functions similarly to `<c-t>`, but with unmuted channels only.
| `gW`      | `g`et `W`hen      | Displays the post time of the message under the cursor
| `K`       | `k` message       | Go to the message above the current one
| `J`       | `j` message       | Go to the message below the current one
| `gx`      | `G`o lin`ks`      | Attempts to open the word under the cursor as a link. Uses the currently-set link openers (see configuration)
| `<c-g>`   | (See above)       | Attempt to open the first link before the current cursor position using the same method as `gx`.
| `<a-g>`   | (See above)       | Attempt to open the first link before the current cursor position. Additional media content set on the message is opened, instead of the actual link.
| `<enter>` | Enter reference   | Attempt to find the referenced message in the buffer, then move the cursor to the line containing it

Note: after "entering" the reply buffer, you will be in insert mode in its window.


### Reply buffer

| Key(s)    | Mnemonic  | Explanation
|-----------|-----------|-------------------------------------------------------------
| `<c-c>`   | `C`ancel  | Returns the cursor to the previous window. Works in normal and insert mode.
| `<enter>` | Submit    | Submit the message using the means supplied when the buffer was entered. I.e., send or edit the message. Works in normal and insert modes. If you want to insert a newline, use `<s-enter>` instead.
| `@`       | `At` user | Starts completion based on the members of the channel currently targetted. `<tab>` and `<s-tab>` can be used to navigate this list. Only works in insert mode.

Note that leaving the reply buffer for any reason will cause its contents to be
deleted and the reply action (send message, edit) to be forgotten.


Configuration
-------------

### `g:vimcord_discord_username`, `g:vimcord_discord_password`

Login credentials for discord. It goes without saying that exposing these
in your `.vimrc` is dangerous and inadvisable.

Rather than plain text, these may also be specified in base64 by prefacing the
base64 string with `b64:`. This only makes it harder to read at a glance, and
does not confer any security benefits.


### `g:vimcord_dnd_paste_threshold`

The minimum number of inserted characters for which the reply buffer can
recognize that a file has been dragged-and-dropped to test for a filename.
When less than or equal to zero, disables, events in the reply buffer which
check for pastes are not bound.

Default value is 8 (enabled).


### `g:vimcord_shift_width`

The number of spaces inserted before message contents. The author of a message
is displayed on a separate line, with only one space prior. Runtime changes
will not be applied to old messages.

Default value is 4. Minimum value is 1.


### `g:vimcord_show_link_previews`

Whether or not to enable link previews. This mimics content displayed in the
Discord webapp, but without images.

Default value is 1 (enabled).


### `g:vimcord_max_suggested_servers`

The number of channels to display as suggestions when searching them by name.

Default value is 10.


### `g:vimcord_connection_refresh_interval_seconds`

Vim queries the plugin for its current Discord connection/login status periodically.
This is number of seconds between each query.

Default value is 60 (1 minute).


### `g:vimcord_image_opener`

Command name or path to executable to use to open image links.

Default value is `feh`.


### `g:vimcord_video_opener`

Command name or path to executable to use to open video links.

Default value is `mpv`.


### `g:vimcord_image_link_formats`

List of patterns which, when matched by a link, will be opened as an image
when using `gx` or `ctrl-g`.

Default values is an empty list.


### `g:vimcord_video_link_formats`

List of patterns which, when matched by a link, will be opened as a video
when using `gx` or `ctrl-g`.

Default value supports links from YouTube and TikTok.


### `g:vimcord_image_mimes`

List of MIME types which, when matched by the Content-Type header (acquired
by HEAD) of a link, will be opened as an image when using `gx` or `ctrl-g`.

Default value is `["image/png", "image/jpeg"]`


### `g:vimcord_video_mimes`

List of MIME types which, when matched by the Content-Type header (acquired
by HEAD) of a link, will be opened as a video when using `gx` or `ctrl-g`.

Default value is `["image/gif", "video/.*"]`


Highlights
----------

See the helpdoc for information regarding highlights.


TODOs
-----

- Planned soon
    - Make `<c-g>` and `<a-g>` better
        - Show all "media" (such as previews and opengraph videos) with the latter, not just opengraph images
    - Sorting the main buffer based on message channel id
        - Difficult because of extmarks
    - Closing reply buffer just hides it

- Unplanned - maybe soon?
    - Display user connection status (sign column tricks?)
    - Separate discord content out from "normal" reply window/message window pipeline (partially done)
    - Message deletion doesn't affect the first line of a message (requires the buffer knowing about Discord)

- Future work
    - Per-channel buffers: keep main accumulator, but extras can be opened (especially for muted channels)
    - Syntax for discord pseudo-markdown
    - Alternate display mode using `virt_lines_leftcol` for post authors
