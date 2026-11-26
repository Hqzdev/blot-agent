# `ContextAndProfilesTest.java`

Проверяет материалы проекта в чате, сжатие истории, неизменяемость настроек активной сессии и порядок сообщений при вызове инструмента.

[Исходник: `backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/ContextAndProfilesTest.java`](../../../../../../../../../backend/infrastructure/src/test/java/dev/blot/infrastructure/workspace/ContextAndProfilesTest.java)

Модуль: [infrastructure](../../../../../../../README.md). Раздел: [Проверки адаптеров и сценариев](index.md).

## Проверки

- `repositoryFreeProjectsCarryMaterialsIntoChatWithoutKeywordMatching`
- `compactsClosedHistoryToTargetAndRetainsOriginals`
- `frozenSessionDoesNotChangeWhenProfileIsEdited`
- `keepsToolExchangeTogetherWhenUserAnswersBeforeToolResult`
