# Grok Bot каталог экранов и UI блоков

Снимки сгруппированы по назначению. «Официальный макет» — интерактивная демонстрация на публичном сайте; «видео» — ранее сохранённый кадр обзора. Оба источника полезны для визуального устройства, но не заменяют проверку авторизованной версии. [Полная галерея](index.html), [машинный индекс](screens.json).

## Навигация и профиль

| Блок | Состав и назначение | Изображение | Происхождение |
| --- | --- | --- | --- |
| Основное окно | Sidebar, переписка, composer, компьютер и routines | [S008](screenshots/08-design-app-shell.jpg) | Официальный макет |
| Состав ботов | Аватар, имя, preview сообщения, переключение агента | [S073](../grok-bot-charlie-chang/screenshots/0620-team-roster.jpg) | Видео |
| Меню создания | Новый бот или групповой чат | [S032](../grok-bot-video/screenshots/0120-create-bot.jpg) | Видео |
| Профиль | Имя, label, уведомления и вкладки | [S063](../grok-bot-charlie-chang/screenshots/0155-bot-profile.jpg) | Видео; описание личного бота устарело |
| Выбор внешности | Форма, цвет, Generate и Upload | [S034](../grok-bot-video/screenshots/0140-avatar-picker.jpg) | Видео |
| Система аватаров | Геометрические формы и выразительные глаза | [S026](screenshots/11-avatar-system.jpg) | Официальный макет |
| Настройка роли | Варианты обязанностей и свободный ответ | [S035](../grok-bot-video/screenshots/0150-bot-onboarding.jpg) | Видео |
| Добавление в группу | Выбор нескольких ботов | [S082](../grok-bot-charlie-chang/screenshots/1050-group-members.jpg) | Видео |
| Совместная задача | Общий диалог и передача работы специалисту | [S083](../grok-bot-charlie-chang/screenshots/1120-group-invoices.jpg) | Видео |

## Карточки внутри переписки

| Блок | Видимые поля и действия | Изображение |
| --- | --- | --- |
| Черновик email | Отправитель, адресат, тема, тело, Send и Discard | [S009](screenshots/09-widget-01.jpg) |
| Вопрос | Несколько вариантов, свой ответ, Submit | [S010](screenshots/09-widget-02.jpg) |
| Платёж | Получатель, детализация, налог, итог, Allow и Deny | [S011](screenshots/09-widget-03.jpg) |
| Команда | Описание последствия, Show command, Allow, Always allow, Deny | [S012](screenshots/09-widget-04.jpg) |
| Передача компьютера | Причина ручного шага, Take over, I’m done, Skip | [S013](screenshots/09-widget-05.jpg) |
| Cloud Agent | Статус, ветка, изменённые файлы, View PR, Open in Cursor | [S014](screenshots/09-widget-06.jpg) |
| Черновик Slack | Workspace, канал, ветка, текст, Send и Discard | [S015](screenshots/09-widget-07.jpg) |
| Приложение | Иконка, назначение, состояние Added | [S016](screenshots/09-widget-08.jpg) |
| Защищённый ввод | Назначение токена, поле, Save securely | [S017](screenshots/09-widget-09.jpg) |
| Согласованное действие | Состояние Allowed once и список сайтов | [S018](screenshots/09-widget-10.jpg) |
| Ошибка отправки | Сообщение о сохранённом черновике, Try again и Dismiss | [S019](screenshots/09-widget-11.jpg) |

