"use client";

import { useEffect, useState } from "react";
import { api, type QualityReport } from "@/lib/api";
import { isAdmin, useStore } from "@/lib/store";
import { Icon } from "@/components/icon";

/** Results of the automatic answer-quality test (questions written from random paragraphs). */
export function QualityCard() {
  const s = useStore();
  const [data, setData] = useState<{ latest: QualityReport | null; running: boolean } | null>(null);
  useEffect(() => {
    let stop = false;
    const tick = () => api.quality().then((d) => { if (!stop) setData(d); }).catch(() => {});
    tick();
    const t = setInterval(tick, data?.running ? 8000 : 60000);
    return () => { stop = true; clearInterval(t); };
  }, [data?.running]);
  const run = async (fresh: boolean) => { await api.runQuality(fresh); s.toast("Test started. It takes a few minutes."); setData(await api.quality()); };
  const r = data?.latest;
  const figures: [string, number | undefined, string][] = [
    ["Right paragraph found", r?.paragraph_found, "search found the paragraph the question was written from"],
    ["Right document cited", r?.cited_right_document, "the answer cited that document"],
    ["Answered correctly", r?.answered_correctly, "judged against the expected answer"],
  ];
  return (
    <div className="card">
      <div className="card-h"><div><h3>Answer quality</h3>
        <span className="xs muted">{r ? `Automatic test of ${r.questions} questions · ${new Date(r.at).toLocaleString("en-IN", { dateStyle: "medium", timeStyle: "short" })}` : "No test has been run yet"}</span></div>
        {isAdmin(s) && <div className="row">
          {data?.running ? <span className="pill info"><span className="spin" /> Running…</span> : <>
            <button className="btn sm" type="button" onClick={() => void run(false)}><Icon n="rev" s /> Run test</button>
            <button className="btn sm ghost" type="button" title="Write new questions from the documents as they are now" onClick={() => void run(true)}>New questions</button>
          </>}
        </div>}
      </div>
      {r ? (
        <div className="card-b" style={{ display: "flex", flexDirection: "column", gap: 14 }}>
          <div className="kpis kpis3">{figures.map(([label, v, hint]) => (
            <div key={label} className="kpi"><span>{label}</span><b>{v ?? "—"}%</b><small>{hint}</small></div>
          ))}</div>
          {Object.keys(r.correct_by_style).length > 0 && <p className="sm">Correct by how the question was asked: {Object.entries(r.correct_by_style).map(([k, v]) => `${k} ${v}%`).join(" · ")}</p>}
          <p className="xs muted">Questions are written by the AI from random paragraphs, so they are usually clearer than real ones: treat these figures as the best case. Answers people rate 👎 in Reports show where real questions go wrong.</p>
          {r.misses.length > 0 && (
            <details><summary className="sm">Answers judged wrong ({r.misses.length})</summary>
              <div className="table-wrap" style={{ marginTop: 8 }}><table className="t"><thead><tr><th>Question</th><th>Expected</th><th>Answer given</th><th>Paragraph found</th></tr></thead>
                <tbody>{r.misses.map((m, i) => <tr key={i}><td>{m.question}</td><td>{m.answer}</td><td className="xs">{m.got}</td><td>{m.found ? "Yes" : "No"}</td></tr>)}</tbody></table></div>
            </details>
          )}
        </div>
      ) : <div className="empty sm">{isAdmin(s) ? "Run a test to measure how well the assistant answers from your documents." : "An administrator can run the test."}</div>}
    </div>
  );
}
