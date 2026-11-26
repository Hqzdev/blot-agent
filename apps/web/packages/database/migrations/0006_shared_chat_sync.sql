CREATE TABLE blot_web.chat_replica_state (
  owner_id uuid PRIMARY KEY REFERENCES public.blot_accounts(id) ON DELETE CASCADE,
  clock jsonb NOT NULL DEFAULT '{}',
  fingerprint text,
  snapshot_id uuid
);
CREATE TABLE blot_web.chat_replica_records (
  owner_id uuid NOT NULL REFERENCES public.blot_accounts(id) ON DELETE CASCADE,
  kind text NOT NULL,
  record_id uuid NOT NULL,
  record jsonb NOT NULL,
  PRIMARY KEY(owner_id, kind, record_id)
);
CREATE TABLE blot_web.chat_replica_imports (
  snapshot_id uuid PRIMARY KEY REFERENCES public.blot_workspace_backups(id) ON DELETE CASCADE,
  owner_id uuid NOT NULL REFERENCES public.blot_accounts(id) ON DELETE CASCADE
);
CREATE TABLE blot_web.chat_events (
  id bigserial PRIMARY KEY,
  owner_id uuid NOT NULL REFERENCES public.blot_accounts(id) ON DELETE CASCADE,
  kind text NOT NULL,
  record_id uuid NOT NULL,
  deleted boolean NOT NULL,
  payload jsonb
);
CREATE INDEX chat_events_owner ON blot_web.chat_events(owner_id,id);
CREATE TABLE blot_web.message_order (
  message_id uuid PRIMARY KEY REFERENCES conversation.messages(id) ON DELETE CASCADE,
  position bigint NOT NULL
);

CREATE FUNCTION blot_web.capture_chat_change() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE item jsonb; owner uuid; record_kind text;
BEGIN
  IF current_setting('blot.sync_projection', true) = 'on' THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN item := to_jsonb(OLD); ELSE item := to_jsonb(NEW); END IF;
  IF TG_TABLE_NAME = 'chats' THEN
    owner := (item->>'user_id')::uuid; record_kind := 'Conversation';
  ELSE
    SELECT user_id INTO owner FROM conversation.chats WHERE id = (item->>'chat_id')::uuid;
    IF owner IS NULL THEN
      SELECT owner_id INTO owner FROM blot_web.chat_replica_records WHERE kind='Message' AND record_id=(item->>'id')::uuid LIMIT 1;
    END IF;
    record_kind := 'Message';
  END IF;
  IF owner IS NOT NULL AND EXISTS(SELECT 1 FROM public.blot_accounts WHERE id=owner) THEN
    INSERT INTO blot_web.chat_events(owner_id,kind,record_id,deleted,payload)
      VALUES(owner,record_kind,(item->>'id')::uuid,TG_OP='DELETE',CASE WHEN TG_OP='DELETE' THEN NULL ELSE item END);
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END $$;
CREATE TRIGGER capture_chat_change AFTER INSERT OR UPDATE OR DELETE ON conversation.chats FOR EACH ROW EXECUTE FUNCTION blot_web.capture_chat_change();
CREATE TRIGGER capture_message_change AFTER INSERT OR UPDATE OR DELETE ON conversation.messages FOR EACH ROW EXECUTE FUNCTION blot_web.capture_chat_change();

INSERT INTO blot_web.chat_events(owner_id,kind,record_id,deleted,payload)
  SELECT c.user_id,'Conversation',c.id,false,to_jsonb(c) FROM conversation.chats c JOIN public.blot_accounts a ON a.id=c.user_id ORDER BY c.created_at,c.id;
INSERT INTO blot_web.chat_events(owner_id,kind,record_id,deleted,payload)
  SELECT c.user_id,'Message',m.id,false,to_jsonb(m) FROM conversation.messages m JOIN conversation.chats c ON c.id=m.chat_id JOIN public.blot_accounts a ON a.id=c.user_id ORDER BY m.created_at,m.id;

CREATE FUNCTION blot_web.erase_account_chats() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM conversation.chats WHERE user_id=OLD.id;
  DELETE FROM identity.blot_profiles WHERE owner_id=OLD.id;
  RETURN OLD;
END $$;
CREATE TRIGGER erase_account_chats BEFORE DELETE ON public.blot_accounts FOR EACH ROW EXECUTE FUNCTION blot_web.erase_account_chats();
