import type { Metadata } from "next";
import { Geist, Geist_Mono, Noto_Sans_Devanagari, Noto_Serif_Devanagari, Source_Serif_4 } from "next/font/google";
import "./globals.css";

const geist = Geist({ subsets: ["latin"], variable: "--font-geist" });
const mono = Geist_Mono({ subsets: ["latin"], variable: "--font-mono" });
const hindi = Noto_Sans_Devanagari({ subsets: ["devanagari"], weight: ["400", "500", "600"], variable: "--font-hi" });
const serif = Source_Serif_4({ subsets: ["latin"], variable: "--font-serif" }); // official document pages only
const hindiSerif = Noto_Serif_Devanagari({ subsets: ["devanagari"], weight: ["400", "600"], variable: "--font-hi-serif" });

export const metadata: Metadata = {
  title: "SVSU Knowledge Assistant",
  description: "Answers from university records and documents, with their sources.",
};

// Saved theme, else the system preference — applied before first paint.
const THEME_SCRIPT = `(function(){var t;try{t=localStorage.getItem("svsu_theme")}catch(e){}
if(t!=="light"&&t!=="dark")t=matchMedia("(prefers-color-scheme: dark)").matches?"dark":"light";
document.documentElement.setAttribute("data-theme",t)})()`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const fonts = [geist, mono, hindi, serif, hindiSerif].map((f) => f.variable).join(" ");
  return (
    <html lang="en" data-theme="light" className={fonts} suppressHydrationWarning>
      <head><script dangerouslySetInnerHTML={{ __html: THEME_SCRIPT }} /></head>
      <body>{children}</body>
    </html>
  );
}
