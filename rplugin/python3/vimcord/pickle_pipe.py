'''
pickle_server.py

A simple client/server protocol which can forward events and respond to
requests for members and methods.
'''
import asyncio
import base64
import gzip
import json
import logging
import pickle

log = logging.getLogger(__name__)
log.setLevel("DEBUG")

class PicklePipeException(Exception):
    '''Exception object passed when pickling errors occur'''

def decode_for_pipe(data):
    unb64 = base64.b64decode(data)
    dilute = gzip.decompress(unb64)
    return pickle.loads(dilute)

def encode_for_pipe(obj):
    pickled = pickle.dumps(obj)
    concentrate = gzip.compress(pickled)
    return base64.b64encode(concentrate) + b"\n"

def convert_return(obj):
    '''
    Convert an object into a form suitable for pickling.
    For example, `dict_value`s are not picklable, but `list`s are.
    '''
    # TODO: or dict-like?
    if isinstance(obj, dict):
        return obj
    try:
        return [i for i in obj]
    except:
        pass
    return obj

class PickleServerProtocol(asyncio.Protocol):
    '''
    Small server protocol which can respond to queries based on a reference
    object provided. Can also emit server-side events.
    Queries and responses are gzipped pickles encoded in base64.

    Queries are of the form `[request_id, path, *args]`, where path is a period
    (.)-separated sequence of names which are iteratively applied to the base
    object with getattr. If the path resolves to a member, `args` do nothing,
    and the object is sent in response. If the path instead resolves to a
    method, it is called using `args` provided. When the method is a coroutine,
    the result is awaited before writing the response.

    Responses are of the form [request_id, data], where data contains the
    result of the query.

    Events are of the form `["event", event_name, *data]`, where data comes from
    the event handler.
    '''
    def __init__(self, obj, log: logging.Logger):
        self.transport = None
        self.reference_object = obj
        self.log = log

    def connection_made(self, transport):
        '''Process communication initiated. Save transport and send connected event.'''
        self.transport = transport
        self.log.debug("Connected!")

    def data_received(self, data):
        '''Reply to data request with pickle'''
        try:
            if not data.rstrip(): return
            unpickled = decode_for_pipe(data)
            asyncio.get_event_loop().create_task(self._reply(unpickled))
        except Exception as e:
            self.log.error("Error %s occurred during read!", e, stack_info=True)

    def connection_lost(self, exc):
        '''Process communication closed. Call close event.'''
        self.transport = None
        self.log.error("Connection lost! %s", exc)

    def write(self, base, args):
        if self.transport is not None:
            try:
                self.transport.write(encode_for_pipe(base + args))
            except pickle.PicklingError:
                self.log.error("Could not pickle %s!", args)
                self.transport.write(encode_for_pipe(base + [PicklePipeException()]))

    async def _reply(self, unpickled):
        request_id, verb, data = unpickled
        args, kwargs = data

        # getattrs until we're at the method we want
        base = self.reference_object
        path = verb.split(".")[1:]
        for fragment in path:
            base = getattr(base, fragment)

        if request_id == -1:
            if asyncio.iscoroutinefunction(base):
                self.log.debug("Creating task for coroutine %s", base)
                asyncio.get_event_loop().create_task(base(*args, **kwargs))
            else:
                self.log.debug("Creating task for method %s", base)
                asyncio.get_event_loop().call_soon(base, *args, **kwargs)
                # self.log.error("Requested path (%s) is not a coroutine function!", verb)
                # self.write(
                #     [request_id],
                #     [PicklePipeException("Requested path is not a coroutine function!")]
                # )
            return

        if not callable(base):
            self.log.debug("Got member %s", verb)
            self.write([request_id], [convert_return(base)])
            return

        self.log.debug("Running method %s", verb)
        ret = base(*args, **kwargs)
        if asyncio.iscoroutine(ret):
            self.log.debug("Awaiting coroutine")
            ret = await ret

        self.write([request_id], [convert_return(ret)])

    def get_event_handler(self, event_name):
        async def event_handler(*data):
            self.write(["event", event_name], list(data))
        return event_handler

class PickleClientProtocol(asyncio.Protocol):
    '''
    Small client protocol for corresponding with PickleClientProtocol.
    Queries and responses are gzipped pickles encoded in base64.

    Supports asynchronous queries to the server with `wait_for`, with the
    path provided as the first argument and remaining arguments as arguments to
    the server method.

    Can bind events from the server to callbacks with signature (*data)
    '''
    def __init__(self):
        self.transport = None
        self._events = {}

        self._waiting_property = {}
        self._request_number = 0

    def connection_made(self, transport):
        '''Process communication initiated; save transport.'''
        self.transport = transport

    def data_received(self, data):
        '''
        Split out received data into individual pickles.
        Respond to events and waiting data.
        '''
        #TODO: investigate better serialization
        for i in data.split(b"\n"):
            try:
                if not i.rstrip(): continue
                unpickle = decode_for_pipe(i)
                # got bad data
                if not isinstance(unpickle, list) or len(unpickle) < 2:
                    self._call_event("PROTOCOL_UNKNOWN_DATA", unpickle)
                    log.warn("Unknown data received over pipe")
                    log.debug(unpickle)
                    continue

                # actually handle the data
                # events
                if unpickle[0] == "event":
                    if len(unpickle) >= 3 and isinstance(unpickle[2], PicklePipeException):
                        self._call_event("PROTOCOL_ERROR", unpickle[1])
                        continue
                    self._call_event(unpickle[1], unpickle[2:])
                elif (waiting_future := self._waiting_property.get(unpickle[0])) is not None:
                    if isinstance(unpickle[1], PicklePipeException):
                        waiting_future.cancel()
                        continue
                    waiting_future.set_result(unpickle[1])
            except Exception as e:
                log.error("Error occurred in received data: %s", e, stack_info=True)

    def connection_lost(self, exc):
        '''Process communication closed. Call close event.'''

    def event(self, event_name, handler):
        '''
        Bind event `handler` to event `event_name`.
        Handler should have matching arguments to the event emitted by the server.
        '''
        if event_name not in self._events:
            self._events[event_name] = []

        if not asyncio.iscoroutinefunction(handler):
            raise TypeError("Handled function must be coroutine!")

        self._events[event_name].append(handler)

    async def wait_for(self, action, *args, **kwargs):
        '''
        Request remote data from the server's reference object.
        The remote data can be a method, in which case it will be called with (*args)
        '''
        self.transport.write(encode_for_pipe([
            self._request_number,
            action,
            [ args, kwargs ]
        ]))

        future = asyncio.get_event_loop().create_future()
        self._waiting_property[self._request_number] = future
        self._request_number += 1

        return await future

    def create_remote_task(self, action, *args, **kwargs):
        '''
        Start a task on the remote server, without waiting for any results
        '''
        self.transport.write(encode_for_pipe([
            -1,
            action,
            [ args, kwargs ]
        ]))

    def _call_event(self, event_name, args):
        '''Run event callbacks for the events registered to event_name'''
        log.debug("Dispatching event %s", event_name)
        asyncio.gather(*[handler(*args) for handler in self._events.get(event_name, [])])
