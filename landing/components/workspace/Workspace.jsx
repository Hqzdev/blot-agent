"use client";

import { useEffect, useRef, useState } from "react";
import { ArrowDownToLine, ArrowUpRight, Layers3, Route, FileText } from "lucide-react";
import Link from "next/link";
import { projectPlan, schedule } from "@/lib/workspace/data.mjs";
import TaskCatalog from "./TaskCatalog";
import TaskDetail from "./TaskDetail";
import Roadmap from "./Roadmap";
import SpecificationView from "./SpecificationView";

const tabs = [
  { id: "tasks", title: "Задачи", icon: Layers3 },
  { id: "roadmap", title: "Roadmap", icon: Route },
  { id: "specification", title: "Техническое задание", icon: FileText },
];

export default function Workspace() {
  const [activeTab, setActiveTab] = useState("tasks");
  const [catalogScope, setCatalogScope] = useState({ status: "active", type: "all" });
  const [selectedTask, setSelectedTask] = useState(null);
  const tabRefs = useRef([]);

  useEffect(() => {
    const restoreLocation = () => {
      const url = new URL(window.location.href);
      const tab = url.hash.slice(1);
      if (!tab || tab === "completed" || tab === "tasks") {
        setActiveTab("tasks");
        setCatalogScope({ status: tab === "completed" ? "completed" : "active", type: "all" });
      } else if (tabs.some((item) => item.id === tab)) setActiveTab(tab);
      else if (tab.startsWith("spec-")) setActiveTab("specification");
      const stream = projectPlan.getStream(url.searchParams.get("stream"));
      if (stream && (!tab || tab === "tasks")) {
        setActiveTab("tasks");
        setCatalogScope({ status: "all", type: "all", stream: stream.id });
      }
      const task = projectPlan.getTask(url.searchParams.get("task"));
      setSelectedTask(task || null);
      if (task) {
        setActiveTab("tasks");
        setCatalogScope(stream?.taskIds.includes(task.id)
          ? { status: "all", type: "all", stream: stream.id }
          : { status: task.status === "completed" ? "completed" : "active", type: "all" });
      }
    };
    restoreLocation();
    window.addEventListener("popstate", restoreLocation);
    window.addEventListener("hashchange", restoreLocation);
    return () => {
      window.removeEventListener("popstate", restoreLocation);
      window.removeEventListener("hashchange", restoreLocation);
    };
  }, []);

  const selectTab = (id) => {
    setActiveTab(id);
    if (id === "tasks") setCatalogScope({ status: "active", type: "all" });
    const url = new URL(window.location.href);
    url.hash = id;
    url.searchParams.delete("stream");
    window.history.replaceState(null, "", url);
  };

  const selectCatalogScope = (scope) => {
    setCatalogScope(scope);
    const url = new URL(window.location.href);
    url.hash = scope.status === "completed" ? "completed" : "tasks";
    url.searchParams.delete("stream");
    window.history.replaceState(null, "", url);
  };

  const openStream = (id) => {
    setActiveTab("tasks");
    setCatalogScope({ status: "all", type: "all", stream: id });
    const url = new URL(window.location.href);
    url.hash = "tasks";
    url.searchParams.set("stream", id);
    url.searchParams.delete("task");
    window.history.replaceState(null, "", url);
    tabRefs.current[0]?.focus();
  };

  const openTask = (task) => {
    setSelectedTask(task);
    setActiveTab("tasks");
    const status = task.status === "completed" ? "completed" : "active";
    const url = new URL(window.location.href);
    const stream = projectPlan.getStream(url.searchParams.get("stream"));
    const inStream = stream?.taskIds.includes(task.id);
    setCatalogScope((scope) => inStream ? { status: "all", type: "all", stream: stream.id }
      : !scope.stream && scope.status === status ? scope : { status, type: "all" });
    if (!inStream) url.searchParams.delete("stream");
    url.hash = inStream ? "tasks" : status === "completed" ? "completed" : "tasks";
    url.searchParams.set("task", task.id);
    window.history.replaceState(null, "", url);
  };

  const closeTask = () => {
    setSelectedTask(null);
    const url = new URL(window.location.href);
    url.searchParams.delete("task");
    window.history.replaceState(null, "", url);
  };

  const handleTabKey = (event, index) => {
    const nextIndex = event.key === "ArrowRight" ? (index + 1) % tabs.length
      : event.key === "ArrowLeft" ? (index + tabs.length - 1) % tabs.length
      : event.key === "Home" ? 0 : event.key === "End" ? tabs.length - 1 : null;
    if (nextIndex === null) return;
    event.preventDefault();
    selectTab(tabs[nextIndex].id);
    tabRefs.current[nextIndex]?.focus();
  };

  return (
    <main className="ws-page" lang="ru" id="main-content" tabIndex={-1}>
      <div className="ws-topline">
        <div className="ws-breadcrumb"><Link href="/">Blot</Link><span>/</span><span>Рабочая среда проекта</span></div>
        <span className="ws-version">План · 01.11.2026</span>
      </div>
      <header className="ws-header">
        <div>
          <div className="ws-eyebrow"><span /> ОТ КОНЦЕПЦИИ ДО РЕЛИЗА</div>
          <h1>Рабочая среда.</h1>
          <p>План команды агентов для macOS и Windows.<br className="ws-desktop-break" /> Чаты, расписания и подтверждения — на iOS и Android.</p>
          <a className="ws-download" href="/BLOT_TECHNICAL_SPECIFICATION.md" download><ArrowDownToLine size={16} /> Скачать полное ТЗ <span>MD</span></a>
        </div>
        <div className="ws-dates" aria-label="Контрольные даты">
          <div><span className="ws-date-number">01<span> / 12</span></span><div><strong>Функции готовы</strong><span>Сквозная beta · {schedule.featureReady.slice(0, 4)}</span></div></div>
          <div><span className="ws-date-number ws-date-range">02–14<span> / 12</span></span><div><strong>Проверка и багфиксы</strong><span>Финальная регрессия</span></div></div>
          <div className="ws-delivery"><span className="ws-date-number">15<span> / 12</span></span><div><strong>Сдача проекта <ArrowUpRight size={14} /></strong><span>Сборки и протокол приёмки</span></div></div>
        </div>
      </header>
      <div className="ws-tabs" role="tablist" aria-label="Разделы рабочей среды">
        {tabs.map(({ id, title, icon: Icon }, index) => (
          <button key={id} id={`ws-tab-${id}`} role="tab" aria-selected={activeTab === id} aria-controls={`ws-panel-${id}`} tabIndex={activeTab === id ? 0 : -1} ref={(element) => { tabRefs.current[index] = element; }} onClick={() => selectTab(id)} onKeyDown={(event) => handleTabKey(event, index)}>
            <Icon size={17} /><span>{title}</span>{id === "tasks" && <span className="ws-tab-count">{projectPlan.remainingTasks.length}</span>}
          </button>
        ))}
        <span className="ws-tab-note">{projectPlan.completedTasks.length} выполнено · {projectPlan.tasks.length} всего</span>
      </div>
      <section className="ws-panel" id={`ws-panel-${activeTab}`} role="tabpanel" tabIndex={0} aria-labelledby={`ws-tab-${activeTab}`}>
        {activeTab === "tasks" && <TaskCatalog key={`${catalogScope.status}-${catalogScope.stream || "all"}`} status={catalogScope.status} type={catalogScope.type} stream={catalogScope.stream} onScopeChange={selectCatalogScope} onOpenTask={openTask} />}
        {activeTab === "roadmap" && <Roadmap onOpenStream={openStream} onOpenTask={(task) => { selectTab("tasks"); openTask(task); }} />}
        {activeTab === "specification" && <SpecificationView />}
      </section>
      <TaskDetail task={selectedTask} onClose={closeTask} onOpenTask={openTask} />
    </main>
  );
}
