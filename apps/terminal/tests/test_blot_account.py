from __future__ import annotations

import base64
import hashlib
import json
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest
from typer.testing import CliRunner

from pilot_agent.agent.types import Message, Role, ToolResult, ToolSpec, from_json, to_json
from pilot_agent.cli import main
from pilot_agent.cli.blot_account import AccountError, BlotAccount
from pilot_agent.providers.blot import BlotProvider

OLD_ACCESS, OLD_REFRESH, NEW_ACCESS, NEW_REFRESH = (character * 43 for character in "arbt")
CODE = "c" * 43


def tokens(access: str, refresh: str, *, seconds: int = 900) -> dict[str, str]:
    return {
        "accessToken": access,
        "refreshToken": refresh,
        "expiresAt": (datetime.now(UTC) + timedelta(seconds=seconds)).isoformat(),
    }


def test_browser_callback_checks_state_and_exchanges_pkce(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    account = BlotAccount(home=tmp_path, origin="https://blot.example")
    browser = {}
    request = httpx.request

    def open_browser(url: str) -> bool:
        browser.update({k: v[0] for k, v in parse_qs(urlsplit(url).query).items()})

        def callback() -> None:
            with httpx.Client(trust_env=False) as client:
                redirect = browser["redirect_uri"]
                wrong = client.get(redirect, params={"state": "z" * 43, "code": CODE})
                assert wrong.status_code == 400
                accepted = client.get(redirect, params={"state": browser["state"], "code": CODE})
                assert accepted.status_code == 200

        future = pool.submit(callback)
        futures.append(future)
        return True

    def exchange(method: str, url: str, **kwargs: object) -> httpx.Response:
        if url.startswith("http://"):
            return request(method, url)
        if method == "GET" and url.endswith("/v1/cli/model"):
            return httpx.Response(401, json={"code": "session_required"})
        assert method == "POST" and url == "https://blot.example/v1/auth/browser/token"
        body = kwargs["json"]
        assert isinstance(body, dict)
        assert body["code"] == CODE
        assert body["redirectURI"] == browser["redirect_uri"]
        assert body["clientID"] == "blot-cli"
        digest = hashlib.sha256(body["codeVerifier"].encode()).digest()
        assert base64.urlsafe_b64encode(digest).decode().rstrip("=") == browser["code_challenge"]
        return httpx.Response(200, json=tokens(OLD_ACCESS, OLD_REFRESH))

    monkeypatch.setattr("webbrowser.open", open_browser)
    monkeypatch.setattr("httpx.request", exchange)
    with ThreadPoolExecutor() as pool:
        futures = []
        account.sign_in(lambda _: None)
        for future in futures:
            future.result()
    assert json.loads(account.path.read_text())["accessToken"] == OLD_ACCESS
    assert os.stat(account.path).st_mode & 0o777 == 0o600


def test_run_defaults_to_blot_and_refreshes_saved_session(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(tmp_path)
    monkeypatch.setenv("PILOT_AGENT_HOME", str(tmp_path / "home"))
    monkeypatch.setenv("BLOT_CLI_ORIGIN", "https://blot.example")
    account = BlotAccount()
    account.path.parent.mkdir()
    account.path.write_text(
        json.dumps(
            {
                "origin": account.origin,
                **tokens(OLD_ACCESS, OLD_REFRESH, seconds=-1),
            }
        )
    )
    paths = []

    def remote(method: str, url: str, **kwargs: object) -> httpx.Response:
        path = urlsplit(url).path
        paths.append(path)
        if path.endswith("/refresh"):
            assert kwargs["json"] == {"refreshToken": OLD_REFRESH}
            return httpx.Response(200, json=tokens(NEW_ACCESS, NEW_REFRESH))
        headers = kwargs["headers"]
        assert isinstance(headers, dict) and headers["Authorization"] == f"Bearer {NEW_ACCESS}"
        assert path == "/v1/cli/model"
        if method == "GET":
            return httpx.Response(200, json={"model": "GigaChat-2", "contextTokens": 32768})
        return httpx.Response(200, json={"choices": [{"message": {"content": "Account works"}}]})

    monkeypatch.setattr("httpx.request", remote)
    result = CliRunner().invoke(main.app, ["run", "Inspect this project"], prog_name="blot")
    assert result.exit_code == 0, result.output
    assert "Account works" in result.output
    assert paths == ["/v1/auth/refresh", "/v1/cli/model", "/v1/cli/model"]
    assert json.loads(account.path.read_text())["refreshToken"] == NEW_REFRESH


def test_function_result_and_provider_state_survive_the_session(tmp_path: Path) -> None:
    provider = BlotProvider(
        BlotAccount(home=tmp_path), {"model": "GigaChat", "contextTokens": 32768}
    )
    response = provider._response(
        {
            "choices": [
                {
                    "finish_reason": "function_call",
                    "message": {
                        "function_call": {"name": "read_file", "arguments": {"path": "main.py"}},
                        "functions_state_id": "saved-state",
                    },
                }
            ]
        }
    )
    restored = from_json(to_json(response.message))
    assert isinstance(restored, Message)
    assert restored.tool_calls[0].state_id == "saved-state"
    result = Message(role=Role.TOOL, tool_results=[ToolResult(restored.tool_calls[0].id, "answer")])
    tool = ToolSpec("read_file", "Read", {"type": "object"})

    def complete(method: str, path: str, *, payload: dict) -> dict:
        assert payload["messages"][2]["functions_state_id"] == "saved-state"
        assert payload["messages"][3] == {
            "role": "function",
            "name": "read_file",
            "content": '{"output": "answer", "error": false}',
        }
        return {"choices": [{"message": {"content": "Done"}}]}

    provider.account.authenticated_request = complete
    response = provider.complete(
        "System", [Message(role=Role.USER, content="Read"), restored, result], [tool]
    )
    assert response.message.content == "Done"


def test_noninteractive_run_requests_login_without_opening_browser(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("PILOT_AGENT_HOME", str(tmp_path))
    with pytest.raises(AccountError, match="blot login"):
        BlotAccount().check_model_api()
