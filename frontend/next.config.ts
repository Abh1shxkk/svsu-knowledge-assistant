import type { NextConfig } from "next";

// A client-side app behind its own login, so static prerendering and Cache Components add no value.
const nextConfig: NextConfig = {
  cacheComponents: false,
  partialPrefetching: false,
  output: "standalone",                       // a self-contained server for deployment (deploy/README.md)
  distDir: process.env.NEXT_DIST_DIR || ".next",  // lets a production build sit beside a running dev server
};

export default nextConfig;
