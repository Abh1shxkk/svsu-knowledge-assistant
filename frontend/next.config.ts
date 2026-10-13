import type { NextConfig } from "next";

// This app is a client SPA behind EMS login, so static prerendering/Cache Components add no value.
const nextConfig: NextConfig = {
  cacheComponents: false,
  partialPrefetching: false,
};

export default nextConfig;
