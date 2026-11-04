package dev.blot.api.workspace;

import dev.blot.api.workspace.commands.BasicCommands;
import dev.blot.api.workspace.commands.GitCommands;
import dev.blot.api.workspace.commands.LibraryCommands;
import dev.blot.api.workspace.commands.WorkflowCommands;
import dev.blot.api.workspace.installation.InstallationConfiguration;
import dev.blot.application.ports.*;
import dev.blot.application.ports.ArtifactStore;
import dev.blot.application.ports.EmailSender;
import dev.blot.application.ports.GitGateway;
import dev.blot.application.ports.JsonCodec;
import dev.blot.application.ports.PasswordHasher;
import dev.blot.application.ports.ProcessGateway;
import dev.blot.application.ports.ProjectAccess;
import dev.blot.application.ports.ProviderGateway;
import dev.blot.application.ports.SecretStore;
import dev.blot.application.ports.WorkspaceStore;
import dev.blot.application.workspace.*;
import dev.blot.application.workspace.Records;
import dev.blot.application.workspace.WorkspaceMaintenance;
import dev.blot.application.workspace.agent.AgentCommunicationTools;
import dev.blot.application.workspace.agent.AgentExecutionService;
import dev.blot.application.workspace.agent.AgentFiles;
import dev.blot.application.workspace.agent.AgentResultService;
import dev.blot.application.workspace.agent.DelegationService;
import dev.blot.application.workspace.agent.RoleCatalog;
import dev.blot.application.workspace.artifact.ArtifactMaintenance;
import dev.blot.application.workspace.automation.AutomationService;
import dev.blot.application.workspace.billing.BudgetService;
import dev.blot.application.workspace.billing.BudgetedProvider;
import dev.blot.application.workspace.commands.CommandDispatcher;
import dev.blot.application.workspace.commands.ToolDefinitions;
import dev.blot.application.workspace.conversation.ContextBuilder;
import dev.blot.application.workspace.conversation.ContextCompactor;
import dev.blot.application.workspace.conversation.ConversationLifecycle;
import dev.blot.application.workspace.conversation.ConversationService;
import dev.blot.application.workspace.conversation.MemoryService;
import dev.blot.application.workspace.conversation.SessionService;
import dev.blot.application.workspace.data.DataLifecycleService;
import dev.blot.application.workspace.execution.GenerationStateService;
import dev.blot.application.workspace.execution.GenerationWorker;
import dev.blot.application.workspace.execution.PreparedActionExecutor;
import dev.blot.application.workspace.execution.RetryService;
import dev.blot.application.workspace.execution.RetryingProvider;
import dev.blot.application.workspace.execution.RunService;
import dev.blot.application.workspace.execution.SerializedProvider;
import dev.blot.application.workspace.execution.ToolHistory;
import dev.blot.application.workspace.execution.ToolRecoveryService;
import dev.blot.application.workspace.execution.ToolService;
import dev.blot.application.workspace.execution.WorkflowScheduler;
import dev.blot.application.workspace.git.GitOperationService;
import dev.blot.application.workspace.git.GitPreparationService;
import dev.blot.application.workspace.identity.AccountService;
import dev.blot.application.workspace.identity.DeviceService;
import dev.blot.application.workspace.identity.EmailChallengeService;
import dev.blot.application.workspace.identity.TokenGenerator;
import dev.blot.application.workspace.integrations.IntegrationService;
import dev.blot.application.workspace.library.LegacyImportService;
import dev.blot.application.workspace.library.LibraryService;
import dev.blot.application.workspace.permissions.PermissionService;
import dev.blot.application.workspace.profile.ProfileService;
import dev.blot.application.workspace.projects.ProjectService;
import dev.blot.application.workspace.providers.ModelStreamingService;
import dev.blot.application.workspace.providers.ProviderCertificateService;
import dev.blot.application.workspace.providers.ProviderSettingsService;
import dev.blot.application.workspace.review.ReviewService;
import dev.blot.application.workspace.statistics.StatisticsService;
import dev.blot.core.workspace.profile.ProfileData;
import dev.blot.infrastructure.workspace.*;
import dev.blot.infrastructure.workspace.InstallationLock;
import dev.blot.infrastructure.workspace.JacksonCodec;
import dev.blot.infrastructure.workspace.artifacts.LocalArtifactStore;
import dev.blot.infrastructure.workspace.database.SqliteWorkspaceStore;
import dev.blot.infrastructure.workspace.execution.MacPlatformBridge;
import dev.blot.infrastructure.workspace.execution.VirtualMachineProcessGateway;
import dev.blot.infrastructure.workspace.git.LocalGitGateway;
import dev.blot.infrastructure.workspace.git.LocalWorkspaceCleaner;
import dev.blot.infrastructure.workspace.projects.LocalProjectAccess;
import dev.blot.infrastructure.workspace.projects.MacProjectAccess;
import dev.blot.infrastructure.workspace.provider.GigaChatGateway;
import dev.blot.infrastructure.workspace.provider.PemCertificates;
import dev.blot.infrastructure.workspace.provider.SmtpEmailSender;
import dev.blot.infrastructure.workspace.security.ArgonPasswordHasher;
import dev.blot.infrastructure.workspace.security.ConfiguredSecretStore;
import dev.blot.infrastructure.workspace.security.MacKeychainSecretStore;
import java.net.URI;
import java.net.http.HttpClient;
import java.nio.file.*;
import java.time.*;
import java.util.UUID;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.core.env.Environment;

