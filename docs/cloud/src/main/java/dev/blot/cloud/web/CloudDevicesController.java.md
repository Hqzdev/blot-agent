# `CloudDevicesController.java`

Обслуживает регистрацию, список, сопряжение и отзыв облачных устройств. Выдаёт обновления ключей устройству через соответствующий сервис.

[Исходник: `backend/cloud/src/main/java/dev/blot/cloud/web/CloudDevicesController.java`](../../../../../../../../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudDevicesController.java)

Модуль: [cloud](../../../../../../../README.md). Раздел: [Маршруты облачного API](index.md).

## HTTP-маршруты

- `POST /v1/devices/bootstrap`
- `GET /v1/devices`
- `POST /v1/devices/pairings`
- `POST /v1/devices/pairings/claim`
- `GET /v1/devices/pairings/{id}`
- `POST /v1/devices/pairings/approve`
- `GET /v1/devices/pairings/{id}/result`
- `POST /v1/devices/revoke`
- `GET /v1/devices/keys`
