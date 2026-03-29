import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  const { name } = await req.json();

  return new Response(
    JSON.stringify({ message: `Hello ${name || "world"}!` }),
    { headers: { "Content-Type": "application/json" } }
  );
});
