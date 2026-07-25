#!/usr/bin/env python3
"""
Gubernator - OpenTelemetry & Jaeger Traffic Generator
Generates realistic multi-service distributed traces to Jaeger OTLP (:4318) or via HTTP endpoints (:8080).
"""

import argparse
import json
import random
import secrets
import sys
import time
import urllib.error
import urllib.request


def create_span(span_name, service_name, trace_id, span_id, parent_span_id, duration_ms, attrs, is_error=False, error_msg=""):
    start_nano = int(time.time() * 1e9)
    end_nano = start_nano + int(duration_ms * 1e6)
    
    attr_list = [{'key': str(k), 'value': {'stringValue': str(v)}} for k, v in attrs.items()]
    if is_error:
        attr_list.append({'key': 'error', 'value': {'stringValue': 'true'}})
        attr_list.append({'key': 'exception.message', 'value': {'stringValue': error_msg}})
    
    status_code = 2 if is_error else 1  # 2 = STATUS_CODE_ERROR, 1 = STATUS_CODE_OK
    
    return {
        'traceId': trace_id,
        'spanId': span_id,
        'parentSpanId': parent_span_id,
        'name': span_name,
        'kind': 1,  # SPAN_KIND_INTERNAL / SERVER
        'startTimeUnixNano': str(start_nano),
        'endTimeUnixNano': str(end_nano),
        'attributes': attr_list,
        'status': {'code': status_code, 'message': error_msg if is_error else ''}
    }


