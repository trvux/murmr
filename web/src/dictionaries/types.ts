/** Every word on the site. English and Vietnamese must both satisfy this type, so one cannot lack what the other has. */
export interface Dictionary {
  meta: { title: string; description: string; keywords: string[]; ogAlt: string };
  nav: { features: string; useCases: string; privacy: string; faq: string; download: string; language: string; home: string };
  hero: {
    eyebrow: string;
    title: string;
    subtitle: string;
    cta: string;
    ctaNote: string;
    secondary: string;
    demo: { hold: string; listening: string; transcribing: string; sentence: string; fieldLabel: string; replay: string };
  };
  proof: { value: string; label: string }[];
  wpm: {
    eyebrow: string;
    title: string;
    intro: string;
    prompt: string;
    sentence: string;
    placeholder: string;
    start: string;
    again: string;
    typing: string;
    speaking: string;
    wpm: string;
    accuracy: string;
    faster: string;
    saved: string;
    savedNote: string;
    wordsPerDay: string;
    disclaimer: string;
    tooFast: string;
    sourceLabel: string;
    sourceText: string;
    sourceUrl: string;
  };
  cleanup: {
    eyebrow: string;
    title: string;
    intro: string;
    rawLabel: string;
    cleanLabel: string;
    toggleRaw: string;
    toggleClean: string;
    examples: { tag: string; raw: string; clean: string }[];
    note: string;
  };
  how: { eyebrow: string; title: string; steps: { title: string; text: string }[] };
  features: { eyebrow: string; title: string; items: { title: string; text: string }[] };
  useCases: {
    eyebrow: string;
    title: string;
    intro: string;
    sayLabel: string;
    getLabel: string;
    items: { who: string; say: string; get: string }[];
  };
  privacy: {
    eyebrow: string;
    title: string;
    intro: string;
    points: { title: string; text: string }[];
    link: string;
    openSource: string;
  };
  download: {
    eyebrow: string;
    title: string;
    text: string;
    button: string;
    requires: string;
    version: string;
    released: string;
    checksum: string;
    github: string;
    changelog: string;
    firstLaunchTitle: string;
    firstLaunchText: string;
    firstLaunchAlt: string;
    free: string;
  };
  faq: { eyebrow: string; title: string; items: { q: string; a: string }[] };
  footer: { tagline: string; product: string; project: string; legal: string; privacy: string; source: string; license: string; hub: string; builtBy: string };
}