/** Единственное место выбора реальных адаптеров. */
@Configuration
public class WorkspaceConfiguration {
  @Bean
  JsonCodec jsonCodec() {
    return new JacksonCodec();
  }

  @Bean
  Clock workspaceClock() {
    return Clock.systemUTC();
  }

  @Bean
  TokenGenerator tokenGenerator() {
    return new TokenGenerator();
  }

  @Bean
  Records records(Clock clock) {
    return new Records(clock);
  }

  @Bean(destroyMethod = "close")
  InstallationLock installationLock(@Value("${blot.database:blot.db}") String path) {
    return new InstallationLock(Path.of(path));
  }

  @Bean
  WorkspaceStore workspaceStore(
      @Value("${blot.database:blot.db}") String database,
      JsonCodec json,
      Clock clock,
      InstallationLock lock) {
    return new SqliteWorkspaceStore(Path.of(database), json, clock);
  }

  @Bean
  PasswordHasher passwordHasher() {
    return new ArgonPasswordHasher();
  }

  @Bean
  MacPlatformBridge platformBridge(
      JsonCodec json, @Value("${blot.platform-bridge:disabled}") String mode) {
    return new MacPlatformBridge(json, mode.equals("stdio"));
  }

  @Bean
  InstallationConfiguration installationConfiguration(Environment environment) {
    return new InstallationConfiguration(environment);
  }

  @Bean
  SecretStore secrets(MacPlatformBridge bridge, InstallationConfiguration configuration) {
    return new ConfiguredSecretStore(configuration.secrets(), new MacKeychainSecretStore(bridge));
  }

  @Bean
  EmailSender emailSender(SecretStore secrets) {
    return new SmtpEmailSender(secrets);
  }

  @Bean
  EmailChallengeService challenges(
      WorkspaceStore store,
      EmailSender sender,
      PasswordHasher hasher,
      Clock clock,
      Records records,
      TokenGenerator tokens) {
    return new EmailChallengeService(store, sender, hasher, clock, records, tokens);
  }

  @Bean
  AccountService accounts(
      WorkspaceStore store,
      PasswordHasher hasher,
      EmailChallengeService challenges,
      Records records,
      Clock clock) {
    return new AccountService(store, hasher, challenges, records, clock);
  }

  @Bean
  SessionService sessions(
      WorkspaceStore store, TokenGenerator tokens, Records records, Clock clock) {
    return new SessionService(store, tokens, records, clock);
  }

  @Bean
  DeviceService devices(
      WorkspaceStore store,
      Records records,
      Clock clock,
      TokenGenerator tokens,
      SessionService sessions) {
    return new DeviceService(store, records, clock, tokens, sessions);
  }

  @Bean
  ConversationService conversations(Records records) {
    return new ConversationService(records);
  }

  @Bean
  MemoryService memory(WorkspaceStore store, Records records) {
    return new MemoryService(store, records);
  }

  @Bean
  RetryService retries(Records records, ConversationService conversations) {
    return new RetryService(records, conversations);
  }

  @Bean
  ProviderSettingsService settings(
      WorkspaceStore store, Records records, InstallationConfiguration configuration) {
    return new ProviderSettingsService(store, records, configuration.provider());
  }

  @Bean(initMethod = "recover")
  BudgetService budgets(WorkspaceStore store, Records records) {
    return new BudgetService(store, records);
  }

