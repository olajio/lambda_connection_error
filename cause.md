# Revised Analysis: Prometheus Alert Lambda Connection Timeout

## What the new traceback tells us

The corrected traceback only shows the final re-raise from `lambda_handler` line 153 — it doesn't show the underlying urllib3/elastic_transport stack. But looking at `prometheus_alert_lambda.py`, line 153 is exactly this:

```python
raise Exception('Error: ', error)
```

…which is the catch-all at the bottom of `lambda_handler`. The string `'Connection timed out'` in `error` came from `ingest_logs()`:

```python
def ingest_logs(alerts):
    print('Ingesting alert events in Elastic...')
    try:
        es = local_cache.get('es')
        result = elasticsearch.helpers.bulk(es, gendata(alerts), request_timeout=8)
        return result, None
    except Exception as e:
        print(f"Elastic Exception: {e}")
        return None, str(e)
```

So the original analysis still holds — the underlying exception is the same `elastic_transport.ConnectionTimeout` from the bulk indexing call. **My diagnosis does not change.** This is not a different bug; it's the same Elastic indexing timeout, just reported from this Lambda's own file instead of the cloudwatch one.

---

## Restated cause (with full certainty for `prometheus_alert_lambda.py`)

The Lambda fails when Elastic Cloud doesn't return a response to the bulk index request fast enough. Two compounding things cause this:

### Cause 1 (primary): `request_timeout=8` in the bulk call

In `prometheus_alert_lambda.py`:

```python
result = elasticsearch.helpers.bulk(es, gendata(alerts), request_timeout=8)
```

You explicitly cap the Elastic indexing call at **8 seconds**. Anytime Elastic Cloud takes longer than 8s — which can absolutely happen during merges, rebalancing, hot shard activity, or even just network jitter to `aws.found.io` — the call fails with `ConnectionTimeout`. There is **no retry**.

### Cause 2 (compounding): Lambda timeout = 10 seconds

From `prometheus/prometheus_alerts.tf`:

```hcl
timeout = 10
```

Even if you raised `request_timeout` to 30, the Lambda itself would die at 10s. So the Lambda's hard wall is the second constraint that has to move.

### Why it's intermittent

The bulk call usually finishes in under 8 seconds. When Elastic latency, NAT egress, or cross-region jitter pushes it past 8s — even occasionally — you get this error. Cold starts make it worse because secrets fetch + TLS handshake + ES client construction eats 1–3 seconds of the budget before `bulk()` even runs.

### Why I'm 100% certain on this file

I'm certain about three things based purely on the code shown:

1. The `request_timeout=8` value in `ingest_logs()` is the active cap on the Elastic call. That's a fact from the code, not inference.
2. The Lambda's `timeout = 10` in Terraform is the outer cap. Also a fact.
3. The error string `'Connection timed out'` originates from `elastic_transport.ConnectionTimeout`, which is the documented exception class the elasticsearch-py 8.11.0 client raises when urllib3 hits a read timeout — and `helpers.bulk` is the only network call inside `ingest_logs()`. There is no other path to this error.

What I cannot be 100% certain about without the underlying urllib3 traceback (which the new error message strips out) is whether the *specific failed invocation* hit the 8s `request_timeout` cap or something else like a NAT issue or DNS hiccup. But the fix below covers all of those cases regardless.

---

## The fix

### 1. Increase `request_timeout` and add retries in `prometheus_alert_lambda.py`

In `ingest_logs()`:

```python
def ingest_logs(alerts):
    print('Ingesting alert events in Elastic...')
    try:
        es = local_cache.get('es')
        result = elasticsearch.helpers.bulk(
            es,
            gendata(alerts),
            request_timeout=30,
            max_retries=3,
            initial_backoff=2,
            max_backoff=10,
        )
        return result, None
    except Exception as e:
        print(f"Elastic Exception: {e}")
        return None, str(e)
```

In `get_es_client()`, modernize the client construction (the `timeout=` kwarg is deprecated in elasticsearch-py 8.x; use `request_timeout`):

```python
def get_es_client(elk_host, api_key):
    print('Setting Elastic client!')
    try:
        es = elasticsearch.Elasticsearch(
            elk_host,
            api_key=api_key,
            request_timeout=30,
            max_retries=3,
            retry_on_timeout=True,
            verify_certs=False,
            ssl_show_warn=False,
        )
        local_cache['es'] = es
        return es
    except elasticsearch.AuthenticationException as e:
        print(f"Elastic AuthenticationException: {e}")
        return None
```

### 2. Increase the Lambda timeout from 10 to 60 seconds

In `prometheus/prometheus_alerts.tf`, both Lambda resources:

```hcl
resource "aws_lambda_function" "prometheus_alert_lambda" {
  ...
  timeout = 60   # was 10
}

resource "aws_lambda_function" "prometheus_alert_lambda_virginia" {
  ...
  timeout = 60   # was 10
}
```

And in the SAM template (`mon-prometheus_alert_lambda_template.yaml`):

```yaml
Timeout: 60
```

Cost impact is negligible — Lambda bills on actual execution duration, not the configured timeout. Successful invocations still finish in ~1–2 seconds.

### 3. Rebuild and deploy

Since this Lambda runs from a container image (`core-shd-ci-us-east-2-ecr-monitoring:1.17.2`), you need to:

1. Update `prometheus_alert_lambda.py` in the source repo that builds this image.
2. Build and push a new tag (e.g., `1.17.3`) to ECR for both `us-east-2` and `us-east-1`.
3. Update `prometheus_alert_image_ohio` and `prometheus_alert_image_virginia` in `prometheus/_locals.tf` to point at the new tag.
4. `terraform apply` for both regions.

---

## TL;DR

**Cause:** The bulk call uses `request_timeout=8` with no retries, and the Lambda has a 10-second hard timeout. When Elastic Cloud takes longer than 8s to respond to the bulk index — which happens intermittently — the call fails with `ConnectionTimeout` and there's nothing to recover it.

**Fix:** Change `request_timeout=8` → `request_timeout=30` and add `max_retries=3` in the `helpers.bulk()` call, modernize the `Elasticsearch(...)` client construction with `retry_on_timeout=True`, and bump the Lambda timeout from 10 to 60 seconds in Terraform and the SAM template. Then rebuild the container image and roll out a new tag.

Want me to produce a unified diff for `prometheus_alert_lambda.py` plus the Terraform and SAM changes?
