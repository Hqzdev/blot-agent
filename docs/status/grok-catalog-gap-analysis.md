# Что осталось из каталога Grok Bot

Проверено 18 ноября 2026 года в текущем рабочем проекте. Основание — присланный каталог из 61 пункта и исходный код macOS/iOS, общего Swift core и Java cloud. Это проверка покрытия функций и доступных экранов, а не повторная проверка всех сценариев на устройствах.

Уточнение после чтения [расширенного реестра F001–F311](grok-functional-gap-analysis.md): отдельные настройки/описание роли и экран памяти личного Grok Bot названы там устаревшими. Указанные ниже отличия профиля S063 относятся к старому визуальному референсу; они не являются обязательными недоделками относительно текущей версии Grok. Расширенный отчёт отделяет эти исторические отличия от недостающих функций Blot.

Для визуальной части учитывается светлый интерфейс. Старые тёмные кадры с ведущим не используются как образец. Округления, Liquid Glass и увеличенные невидимые области нажатия — отдельные требования пользователя; их не нужно отменять ради точного копирования прямоугольных официальных макетов.

Обозначения:

- **Есть основа** — найден рабочий экран и связанный обработчик. Это не означает полное визуальное совпадение или новую проверку внешнего сервиса.
- **Частично** — найдена реализация части сценария; недостающая часть указана явно.
- **Не найдено** — соответствующий пользовательский сценарий не найден в действующих Apple-клиентах и проверенном core/backend. Иконка или упоминание в демонстрационных данных не считается реализацией.
- **Отдельно** — существует собственный продуктовый вариант; его отличие от Grok само по себе не является ошибкой.

## Существенные незакрытые пункты

1. **Платёж S011 подменён другим сценарием.** В Blot есть `subscription`: выбор Premium/Super/Ultra и переход к оплате подписки. Нет карточки оплаты покупки агентом с получателем, позициями, налогом, итогом и Allow/Deny. Подписку следует сохранить отдельным типом; наличие 11 типов карточек не означает покрытие исходных 11 сценариев.
2. **Каталог внешних приложений опережает реальные подключения.** Gmail, Google Calendar/Drive, Slack, Notion, QuickBooks, Freshdesk и 1Password присутствуют в каталоге. В действующих macOS/iOS detail-экранах неподключённого внешнего сервиса кнопка отключена и показано «Подключение … пока недоступно». Apple-интеграции и настраиваемый MCP реализованы отдельно. Наличие классов Google OAuth также не доказывает готовый вход в Gmail из каталога.
3. **Teach a task отсутствует.** Есть создание, версии, назначение и запуск текстовых навыков. Нет записи демонстрации с таймером, остановки записи и превращения действий в изученный навык.
4. **Routines не имеют полного управления.** Есть создание, расписание, включение/пауза, ручной запуск и сведения о выполнении. В действующих экранах не найдены редактирование существующих инструкции/времени и удаление. `updateSchedule` сейчас только инвертирует `enabled`.
5. **Cloud Agent и полноценный компьютер не закрыты.** Есть локальные задачи, Git/терминал, diff, условные ссылки на PR/Cursor, встроенный браузер и ручной вход. Нет найденного пользовательского сценария отдельного облачного рабочего стола/исполнителя. Java cloud управляет арендой исполнения, устройствами и синхронизацией; это не такой рабочий стол.
6. **Vault, Import Memory, Team Bot Manage, Teams setup, встречи и телефонные звонки не реализованы как в каталоге.** Keychain, память сообщений, групповой чат и голосовой разговор с агентом закрывают другие части продукта.
7. **Custom Rules и Pages/Library только частично.** Есть локальные доверенные операции и отзыв разрешений проекта, файлы/предпросмотр и панель рядом с чатом. Не найден полный общий редактор правил с командными блокировками и библиотека страниц с pins/sharing.
8. **Профиль и служебные экраны отличаются по составу.** Нет полного профиля агента с собственными labels/уведомлениями/вкладками как в S063; нет Generate/Upload аватара агента. Usage показывает фактические токены, но не полный Billing. Updates показывает установленную версию, но не управление обновлением компьютера агента.

## Полная сверка каталога

### Навигация и профиль — 9 пунктов

