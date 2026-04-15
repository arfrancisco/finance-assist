import { query } from "../graphql-client.js";

const GQL = `query SelfAudit($horizon: String, $limit: Int) {
  selfAuditRuns(horizon: $horizon, limit: $limit) {
    id
    runDate
    horizon
    sampleSize
    hitRate
    avgReturn
    avgExcessReturn
    brierScore
    calibrationNotes
    summaryText
    createdAt
  }
}`;

export const getSelfAudit = {
  name: "get_self_audit",
  description:
    "Get accuracy audit runs showing how well the model's predictions have performed. Returns hit rate, average return, excess return vs. PSEi benchmark, and Brier score per horizon.",
  inputSchema: {
    type: "object",
    properties: {
      horizon: {
        type: "string",
        description: "Filter by horizon: '5d', '20d', or '60d'. Omit for all horizons.",
      },
      limit: {
        type: "integer",
        description: "Number of audit runs to return, most recent first (default: 10)",
      },
    },
    required: [],
  },
  async handler({ horizon, limit = 10 }) {
    const data = await query(GQL, { horizon, limit });
    return data.selfAuditRuns;
  },
};
