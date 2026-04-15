import { config } from "dotenv";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));
config({ path: join(__dirname, ".env") });

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import { getPipelineStatus } from "./tools/get_pipeline_status.js";
import { listStocks }         from "./tools/list_stocks.js";
import { getStock }           from "./tools/get_stock.js";
import { getTopPredictions }  from "./tools/get_top_predictions.js";
import { getSelfAudit }       from "./tools/get_self_audit.js";
import { searchDisclosures }  from "./tools/search_disclosures.js";

const TOOLS = [
  getPipelineStatus,
  listStocks,
  getStock,
  getTopPredictions,
  getSelfAudit,
  searchDisclosures,
];

const server = new Server(
  { name: "finance-assist", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS.map((t) => ({
    name:        t.name,
    description: t.description,
    inputSchema: t.inputSchema,
  })),
}));

server.setRequestHandler(CallToolRequestSchema, async (req) => {
  const tool = TOOLS.find((t) => t.name === req.params.name);
  if (!tool) {
    return {
      isError: true,
      content: [{ type: "text", text: `Unknown tool: ${req.params.name}` }],
    };
  }

  try {
    const result = await tool.handler(req.params.arguments ?? {});
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
    };
  } catch (err) {
    return {
      isError: true,
      content: [{ type: "text", text: err.message }],
    };
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