| Каталог | Статус | Что есть / что осталось |
| --- | --- | --- |
| S008. Основное окно | Есть основа | На Mac sidebar, чат, composer, изменяемые ширины боковых панелей, preview браузера и routines. На iOS отдельная мобильная компоновка. Полное визуальное совпадение всех страниц этим не подтверждено. [A] |
| S073. Состав ботов | Есть основа | Список чатов/агентов, аватары, превью последних сообщений, переключение. [A] |
| S032. Меню создания | Есть основа | Создание агента и группового чата. [A] |
| S063. Профиль агента | Частично | Имя, инструкции, модель, доступ, навыки; на Mac есть отдельный inspector с обзором/памятью/навыками. Не воспроизведён весь профиль из кадра с самостоятельным label и настройками уведомлений конкретного бота. Глобальные настройки уведомлений не заменяют это. [B] |
| S034. Выбор внешности | Частично | Форма, цвет; на Mac Randomize имени/формы/цвета. Нет Generate изображения и Upload изображения аватара агента. Загрузка фото пользователя — другой сценарий. [B] |
| S026. Система аватаров | Есть основа | Геометрические формы, глаза, позы и движение. Точное соответствие каждой фазе Grok не устанавливалось по неподвижным снимкам. [B, D] |
| S035. Настройка роли | Есть основа | Имя/роль, инструкции, предложения шаблонов на Mac. Последовательность onboarding и набор вариантов отличаются от кадра. [B] |
| S082. Добавление в группу | Есть основа | Выбор нескольких агентов, создание и редактирование участников. [A] |
| S083. Совместная задача | Есть основа | Групповой диалог, координатор, передача работы участникам. Внешние бизнес-сценарии с неподключёнными сервисами отдельно не закрыты. [A] |

### Карточки переписки — 11 пунктов

| Каталог | Статус | Что есть / что осталось |
| --- | --- | --- |
| S009. Черновик email | Есть основа | Поля письма, редактирование, отправка/отмена через подготовленное действие Apple Mail. Готовый Gmail-коннектор этим не подтверждается. [C] |
| S010. Вопрос | Есть основа | Варианты, свой ответ и отправка. [C] |
| S011. Платёж | Не найдено | Вместо оплаты покупки агентом сделана подписка Blot. Нет исходных полей счёта и действий Allow/Deny. [C] |
| S012. Команда | Есть основа | Последствия, раскрытие команды, разовое разрешение, разрешение точной команды в пределах проекта/агента, отказ. Это не общий редактор Custom Rules. [C, G] |
| S013. Передача компьютера | Есть основа | Ручной шаг в выбранной вкладке встроенного браузера, завершение/пропуск. Не управление произвольным удалённым рабочим столом. [C, E] |
| S014. Cloud Agent | Частично | Карточка результата локальной задачи: состояние, ветка, файлы/diff; PR только при наличии URL, Cursor при наличии локального проекта и приложения. Облачный исполнитель не найден. [C, E] |
| S015. Черновик Slack | Частично | Карточка, редактирование и review/send/discard для поддерживаемых имён инструментов подключённого MCP-сервера Slack. Нет штатного Slack OAuth из каталога. Сценарий отправки в реальный workspace заново не проверялся. [C, F] |
| S016. Приложение | Частично | Карточка и состояние подключения есть. Для Apple-приложений существует отдельный рабочий flow; для внешних каталог не даёт завершить подключение. Значок Added не означает готовый доступ. [C, F] |
| S017. Защищённый ввод | Есть основа | Поле секрета, цель, сохранение в Keychain на устройстве исполнения. Полного Vault нет. [C] |
| S018. Согласованное действие | Есть основа | Список доменов, выбор допустимого поднабора и разовое разрешение переноса cookies между профилями встроенного браузера. Это собственная реализация; картинка Grok не доказывает наличие такой общей функции у Grok. [C, E] |
| S019. Ошибка отправки | Есть основа | Сохранённый черновик, проверка неизвестного результата, затем повтор; закрытие карточки. Прямое копирование Try again заменено проверкой результата для защиты от дублей. [C] |

### Состояния и активность — 8 пунктов

