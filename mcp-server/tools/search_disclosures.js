import { query } from "../graphql-client.js";

const GQL = `query SearchDisclosures($symbol: String, $disclosureType: String, $limit: Int) {
  disclosures(symbol: $symbol, disclosureType: $disclosureType, limit: $limit) {
    id
    disclosureDate
    disclosureType
    title
    bodyText
    sourceUrl
  }
}`;

export const searchDisclosures = {
  name: "search_disclosures",
  description:
    "Search recent corporate disclosures from PSE EDGE. Filter by stock symbol or disclosure type. Returns title, body text, and date. Useful for understanding recent corporate news and events.",
  inputSchema: {
    type: "object",
    properties: {
      symbol: {
        type: "string",
        description: "PSE stock symbol to filter by, e.g. 'ALI'. Omit for all stocks.",
      },
      disclosure_type: {
        type: "string",
        description: "Filter by disclosure type, e.g. 'Dividend', 'Annual Report', 'Material Information'",
      },
      limit: {
        type: "integer",
        description: "Number of disclosures to return, most recent first (default: 20)",
      },
    },
    required: [],
  },
  async handler({ symbol, disclosure_type, limit = 20 }) {
    const data = await query(GQL, { symbol, disclosureType: disclosure_type, limit });
    return data.disclosures;
  },
};