def send_otlp_batch(endpoint, resource_spans):
    payload = {'resourceSpans': resource_spans}
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(endpoint, data=data, headers={'Content-Type': 'application/json'}, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception as e:
        print(f"❌ Error sending OTLP payload to {endpoint}: {e}", file=sys.stderr)
        return False


def build_scenario_spans(scenario):
    trace_id = secrets.token_hex(16)
    spans_by_service = []
    
    if scenario == 'checkout':
        # E-Commerce Checkout Flow (4 services, 4 spans)
        s_front = secrets.token_hex(8)
        s_pay = secrets.token_hex(8)
        s_inv = secrets.token_hex(8)
        s_notify = secrets.token_hex(8)
        
        user_id = f"usr_{random.randint(1000, 9999)}"
        order_id = f"ord_{secrets.token_hex(4)}"
        amount = round(random.uniform(19.99, 499.99), 2)
        
        spans_by_service.append(('checkout-frontend', [
            create_span('POST /api/v1/checkout', 'checkout-frontend', trace_id, s_front, '', 120, {
                'http.method': 'POST', 'http.url': 'https://shop.gbnt.test/checkout',
                'user.id': user_id, 'order.id': order_id, 'order.amount': str(amount)
            })
        ]))
        
        spans_by_service.append(('payment-gateway', [
            create_span('PROCESS /v2/charge', 'payment-gateway', trace_id, s_pay, s_front, 65, {
                'payment.provider': 'stripe', 'payment.currency': 'USD',
                'payment.amount': str(amount), 'payment.status': 'succeeded'
            })
        ]))
        
        spans_by_service.append(('inventory-service', [
            create_span('UPDATE inventory_stock', 'inventory-service', trace_id, s_inv, s_pay, 30, {
                'db.system': 'postgresql', 'db.name': 'inventory_db', 'db.statement': 'UPDATE items SET stock = stock - 1'
            })
        ]))
        
        spans_by_service.append(('notification-worker', [
            create_span('SEND order_confirmation_email', 'notification-worker', trace_id, s_notify, s_inv, 15, {
                'messaging.system': 'rabbitmq', 'messaging.destination': 'email-queue', 'recipient': f"{user_id}@example.com"
            })
        ]))

    elif scenario == 'auth':
        # User Authentication Flow (3 services, 3 spans)
        s_front = secrets.token_hex(8)
        s_auth = secrets.token_hex(8)
        s_db = secrets.token_hex(8)
        
        username = random.choice(['alex', 'mario', 'maria', 'dev_user', 'admin'])
        
        spans_by_service.append(('auth-frontend', [
            create_span('POST /auth/login', 'auth-frontend', trace_id, s_front, '', 85, {
                'http.method': 'POST', 'http.route': '/auth/login', 'user.name': username
            })
        ]))
        
        spans_by_service.append(('identity-provider', [
            create_span('VERIFY_CREDENTIALS', 'identity-provider', trace_id, s_auth, s_front, 50, {
                'auth.realm': 'gubernator-sso', 'jwt.algorithm': 'RS256'
            })
        ]))
        
        spans_by_service.append(('user-db', [
            create_span('SELECT users', 'user-db', trace_id, s_db, s_auth, 20, {
                'db.system': 'sqlite', 'db.statement': 'SELECT * FROM users WHERE username = ?'
            })
        ]))

    elif scenario == 'search':
        # Catalog Search Flow with Redis Cache (3 services, 3 spans)
        s_front = secrets.token_hex(8)
        s_redis = secrets.token_hex(8)
        s_es = secrets.token_hex(8)
        
        query = random.choice(['docker', 'gubernator', 'kubernetes', 'jaeger', 'prometheus'])
        cache_hit = random.choice([True, False])
        
        spans_by_service.append(('search-frontend', [
            create_span('GET /search', 'search-frontend', trace_id, s_front, '', 40 if cache_hit else 110, {
                'http.method': 'GET', 'http.query': f"?q={query}", 'cache.hit': str(cache_hit).lower()
            })
        ]))
        
        spans_by_service.append(('redis-cache', [
            create_span('GET cache_key', 'redis-cache', trace_id, s_redis, s_front, 8, {
                'db.system': 'redis', 'db.operation': 'GET', 'redis.key': f"search:{query}"
            })
        ]))
        
        if not cache_hit:
            spans_by_service.append(('elasticsearch-cluster', [
                create_span('POST /products/_search', 'elasticsearch-cluster', trace_id, s_es, s_redis, 60, {
                    'db.system': 'elasticsearch', 'db.statement': f"{{\"query\": {{\"match\": {{\"name\": \"{query}\"}}}}}}"
                })
            ]))

    elif scenario == 'error':
        # Simulated Service Failure Trace (3 services, 3 spans, 1 failed)
        s_front = secrets.token_hex(8)
        s_api = secrets.token_hex(8)
        s_db = secrets.token_hex(8)
        
        spans_by_service.append(('jaeger-frontend', [
            create_span('GET /error-demo', 'jaeger-frontend', trace_id, s_front, '', 95, {
                'http.method': 'GET', 'http.status_code': '500', 'http.target': '/error-demo'
            }, is_error=True, error_msg="Upstream service returned HTTP 500 Internal Server Error")
        ]))
        
        spans_by_service.append(('jaeger-api', [
            create_span('POST /v1/process-job', 'jaeger-api', trace_id, s_api, s_front, 70, {
                'http.method': 'POST', 'rpc.service': 'JobProcessor'
            }, is_error=True, error_msg="Database connection timeout after 5000ms")
        ]))
        
        spans_by_service.append(('database-cluster', [
            create_span('CONNECT db_pool', 'database-cluster', trace_id, s_db, s_api, 5, {
                'db.system': 'postgresql', 'db.name': 'production_db'
            }, is_error=True, error_msg="FATAL: too many connections for role 'app_user'")
        ]))

    else:
        # Standard Landing Page Flow
        s_front = secrets.token_hex(8)
        s_api = secrets.token_hex(8)
        s_worker = secrets.token_hex(8)
        
        spans_by_service.append(('jaeger-frontend', [
            create_span('GET /', 'jaeger-frontend', trace_id, s_front, '', 45, {
                'http.method': 'GET', 'http.url': 'http://jaeger.gbnt.test/'
            })
        ]))
        
        spans_by_service.append(('jaeger-api', [
            create_span('POST /process', 'jaeger-api', trace_id, s_api, s_front, 30, {
                'http.method': 'POST', 'http.target': '/process'
            })
        ]))
        
        spans_by_service.append(('jaeger-worker', [
            create_span('EXEC /work', 'jaeger-worker', trace_id, s_worker, s_api, 15, {
                'job.status': 'completed'
            })
        ]))

    # Convert to OTLP resourceSpans payload format
    resource_spans = []
    for service_name, span_list in spans_by_service:
        resource_spans.append({
            'resource': {
                'attributes': [{'key': 'service.name', 'value': {'stringValue': service_name}}]
            },
            'scopeSpans': [
                {
                    'scope': {'name': 'gubernator-traffic-generator', 'version': '1.0.0'},
                    'spans': span_list
                }
            ]
        })
        
    return trace_id, resource_spans


def main():
    parser = argparse.ArgumentParser(description='Gubernator OpenTelemetry & Jaeger Traffic Generator')
    parser.add_argument('--count', type=int, default=10, help='Number of trace batches to send (default: 10)')
    parser.add_argument('--scenario', choices=['all', 'checkout', 'auth', 'search', 'error', 'landing'], default='all', help='Scenario preset to generate')
    parser.add_argument('--target', choices=['otlp', 'http'], default='otlp', help='Send via OTLP endpoint (:4318) or HTTP requests (:8080)')
    parser.add_argument('--endpoint', default='', help='Target endpoint URL (default: OTLP=http://localhost:4318/v1/traces, HTTP=http://localhost:8080/)')
    parser.add_argument('--delay', type=float, default=0.2, help='Delay in seconds between requests (default: 0.2)')
    
    args = parser.parse_args()
    
    scenarios = ['checkout', 'auth', 'search', 'error', 'landing'] if args.scenario == 'all' else [args.scenario]
    
    if args.target == 'otlp':
        otlp_endpoint = args.endpoint or 'http://localhost:4318/v1/traces'
        print(f"🚀 Generating {args.count} trace batches to Jaeger OTLP endpoint: {otlp_endpoint}")
        print(f"📋 Selected scenario(s): {', '.join(scenarios)}\n")
        
        success_count = 0
        for i in range(1, args.count + 1):
            curr_scenario = random.choice(scenarios) if args.scenario == 'all' else args.scenario
            trace_id, resource_spans = build_scenario_spans(curr_scenario)
            
            ok = send_otlp_batch(otlp_endpoint, resource_spans)
            if ok:
                success_count += 1
                print(f"  [{i}/{args.count}] ✅ Sent '{curr_scenario}' trace (Trace ID: {trace_id})")
            else:
                print(f"  [{i}/{args.count}] ❌ Failed to send '{curr_scenario}' trace")
                
            if i < args.count and args.delay > 0:
                time.sleep(args.delay)
                
        print(f"\n✨ Done! Successfully sent {success_count}/{args.count} traces to Jaeger.")
        print(f"🔍 Inspect traces in Jaeger UI: http://localhost:4001/jaeger/ or http://localhost:16686/")
        
    else:
        http_endpoint = args.endpoint or 'http://localhost:8080/'
        print(f"🌐 Generating {args.count} HTTP requests to frontend endpoint: {http_endpoint}")
        print(f"📋 Selected scenario(s): {', '.join(scenarios)}\n")
        
        routes = {
            'checkout': '/checkout',
            'auth': '/auth/login',
            'search': '/search?q=gubernator',
            'error': '/error-demo',
            'landing': '/'
        }
        
        success_count = 0
        for i in range(1, args.count + 1):
            curr_scenario = random.choice(scenarios) if args.scenario == 'all' else args.scenario
            route = routes.get(curr_scenario, '/')
            url = http_endpoint.rstrip('/') + route
            
            try:
                with urllib.request.urlopen(url, timeout=3) as resp:
                    print(f"  [{i}/{args.count}] ✅ GET {route} -> HTTP {resp.status}")
                    success_count += 1
            except urllib.error.HTTPError as e:
                print(f"  [{i}/{args.count}] ⚠️ GET {route} -> HTTP {e.code} (Expected for error-demo)")
                success_count += 1
            except Exception as e:
                print(f"  [{i}/{args.count}] ❌ GET {route} -> Failed: {e}")
                
            if i < args.count and args.delay > 0:
                time.sleep(args.delay)
                
        print(f"\n✨ Done! Sent {success_count}/{args.count} HTTP requests.")


if __name__ == '__main__':
    main()
