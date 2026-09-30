# Dashboards as code

Grafana dashboards live here as versioned JSON, reviewed in pull requests like
any other code. Click-built dashboards drift, disappear with the workspace,
and cannot be diffed; committed JSON can.

## What's here

| File | Purpose |
|------|---------|
| `orders-api-overview.json` | Golden signals for the orders API: request rate, error rate (server vs client), latency percentiles (p50/p95/p99), availability, and the `orders_created` custom business metric. |

The dashboard uses template variables (`$subscription`, `$resource_group`,
`$resource`) so the same JSON works against any deployment of this stack
without editing resource IDs into the file.

## Importing manually (quickest)

1. Deploy the stack, then open the Grafana endpoint:

   ```bash
   cd terraform && terraform output -raw grafana_endpoint
   ```

2. Sign in with your Entra ID account (the deployer is granted Grafana Admin
   by Terraform).
3. Dashboards -> New -> Import -> paste the contents of
   `orders-api-overview.json`.
4. When prompted, map the `Azure Monitor` input to the built-in Azure Monitor
   data source (Managed Grafana provisions it automatically).
5. Pick your subscription, resource group, and App Insights component from
   the variable dropdowns at the top.

## Importing via CLI (repeatable)

Azure Managed Grafana supports import through the `az grafana` extension:

```bash
az extension add --name amg
az grafana dashboard import \
  --name <grafana-resource-name> \
  --resource-group <resource-group> \
  --definition dashboards/orders-api-overview.json
```

## Provisioning in CI (production pattern)

For a real platform, push dashboards on merge to main so Grafana always
reflects the repo. Two good options:

- `az grafana dashboard import` in a pipeline step (simple, used here).
- The `grafana` Terraform provider pointed at the Managed Grafana endpoint
  with a service account token, managing `grafana_dashboard` resources. This
  makes drift visible in `terraform plan`, at the cost of a second provider
  and token lifecycle. Worth it once you pass a handful of dashboards.

## Data note

Panels render real data only after telemetry exists. Run
`scripts/generate-traffic.sh` for a few minutes after deploying; App Insights
ingestion lag is typically 1-2 minutes.
