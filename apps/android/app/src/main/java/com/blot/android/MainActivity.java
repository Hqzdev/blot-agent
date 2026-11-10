package com.blot.android;

import android.app.Activity;
import android.os.Bundle;
import dev.blot.client.WorkspaceClient;
import java.net.URI;
import java.util.UUID;
import java.util.concurrent.*;

public final class MainActivity extends Activity {
    private final ScheduledExecutorService network = Executors.newSingleThreadScheduledExecutor();
    private WorkspaceClient client;
    private WorkspaceScreen screen;
    private boolean busy;
    private UUID pendingMessage;
    private String pendingDraft;
    private record Retained(WorkspaceClient client, UUID pendingMessage, String pendingDraft) {}

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        screen = new WorkspaceScreen(this);
        screen.bind(this::connect, this::createAgent, this::createChat, this::send, this::refresh);
        setContentView(screen);
        screen.setOnApplyWindowInsetsListener((view, insets) -> {
            var bars = insets.getInsets(android.view.WindowInsets.Type.systemBars() | android.view.WindowInsets.Type.ime());
            view.setPadding(24 + bars.left, 16 + bars.top, 24 + bars.right, 16 + bars.bottom);
            return insets;
        });
        if (state != null) screen.restoreDraft(state.getString("draft", ""));
        if (getLastNonConfigurationInstance() instanceof Retained retained) {
            client = retained.client(); pendingMessage = retained.pendingMessage(); pendingDraft = retained.pendingDraft();
            refresh();
        }
        network.scheduleWithFixedDelay(() -> runOnUiThread(this::refresh), 2, 2, TimeUnit.SECONDS);
    }

    private void connect() {
        if (busy) return;
        try {
            var connection = new WorkspaceClient(URI.create(screen.address()), screen.token());
            run(() -> { var state = connection.connect(); client = connection; return state; }, screen::connected);
        } catch (IllegalArgumentException error) { screen.error(error.getMessage()); }
    }
    private void createAgent() {
        if (client == null || busy) return;
        String name = screen.agentName(), instructions = screen.instructions(), model = screen.model();
        if (name.isBlank() || model.isBlank()) { screen.error("Укажите имя агента и модель"); return; }
        run(() -> { client.saveAgent(name, instructions, model); return client.refresh(); }, () -> {});
    }
    private void createChat() {
        if (client == null || busy || screen.selectedAgent() == null) return;
        var agent = screen.selectedAgent();
        run(() -> { client.createConversation(agent, "Чат с " + agent.name()); return client.refresh(); }, () -> {});
    }
    private void send() {
        if (client == null || busy || screen.selectedConversation() == null) return;
        String draft = screen.draft();
        if (draft.isBlank()) return;
        if (pendingMessage != null && !draft.equals(pendingDraft)) { screen.error("Сначала проверьте отправку прежнего сообщения, вернув его текст"); return; }
        if (pendingMessage == null) { pendingMessage = UUID.randomUUID(); pendingDraft = draft; }
        var conversation = screen.selectedConversation(); UUID command = pendingMessage;
        run(() -> {
            try { client.send(conversation, draft, command); }
            catch (WorkspaceClient.Failure failure) {
                if (failure.status() > 0) runOnUiThread(() -> { pendingMessage = null; pendingDraft = null; });
                throw failure;
            }
            return client.refresh();
        }, () -> { if (screen.draft().equals(draft)) screen.clearDraft(); pendingMessage = null; pendingDraft = null; });
    }
    private void refresh() { if (client != null && !busy) run(client::refresh, () -> {}); }
    private void run(Callable<WorkspaceClient.State> operation, Runnable success) {
        if (isDestroyed() || network.isShutdown()) return;
        busy = true; screen.busy(true);
        network.execute(() -> {
            try {
                var state = operation.call();
                runOnUiThread(() -> { screen.render(state);
                    if (pendingMessage != null && state.messages().stream().anyMatch(message -> message.role() == dev.blot.core.v3.MessageRole.USER && pendingMessage.equals(message.commandId()))) {
                        if (screen.draft().equals(pendingDraft)) screen.clearDraft();
                        pendingMessage = null; pendingDraft = null;
                    }
                    screen.error(pendingMessage == null ? "" : "Статус отправки пока не подтверждён. Повторите проверку с прежним текстом.");
                    success.run(); busy = false; screen.busy(false); });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    screen.error(error.getMessage() == null ? "Не удалось связаться с сервером" : error.getMessage()); busy = false; screen.busy(false);
                });
            }
        });
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        state.putString("draft", screen.draft());
        super.onSaveInstanceState(state);
    }
    @Override public Object onRetainNonConfigurationInstance() { return new Retained(client, pendingMessage, pendingDraft); }
    @Override protected void onDestroy() {
        network.shutdownNow(); client = null;
        super.onDestroy();
    }
}
