import { redirect } from "next/navigation";

export const metadata = { title: "Создать аккаунт Ori", robots: { index: false, follow: false } };
export default function Register() { redirect("/login?intent=register"); }
