import { query } from "../graphql-client.js";

const GQL = `query ListStocks($sector: String, $activeOnly: Boolean) {
  stocks(sector: $sector, activeOnly: $activeOnly) {
    id
    symbol
    companyName
    sector
    industry
    isActive
  }
}`;

export const listStocks = {
  name: "list_stocks",
  description:
    "Lists all stocks tracked by the system. Filter by sector or include inactive stocks. Returns symbol, company name, sector, and industry.",
  inputSchema: {
    type: "object",
    properties: {
      sector: {
        type: "string",
        description: "Filter by PSE sector name, e.g. 'Financials', 'Property', 'Mining & Oil'",
      },
      active_only: {
        type: "boolean",
        description: "Only return active stocks (default: true)",
      },
    },
    required: [],
  },
  async handler({ sector, active_only = true }) {
    const data = await query(GQL, { sector, activeOnly: active_only });
    return data.stocks;
  },
};
