import Workspace from "@/components/workspace/Workspace";
import "./workspace.css";

export const metadata = {
  title: "Ori — рабочая среда проекта",
  description: "Подробные задачи, техническое задание и roadmap Ori до 15 декабря 2026 года.",
};

export default function WorkspacePage() {
  return <Workspace />;
}
