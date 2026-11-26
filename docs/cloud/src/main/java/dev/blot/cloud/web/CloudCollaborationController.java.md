# `CloudCollaborationController.java`

Обслуживает команды, участников, приглашения, ботов и публикации. Для публичной ссылки выдаёт данные или готовую HTML-страницу.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudCollaborationController.java`](https://github.com/Hqzdev/kiln-agent/blob/4e6c47f65e0e734dedc122d586c7bb67d37395a3/backend/cloud/src/main/java/dev/blot/cloud/web/CloudCollaborationController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `GET /v1/collaboration/teams`
- `POST /v1/collaboration/teams`
- `GET /v1/collaboration/teams/{team}/members`
- `POST /v1/collaboration/teams/{team}/invites`
- `POST /v1/collaboration/invites/accept`
- `DELETE /v1/collaboration/teams/{team}/members/{account}`
- `GET /v1/collaboration/teams/{team}/bots`
- `PUT /v1/collaboration/teams/{team}/bots/{id}`
- `DELETE /v1/collaboration/teams/{team}/bots/{id}`
- `POST /v1/collaboration/publications`
- `GET /v1/collaboration/publications`
- `DELETE /v1/collaboration/publications/{id}`
- `GET /v1/collaboration/public/{token}`
- `GET /v1/collaboration/share/{token}`

## Связанные файлы

- [CloudTeams](../collaboration/CloudTeams.java.md)
- [CloudPublishedContent](../collaboration/CloudPublishedContent.java.md)
- [CloudPublicationRenderer](../collaboration/CloudPublicationRenderer.java.md)