  @Bean(initMethod = "recover")
  SerializedProvider provider(
      JsonCodec json,
      SecretStore secrets,
      Clock clock,
      BudgetService budgets,
      Records records,
      WorkspaceStore storeForQueue,
      ProviderSettingsService settings,
      @Value("${blot.provider.url:https://api.giga.chat/v1/}") String url,
      @Value("${blot.provider.oauth:https://ngw.devices.sberbank.ru:9443/api/v2/oauth}")
          String oauth) {
    var gateway =
        new GigaChatGateway(
            HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(20)).build(),
            json,
            secrets,
            URI.create(url),
            URI.create(oauth),
            clock);
    return new SerializedProvider(
        new RetryingProvider(new BudgetedProvider(gateway, budgets, settings, json)),
        storeForQueue,
        records);
  }

  @Bean
  ContextCompactor compactor(ProviderGateway provider, JsonCodec json) {
    return new ContextCompactor(provider, json);
  }

  @Bean
  ContextBuilder contextBuilder(
      WorkspaceStore store,
      ProviderGateway provider,
      MemoryService memory,
      Records records,
      ContextCompactor compactor,
      JsonCodec json) {
    return new ContextBuilder(store, provider, memory, records, compactor, json);
  }

  @Bean
  CommandDispatcher dispatcher(
      WorkspaceStore store,
      JsonCodec json,
      TokenGenerator tokens,
      ConversationService conversations,
      MemoryService memory,
      ProviderSettingsService settings,
      DeviceService devices,
      BudgetService budgets,
      ProjectService projects,
      RunService runs,
      PermissionService permissions,
      Records records,
      IntegrationService integration,
      ProfileService profiles,
      RetryService retries) {
    var dispatcher = new CommandDispatcher(store, json, tokens);
    new BasicCommands(dispatcher, json, conversations, memory, settings, devices, budgets);
    new WorkflowCommands(dispatcher, json, projects, runs, permissions, records, integration);
    dispatcher.register(
        "profile.save",
        (tx, a, c) -> {
          var p = json.convert(c.payload(), ProfileChange.class);
          return profiles.save(tx, a, c.projectId(), p.id(), c.expectedVersion(), p.data());
        });
    dispatcher.register(
        "task.retry",
        (tx, a, c) ->
            retries.retryTask(
                tx, a, UUID.fromString((String) c.payload().get("id")), c.expectedVersion()));
    dispatcher.register(
        "generation.retry",
        (tx, a, c) ->
            retries.retryConversation(
                tx, a, UUID.fromString((String) c.payload().get("id")), c.expectedVersion()));
    return dispatcher;
  }

  @Bean
  GitGateway git(@Value("${blot.workspaces:.build/blot-workspaces}") String path) {
    return new LocalGitGateway(Path.of(path));
  }

  @Bean
  ArtifactStore artifactStore(@Value("${blot.artifacts:.build/blot-artifacts}") String path) {
    return new LocalArtifactStore(Path.of(path));
  }

  @Bean
  ProcessGateway processes(
      @Value("${blot.data-directory}") String path, MacPlatformBridge bridge, JsonCodec json) {
    return new VirtualMachineProcessGateway(Path.of(path).resolve("vm/jobs"), bridge, json);
  }

  @Bean
  PermissionService permissions(
      Records records, JsonCodec json, TokenGenerator tokens, Clock clock) {
    return new PermissionService(records, json, tokens, clock);
  }

  @Bean
  RoleCatalog roles() {
    return new RoleCatalog();
  }

  @Bean
  ProjectService projects(GitGateway git, Records records, ProjectAccess access) {
    return new ProjectService(git, records, access);
  }

  @Bean
  RunService runs(Records records, ConversationService conversations, RoleCatalog roles) {
    return new RunService(records, conversations, roles);
  }

  @Bean
  IntegrationService integration(WorkspaceStore store, Records records) {
    return new IntegrationService(store, records);
  }

  @Bean
  ProfileService profiles(
      WorkspaceStore store,
      Records records,
      RoleCatalog roles,
      ToolDefinitions tools,
      ProviderSettingsService settings) {
    return new ProfileService(store, records, roles, tools, settings);
  }

  @Bean
  WorkflowScheduler scheduler(
      WorkspaceStore store,
      Records records,
      ConversationService conversations,
      GitGateway git,
      ProfileService profiles,
      IntegrationService integration,
      ArtifactStore artifacts) {
    return new WorkflowScheduler(
        store, records, conversations, git, profiles, integration, artifacts);
  }

  @Bean
  ReviewService reviews(Records records) {
    return new ReviewService(records);
  }

  @Bean
  DelegationService delegation(WorkspaceStore store, Records records) {
    return new DelegationService(store, records);
  }

  @Bean
  PreparedActionExecutor preparedActions(
      WorkspaceStore store,
      Records records,
      PermissionService permissions,
      GitGateway git,
      ProcessGateway processes,
      ArtifactStore artifacts,
      TokenGenerator tokens,
      AgentFiles files) {
    return new PreparedActionExecutor(
        store, records, permissions, git, processes, artifacts, tokens, files);
  }

  @Bean
  AgentCommunicationTools communicationTools(WorkspaceStore store, Records records) {
    return new AgentCommunicationTools(store, records);
  }

  @Bean
  ToolService tools(
      WorkspaceStore store,
      PermissionService permissions,
      GitGateway git,
      JsonCodec json,
      TokenGenerator tokens,
      DelegationService delegation,
      ToolDefinitions definitions,
      AgentFiles files,
      PreparedActionExecutor actions,
      AgentCommunicationTools communication) {
    return new ToolService(
        store,
        permissions,
        git,
        json,
        tokens,
        delegation,
        definitions,
        files,
        actions,
        communication);
  }

  @Bean
  ToolDefinitions definitions() {
    return new ToolDefinitions();
  }

  @Bean
  AgentFiles agentFiles(
      WorkspaceStore store, TokenGenerator tokens, ArtifactStore artifacts, Records records) {
    return new AgentFiles(store, tokens, artifacts, records);
  }

  @Bean
  ModelStreamingService streaming(
      WorkspaceStore store,
      Records records,
      ProviderGateway provider,
      ConversationService conversations) {
    return new ModelStreamingService(store, records, provider, conversations);
  }

  @Bean
  GenerationStateService generationStates(WorkspaceStore store, Records records) {
    return new GenerationStateService(store, records);
  }

  @Bean
  AgentResultService agentResults(
      WorkspaceStore store,
      Records records,
      ReviewService reviews,
      GitGateway git,
      ArtifactStore artifacts,
      WorkflowScheduler scheduler,
      JsonCodec json) {
    return new AgentResultService(store, records, reviews, git, artifacts, scheduler, json);
  }

  @Bean
  ToolHistory toolHistory(
      WorkspaceStore store, ConversationService conversations, ToolService tools, JsonCodec json) {
    return new ToolHistory(store, conversations, tools, json);
  }

  @Bean
  AgentExecutionService agentExecution(
      WorkspaceStore store,
      Records records,
      ConversationService conversations,
      ContextBuilder context,
      ModelStreamingService streaming,
      ToolService tools,
      AgentResultService results,
      JsonCodec json,
      ProfileService profiles,
      ToolHistory toolHistory) {
    return new AgentExecutionService(
        store, records, conversations, context, streaming, tools, results, profiles, toolHistory);
  }

  @org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(
      name = "blot.worker.enabled",
      havingValue = "true",
      matchIfMissing = true)
  @Bean(initMethod = "start", destroyMethod = "close")
  GenerationWorker worker(
      WorkspaceStore store,
      Records records,
      WorkspaceStore storeForQueue,
      ProviderSettingsService settings,
      ContextBuilder context,
      RunService runs,
      WorkflowScheduler scheduler,
      JsonCodec json,
      ModelStreamingService streaming,
      AgentExecutionService agents,
      GenerationStateService states,
      ToolRecoveryService recovery,
      GitOperationService gitRecovery,
      WorkspaceMaintenance workspaceMaintenance) {
    return new GenerationWorker(
        store, records, settings, context, runs, scheduler, json, streaming, agents, states);
  }

  @Bean
  LibraryService library(Records records, RoleCatalog roles) {
    return new LibraryService(records, roles);
  }

  @Bean(destroyMethod = "close")
  AutomationService automations(
      WorkspaceStore store,
      Records records,
      Clock clock,
      CommandDispatcher commands,
      JsonCodec json,
      LibraryService library,
      RunService runs,
      @Value("${blot.automations.enabled:true}") boolean enabled) {
    var service = new AutomationService(store, records, clock, commands);
    new LibraryCommands(commands, json, library, service, runs);
    if (enabled) service.start();
    return service;
  }

  @Bean(initMethod = "start", destroyMethod = "close")
  GitOperationService gitOperations(
      WorkspaceStore store,
      Records records,
      PermissionService permissions,
      GitGateway git,
      TokenGenerator tokens,
      GitPreparationService preparation,
      CommandDispatcher commands,
      JsonCodec json) {
    var service = new GitOperationService(store, records, permissions, git, tokens);
    new GitCommands(commands, json, service, preparation);
    return service;
  }

  @Bean(initMethod = "start", destroyMethod = "close")
  ToolRecoveryService toolRecovery(
      WorkspaceStore store,
      Records records,
      AgentFiles files,
      GitGateway git,
      TokenGenerator tokens,
      CommandDispatcher commands) {
    var service = new ToolRecoveryService(store, records, files, git, tokens);
    for (String command : java.util.List.of("tool.reconcile", "tool.abandon"))
      commands.register(
          command,
          (tx, a, c) ->
              service.request(
                  tx,
                  a,
                  UUID.fromString((String) c.payload().get("id")),
                  c.expectedVersion(),
                  command.equals("tool.abandon")));
    return service;
  }

  @Bean
  DataLifecycleService dataLifecycle(
      WorkspaceStore store, Records records, CommandDispatcher commands, JsonCodec json) {
    var service = new DataLifecycleService(store, records);
    commands.register(
        "project.delete",
        (tx, a, c) -> {
          var p = json.convert(c.payload(), java.util.Map.class);
          service.deleteProject(
              tx, a, java.util.UUID.fromString((String) p.get("id")), c.expectedVersion());
          return java.util.Map.of("deleted", true);
        });
    return service;
  }

  @Bean(initMethod = "start", destroyMethod = "close")
  ArtifactMaintenance artifactMaintenance(
      WorkspaceStore store, ArtifactStore artifacts, Clock clock) {
    return new ArtifactMaintenance(store, artifacts, clock);
  }

  @Bean(initMethod = "start", destroyMethod = "close")
  WorkspaceMaintenance workspaceMaintenance(
      WorkspaceStore store,
      Records records,
      ProjectAccess access,
      @Value("${blot.workspaces:.build/blot-workspaces}") String path) {
    // В App Sandbox bookmarks восстанавливаются до работы с очередью удаления.
    return new WorkspaceMaintenance(store, new LocalWorkspaceCleaner(Path.of(path)), records);
  }

  @Bean
  LegacyImportService legacyImport(
      ProjectService projects,
      ArtifactStore artifacts,
      Records records,
      JsonCodec json,
      CommandDispatcher commands) {
    var service = new LegacyImportService(projects, artifacts, records, json);
    commands.register(
        "legacy.adopt",
        (tx, actor, command) -> {
          var payload = json.convert(command.payload(), LegacyAdoption.class);
          return service.adopt(tx, actor, payload.sourceProjectId(), payload.confirmed());
        });
    return service;
  }

  record LegacyAdoption(UUID sourceProjectId, boolean confirmed) {}

  @Bean
  @org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(
      name = "blot.platform-bridge",
      havingValue = "disabled",
      matchIfMissing = true)
  ProjectAccess localProjectAccess() {
    return new LocalProjectAccess();
  }

  @Bean(initMethod = "restore", destroyMethod = "close")
  @org.springframework.boot.autoconfigure.condition.ConditionalOnProperty(
      name = "blot.platform-bridge",
      havingValue = "stdio")
  MacProjectAccess macProjectAccess(
      MacPlatformBridge bridge,
      WorkspaceStore store,
      @Value("${blot.project-access-library:}") String library) {
    return new MacProjectAccess(bridge, store, library);
  }

  @Bean
  ConversationLifecycle conversationLifecycle(
      Records records, MemoryService memory, CommandDispatcher commands, JsonCodec json) {
    var service = new ConversationLifecycle(records, memory);
    commands.register(
        "conversation.update",
        (tx, actor, command) -> {
          var payload = json.convert(command.payload(), ConversationChange.class);
          return service.change(
              tx,
              actor,
              payload.id(),
              command.expectedVersion(),
              payload.title(),
              payload.archived());
        });
    commands.register(
        "message.delete",
        (tx, actor, command) -> {
          service.deleteMessage(
              tx,
              actor,
              UUID.fromString((String) command.payload().get("id")),
              command.expectedVersion());
          return java.util.Map.of("deleted", true);
        });
    return service;
  }

  record ConversationChange(UUID id, String title, Boolean archived) {}

  @Bean
  ProviderCertificateService providerCertificates(SecretStore secrets) {
    return new ProviderCertificateService(secrets, new PemCertificates());
  }

  @Bean
  GitPreparationService gitPreparation(
      WorkspaceStore store, PermissionService permissions, GitGateway git) {
    return new GitPreparationService(store, permissions, git);
  }

  @Bean
  StatisticsService statistics(WorkspaceStore store) {
    return new StatisticsService(store);
  }

  record ProfileChange(UUID id, ProfileData data) {}
}
