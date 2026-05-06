I'll create the unified diff files for you.I've produced four files — the combined `.patch` you can apply with `git apply` in one shot, plus three individual `.diff` files if you prefer to review them separately.

## Summary of changes

**`prometheus_alert_lambda.py`** (2 hunks):
- `get_es_client()` — replaced deprecated `timeout=60` with `request_timeout=30`, added `max_retries=3` and `retry_on_timeout=True`
- `ingest_logs()` — replaced `request_timeout=8` with `request_timeout=30`, added `max_retries=3` with backoff (2s → 10s)

**`prometheus/prometheus_alerts.tf`** (2 hunks):
- `aws_lambda_function.prometheus_alert_lambda` (Ohio): `timeout = 10` → `timeout = 60`
- `aws_lambda_function.prometheus_alert_lambda_virginia` (Virginia): `timeout = 10` → `timeout = 60`

**`mon-prometheus_alert_lambda_template.yaml`** (1 hunk):
- `Timeout: 10` → `Timeout: 60`

## How to apply

```bash
# from the repo root
git apply prometheus_alert_timeout_fix.patch
```

Or if you'd rather not use git apply:

```bash
patch -p1 < prometheus_alert_timeout_fix.patch
```

## Caveat on line numbers

The hunk line numbers (`@@ -76,7 +76,14 @@` and `@@ -228,7 +235,13 @@`) for the Python file are computed from the version you shared. If your working tree has diverged, `git apply --3way` will help reconcile, or you can apply each individual `.diff` separately and let the patch tool fuzz-match.

## Don't forget

After applying, you still need to:

1. Build a new container image (e.g., tag `1.17.3`) and push to both `core-shd-ci-us-east-2-ecr-monitoring` and `core-shd-ci-us-east-1-ecr-monitoring` ECR repos.
2. Bump `prometheus_alert_image_ohio` and `prometheus_alert_image_virginia` in `prometheus/_locals.tf` to the new tag.
3. `terraform apply` for both regions.

The Terraform timeout change alone won't help until the new image with the patched Python is actually rolled out — and the Python change alone won't help until Terraform raises the Lambda's hard 60s wall.
