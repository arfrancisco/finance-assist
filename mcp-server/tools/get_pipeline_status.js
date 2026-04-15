import { query } from "../graphql-client.js";

const GQL = `query {
  pipelineStatus {
    lastEodhdSync
    lastPseEdgeSync
    latestPriceDate
    latestPredictionDate
    latestSnapshotDate
    latestAuditDate
    stockCount
    activeStockCount
    priceCount
    disclosureCount
    snapshotCount
    predictionCount
    reportCount
    outcomeCount
  }
}`;

export const getPipelineStatus = {
  name: "get_pipeline_status",
  description:
    "Returns system health metrics: last sync times per data source and record counts per table. Use this first to check data freshness before querying predictions or prices.",
  inputSchema: { type: "object", properties: {}, required: [] },
  async handler() {
    const data = await query(GQL);
    return data.pipelineStatus;
  },
};
