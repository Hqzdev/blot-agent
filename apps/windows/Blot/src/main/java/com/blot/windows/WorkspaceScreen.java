package com.blot.windows;

import dev.blot.client.WorkspaceClient;
import dev.blot.core.v3.*;
import java.util.*;
import javafx.geometry.Insets;
import javafx.scene.control.*;
import javafx.scene.layout.*;

final class WorkspaceScreen extends BorderPane {
    private final TextField address = new TextField("http://127.0.0.1:8080");
    private final PasswordField token = new PasswordField();
    private final Button connect = new Button("Подключиться");
    private final TextField agentName = new TextField();
    private final TextField model = new TextField("GigaChat");
    private final TextArea instructions = new TextArea();
    private final Button addAgent = new Button("Создать агента");
    private final ComboBox<String> agents = new ComboBox<>();
    private final Button addChat = new Button("Новый чат");
    private final ListView<String> conversations = new ListView<>();
    private final TextArea transcript = new TextArea();
    private final TextArea draft = new TextArea();
    private final Button send = new Button("Отправить");
    private final Button refresh = new Button("Обновить");
    private final Label status = new Label();
    private WorkspaceClient.State state;

    WorkspaceScreen() {
        setPadding(new Insets(20));
        address.setPromptText("Адрес сервера"); token.setPromptText("Сессия устройства");
        var connection = new HBox(10, new Label("Сервер"), address, token, connect, refresh);
        HBox.setHgrow(address, Priority.ALWAYS); HBox.setHgrow(token, Priority.ALWAYS);
        setTop(new VBox(10, connection, status));
        agentName.setPromptText("Имя агента"); instructions.setPromptText("Инструкции агента"); instructions.setPrefRowCount(3);
        agents.setMaxWidth(Double.MAX_VALUE);
        var sidebar = new VBox(10, new Label("Агенты"), agents, addChat, new Separator(), agentName, new Label("Модель"), model, instructions, addAgent, new Separator(), new Label("Чаты"), conversations);
        sidebar.setPrefWidth(260); sidebar.setPadding(new Insets(16, 16, 0, 0)); VBox.setVgrow(conversations, Priority.ALWAYS); setLeft(sidebar);
        transcript.setEditable(false); transcript.setWrapText(true); draft.setPromptText("Сообщение"); draft.setWrapText(true); draft.setPrefRowCount(3);
        var composer = new HBox(10, draft, send); HBox.setHgrow(draft, Priority.ALWAYS);
        var chat = new VBox(12, transcript, composer); chat.setPadding(new Insets(16, 0, 0, 0)); VBox.setVgrow(transcript, Priority.ALWAYS); setCenter(chat);
        conversations.getSelectionModel().selectedIndexProperty().addListener((ignored, oldValue, newValue) -> renderMessages());
        busy(false);
    }
    void bind(Runnable connection, Runnable agent, Runnable chat, Runnable message, Runnable update) {
        connect.setOnAction(e -> connection.run()); addAgent.setOnAction(e -> agent.run()); addChat.setOnAction(e -> chat.run()); send.setOnAction(e -> message.run()); refresh.setOnAction(e -> update.run());
    }
    String address() { return address.getText().trim(); }
    String token() { return token.getText().trim(); }
    String agentName() { return agentName.getText().trim(); }
    String instructions() { return instructions.getText(); }
    String model() { return model.getText().trim(); }
    String draft() { return draft.getText(); }
    void clearDraft() { draft.clear(); }
    void error(String message) { status.setText(message); }
    void connected() { token.clear(); }
    void busy(boolean value) {
        connect.setDisable(value); refresh.setDisable(value || state == null); addAgent.setDisable(value || state == null); addChat.setDisable(value || state == null); send.setDisable(value || state == null);
    }
    AgentProfile selectedAgent() {
        int i = agents.getSelectionModel().getSelectedIndex(); return state == null || i < 0 || i >= state.agents().size() ? null : state.agents().get(i);
    }
    Conversation selectedConversation() {
        int i = conversations.getSelectionModel().getSelectedIndex(); return state == null || i < 0 || i >= state.conversations().size() ? null : state.conversations().get(i);
    }
    void render(WorkspaceClient.State next) {
        UUID agent = selectedAgent() == null ? null : selectedAgent().metadata().id();
        UUID conversation = selectedConversation() == null ? null : selectedConversation().metadata().id();
        state = next;
        agents.getItems().setAll(next.agents().stream().map(AgentProfile::name).toList());
        conversations.getItems().setAll(next.conversations().stream().map(Conversation::title).toList());
        int selected = 0;
        for (int i = 0; i < next.agents().size(); i++) if (next.agents().get(i).metadata().id().equals(agent)) selected = i;
        if (!next.agents().isEmpty()) agents.getSelectionModel().select(selected);
        selected = Math.max(0, next.conversations().size() - 1);
        for (int i = 0; i < next.conversations().size(); i++) if (next.conversations().get(i).metadata().id().equals(conversation)) selected = i;
        if (!next.conversations().isEmpty()) conversations.getSelectionModel().select(selected);
        renderMessages();
    }
    private void renderMessages() {
        var conversation = selectedConversation(); if (conversation == null) { transcript.clear(); return; }
        var text = new StringBuilder();
        for (var message : state.messages()) if (message.conversationId().equals(conversation.metadata().id())) {
            text.append(message.role() == MessageRole.USER ? "Вы" : "Агент").append("\n");
            text.append(message.content().isEmpty() ? delivery(message.delivery()) : message.content()).append("\n\n");
        }
        if (!transcript.getText().contentEquals(text)) { transcript.setText(text.toString()); transcript.positionCaret(transcript.getLength()); }
    }
    private String delivery(DeliveryState value) {
        return switch (value) { case SAVED, ACCEPTED -> "Ожидает ответа"; case RUNNING -> "Отвечает…"; case FAILED -> "Не удалось получить ответ"; case INTERRUPTED -> "Ответ прерван"; default -> ""; };
    }
}
