import { mkdir, readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { projectPlan, schedule } from "../lib/workspace/data.mjs";
import { specification, epics, testMatrix, finalScenario, sources } from "../lib/workspace/specification.mjs";
import { documents } from "../lib/workspace/documentation.mjs";
import { publishDocumentation } from "./publish-documentation.mjs";

const tableText = (text) => String(text).replaceAll("|", "\\|").replaceAll("\n", " ");

const executionLines = [
  "# Blot: порядок выполнения задач",
  "",
  "План включает все задачи. Выполняйте сверху вниз: каждая зависимость расположена раньше задачи, которая её использует. Среди независимых задач сначала идут обязательные P0, затем расширения P1. Порядок внутри готовых задач — рекомендуемый, а не дополнительный запрет параллельной работы.",
  "",
  "Java и SwiftUI пишет пользователь. Подготовленные папки и настройки не означают, что реализация и проверки уже завершены. Статус «Можно начать» означает только готовность зависимостей; это не отметка выполнения.",
  "",
  "## Что можно начать сейчас",
  "",
  ...projectPlan.readyTasks.map((task) => `- ${task.id}: ${task.title}`),
  "",
  "## Полный порядок",
  "",
  "| Шаг | Задача | Приоритет | Сначала выполнить | Состояние |",
  "| --- | --- | --- | --- | --- |",
  ...projectPlan.tasks.map((task) => `| ${task.planOrder} | ${tableText(`${task.id}: ${task.title}`)} | ${task.priority} | ${task.dependencies.join(", ") || "—"} | ${task.status === "completed" ? "Выполнено" : projectPlan.canStart(task) ? "Можно начать" : "Ожидает зависимостей"} |`),
  "",
  "## Что конкретно писать или делать",
  "",
  ...projectPlan.tasks.flatMap((task) => [
    `### ${task.planOrder}. ${task.id}: ${task.title}`,
    "",
    task.writingGuide,
    "",
    `Файлы: ${task.files.map((file) => `\`${file.path}\``).join(", ")}.`,
    "",
    `Проверка: ${task.tests.join(" ")}`,
    "",
  ]),
  "Сроки в roadmap — исходный календарный план. Они не меняют технические зависимости и уточняются по фактическому прогрессу. Создание окна или макета можно делать параллельно с сервером; подключение реальных функций требует готовности их API и данных.",
];
const executionMarkdown = `${executionLines.join("\n")}\n`;
await writeFile(new URL("../../docs/archive/implementation-plan.md", import.meta.url), executionMarkdown, "utf8");
await writeFile(new URL("../public/implementation-plan.md", import.meta.url), executionMarkdown, "utf8");

await publishDocumentation();

const lines = [];
const list = (items) => items.forEach((item) => lines.push(`- ${item}`));
const section = (heading, items) => { lines.push(`\n##### ${heading}\n`); list(items); };

lines.push(`# ${specification.title}\n`, `Версия: ${specification.version}. Все сроки — плановые, часовой пояс Asia/Yekaterinburg.\n`, specification.introduction, "\n## Контрольные даты\n");
list([`Начало реализации: ${schedule.start}.`, `Готовность обязательных функций: ${schedule.featureReady}.`, `Финальная проверка и исправления: ${schedule.validationStart} — ${schedule.validationEnd}.`, `Сдача проекта: ${schedule.delivery}.`]);
lines.push("\n## Как пользоваться этим документом\n", `Разделы 01–13 задают поведение продукта, архитектуру и приёмку. Все ${projectPlan.tasks.length} пунктов декомпозиции опубликованы отдельными карточками на сайте: с исходным ID, сроком, файлами, результатом, зависимостями и проверкой. Прежние ${projectPlan.workPackages.length} подробных карточек сохранены как пакеты работ; они группируют подзадачи и не прибавляются к общему числу задач.`, `\nВыполнено ${projectPlan.completedTasks.length} документальных задач; осталось ${projectPlan.remainingTasks.length}. Созданные MD приложены к карточкам и полностью включены в раздел 23. Native/Java implementation и её проверки остаются запланированными. Сроки уточняются по фактическим результатам и зависимостям.`);
for (const chapter of specification.chapters) {
  lines.push(`\n## ${chapter.title}\n`);
  chapter.paragraphs.forEach((paragraph) => lines.push(`${paragraph}\n`));
  list(chapter.bullets);
}
lines.push("\n## 14. Roadmap: блоки, сроки и контрольные результаты\n", "Работы разных типов идут параллельно при выполнении зависимостей. Ранний BLE-прототип снимает техническую неопределённость до основной мобильной интеграции. Окно 2–14 декабря сохраняется для итоговой проверки и исправлений.", "\n| Блок | Начало | Дедлайн | Результат | Условие прохождения | Карточки |", "| --- | --- | --- | --- | --- | --- |");
for (const stream of projectPlan.streams) lines.push(`| ${[stream.title, stream.start, stream.end, stream.output, stream.gate, stream.taskIds.join(", ")].map(tableText).join(" | ")} |`);
lines.push("\n## 15. Полная декомпозиция реализации\n");
for (const epic of epics) {
  lines.push(`\n### ${epic.id}. ${epic.title}\n`);
  list(epic.tasks.map((task) => `**${task.id}** — ${task.title}`));
}
function renderCatalog(collection) {
  for (const task of collection) {
    const type = projectPlan.getType(task.type);
    lines.push(`\n#### ${task.id}. ${task.title}\n`, `Тип: ${type.label} · Приоритет: ${task.priority} · Дедлайн: ${task.due} · Статус: ${task.status === "completed" ? "Выполнено" : "Запланировано"}\n`, `**Цель:** ${task.goal}\n`, `**Результат:** ${task.result}\n`, `**Зависимости:** ${task.dependencies.join(", ") || "Нет"}.\n`, `**Покрытие полной декомпозиции:** ${task.covers.join(", ")}.\n`);
    if (task.deliverables?.length) {
      lines.push("**Подготовленные документы:**\n");
      list(task.deliverables.map((artifact) => `\`${artifact.path}\` — ${artifact.summary}`));
    }
    if (task.status === "completed") {
      lines.push(`\n**Выполнено:** ${task.completedAt}. Проверка документального результата:\n`);
      list(task.completionChecks);
    }
    if (task.streamId) lines.push(`**Блок roadmap:** ${projectPlan.getStream(task.streamId).title}.\n`);
    if (task.workPackageIds) lines.push(`**Пакеты работ:** ${task.workPackageIds.join(", ")}.\n`);
    if (task.writingGuide) lines.push("\n##### Что конкретно написать или сделать\n", task.writingGuide);
    section("Экраны и поверхности", task.screens);
    lines.push("\n##### Будущие файлы и ответственность\n", "| Путь | Назначение |", "| --- | --- |");
    task.files.forEach((file) => lines.push(`| \`${tableText(file.path)}\` | ${tableText(file.purpose)} |`));
    lines.push("\n##### Порядок реализации\n");
    task.steps.forEach((step, index) => lines.push(`${index + 1}. ${step}`));
    lines.push("\n##### Критерии готовности\n"); list(task.acceptance);
    lines.push("\n##### Проверки\n"); list(task.tests);
  }
}
lines.push(`\n## 16. Полный каталог: ${projectPlan.tasks.length} подзадач\n`);
renderCatalog(projectPlan.tasks);
lines.push(`\n## 17. Подробные пакеты работ: ${projectPlan.workPackages.length} блоков\n`);
renderCatalog(projectPlan.workPackages);
lines.push("\n## 18. Матрица тестирования всего проекта\n", "| Область | Сценарий | Уровень | Ожидаемый результат |", "| --- | --- | --- | --- |");
testMatrix.forEach((row) => lines.push(`| ${row.map(tableText).join(" | ")} |`));
lines.push("\n## 19. Финальный сценарий приёмки\n");
finalScenario.forEach((step, index) => lines.push(`${index + 1}. ${step}`));
lines.push("\n## 20. Комплект передачи 15 декабря\n");
list(["Подписанная и нотарифицированная macOS-сборка с bundled Java runtime.", "Подписанная iOS beta, протестированная на физическом iPhone.", "Исходники, зафиксированные версии, инструкции сборки, установки и сопряжения.", "Заполненная матрица приёмки, evidence проверок и контрольный репозиторий.", "Список исправленных и оставшихся дефектов, известные ограничения и протокол финального согласования."]);
lines.push("\n## 21. Официальные источники для технических решений\n");
list(sources.map((source) => `[${source.title}](${source.url})`));
lines.push(`\n## 22. Выполненные задачи: ${projectPlan.completedTasks.length}\n`, "| Задача | Дата | Документ | Проверка |", "| --- | --- | --- | --- |");
projectPlan.completedTasks.forEach((task) => lines.push(`| ${[`${task.id}: ${task.title}`, task.completedAt, task.deliverables.map((artifact) => artifact.path).join(", "), task.documentationSummary].map(tableText).join(" | ")} |`));
lines.push("\n## 23. Подготовленные архитектурные документы\n");
for (const document of documents) {
  const content = await readFile(new URL(`../../${document.path}`, import.meta.url), "utf8");
  lines.push(`\n### ${document.path}\n`);
  lines.push(content.replace(/^(#{1,6}) /gm, (_, hashes) => `${"#".repeat(Math.min(hashes.length + 3, 6))} `));
}

const outputDirectory = new URL("../public/", import.meta.url);
await mkdir(outputDirectory, { recursive: true });
const outputFile = new URL("BLOT_TECHNICAL_SPECIFICATION.md", outputDirectory);
await writeFile(outputFile, `${lines.join("\n")}\n`, "utf8");
console.log(`Saved ${fileURLToPath(outputFile)} (${projectPlan.tasks.length} detailed tasks, ${epics.reduce((total, epic) => total + epic.tasks.length, 0)} decomposition items).`);
