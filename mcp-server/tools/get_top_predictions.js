import { query } from "../graphql-client.js";

const GQL = `query TopPredictions($horizon: String, $date: String, $limit: Int) {
  predictions(horizon: $horizon, date: $date, limit: $limit) {
    asOfDate
    horizon
    rankPosition
    totalScore
    predictedProbability
    predictedDirection
    recommendationType
    confidence
    expectedReturnMin
    expectedReturnMax
    stock {
      symbol
      companyName
      sector
    }
    report {
      summaryText
    }
    outcome {
      rawReturn
      excessReturn
      wasPositive
      beatBenchmark
      outcomeLabel
    }
  }
}`;

export const getTopPredictions = {
  name: "get_top_predictions",
  description:
    "Get the top-ranked stock predictions for a given horizon. If no date is specified, returns the most recent predictions. Includes AI-generated summaries and outcome data where available.",
  inputSchema: {
    type: "object",
    properties: {
      horizon: {
        type: "string",
        description: "Investment horizon: '5d', '20d', or '60d' (default: '20d')",
      },
      date: {
        type: "string",
        description: "ISO8601 date, e.g. '2024-12-31'. Defaults to the latest available date.",
      },
      limit: {
        type: "integer",
        description: "Number of top stocks to return (default: 10)",
      },
    },
    required: [],
  },
  async handler({ horizon = "20d", date, limit = 10 }) {
    const data = await query(GQL, { horizon, date, limit });
    return data.predictions;
  },
};
