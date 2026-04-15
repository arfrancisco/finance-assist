const GRAPHQL_URL = `${process.env.FINANCE_ASSIST_URL ?? "http://localhost:3000"}/graphql`;
const API_KEY = process.env.MCP_API_KEY;

if (!API_KEY) {
  throw new Error("MCP_API_KEY env var is not set. Copy mcp-server/.env.example to mcp-server/.env and fill in the values.");
}

export async function query(gql, variables = {}) {
  const resp = await fetch(GRAPHQL_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({ query: gql, variables }),
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`GraphQL HTTP ${resp.status}: ${text}`);
  }

  const { data, errors } = await resp.json();
  if (errors?.length) {
    throw new Error(errors.map((e) => e.message).join("; "));
  }
  return data;
}