Все 11 карточек выше сняты с [официальной статьи о дизайне](https://x.ai/news/designing-grok-bot#the-shape-of-information). Их кнопки демонстрируют внешний вид. Например, наличие demo-карточки копирования cookies не означает отдельную общедоступную функцию переноса cookies в текущем приложении.

## Состояния и активность

| Состояние или блок | Изображение |
| --- | --- |
| Idle | [S020](screenshots/10-state-idle.jpg) |
| Working | [S021](screenshots/10-state-working.jpg) |
| Waiting | [S022](screenshots/10-state-waiting.jpg) |
| Blocked | [S023](screenshots/10-state-blocked.jpg) |
| Thinking | [S024](screenshots/10-state-thinking.jpg) |
| Done | [S025](screenshots/10-state-done.jpg) |
| Варианты показа активности | [S028](screenshots/13-activity-patterns.jpg) |
| Сообщение о сохранённой памяти и предложение изменения | [S007](screenshots/07-official-feature-6.jpg) |

Снимок фиксирует одну фазу движения и выбранную вкладку. По нему нельзя восстановить всю анимацию, длительности, easing или физику пружины. Панель activity в статье также включает исследовавшиеся способы отображения; их нельзя все объявлять текущими отдельными режимами приложения.

## Компьютер и обучение

| Блок | Назначение | Изображение | Происхождение |
| --- | --- | --- | --- |
| Preview | Экран бота внутри панели профиля | [S045](../grok-bot-video/screenshots/0445-computer-preview.jpg) | Видео |
| Рабочий стол | Браузер и постоянная среда | [S069](../grok-bot-charlie-chang/screenshots/0435-desktop-ready.jpg) | Видео |
| Вход на сайт | Пользователь завершает чувствительный шаг | [S003](screenshots/03-official-feature-2.jpg) | Демонстрация сайта |
| Teach a task | Запись действий и таймер | [S071](../grok-bot-charlie-chang/screenshots/0520-teach-task.jpg) | Видео |
| Результат обучения | Объяснение выученной процедуры | [S048](../grok-bot-video/screenshots/0550-learned-workflow.jpg) | Видео |
| Запуск навыка | Меню сохранённого skill в composer | [S050](../grok-bot-video/screenshots/0650-saved-skill.jpg) | Видео; текущий docs описывает запуск по имени |
| Динамические обои | Светлые и тёмные варианты времени суток | [S027](screenshots/12-computer-wallpapers.jpg) | Официальный макет |

## Подключения и регулярная работа

| Блок | Состав | Изображение |
| --- | --- | --- |
| Connect apps | Поиск, категории, приложения и skills | [S038](../grok-bot-video/screenshots/0235-app-catalog.jpg) |
| Connect card | Требование авторизации в контексте задачи | [S036](../grok-bot-video/screenshots/0210-gmail-connect.jpg) |
| Account authorization | Добавление и метка аккаунта | [S068](../grok-bot-charlie-chang/screenshots/0335-gmail-authorization.jpg) |
| Менеджер паролей | Карточка 1Password | [S081](../grok-bot-charlie-chang/screenshots/1025-password-manager.jpg) |
| Список routines | Имя, расписание и переключатель | [S055](../grok-bot-video/screenshots/0800-routines-list.jpg) |
| Детали routine | Instruction, расписание, Pause, Edit, Delete | [S054](../grok-bot-video/screenshots/0755-routine-settings.jpg) |
| Файл в задаче | Документ SOP как основание для работы | [S052](../grok-bot-video/screenshots/0720-support-document.jpg) |
| Рекомендации товаров | Список вариантов, цены и ссылки | [S077](../grok-bot-charlie-chang/screenshots/0910-product-recommendations.jpg) |

Эта группа — видеокадры прежних версий. Особенно важно ограничение Gmail: текущая документация описывает один mailbox за раз. Кадр добавления второго аккаунта не доказывает текущую поддержку двух Gmail. [Текущие правила подключений](https://docs.x.ai/grok-bot/computer-and-apps).

## Команда настройки и каталоги

| Блок | Изображение | Происхождение |
| --- | --- | --- |
| Slack с несколькими ботами | [S006](screenshots/06-official-feature-5.jpg) | Демонстрация сайта |
| Бот на видеовстрече | [S005](screenshots/05-official-feature-4.jpg) | Демонстрация сайта |
| Инициативное предложение | [S002](screenshots/02-official-feature-1.jpg) | Демонстрация сайта |
| Usage & Billing | [S065](../grok-bot-charlie-chang/screenshots/0245-usage-billing.jpg) | Видео |
| Updates и компьютер | [S066](../grok-bot-charlie-chang/screenshots/0255-updates.jpg) | Видео |
| Профиль и weekly usage | [S060](../grok-bot-video/screenshots/0848-weekly-usage-details.jpg) | Видео |
| Marketplace | [S029](screenshots/14-marketplace.jpg) | Публичный сайт 16 ноября |
| Template detail | [S030](screenshots/15-marketplace-template.jpg) | Публичный сайт 16 ноября |
| Весь landing | [S001](screenshots/01-official-landing-full.jpg) | Публичный сайт 16 ноября |

## Экраны подтверждённые только руководствами

Для следующих блоков не найдено проверенного изображения в текущем наборе. Они не заменены реконструкциями:

- **Vault:** список Login/Card/Contact info, New item, импорт CSV, hints и payment accounts. [Источник](https://docs.x.ai/grok-bot/vault).
- **Custom Rules:** Ask first/Allow automatically, редактирование и locked team rules. [Источник](https://docs.x.ai/grok-bot/approvals-security-and-privacy).
- **Import Memory:** prompt для другого ассистента и Add to Memory. [Источник](https://docs.x.ai/grok-bot/bots).
- **Pages и Library:** разделённое окно страницы и чата, фильтры, pins и sharing. [Источник](https://docs.x.ai/grok-bot/files-and-results).
- **Team Bot Manage:** General, Knowledge, Analytics и Review learnings. [Источник](https://docs.x.ai/grok-bot/team-bots).
- **Teams setup:** Waiting on admin approval, Check again, Resubmit. [Источник](https://docs.x.ai/grok-bot/microsoft-teams).
- **Телефонные звонки:** Call, live transcript, Take over и запись. [Источник](https://docs.x.ai/grok-bot/chat-and-collaboration).
- **Устройства телефона:** This iPhone/This device и состояния разрешений. [Источник](https://docs.x.ai/grok-bot/mobile).
- **Enterprise dashboard:** network, hooks, audit, setup scripts и массовое управление компьютерами. [Источник](https://docs.x.ai/grok-bot/teams-and-enterprises).
