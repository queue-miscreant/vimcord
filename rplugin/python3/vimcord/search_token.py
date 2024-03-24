import logging
import os
import re

log = logging.getLogger(__name__)
log.setLevel(logging.DEBUG)

def get_all_tokens(path):
    '''
    Search through `path` (which should be a discord config directory) for stored user tokens
    Implementation taken from wodxgod/Discord-Token-Grabber
    '''
    path = os.path.join(path, 'Local Storage', 'leveldb')
    tokens = {}

    for file_name in os.listdir(path):
        if not file_name.endswith('.log') and not file_name.endswith('.ldb'):
            continue

        log.debug("Searching file %s", file_name)
        file = os.path.join(path, file_name)
        time = os.path.getmtime(file)
        lines = []
        with open(file, errors='ignore') as a:
            lines = [line for line in map(lambda x: x.strip(), a.readlines()) if line]

        for line in lines:
            for regex in (r'[\w-]{24}\.[\w-]{6}\.[\w-]{27}', r'mfa\.[\w-]{84}'):
                for token in re.findall(regex, line):
                    if tokens.get(time) is None:
                        tokens[time] = []
                    tokens[time].append(token)

    return tokens

def search_latest_token(path):
    '''
    Pick the latest result from `get_all_tokens(path)`
    '''
    tokens = get_all_tokens(path)

    if not tokens:
        return None
    latest_key = sorted(tokens.keys(), reverse=True)[0]
    return tokens[latest_key][-1]

if __name__ == "__main__":
    import sys
    logging.basicConfig()
    get_all_tokens(sys.argv[1])
