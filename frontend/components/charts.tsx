/** Monochrome single-series charts (ink on surface), so they work in light and dark mode.
 *  Each shows its value on hover/focus and carries a screen-reader table. */

type Pt = { label: string; value: number };

const W = 300, H = 120, PAD_B = 18, PAD_T = 16;

function SrTable({ caption, points }: { caption: string; points: Pt[] }) {
  return (
    <table className="sr-only"><caption>{caption}</caption>
      <tbody>{points.map((p) => <tr key={p.label}><th>{p.label}</th><td>{p.value}</td></tr>)}</tbody></table>
  );
}

/** Line + soft area, like a trend sparkline. */
export function AreaChart({ points, caption }: { points: Pt[]; caption: string }) {
  const max = Math.max(1, ...points.map((p) => p.value));
  const step = points.length > 1 ? W / (points.length - 1) : W;
  const xy = points.map((p, i) => [i * step, H - PAD_B - (p.value / max) * (H - PAD_B - PAD_T)] as const);
  const line = xy.map(([x, y], i) => `${i ? "L" : "M"}${x.toFixed(1)},${y.toFixed(1)}`).join(" ");
  const id = "ag" + caption.replace(/\W/g, "");
  return (
    <div className="chart">
      <svg viewBox={`-6 0 ${W + 12} ${H}`} aria-hidden>
        <defs><linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="var(--chart)" stopOpacity=".22" /><stop offset="1" stopColor="var(--chart)" stopOpacity="0" />
        </linearGradient></defs>
        <path d={`${line} L${W},${H - PAD_B} L0,${H - PAD_B} Z`} fill={`url(#${id})`} />
        <path d={line} fill="none" stroke="var(--chart)" strokeWidth="2.25" strokeLinejoin="round" strokeLinecap="round" />
        {xy.map(([x, y], i) => (
          <g key={i} className="pt" tabIndex={-1}>
            <rect className="hit" x={x - step / 2} y={0} width={step} height={H} />
            <circle cx={x} cy={y} r="3.5" fill="var(--surface)" stroke="var(--chart)" strokeWidth="2" />
            <text x={x} y={y - 9} textAnchor="middle">{points[i].value}</text>
            <text className="ax" x={x} y={H - 3} textAnchor="middle" style={{ opacity: 1 }}>{points[i].label}</text>
          </g>
        ))}
      </svg>
      <SrTable caption={caption} points={points} />
    </div>
  );
}

/** Vertical bars with rounded tops anchored to the baseline. `thin` gives the needle look. */
export function BarChart({ points, caption, thin = false }: { points: Pt[]; caption: string; thin?: boolean }) {
  const max = Math.max(1, ...points.map((p) => p.value));
  const slot = W / Math.max(points.length, 1);
  const bw = Math.min(thin ? 6 : 26, slot * (thin ? 0.3 : 0.62));
  const base = H - PAD_B;
  return (
    <div className="chart">
      <svg viewBox={`0 0 ${W} ${H}`} aria-hidden>
        <line x1="0" x2={W} y1={base + 0.5} y2={base + 0.5} stroke="var(--line)" />
        {points.map((p, i) => {
          const h = p.value ? Math.max(4, (p.value / max) * (base - PAD_T)) : 0;
          const x = i * slot + (slot - bw) / 2, y = base - h, r = Math.min(4, bw / 2, h);
          const d = h ? `M${x},${base} V${y + r} Q${x},${y} ${x + r},${y} H${x + bw - r} Q${x + bw},${y} ${x + bw},${y + r} V${base} Z` : "";
          return (
            <g key={i} className="pt" tabIndex={-1}>
              <rect className="hit" x={i * slot} y={0} width={slot} height={H} />
              {d && <path d={d} fill="var(--chart)" />}
              <text x={x + bw / 2} y={y - 5} textAnchor="middle">{p.value}</text>
              <text className="ax" x={x + bw / 2} y={H - 3} textAnchor="middle" style={{ opacity: 1 }}>{p.label}</text>
            </g>
          );
        })}
      </svg>
      <SrTable caption={caption} points={points} />
    </div>
  );
}

/** Half-circle tick gauge with the value in the middle, like a dial. */
export function TickGauge({ percent, label }: { percent: number; label: string }) {
  const ticks = 36, cx = 110, cy = 104, r1 = 70, r2 = 86;
  return (
    <div className="chart" style={{ display: "flex", flexDirection: "column", alignItems: "center" }}>
      <svg viewBox="0 0 220 116" style={{ maxWidth: 260 }} role="img" aria-label={`${label}: ${percent}%`}>
        {Array.from({ length: ticks + 1 }, (_, i) => {
          const a = Math.PI - (i / ticks) * Math.PI;
          const on = i / ticks <= percent / 100;
          const long = i % 6 === 0;
          const ri = long ? r1 - 4 : r1;
          return <line key={i} x1={cx + ri * Math.cos(a)} y1={cy - ri * Math.sin(a)} x2={cx + r2 * Math.cos(a)} y2={cy - r2 * Math.sin(a)}
            stroke={on ? "var(--chart)" : "var(--line-2)"} strokeWidth={long ? 3 : 2} strokeLinecap="round" />;
        })}
        <rect x={cx - 34} y={cy - 46} width="68" height="40" rx="20" fill="var(--chart)" />
        {/* inline style: the general `.chart text` rule (small, grey axis labels) would otherwise win */}
        <text x={cx} y={cy - 20} textAnchor="middle" style={{ fill: "var(--accent-ink)", fontSize: 17, fontWeight: 600 }}>{percent}%</text>
      </svg>
      <span className="xs muted" style={{ marginTop: 2 }}>{label}</span>
    </div>
  );
}