| Каталог | Статус | Что есть / что осталось |
| --- | --- | --- |
| S020. Idle | Есть основа | На Mac отдельное состояние Ready с привязкой к состоянию задачи. На iOS показ присутствия устроен иначе. [D] |
| S021. Working | Есть основа | На Mac отдельное состояние, движение аватара и активность инструментов. Единый идентичный показ на iOS не подтверждён. [D] |
| S022. Waiting | Есть основа | На Mac ожидание ввода/карточки пользователя. [D] |
| S023. Blocked | Есть основа | На Mac отдельный статус для подтверждения, паузы и ошибок. [D] |
| S024. Thinking | Есть основа | Индикатор набора/размышления; на Mac отдельное состояние и движение аватара. [D] |
| S025. Done | Есть основа | Завершение задачи и соответствующее состояние на Mac. [D] |
| S028. Варианты activity | Частично | Есть строки реальных tool calls и состояния исполнения. Не все варианты исследовательского макета воспроизведены; нельзя считать каждый вариант обязательным актуальным режимом Grok. [D] |
| S007. Память и предложение изменения | Частично | Сохранение из сообщения, список, изменение/удаление; core умеет создавать candidate. Не найден законченный отдельный flow принятия/отклонения кандидата в UI: `accepting: true` из Apple UI не вызывается. [H] |

### Компьютер и обучение — 7 пунктов

| Каталог | Статус | Что есть / что осталось |
| --- | --- | --- |
| S045. Preview | Есть основа | Mac inspector делает snapshot действующей WKWebView, открывает браузер. Это preview браузера, не всего рабочего стола. [E] |
| S069. Рабочий стол | Частично | Есть постоянные профили браузера, локальные файлы/проекты и инструменты исполнения. Нет найденной самостоятельной среды рабочего стола с произвольными приложениями и удалённым экраном. [E] |
| S003. Чувствительный вход | Есть основа | Пользователь завершает ручной шаг в браузере. [C, E] |
| S071. Teach a task | Не найдено | Нет записи действий с таймером, остановки и обработки демонстрации. [I] |
| S048. Результат обучения | Не найдено | Нет результата записанной процедуры и перехода из записи к сохранённому навыку. Текстовый редактор skills — отдельный имеющийся механизм. [I] |
| S050. Запуск навыка из composer | Частично | На Mac кнопка ведёт в список навыков, где есть запуск с параметрами. Нет такого же inline-меню сохранённых навыков в composer; мобильная точка входа тоже отличается. [I] |
| S027. Динамические обои | Не найдено | Нет среды рабочего стола и переключаемых обоев по времени суток. Тема приложения — другой механизм. [E] |

### Подключения и регулярная работа — 8 пунктов

| Каталог | Статус | Что есть / что осталось |
| --- | --- | --- |
| S038. Connect apps | Частично | Каталог, поиск/категории и шаблоны на Mac; каталог приложений на iOS; рабочие Apple/MCP-подключения. Штатное подключение перечисленных внешних сервисов не доведено. [F, J] |
| S036. Connect card | Частично | Карточка приложения и требование доступа есть; законченный вход в Gmail/Slack из карточки не найден. [C, F] |
| S068. Account authorization | Не найдено | Нет действующего пользовательского flow внешнего сервиса из каталога с авторизацией и присвоением метки аккаунту. Регистрация Apple-ресурса или ручная настройка MCP не равнозначны этому сценарию. [F] |
| S081. 1Password | Не найдено | Иконка/описание в каталоге есть; действующий коннектор, выбор vault и использование записей не найдены. [F] |
| S055. Список routines | Есть основа | Список/календарь, время, часовой пояс, включение/пауза, ручной запуск, данные о выполнениях. [K] |
| S054. Детали routine | Частично | Создание и пауза есть; отсутствует полный экран редактирования существующего задания и удаление. Mac inspector открывает общий список. [K] |
| S052. SOP-файл | Есть основа | Импорт и прикрепление файлов, чтение текста/PDF/OCR, использование результата инструментом. Это не отдельный экран управления базой знаний команды. [L] |
| S077. Рекомендации товаров | Частично | Ответ может содержать текст, цены и ссылки. Отдельного структурированного блока товаров с полями и соответствующим renderer в проверенном наборе карточек нет; качество поиска/актуальность цен здесь не проверялись. [C, L] |

### Команда, настройки и каталоги — 9 пунктов

