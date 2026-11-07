import Image from "next/image";
import Link from "next/link";
import { localePath, type Locale } from "@/lib/i18n";

export function Logo({ locale, label }: { locale: Locale; label: string }) {
  return (
    <Link href={localePath(locale)} aria-label={label} className="flex items-center gap-2.5">
      <Image src="/icon.png" alt="" width={32} height={32} className="rounded-[8px]" priority />
      <span className="font-display text-xl font-semibold tracking-tight">Murmr</span>
      <span className="hidden font-mono text-[10px] uppercase tracking-[0.3em] text-muted-foreground sm:inline">Stream</span>
    </Link>
  );
}
