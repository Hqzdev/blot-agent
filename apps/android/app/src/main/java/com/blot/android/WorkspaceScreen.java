package com.blot.android;

import android.content.Context;
import android.text.InputType;
import android.view.View;
import android.widget.*;
import dev.blot.client.WorkspaceClient;
import dev.blot.core.v3.*;
import java.util.*;

final class WorkspaceScreen extends LinearLayout {
    private final EditText address, token, agentName, model, instructions, draft;
    private final TextView status, transcript;
    private final Spinner agents, conversations;
    private final Button connect, addAgent, addChat, send, refresh;
    private WorkspaceClient.State state;

    WorkspaceScreen(Context context) {
        super(context);
        setOrientation(VERTICAL); setPadding(24, 24, 24, 16);
        address = input("HTTPS-адрес сервера");
        token = input("Сессия устройства"); token.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        connect = button("Подключиться"); refresh = button("Обновить");
        status = new TextView(context); addView(status);
        var agentFields = new LinearLayout(context); agentFields.setOrientation(VERTICAL);
        agentName = field(agentFields, "Имя агента"); model = field(agentFields, "Модель"); model.setText("GigaChat"); instructions = field(agentFields, "Инструкции агента");
        var details = new TextView(context); details.setText("Создать агента ▾"); addView(details); addView(agentFields); agentFields.setVisibility(GONE);
        details.setOnClickListener(v -> agentFields.setVisibility(agentFields.getVisibility() == GONE ? VISIBLE : GONE));
        addAgent = new Button(context); addAgent.setText("Создать агента"); agentFields.addView(addAgent);
        agents = new Spinner(context); addView(agents); addChat = button("Новый чат");
        conversations = new Spinner(context); addView(conversations);
        transcript = new TextView(context); transcript.setTextIsSelectable(true); transcript.setTextSize(16);
        var scroll = new ScrollView(context); scroll.addView(transcript); addView(scroll, new LayoutParams(LayoutParams.MATCH_PARENT, 0, 1));
        draft = input("Сообщение"); draft.setMaxLines(4); draft.setSingleLine(false); send = button("Отправить");
        conversations.setOnItemSelectedListener(new AdapterView.OnItemSelectedListener() {
            public void onItemSelected(AdapterView<?> parent, View view, int position, long id) { renderMessages(); }
            public void onNothingSelected(AdapterView<?> parent) { renderMessages(); }
        });
        busy(false);
    }
    private EditText input(String hint) { return field(this, hint); }
    private EditText field(LinearLayout parent, String hint) {
        var field = new EditText(getContext()); field.setHint(hint); field.setSingleLine(true); parent.addView(field); return field;
    }
    private Button button(String title) { var value = new Button(getContext()); value.setText(title); addView(value); return value; }
    void bind(Runnable connection, Runnable agent, Runnable chat, Runnable message, Runnable update) {
        connect.setOnClickListener(v -> connection.run()); addAgent.setOnClickListener(v -> agent.run()); addChat.setOnClickListener(v -> chat.run()); send.setOnClickListener(v -> message.run()); refresh.setOnClickListener(v -> update.run());
    }
    String address() { return address.getText().toString().trim(); }
    String token() { return token.getText().toString().trim(); }
    String agentName() { return agentName.getText().toString().trim(); }
    String instructions() { return instructions.getText().toString(); }
    String model() { return model.getText().toString().trim(); }
    String draft() { return draft.getText().toString(); }
    void restoreDraft(String value) { draft.setText(value); }
    void clearDraft() { draft.setText(""); }
    void error(String message) { status.setText(message); }
    void connected() { token.setText(""); }
    void busy(boolean value) {
        connect.setEnabled(!value); refresh.setEnabled(!value && state != null); addAgent.setEnabled(!value && state != null); addChat.setEnabled(!value && state != null); send.setEnabled(!value && state != null);
    }
    AgentProfile selectedAgent() { int i = agents.getSelectedItemPosition(); return state == null || i < 0 || i >= state.agents().size() ? null : state.agents().get(i); }
    Conversation selectedConversation() { int i = conversations.getSelectedItemPosition(); return state == null || i < 0 || i >= state.conversations().size() ? null : state.conversations().get(i); }
    void render(WorkspaceClient.State next) {
        UUID agent = selectedAgent() == null ? null : selectedAgent().metadata().id();
        UUID conversation = selectedConversation() == null ? null : selectedConversation().metadata().id();
        state = next;
        agents.setAdapter(adapter(next.agents().stream().map(AgentProfile::name).toList()));
        conversations.setAdapter(adapter(next.conversations().stream().map(Conversation::title).toList()));
        int selected = 0;
        for (int i = 0; i < next.agents().size(); i++) if (next.agents().get(i).metadata().id().equals(agent)) selected = i;
        agents.setSelection(selected);
        selected = Math.max(0, next.conversations().size() - 1);
        for (int i = 0; i < next.conversations().size(); i++) if (next.conversations().get(i).metadata().id().equals(conversation)) selected = i;
        conversations.setSelection(selected); renderMessages();
    }
    private ArrayAdapter<String> adapter(List<String> values) {
        var adapter = new ArrayAdapter<String>(getContext(), android.R.layout.simple_spinner_item, values);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item); return adapter;
    }
    private void renderMessages() {
        var conversation = selectedConversation(); if (conversation == null) { transcript.setText(""); return; }
        var text = new StringBuilder();
        for (var message : state.messages()) if (message.conversationId().equals(conversation.metadata().id())) {
            text.append(message.role() == MessageRole.USER ? "Вы" : "Агент").append("\n");
            text.append(message.content().isEmpty() ? delivery(message.delivery()) : message.content()).append("\n\n");
        }
        if (!transcript.getText().toString().contentEquals(text)) transcript.setText(text);
    }
    private String delivery(DeliveryState value) {
        return switch (value) { case SAVED, ACCEPTED -> "Ожидает ответа"; case RUNNING -> "Отвечает…"; case FAILED -> "Не удалось получить ответ"; case INTERRUPTED -> "Ответ прерван"; default -> ""; };
    }
}
