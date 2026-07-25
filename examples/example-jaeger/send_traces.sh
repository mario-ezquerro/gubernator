#!/bin/sh
# Gubernator - OpenTelemetry Trace Generator Shell Script
# Usage: ./send_traces.sh [COUNT] [JAEGER_OTLP_URL]

COUNT=${1:-10}
ENDPOINT=${2:-"http://localhost:4318/v1/traces"}

echo "🚀 Sending $COUNT synthetic OTLP traces to $ENDPOINT..."

i=1
while [ $i -le $COUNT ]; do
  TRACE_ID=$(openssl rand -hex 16 2>/dev/null || date +%s%N | md5sum | cut -c1-32)
  SPAN_FRONT=$(openssl rand -hex 8 2>/dev/null || date +%s | md5sum | cut -c1-16)
  SPAN_API=$(openssl rand -hex 8 2>/dev/null || date +%s%N | md5sum | cut -c1-16)
  
  NOW_NANO=$(date +%s000000000)
  END_NANO=$((NOW_NANO + 45000000))
  
  PAYLOAD="{
    \"resourceSpans\": [{
      \"resource\": { \"attributes\": [{ \"key\": \"service.name\", \"value\": { \"stringValue\": \"shell-traffic-generator\" } }] },
      \"scopeSpans\": [{
        \"scope\": { \"name\": \"curl-trace-sender\" },
        \"spans\": [
          {
            \"traceId\": \"$TRACE_ID\",
            \"spanId\": \"$SPAN_FRONT\",
            \"parentSpanId\": \"\",
            \"name\": \"GET /curl-request\",
            \"kind\": 1,
            \"startTimeUnixNano\": \"$NOW_NANO\",
            \"endTimeUnixNano\": \"$END_NANO\",
            \"attributes\": [
              { \"key\": \"http.method\", \"value\": { \"stringValue\": \"GET\" } },
              { \"key\": \"http.user_agent\", \"value\": { \"stringValue\": \"curl/7.81.0\" } }
            ],
            \"status\": { \"code\": 1 }
          },
          {
            \"traceId\": \"$TRACE_ID\",
            \"spanId\": \"$SPAN_API\",
            \"parentSpanId\": \"$SPAN_FRONT\",
            \"name\": \"POST /api/process-batch\",
            \"kind\": 1,
            \"startTimeUnixNano\": \"$NOW_NANO\",
            \"endTimeUnixNano\": \"$END_NANO\",
            \"attributes\": [
              { \"key\": \"db.system\", \"value\": { \"stringValue\": \"postgresql\" } },
              { \"key\": \"batch.size\", \"value\": { \"stringValue\": \"250\" } }
            ],
            \"status\": { \"code\": 1 }
          }
        ]
      }]
    }]
  }"
  
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$ENDPOINT")
  
  if [ "$HTTP_STATUS" = "200" ]; then
    echo "  [$i/$COUNT] ✅ Trace sent (Trace ID: $TRACE_ID)"
  else
    echo "  [$i/$COUNT] ❌ Failed (HTTP $HTTP_STATUS)"
  fi
  
  i=$((i + 1))
  sleep 0.2
done

echo "✨ Done sending $COUNT traces."
