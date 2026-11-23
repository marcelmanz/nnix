import asyncio
import json
import logging
import os
import socket
import struct
import time

from dbus_fast import BusType, Variant
from dbus_fast.aio import MessageBus
from dbus_fast.service import ServiceInterface, method
from websockets.asyncio.server import broadcast, serve
from websockets.exceptions import ConnectionClosed

PORT = int(os.environ["TV_MOUSE_PORT"])
HOST_FILE = os.path.join(os.environ["STATE_DIRECTORY"], "host")
ADAPTER_PATH = "/org/bluez/hci0"
PROFILE_PATH = "/cool/marcel/tvmouse/profile"
AGENT_PATH = "/cool/marcel/tvmouse/agent"
PAIRING_SECONDS = 120
RECONNECT_INTERVAL_SECONDS = 5

PSM_CONTROL = 0x11
PSM_INTERRUPT = 0x13
SOL_BLUETOOTH = 274
BT_SECURITY = 4
BT_SECURITY_MEDIUM = 2

# 3 buttons, relative X/Y/wheel; the first 3 bytes double as the boot protocol report
REPORT_DESCRIPTOR = bytes.fromhex(
    "05010902a1010901a100050919012903150025019503750181029501750581030501"
    "0930093109381581257f750895038106c0c0"
)

SERVICE_RECORD = f"""<?xml version="1.0" encoding="UTF-8" ?>
<record>
  <attribute id="0x0001"><sequence><uuid value="0x1124" /></sequence></attribute>
  <attribute id="0x0004"><sequence>
    <sequence><uuid value="0x0100" /><uint16 value="0x{PSM_CONTROL:04x}" /></sequence>
    <sequence><uuid value="0x0011" /></sequence>
  </sequence></attribute>
  <attribute id="0x0005"><sequence><uuid value="0x1002" /></sequence></attribute>
  <attribute id="0x0006"><sequence>
    <uint16 value="0x656e" /><uint16 value="0x006a" /><uint16 value="0x0100" />
  </sequence></attribute>
  <attribute id="0x0009"><sequence>
    <sequence><uuid value="0x1124" /><uint16 value="0x0100" /></sequence>
  </sequence></attribute>
  <attribute id="0x000d"><sequence><sequence>
    <sequence><uuid value="0x0100" /><uint16 value="0x{PSM_INTERRUPT:04x}" /></sequence>
    <sequence><uuid value="0x0011" /></sequence>
  </sequence></sequence></attribute>
  <attribute id="0x0100"><text value="TV Mouse" /></attribute>
  <attribute id="0x0101"><text value="Mouse" /></attribute>
  <attribute id="0x0102"><text value="mlab" /></attribute>
  <attribute id="0x0200"><uint16 value="0x0100" /></attribute>
  <attribute id="0x0201"><uint16 value="0x0111" /></attribute>
  <attribute id="0x0202"><uint8 value="0x80" /></attribute>
  <attribute id="0x0203"><uint8 value="0x00" /></attribute>
  <attribute id="0x0204"><boolean value="true" /></attribute>
  <attribute id="0x0205"><boolean value="true" /></attribute>
  <attribute id="0x0206"><sequence><sequence>
    <uint8 value="0x22" /><text encoding="hex" value="{REPORT_DESCRIPTOR.hex()}" />
  </sequence></sequence></attribute>
  <attribute id="0x0207"><sequence><sequence>
    <uint16 value="0x0409" /><uint16 value="0x0100" />
  </sequence></sequence></attribute>
  <attribute id="0x020b"><uint16 value="0x0100" /></attribute>
  <attribute id="0x020c"><uint16 value="0x0c80" /></attribute>
  <attribute id="0x020d"><boolean value="false" /></attribute>
  <attribute id="0x020e"><boolean value="true" /></attribute>
</record>
"""

HIDP_HANDSHAKE_SUCCESSFUL = 0x00
HIDP_HANDSHAKE_ERR_UNSUPPORTED_REQUEST = 0x03
HIDP_TRANS_HID_CONTROL = 0x1
HIDP_TRANS_GET_REPORT = 0x4
HIDP_TRANS_SET_REPORT = 0x5
HIDP_TRANS_GET_PROTOCOL = 0x6
HIDP_TRANS_SET_PROTOCOL = 0x7
HIDP_TRANS_GET_IDLE = 0x8
HIDP_TRANS_SET_IDLE = 0x9
HIDP_TRANS_DATA = 0xA
HIDP_CTRL_VIRTUAL_CABLE_UNPLUG = 0x5
HIDP_DATA_INPUT = 0xA1
HIDP_DATA_OTHER = 0xA0
PROTOCOL_BOOT = 0
PROTOCOL_REPORT = 1

log = logging.getLogger("tv-mouse")


