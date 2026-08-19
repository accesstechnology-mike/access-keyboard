import { handleFixRequest } from "../lib/handle-fix.mjs";

export async function POST(request) {
  return handleFixRequest(request);
}
