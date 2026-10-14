import type { Metadata } from "next";
import localFont from "next/font/local";
import "./globals.css";

// Bundled in app/fonts (OFL-1.1), so builds never depend on downloading fonts from Google.
const geist = localFont({ src: "./fonts/geist-latin-wght-normal.woff2", weight: "100 900", variable: "--font-geist" });
const mono = localFont({ src: "./fonts/geist-mono-latin-wght-normal.woff2", weight: "100 900", variable: "--font-mono" });
const hindi = localFont({ src: "./fonts/noto-sans-devanagari-devanagari-wght-normal.woff2", weight: "100 900", variable: "--font-hi" });
const serif = localFont({ src: "./fonts/source-serif-4-latin-wght-normal.woff2", weight: "200 900", variable: "--font-serif" }); // document pages
const hindiSerif = localFont({ src: "./fonts/noto-serif-devanagari-devanagari-wght-normal.woff2", weight: "100 900", variable: "--font-hi-serif" });

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
