import { query } from "../graphql-client.js";

const GQL = `query GetStock($symbol: String!, $priceLimit: Int, $disclosureLimit: Int) {
  stock(symbol: $symbol) {
    id
    symbol
    companyName
    sector
    industry
    isActive
    recentPrices(limit: $priceLimit) {
      tradingDate
      open
      high
      low
      close
      adjustedClose
      volume
      tradedValue
    }
    latestSnapshot(horizon: "20d") {
      asOfDate
      horizon
      totalScore
      momentum20d
      relativeStrength
      valuationScore
      qualityScore
      liquidityScore
      catalystScore
      riskScore
    }
    latestPredictions(limit: 3) {
      asOfDate
      horizon
      rankPosition
      totalScore
      predictedProbability
      predictedDirection
      recommendationType
      confidence
      report {
        summaryText
        catalystText
        riskText
      }
      outcome {
        evaluationDate
        rawReturn
        excessReturn
        wasPositive
        beatBenchmark
      }
    }
    recentDisclosures(limit: $disclosureLimit) {
      disclosureDate
      disclosureType
      title
      bodyText
    }
  }
}`;

export const getStock = {
  name: "get_stock",
  description:
    "Get detailed information for a single stock by symbol. Returns recent prices, latest feature snapshot (20d horizon), latest predictions with AI reports, and recent disclosures.",
  inputSchema: {
    type: "object",
    properties: {
      symbol: {
        type: "string",
        description: "PSE stock symbol, e.g. 'ALI', 'BDO', 'SM'",
      },
      price_limit: {
        type: "integer",
        description: "Number of recent trading days to return (default: 10)",
      },
      disclosure_limit: {
        type: "integer",
        description: "Number of recent disclosures to return (default: 5)",
      },
    },
    required: ["symbol"],
  },
  async handler({ symbol, price_limit = 10, disclosure_limit = 5 }) {
    const data = await query(GQL, {
      symbol,
      priceLimit: price_limit,
      disclosureLimit: disclosure_limit,
    });
    return data.stock;
  },
};
