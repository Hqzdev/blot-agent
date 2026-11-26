import 'server-only';
import { BlotChatSyncBridge, PostgresBridgeDatabase } from '@blot/chat-sync';
import { DatabaseConnectionProvider } from '@teya/database';

export class ChatSynchronizer {
  private readonly bridge = new BlotChatSyncBridge(
    new PostgresBridgeDatabase(new DatabaseConnectionProvider().get().client),
  );
  async synchronize(ownerID: string) {
    await this.bridge.synchronize(ownerID);
  }
}
