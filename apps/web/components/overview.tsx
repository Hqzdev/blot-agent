const headings = [
  'What’s on the agenda today?',
  'What can I help with today?',
  'Where should we begin?',
  'What are we working on?',
  'Ready when you are.',
  'What’s on your mind?',
];

function selectHeading(chatId: string, nickname?: string) {
  const index =
    Array.from(chatId).reduce(
      (total, character) => (total * 31 + character.charCodeAt(0)) >>> 0,
      7,
    ) % headings.length;

  if (index === 4 && nickname) {
    return `Ready when you are, ${nickname}.`;
  }

  return headings[index];
}

export function Overview({
  chatId,
  nickname,
}: {
  chatId: string;
  nickname?: string;
}) {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-1/2 flex -translate-y-[86px] justify-center px-5 text-center md:-translate-y-[90px]">
      <h1 className="max-w-xl text-[25px] font-normal leading-8 tracking-[-0.025em] text-[var(--chat-ink)] md:text-[27px] md:leading-9">
        {selectHeading(chatId, nickname)}
      </h1>
    </div>
  );
}