def l2cap_socket():
    sock = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
    sock.setsockopt(SOL_BLUETOOTH, BT_SECURITY, struct.pack("BB", BT_SECURITY_MEDIUM, 0))
    sock.setblocking(False)
    return sock


def clamp(value, limit=127):
    return max(-limit, min(limit, value))


class HidLink:
    def __init__(self, on_change):
        self.control = None
        self.interrupt = None
        self.protocol = PROTOCOL_REPORT
        self.on_change = on_change
        self.send_lock = asyncio.Lock()
        self.reconnect_lock = asyncio.Lock()
        self.last_reconnect = 0.0

    @property
    def connected(self):
        return self.control is not None and self.interrupt is not None

    def close(self):
        for sock in (self.control, self.interrupt):
            if sock is not None:
                sock.close()
        was_connected = self.connected
        self.control = None
        self.interrupt = None
        if was_connected:
            log.info("disconnected")
        self.on_change()

    def attach(self, psm, sock, host):
        loop = asyncio.get_running_loop()
        if psm == PSM_CONTROL:
            if self.control is not None:
                self.close()
            self.control = sock
            self.protocol = PROTOCOL_REPORT
            loop.create_task(self.serve_control(sock))
        else:
            if self.interrupt is not None:
                self.interrupt.close()
            self.interrupt = sock
        if self.connected:
            log.info("connected to %s", host)
            with open(HOST_FILE, "w") as f:
                f.write(host)
        self.on_change()

    async def serve_control(self, sock):
        loop = asyncio.get_running_loop()
        while sock is self.control:
            try:
                message = await loop.sock_recv(sock, 64)
            except OSError:
                message = b""
            if sock is not self.control:
                return
            if not message:
                self.close()
                return
            reply = self.control_reply(message)
            if reply is not None:
                try:
                    await loop.sock_sendall(sock, reply)
                except OSError:
                    self.close()
                    return

    def control_reply(self, message):
        transaction, param = message[0] >> 4, message[0] & 0x0F
        if transaction == HIDP_TRANS_HID_CONTROL:
            if param == HIDP_CTRL_VIRTUAL_CABLE_UNPLUG:
                self.close()
            return None
        if transaction == HIDP_TRANS_GET_REPORT:
            return bytes([HIDP_DATA_INPUT]) + self.report(0, 0, 0, 0)
        if transaction == HIDP_TRANS_GET_PROTOCOL:
            return bytes([HIDP_DATA_OTHER, self.protocol])
        if transaction == HIDP_TRANS_SET_PROTOCOL:
            self.protocol = param & 0x01
            return bytes([HIDP_HANDSHAKE_SUCCESSFUL])
        if transaction == HIDP_TRANS_GET_IDLE:
            return bytes([HIDP_DATA_OTHER, 0])
        if transaction in (HIDP_TRANS_SET_REPORT, HIDP_TRANS_SET_IDLE):
            return bytes([HIDP_HANDSHAKE_SUCCESSFUL])
        if transaction == HIDP_TRANS_DATA:
            return None
        return bytes([HIDP_HANDSHAKE_ERR_UNSUPPORTED_REQUEST])

    def report(self, buttons, dx, dy, wheel):
        report = struct.pack("Bbbb", buttons & 0x07, dx, dy, wheel)
        return report[:3] if self.protocol == PROTOCOL_BOOT else report

    async def reconnect(self):
        if self.connected or not os.path.exists(HOST_FILE):
            return
        async with self.reconnect_lock:
            if self.connected or time.monotonic() - self.last_reconnect < RECONNECT_INTERVAL_SECONDS:
                return
            self.last_reconnect = time.monotonic()
            with open(HOST_FILE) as f:
                host = f.read().strip()
            loop = asyncio.get_running_loop()
            log.info("reconnecting to %s", host)
            try:
                for psm in (PSM_CONTROL, PSM_INTERRUPT):
                    sock = l2cap_socket()
                    await asyncio.wait_for(loop.sock_connect(sock, (host, psm)), 10)
                    self.attach(psm, sock, host)
            except (OSError, TimeoutError) as error:
                log.info("reconnect failed: %s", error)
                self.close()

    async def send(self, buttons, dx, dy, wheel):
        if not self.connected:
            asyncio.get_running_loop().create_task(self.reconnect())
            return
        loop = asyncio.get_running_loop()
        async with self.send_lock:
            first = True
            while first or dx or dy or wheel:
                first = False
                step_x, step_y, step_wheel = clamp(dx), clamp(dy), clamp(wheel)
                dx, dy, wheel = dx - step_x, dy - step_y, wheel - step_wheel
                try:
                    await loop.sock_sendall(
                        self.interrupt,
                        bytes([HIDP_DATA_INPUT]) + self.report(buttons, step_x, step_y, step_wheel),
                    )
                except (OSError, AttributeError):
                    self.close()
                    return


