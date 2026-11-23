from __future__ import annotations

import json
from typing import Any, Literal
from uuid import uuid4

from pilot_agent.agent.types import CompletionResponse, Message, Role, ToolCall, ToolSpec
from pilot_agent.cli.blot_account import AccountError, BlotAccount
from pilot_agent.providers.base import Provider
from pilot_agent.providers.hardening import parse_tool_arguments, sanitize_tool_schema


def _history(system: str, messages: list[Message], exposed: set[str]) -> list[dict[str, Any]]:
    system = "\n\n".join([system, *(item.content for item in messages if item.role is Role.SYSTEM)])
    result: list[dict[str, Any]] = [{"role": "system", "content": system}]
    active_phase = next((item.phase for item in reversed(messages) if item.role is Role.USER), None)
    for index, message in enumerate(messages):
        if message.role is Role.SYSTEM or message.role is Role.TOOL:
            continue
        row: dict[str, Any] = {"role": message.role.value, "content": message.content}
        result.append(row)
        if not message.tool_calls:
            continue
        following = messages[index + 1] if index + 1 < len(messages) else None
        outcomes = following.tool_results if following and following.role is Role.TOOL else []
        for call in message.tool_calls:
            outcome = next((item for item in outcomes if item.tool_call_id == call.id), None)
            if outcome is None:
                continue
            detail = json.dumps(
                {"output": outcome.content, "error": outcome.is_error}, ensure_ascii=False
            )
            if (
                len(message.tool_calls) == 1 and call.state_id
                and call.name in exposed and message.phase == active_phase
            ):
                row["function_call"] = {"name": call.name, "arguments": call.arguments}
                row["functions_state_id"] = call.state_id
                result.append({"role": "function", "name": call.name, "content": detail})
            else:
                # History from another provider or mode still supplies context.
                row["content"] += f"\nTool {call.name}: {detail}"
    if len(result) == 1:
        result.append({"role": "user", "content": "Continue."})
    return result


class BlotProvider(Provider):
    def __init__(self, account: BlotAccount, configuration: dict[str, Any]):
        model = configuration.get("model")
        context = configuration.get("contextTokens")
        if (
            not isinstance(model, str)
            or not model
            or not isinstance(context, int)
            or context < 8192
        ):
            raise AccountError("Blot returned an invalid model configuration.")
        super().__init__(model=model, api_key="", base_url=account.origin)
        self.account = account
        self._context_window = context

    def _complete(
        self,
        system: str,
        messages: list[Message],
        tools: list[ToolSpec],
        max_tokens: int = 4096,
    ) -> CompletionResponse:
        payload: dict[str, Any] = {
            "messages": _history(system, messages, {tool.name for tool in tools}),
            "max_tokens": max_tokens,
        }
        if tools:
            payload["functions"] = [
                {
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": sanitize_tool_schema(tool.parameters),
                }
                for tool in tools
            ]
        data = self.account.authenticated_request(
            "POST",
            "/v1/cli/model",
            payload=payload,
        )
        return self._response(data)

    @staticmethod
    def _response(data: dict[str, Any]) -> CompletionResponse:
        try:
            choice = data["choices"][0]
            reply = choice["message"]
            content = reply.get("content") or ""
            if not isinstance(content, str):
                raise ValueError
            message = Message(role=Role.ASSISTANT, content=content)
            call = reply.get("function_call")
            reason: Literal["tool_use", "max_tokens", "end_turn"]
            if call or choice.get("finish_reason") == "function_call":
                name, state = call["name"], reply["functions_state_id"]
                if not isinstance(name, str) or not isinstance(state, str) or not state:
                    raise ValueError
                arguments = call.get("arguments")
                if isinstance(arguments, dict):
                    arguments = json.dumps(arguments)
                parsed = parse_tool_arguments(arguments, tool_name=name)
                if not parsed.ok:
                    raise AccountError("Blot model returned invalid tool arguments.")
                message.tool_calls.append(ToolCall(uuid4().hex, name, parsed.arguments, state))
                reason = "tool_use"
            elif choice.get("finish_reason") in {"length", "max_tokens"}:
                reason = "max_tokens"
            else:
                reason = "end_turn"
            usage = data.get("usage") or {}
            return CompletionResponse(
                message,
                reason,
                {
                    "input_tokens": int(usage.get("prompt_tokens", 0)),
                    "output_tokens": int(usage.get("completion_tokens", 0)),
                },
            )
        except (AttributeError, KeyError, IndexError, TypeError, ValueError) as exc:
            raise AccountError("Blot returned an invalid model response.") from exc

    def count_tokens(self, system: str, messages: list[Message]) -> int:
        encoded = json.dumps(_history(system, messages, set()), ensure_ascii=False).encode()
        return (len(encoded) + 2) // 3

    @property
    def context_window(self) -> int:
        return self._context_window
