#!/usr/bin/env node
// Log in to HashiCorp Vault with the job's GitLab id_tokens JWT and print
// `export NAME='value'` lines for the requested fields of one kv/ci entry.
// For images without the vault CLI. The job captures the output, then evals
// it, so no value reaches the job log:
//
//   VAULT_ENV="$(node scripts/vault-env.mjs <role> <kv path> field=ENV ...)"
//   eval "$VAULT_ENV"
//
// Needs VAULT_ADDR and VAULT_ID_TOKEN. The role accepts protected branches only.

const [role, path, ...pairs] = process.argv.slice(2);
const addr = (process.env.VAULT_ADDR || "").replace(/\/$/, "");
const jwt = process.env.VAULT_ID_TOKEN;

function fail(message) {
  process.stderr.write(`vault-env: ${message}\n`);
  process.exit(1);
}

if (!role || !path || pairs.length === 0) fail("usage: vault-env.mjs <role> <kv path> field=ENV ...");
if (!addr || !jwt) fail("VAULT_ADDR and VAULT_ID_TOKEN must be set");

async function call(method, url, body, token) {
  const res = await fetch(`${addr}/v1/${url}`, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { "X-Vault-Token": token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) fail(`${method} ${url}: HTTP ${res.status}`);
  return res.json();
}

const login = await call("POST", "auth/jwt/login", { role, jwt });
const secret = await call("GET", `kv/data/${path}`, null, login.auth.client_token);
const data = secret.data.data;

const quote = (value) => `'${String(value).replaceAll("'", `'\\''`)}'`;
for (const pair of pairs) {
  const [field, name] = pair.split("=");
  if (!(field in data)) fail(`kv/${path} has no field ${field}`);
  if (!/^[A-Z_][A-Z0-9_]*$/.test(name || "")) fail(`bad variable name for ${field}`);
  process.stdout.write(`export ${name}=${quote(data[field])}\n`);
}
