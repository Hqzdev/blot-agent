"""Browser sign-in and account requests for Blot coding sessions."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import secrets
import tempfile
import webbrowser
from collections.abc import Callable, Iterator
from contextlib import contextmanager, suppress
from dataclasses import asdict, dataclass
from datetime import UTC, datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from time import monotonic
from typing import Any
from urllib.parse import parse_qs, urlencode, urlsplit

import httpx

from pilot_agent.config.schema import default_home

DEFAULT_ORIGIN = "https://blot-agent.vercel.app"
CLIENT_ID = "blot-cli"
CALLBACK_PATH = "/oauth/blot"
TOKEN = re.compile(r"[A-Za-z0-9_-]{43}")


class AccountError(RuntimeError):
    def __init__(self, message: str, status: int = 0):
        super().__init__(message)
        self.status = status


@dataclass(frozen=True)
class AccountSession:
    origin: str
    accessToken: str
    refreshToken: str
    expiresAt: str

    @property
    def expires(self) -> datetime:
        return datetime.fromisoformat(self.expiresAt)

    @classmethod
    def parse(cls, origin: str, data: dict[str, Any]) -> AccountSession:
        try:
            access, refresh, expires = (
                data[key] for key in ("accessToken", "refreshToken", "expiresAt")
            )
            if not TOKEN.fullmatch(access) or not TOKEN.fullmatch(refresh):
                raise ValueError
            if datetime.fromisoformat(expires).tzinfo is None:
                raise ValueError
        except (KeyError, TypeError, ValueError) as exc:
            raise AccountError("Blot returned an invalid account session.") from exc
        return cls(origin, access, refresh, expires)


class BlotAccount:
    def __init__(self, *, home: Path | None = None, origin: str | None = None):
        candidate = origin or os.environ.get("BLOT_CLI_ORIGIN", DEFAULT_ORIGIN)
        uri = urlsplit(candidate)
        loopback = uri.scheme == "http" and uri.hostname == "127.0.0.1"
        if (
            (uri.scheme != "https" and not loopback)
            or not uri.hostname
            or uri.username
            or uri.password
            or uri.path not in {"", "/"}
            or uri.query
            or uri.fragment
        ):
            raise AccountError("BLOT_CLI_ORIGIN must be an HTTPS origin or local 127.0.0.1.")
        self.origin = f"{uri.scheme}://{uri.netloc}"
        self.path = (home or default_home()) / "blot-session.json"

    def request(
        self,
        method: str,
        path: str,
        *,
        payload: dict[str, Any] | None = None,
        access: str | None = None,
        timeout: float = 20,
    ) -> dict[str, Any]:
        headers = {"Accept": "application/json"}
        if access:
            headers["Authorization"] = f"Bearer {access}"
        try:
            response = httpx.request(
                method,
                self.origin + path,
                json=payload,
                headers=headers,
                timeout=timeout,
                follow_redirects=False,
            )
        except (httpx.HTTPError, ValueError) as exc:
            raise AccountError("Could not connect to the Blot API.") from exc
        if response.status_code == 401:
            raise AccountError("Blot sign-in expired. Run blot login.", 401)
        if response.status_code == 429:
            raise AccountError("Blot model request limit reached. Try again later.", 429)
        if response.status_code == 404:
            raise AccountError("This Blot server does not have the terminal API enabled.", 404)
        if not response.is_success:
            raise AccountError(
                f"Blot API request failed ({response.status_code}).", response.status_code
            )
        try:
            data = response.json() if response.content else None
        except ValueError as exc:
            raise AccountError("Blot returned an invalid API response.") from exc
        if data is not None and not isinstance(data, dict):
            raise AccountError("Blot returned an invalid API response.")
        return data or {}

    def check_model_api(self) -> dict[str, Any]:
        return self.authenticated_request("GET", "/v1/cli/model")

    def authenticated_request(
        self,
        method: str,
        path: str,
        *,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        session = self._session()
        try:
            return self.request(
                method, path, payload=payload, access=session.accessToken, timeout=95
            )
        except AccountError as exc:
            if exc.status != 401:
                raise
        refreshed = self._session(stale_access=session.accessToken)
        return self.request(method, path, payload=payload, access=refreshed.accessToken, timeout=95)

    def _session(self, *, stale_access: str | None = None) -> AccountSession:
        with self._locked():
            session = self._load()
            if session is None:
                raise AccountError("Sign in to Blot with blot login.", 401)
            if (
                session.accessToken != stale_access
                and (session.expires - datetime.now(UTC)).total_seconds() > 30
            ):
                return session
            data = self.request(
                "POST", "/v1/auth/refresh", payload={"refreshToken": session.refreshToken}
            )
            updated = AccountSession.parse(self.origin, data)
            self._save(updated)
            return updated

    def sign_in(self, notice: Callable[[str], None]) -> None:
        try:
            self.request("GET", "/v1/cli/model")
        except AccountError as exc:
            if exc.status != 401:
                raise
        verifier = secrets.token_urlsafe(32)
        state = secrets.token_urlsafe(32)
        challenge = (
            base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest())
            .decode()
            .rstrip("=")
        )
        with BrowserCallback(("127.0.0.1", 0), state) as callback:
            redirect = f"http://127.0.0.1:{callback.server_port}{CALLBACK_PATH}"
            browser_url = (
                self.origin
                + "/login?"
                + urlencode(
                    {
                        "response_type": "code",
                        "client_id": CLIENT_ID,
                        "redirect_uri": redirect,
                        "state": state,
                        "code_challenge": challenge,
                        "code_challenge_method": "S256",
                        "intent": "login",
                    }
                )
            )
            notice("Sign in to Blot in your browser. Open this URL if needed:\n" + browser_url)
            with suppress(webbrowser.Error):
                webbrowser.open(browser_url)
            code = callback.wait()
        data = self.request(
            "POST",
            "/v1/auth/browser/token",
            payload={
                "clientID": CLIENT_ID,
                "redirectURI": redirect,
                "code": code,
                "codeVerifier": verifier,
            },
        )
        with self._locked():
            self._save(AccountSession.parse(self.origin, data))

    def sign_out(self) -> None:
        with self._locked():
            session = self._load()
            if session is None:
                return
            try:
                if (session.expires - datetime.now(UTC)).total_seconds() <= 30:
                    data = self.request(
                        "POST", "/v1/auth/refresh", payload={"refreshToken": session.refreshToken}
                    )
                    session = AccountSession.parse(self.origin, data)
                    self._save(session)
                self.request("POST", "/v1/auth/logout", access=session.accessToken)
            except AccountError as exc:
                if exc.status != 401:
                    raise
            self.path.unlink(missing_ok=True)

    @contextmanager
    def _locked(self) -> Iterator[None]:
        import fcntl

        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with self.path.with_suffix(".lock").open("ab") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            yield

    def _load(self) -> AccountSession | None:
        try:
            with self.path.open(encoding="utf-8") as file:
                data = json.load(file)
        except FileNotFoundError:
            return None
        except (ValueError, OSError) as exc:
            raise AccountError("Could not read the Blot session. Run blot login.") from exc
        if not isinstance(data, dict) or data.get("origin") != self.origin:
            return None
        return AccountSession.parse(self.origin, data)

    def _save(self, session: AccountSession) -> None:
        fd, path = tempfile.mkstemp(prefix=".blot-session-", dir=self.path.parent)
        temporary = Path(path)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as file:
                json.dump(asdict(session), file)
            temporary.replace(self.path)
        finally:
            temporary.unlink(missing_ok=True)


class BrowserCallback(HTTPServer):
    def __init__(self, address: tuple[str, int], state: str):
        super().__init__(address, CallbackHandler)
        self.state = state
        self.code: str | None = None
        self.timeout = 0.5

    def get_request(self) -> tuple[Any, Any]:
        connection, address = super().get_request()
        connection.settimeout(2)
        return connection, address

    def wait(self) -> str:
        deadline = monotonic() + 180
        while self.code is None and monotonic() < deadline:
            self.handle_request()
        if self.code is None:
            raise AccountError("Browser sign-in timed out. Run blot login to try again.")
        return self.code


class CallbackHandler(BaseHTTPRequestHandler):
    server: BrowserCallback

    def do_GET(self) -> None:
        target = urlsplit(self.path)
        values = parse_qs(target.query, keep_blank_values=True)
        code = values.get("code", [])
        state = values.get("state", [])
        accepted = (
            self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"
            and target.path == CALLBACK_PATH
            and not target.netloc
            and not target.scheme
            and set(values) == {"code", "state"}
            and len(code) == len(state) == 1
            and TOKEN.fullmatch(code[0])
            and TOKEN.fullmatch(state[0])
            and secrets.compare_digest(state[0], self.server.state)
        )
        if accepted:
            self.server.code = code[0]
        self.send_response(200 if accepted else 400)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(
            b"Blot received the sign-in. Return to your terminal."
            if accepted
            else b"Invalid sign-in callback."
        )

    def log_message(self, format: str, *args: Any) -> None:
        # The callback URL contains an authorization code.
        pass
