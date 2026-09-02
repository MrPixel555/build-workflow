from __future__ import annotations

import argparse
import selectors
import socket
import socketserver
import struct
import threading
from pathlib import Path


class SocksHandler(socketserver.BaseRequestHandler):
    def handle(self) -> None:
        client = self.request
        client.settimeout(15)
        header = client.recv(2)
        if len(header) != 2 or header[0] != 5:
            return
        methods = client.recv(header[1])
        if not methods:
            return
        client.sendall(b"\x05\x00")

        request = self._recv_exact(client, 4)
        if request[0] != 5 or request[1] != 1:
            client.sendall(b"\x05\x07\x00\x01\x00\x00\x00\x00\x00\x00")
            return

        atyp = request[3]
        if atyp == 1:
            host = socket.inet_ntoa(self._recv_exact(client, 4))
        elif atyp == 3:
            length = self._recv_exact(client, 1)[0]
            host = self._recv_exact(client, length).decode("idna")
        elif atyp == 4:
            host = socket.inet_ntop(socket.AF_INET6, self._recv_exact(client, 16))
        else:
            client.sendall(b"\x05\x08\x00\x01\x00\x00\x00\x00\x00\x00")
            return
        port = struct.unpack("!H", self._recv_exact(client, 2))[0]

        self.server.log_destination(host, port)  # type: ignore[attr-defined]
        try:
            remote = socket.create_connection((host, port), timeout=15)
        except OSError:
            client.sendall(b"\x05\x05\x00\x01\x00\x00\x00\x00\x00\x00")
            return

        with remote:
            client.sendall(b"\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x00")
            client.setblocking(False)
            remote.setblocking(False)
            selector = selectors.DefaultSelector()
            selector.register(client, selectors.EVENT_READ, remote)
            selector.register(remote, selectors.EVENT_READ, client)
            while True:
                events = selector.select(timeout=30)
                if not events:
                    return
                for key, _ in events:
                    source = key.fileobj
                    destination = key.data
                    try:
                        data = source.recv(65536)
                    except OSError:
                        return
                    if not data:
                        return
                    try:
                        destination.sendall(data)
                    except OSError:
                        return

    @staticmethod
    def _recv_exact(sock: socket.socket, length: int) -> bytes:
        chunks = bytearray()
        while len(chunks) < length:
            chunk = sock.recv(length - len(chunks))
            if not chunk:
                raise ConnectionError("unexpected EOF")
            chunks.extend(chunk)
        return bytes(chunks)


class ThreadingSocksServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], log_path: Path):
        super().__init__(address, SocksHandler)
        self.log_path = log_path
        self.log_lock = threading.Lock()

    def log_destination(self, host: str, port: int) -> None:
        with self.log_lock:
            with self.log_path.open("a", encoding="utf-8") as stream:
                stream.write(f"{host}:{port}\n")
                stream.flush()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=10808)
    parser.add_argument("--log", type=Path, required=True)
    args = parser.parse_args()
    args.log.parent.mkdir(parents=True, exist_ok=True)
    server = ThreadingSocksServer((args.host, args.port), args.log)
    print(f"SOCKS5 test relay listening on {args.host}:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