| Каталог | Статус | Что есть / что осталось |
| --- | --- | --- |
| S006. Slack с несколькими ботами | Не найдено | Внутренние группы Blot есть; установка нескольких ботов в Slack, входящие события/упоминания и ответы от имени ботов не найдены. Исходящая MCP-карточка не закрывает этот сценарий. [A, F] |
| S005. Видеовстреча | Не найдено | Нет найденного подключения бота к встрече, участника встречи, записи и обработки разговора. [M] |
| S002. Инициативное предложение | Частично | Существуют выполнение по расписанию и предложения модели в ответе. Отдельный механизм проактивных предложений по новым внешним событиям с их просмотром/принятием не найден. [K, F] |
| S065. Usage & Billing | Частично | На Mac/iOS есть фактическая статистика вызовов и токенов; отдельно подписка и web checkout. Нет полного нативного Billing с текущим тарифом/лимитами/историей счетов как единого экрана из каталога. [N, C] |
| S066. Updates и компьютер | Частично | Показывается установленная версия приложения. Нет найденного flow проверки/установки обновления среды компьютера агента. [N] |
| S060. Профиль и weekly usage | Частично | Профиль пользователя, usage, heatmap и статистика моделей есть. Состав/периодизация и визуальная композиция не повторяют весь кадр weekly usage. [N] |
| S029. Marketplace | Частично | Mac-каталог встроенных приложений/шаблонов работает с текущим workspace. Нет найденного пользовательского публичного marketplace с публикацией/версиями/установкой сторонних шаблонов; на iOS нет равного Mac каталога шаблонов. [J] |
| S030. Template detail | Есть основа | На Mac есть имя/роль/инструкция/приложения и добавление настоящего агента в текущую команду. Набор встроен в приложение; отдельного аналогичного template detail на iOS нет. [J] |
| S001. Landing | Отдельно | В `landing/` существует сайт Blot. Он не копирует всю страницу Grok; точное копирование чужого текста/бренда не следует автоматически из задачи об интерфейсе приложения. В этом проходе весь landing визуально не сравнивался. [O] |

### Пункты только из руководств — 9 пунктов

Для этих пунктов в присланном каталоге нет проверенного изображения. Можно установить наличие сценария по коду, но нельзя подтвердить визуальное совпадение с Grok.

| Каталог | Статус | Что есть / что осталось |
| --- | --- | --- |
| Vault | Не найдено | Нет списка Login/Card/Contact info, New item, импорта CSV, hints и payment accounts. Keychain используется для отдельных секретов. [C, F] |
| Custom Rules | Частично | Есть access mode, разовые согласования, точные разрешения команд, доверенные операции и отзыв в настройках проекта. Нет общего CRUD правил Ask first/Allow automatically и locked team rules. Общий `.permissionRules` в live-режиме показывает пустое состояние; Mac privacy — сведения о доступе агентов. [G] |
| Import Memory | Не найдено | Нет отдельного flow с prompt для другого ассистента, импортом и Add to Memory. Можно запомнить существующее сообщение и редактировать память. [H] |
| Pages и Library | Частично | Файлы, поиск по имени, preview и на Mac панель рядом с чатом есть. Нет найденной отдельной библиотеки страниц с фильтрами, pins, совместным редактированием и управляемым sharing. Pins чатов и экспорт файлов — другие возможности. [L] |
| Team Bot Manage | Не найдено | Есть личные агенты и группы; не найдены административные General/Knowledge/Analytics/Review learnings для командного бота. Глобальная статистика моделей не заменяет Analytics конкретного Team Bot. [A, B, N] |
| Teams setup | Не найдено | Не найден Microsoft Teams-коннектор и flow Waiting on admin approval / Check again / Resubmit. [F] |
| Телефонные звонки | Не найдено | Есть разговор пользователя с агентом через микрофон/распознавание/озвучивание. Нет звонка агентом по телефонному номеру с live transcript, передачей человеку и записью звонка. [M] |
| Устройства телефона | Частично | Есть текущий исполнитель, pairing, список телефонов/компьютеров, отзыв доступа и системные permissions. Не собрана такая же единая карточка This iPhone/This device с отдельными состояниями разрешений. Статус paired-card основан на revoked, не на полном мониторинге возможностей устройства. [P] |
| Enterprise dashboard | Не найдено | Есть облачная идентификация, устройства, sync и leases. Не найден отдельный enterprise UI для network/hooks/audit/setup scripts и массового управления компьютерами. [P, Q] |

## Рекомендуемый порядок дальнейшего закрытия

1. **Довести существующие экраны:** профиль агента, Generate/Upload, редактор/удаление routines, review памяти, общие правила, паритет Mac/iOS в статусах и точках входа в навыки.
2. **Довести подключения до результата:** Gmail/Slack и реальные состояния авторизации/ошибок, затем 1Password и остальные нужные сервисы. Не выдавать каталог за наличие коннектора.
3. **Выделить отсутствующие продуктовые сценарии:** оплата покупки агентом отдельно от подписки, Teach a task, Pages/Library и Vault.
4. **Отдельные крупные направления:** облачный компьютер, боты Slack/Teams, встречи/телефон и enterprise. Это требует исполнения и внешних интеграций, а не только оформления карточек.

