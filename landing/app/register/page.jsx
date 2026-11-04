import { redirect } from "next/navigation";

export const metadata = { title: "Создать аккаунт Blot", robots: { index: false, follow: false } };
export default function Register() { redirect("/login?intent=register"); }
