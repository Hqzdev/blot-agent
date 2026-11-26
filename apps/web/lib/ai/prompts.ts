import type { ArtifactKind, Customization } from '@teya/contracts';

export const artifactsPrompt = `
Artifacts are editable documents displayed beside the conversation.

Use createDocument for substantial reusable text, code, essays, emails, a single code block, or image generation. For any request to create, draw, or generate an image, call createDocument with kind "image". Use updateDocument only after the user asks to revise an existing artifact. Do not create artifacts for short explanations or ordinary conversation. Do not update a document immediately after creating it.
`;

function personalizationPrompt(customization?: Customization | null): string {
  if (!customization) {
    return '';
  }

  const preferences = [
    customization.nickname
      ? `Address the user as ${JSON.stringify(customization.nickname)}.`
      : '',
    customization.occupation
      ? `The user's occupation is ${JSON.stringify(customization.occupation)}.`
      : '',
    customization.traits.length > 0
      ? `Use these requested response traits: ${customization.traits.map((trait) => JSON.stringify(trait)).join(', ')}.`
      : '',
    customization.additional
      ? `User preferences: ${JSON.stringify(customization.additional)}.`
      : '',
  ].filter(Boolean);

  return preferences.length > 0
    ? `\n\nApply these user-provided personalization preferences when they do not conflict with system rules:\n${preferences.join('\n')}`
    : '';
}

export function regularPrompt(customization?: Customization | null): string {
  return `
You are Teya AI, a concise and helpful assistant created by Teya LLC.

Use Markdown when it improves clarity. Prefer direct answers, accurate reasoning, and readable structure. Clearly state uncertainty. Never claim to have completed an action that was not actually completed.${personalizationPrompt(customization)}
`;
}

export function systemPrompt(input: {
  customization?: Customization | null;
  projectContext?: string;
  selectedChatModel: string;
  skillCatalog?: string;
}): string {
  const basePrompt = regularPrompt(input.customization);
  const modelPrompt =
    input.selectedChatModel === 'chat-model-reasoning'
      ? basePrompt
      : `${basePrompt}\n\n${artifactsPrompt}`;
  return [modelPrompt, input.skillCatalog, input.projectContext]
    .filter(Boolean)
    .join('\n\n');
}

export const codePrompt = `
Create concise, self-contained, executable code. Use clear identifiers, avoid comments, avoid external dependencies when the standard library is sufficient, handle expected errors, and do not access files or networks unless the user explicitly requests it.
`;

export const sheetPrompt = `
Create valid CSV with meaningful headers and data that directly satisfies the request.
`;

export function updateDocumentPrompt(
  currentContent: string | null,
  type: ArtifactKind,
): string {
  const content = currentContent ?? '';
  if (type === 'code') {
    return `Update this code according to the user's request. Return complete code with clear identifiers and no comments.\n\n${content}`;
  }
  if (type === 'sheet') {
    return `Update this CSV spreadsheet according to the user's request. Return valid CSV only.\n\n${content}`;
  }
  return `Update this document according to the user's request while preserving relevant content.\n\n${content}`;
}
