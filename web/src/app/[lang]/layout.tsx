import { Inter, JetBrains_Mono, Newsreader } from "next/font/google";
import { notFound } from "next/navigation";
import { hasLocale, htmlLang, locales } from "@/lib/i18n";
import "../globals.css";

// next/font reads these options at build time, so they must be written out literally (no shared variable).
const display = Newsreader({ subsets: ["latin", "latin-ext", "vietnamese"], variable: "--font-display", display: "swap", style: ["normal", "italic"] });
const body = Inter({ subsets: ["latin", "latin-ext", "vietnamese"], variable: "--font-body", display: "swap" });
const code = JetBrains_Mono({ subsets: ["latin", "latin-ext", "vietnamese"], variable: "--font-code", display: "swap" });

export function generateStaticParams() {
  return locales.map((lang) => ({ lang }));
}

export default async function LangLayout({ children, params }: LayoutProps<"/[lang]">) {
  const { lang } = await params;
  if (!hasLocale(lang)) notFound();
  return (
    <html lang={htmlLang[lang]} className={`${display.variable} ${body.variable} ${code.variable}`}>
      <body className="min-h-screen bg-background font-sans text-foreground antialiased">{children}</body>
    </html>
  );
}