## Основания в коде

- **A — каркас и группы:** [MacLiveTeamWorkspace](../../apps/macos/BlotMac/Features/Workspace/MacLiveTeamWorkspace.swift), [PhoneWorkspaceScreen](../../apps/ios/BlotIOS/Features/Root/PhoneWorkspaceScreen.swift), [WorkspaceGroupDraft](../../apps/shared/WorkspaceV3/WorkspaceGroupDraft.swift), [WorkspaceGroupResponder](../../apps/shared/WorkspaceV3/WorkspaceGroupResponder.swift), [WorkspaceApplicationInterfaces](../../apps/shared/WorkspaceV3/WorkspaceApplicationInterfaces.swift).
- **B — профиль и внешний вид:** [MacAgentCreationView](../../apps/macos/BlotMac/Features/Agents/MacAgentCreationView.swift), [PhoneAgentCreationView](../../apps/ios/BlotIOS/Features/Onboarding/PhoneAgentCreationView.swift), [MacLiveTeamInspector](../../apps/macos/BlotMac/Features/Workspace/MacLiveTeamInspector.swift), [WorkspaceTeamViews](../../apps/shared/WorkspaceV3/WorkspaceTeamViews.swift), [WorkspaceAvatar](../../packages/BlotDesign/Sources/BlotDesign/Workspace/WorkspaceAvatar.swift).
- **C — карточки и обработчики:** [WorkspaceConversationCard](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceConversationCard.swift), [WorkspaceConversationCards](../../apps/shared/WorkspaceV3/WorkspaceConversationCards.swift), [WorkspaceConversationCardService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceConversationCardService.swift).
- **D — состояния:** [MacChatStyle](../../apps/macos/BlotMac/Features/Workspace/MacChatStyle.swift), [PhoneConversationTitle](../../apps/ios/BlotIOS/Features/Chat/PhoneConversationTitle.swift), [WorkspaceToolActivity](../../apps/shared/WorkspaceV3/WorkspaceToolActivity.swift).
- **E — браузер и локальный компьютер:** [MacChatInspector](../../apps/macos/BlotMac/Features/Workspace/MacChatInspector.swift), [WorkspaceBrowserHost](../../apps/shared/WorkspaceV3/WorkspaceBrowserHost.swift), [WorkspaceBrowserService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceBrowserService.swift), [WorkspaceNativeService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceNativeService.swift).
- **F — подключения:** [PluginCatalog](../../packages/BlotAppleIntegrations/Sources/BlotAppleIntegrations/PluginCatalog.swift), [MacMarketplacePluginDetail](../../apps/macos/BlotMac/Features/Workspace/MacMarketplacePluginDetail.swift), [PhonePluginConnectionView](../../apps/ios/BlotIOS/Features/Plugins/PhonePluginConnectionView.swift), [ApplePluginConnectionView](../../apps/shared/WorkspaceV3/ApplePluginConnectionView.swift), [MCPToolProvider](../../packages/BlotWorkspace/Sources/BlotWorkspace/MCPToolProvider.swift), [LocalWorkspaceService](../../apps/shared/WorkspaceV3/LocalWorkspaceService.swift).
- **G — разрешения:** [WorkspaceSettingsViews](../../apps/shared/WorkspaceV3/WorkspaceSettingsViews.swift), [MacLiveTeamSettings](../../apps/macos/BlotMac/Features/Workspace/MacLiveTeamSettings.swift), [WorkspaceNativeProjectsView](../../apps/shared/WorkspaceV3/WorkspaceNativeProjectsView.swift), [WorkspacePermissionService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspacePermissionService.swift).
- **H — память:** [WorkspaceMemoryService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceMemoryService.swift), [WorkspaceLocalTools](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceLocalTools.swift), [PhonePrivacySettingsView](../../apps/ios/BlotIOS/Features/Settings/PhonePrivacySettingsView.swift), [MacLiveTeamSettings](../../apps/macos/BlotMac/Features/Workspace/MacLiveTeamSettings.swift).
- **I — навыки:** [WorkspaceSkillsView](../../apps/shared/WorkspaceV3/WorkspaceSkillsView.swift), [WorkspaceSkillCommands](../../apps/shared/WorkspaceV3/WorkspaceSkillCommands.swift), [MacWorkspaceComposer](../../apps/macos/BlotMac/Features/Chat/MacWorkspaceComposer.swift).
- **J — каталог и шаблоны:** [MacMarketplacePage](../../apps/macos/BlotMac/Features/Workspace/MacMarketplacePage.swift), [MacMarketplaceTemplateDetail](../../apps/macos/BlotMac/Features/Workspace/MacMarketplaceTemplateDetail.swift), [MacDemoTemplates](../../apps/macos/BlotMac/Features/TeamDesign/Domain/MacDemoTemplates.swift), [WorkspaceRoute](../../apps/shared/WorkspaceV3/WorkspaceRoute.swift).
- **K — расписания:** [WorkspaceTeamViews](../../apps/shared/WorkspaceV3/WorkspaceTeamViews.swift), [PhoneSchedulesView](../../apps/ios/BlotIOS/Features/Schedules/PhoneSchedulesView.swift), [PhoneScheduleEditor](../../apps/ios/BlotIOS/Features/Schedules/PhoneScheduleEditor.swift), [LocalWorkspaceService](../../apps/shared/WorkspaceV3/LocalWorkspaceService.swift), [WorkspaceScheduleService](../../packages/BlotWorkspace/Sources/BlotWorkspace/WorkspaceScheduleService.swift).
- **L — файлы:** [WorkspaceTeamViews](../../apps/shared/WorkspaceV3/WorkspaceTeamViews.swift), [WorkspaceFileCommands](../../apps/shared/WorkspaceV3/WorkspaceFileCommands.swift), [WorkspaceLocalFileView](../../apps/shared/WorkspaceV3/WorkspaceLocalFileView.swift), [PhoneFilesContent](../../apps/ios/BlotIOS/Features/Files/PhoneFilesContent.swift), [WorkspaceBrowserStartPage](../../apps/shared/WorkspaceV3/WorkspaceBrowserStartPage.swift).
- **M — голос:** [WorkspaceVoiceView](../../apps/shared/WorkspaceV3/WorkspaceVoiceView.swift). Название кнопки «Позвонить агенту» относится к голосовой сессии внутри приложения.
- **N — usage и настройки:** [MacSettingsUsagePane](../../apps/macos/BlotMac/Features/Workspace/MacSettingsUsagePane.swift), [PhoneSettingsProfileView](../../apps/ios/BlotIOS/Features/Settings/PhoneSettingsProfileView.swift), [MacLiveTeamSettings](../../apps/macos/BlotMac/Features/Workspace/MacLiveTeamSettings.swift), [PhoneGeneralSettingsView](../../apps/ios/BlotIOS/Features/Settings/PhoneGeneralSettingsView.swift).
- **O — сайт:** [landing/app/page.jsx](../../landing/app/page.jsx), [landing/components/landing/Sections.jsx](../../landing/components/landing/Sections.jsx).
- **P — устройства:** [WorkspaceDevicePairingView](../../apps/shared/WorkspaceV3/WorkspaceDevicePairingView.swift), [WorkspacePairedDeviceCard](../../apps/shared/WorkspaceV3/WorkspacePairedDeviceCard.swift), [PhoneGeneralSettingsView](../../apps/ios/BlotIOS/Features/Settings/PhoneGeneralSettingsView.swift).
- **Q — роль Java cloud:** [CloudExecutionController](../../backend/cloud/src/main/java/dev/blot/cloud/web/CloudExecutionController.java), [CloudLeases](../../backend/cloud/src/main/java/dev/blot/cloud/execution/CloudLeases.java).

## Пределы проверки

Исследованы действующие маршруты и связанные сервисы. Старые `MacTeam*` demo-сценарии не засчитаны как исполнение; используемые live-каталогом компоненты/встроенные шаблоны учтены. Просмотрены светлый официальный каркас S008, платёжная карточка S011 и сохранённый светлый рендер группового чата Blot. Рендер тестового окна не выдан за свежий снимок рабочего аккаунта.

Приложение в этом проходе не менялось, не пересобиралось и заново на устройствах не проверялось. Отправка писем/Slack, оплата и авторизация внешних сервисов не запускались. Совпадение всех отступов, размеров и всех состояний каждого экрана требует отдельной визуальной проверки; наличие кода этого не доказывает.
