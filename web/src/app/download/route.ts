import { NextResponse } from "next/server";
import { site } from "@/lib/site";

/** The one download address to share: always the newest disk image (GitHub counts the downloads). */
export function GET() {
  const response = NextResponse.redirect(`${site.repo}/releases/latest/download/Murmr-Stream.dmg`, 302);
  response.headers.set("Cache-Control", "no-store");
  return response;
}
