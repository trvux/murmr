import type { Locale } from "@/lib/i18n";
import { en } from "./en";
import { vi } from "./vi";
import type { Dictionary } from "./types";

const dictionaries: Record<Locale, Dictionary> = { en, vi };

export const getDictionary = (locale: Locale): Dictionary => dictionaries[locale];
export type { Dictionary };