class Profile(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.Profile1")

    @method()
    def Release(self):
        pass

    @method()
    def NewConnection(self, device: "o", fd: "h", properties: "a{sv}"):
        pass

    @method()
    def RequestDisconnection(self, device: "o"):
        pass


class PairingAgent(ServiceInterface):
    def __init__(self):
        super().__init__("org.bluez.Agent1")

    @method()
    def Release(self):
        pass

    @method()
    def RequestAuthorization(self, device: "o"):
        pass

    @method()
    def RequestConfirmation(self, device: "o", passkey: "u"):
        pass

    @method()
    def AuthorizeService(self, device: "o", uuid: "s"):
        pass

    @method()
    def Cancel(self):
        pass


class TvMouse:
    def __init__(self):
        self.clients = set()
        self.link = HidLink(self.broadcast_status)
        self.pairing_until = 0.0
        self.bus = None

    def status(self):
        return json.dumps(
            {
                "connected": self.link.connected,
                "paired": os.path.exists(HOST_FILE),
                "pairing": max(0, round(self.pairing_until - time.monotonic())),
            }
        )

    def broadcast_status(self):
        broadcast(self.clients, self.status())

    async def bluez_interface(self, path, interface):
        introspection = await self.bus.introspect("org.bluez", path)
        return self.bus.get_proxy_object("org.bluez", path, introspection).get_interface(interface)

    async def setup_bluez(self):
        self.bus = await MessageBus(bus_type=BusType.SYSTEM, negotiate_unix_fd=True).connect()
        self.bus.export(PROFILE_PATH, Profile())
        self.bus.export(AGENT_PATH, PairingAgent())
        profile_manager = await self.bluez_interface("/org/bluez", "org.bluez.ProfileManager1")
        await profile_manager.call_register_profile(
            PROFILE_PATH,
            "00001124-0000-1000-8000-00805f9b34fb",
            {
                "ServiceRecord": Variant("s", SERVICE_RECORD),
                "Role": Variant("s", "server"),
                "RequireAuthentication": Variant("b", True),
                "RequireAuthorization": Variant("b", False),
            },
        )

    async def trust(self, host):
        try:
            device = await self.bluez_interface(
                f"{ADAPTER_PATH}/dev_{host.replace(':', '_')}", "org.bluez.Device1"
            )
            await device.set_trusted(True)
        except Exception as error:
            log.warning("could not trust %s: %s", host, error)

    async def start_pairing(self):
        if self.pairing_until > time.monotonic():
            return
        agent_manager = await self.bluez_interface("/org/bluez", "org.bluez.AgentManager1")
        adapter = await self.bluez_interface(ADAPTER_PATH, "org.bluez.Adapter1")
        await agent_manager.call_register_agent(AGENT_PATH, "NoInputNoOutput")
        await agent_manager.call_request_default_agent(AGENT_PATH)
        await adapter.set_pairable_timeout(PAIRING_SECONDS)
        await adapter.set_discoverable_timeout(PAIRING_SECONDS)
        await adapter.set_pairable(True)
        await adapter.set_discoverable(True)
        self.pairing_until = time.monotonic() + PAIRING_SECONDS
        log.info("pairing window open for %ss", PAIRING_SECONDS)
        self.broadcast_status()
        await asyncio.sleep(PAIRING_SECONDS)
        await agent_manager.call_unregister_agent(AGENT_PATH)
        self.pairing_until = 0.0
        log.info("pairing window closed")
        self.broadcast_status()

    async def listen(self, psm):
        loop = asyncio.get_running_loop()
        server = l2cap_socket()
        server.bind((socket.BDADDR_ANY, psm))
        server.listen(1)
        while True:
            sock, address = await loop.sock_accept(server)
            host = address[0]
            sock.setblocking(False)
            self.link.attach(psm, sock, host)
            if psm == PSM_CONTROL:
                loop.create_task(self.trust(host))

    async def handle_client(self, connection):
        self.clients.add(connection)
        loop = asyncio.get_running_loop()
        try:
            await connection.send(self.status())
            loop.create_task(self.link.reconnect())
            async for message in connection:
                data = json.loads(message)
                if data.get("pair"):
                    loop.create_task(self.start_pairing())
                elif "report" in data:
                    buttons, dx, dy, wheel = (int(value) for value in data["report"])
                    await self.link.send(buttons, dx, dy, wheel)
        except ConnectionClosed:
            pass
        finally:
            self.clients.discard(connection)

    async def run(self):
        await self.setup_bluez()
        loop = asyncio.get_running_loop()
        loop.create_task(self.listen(PSM_CONTROL))
        loop.create_task(self.listen(PSM_INTERRUPT))
        async with serve(self.handle_client, "127.0.0.1", PORT):
            log.info("listening on 127.0.0.1:%s", PORT)
            await asyncio.Future()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    asyncio.run(TvMouse().run())
