# Guía de Integración: Cómo Enviar Trazas a Jaeger en Gubernator (`how-use-jaeger.md`)

Esta guía explica paso a paso todo lo necesario para que cualquier contenedor, microservicio o aplicación que se ejecute en Gubernator transmita sus trazas a **Jaeger** usando el estándar internacional **OpenTelemetry (OTLP)**.

---

## 🏛 Arquitectura y Puertos de Jaeger

Cuando ejecutas el comando `gbnt monitor init` en el nodo Manager de Gubernator, se levanta automáticamente el contenedor de observabilidad `gbnt-monitor-jaeger`.

Este colector expone los puertos receptores estándar de **OpenTelemetry**:

| Protocolo | Puerto Receptores | Endpoint / URL | Recomendado Para |
| --- | --- | --- | --- |
| **OTLP HTTP (JSON / Protobuf)** | `:4318` | `http://gbnt-monitor-jaeger:4318/v1/traces` | Aplicaciones Web, Python, Node.js, PHP, Ruby |
| **OTLP gRPC** | `:4317` | `gbnt-monitor-jaeger:4317` | Servicios Go, Java, Rust, C++ de alto rendimiento |
| **Jaeger UI Dashboard** | `:16686` | `http://localhost:4001/jaeger/` | Inspección visual en la web de Gubernator |

---

## 🌐 1. Conexión de Red (`gbnt-net`)

Para que tus contenedores puedan resolver el nombre de host `gbnt-monitor-jaeger` vía DNS interno de Docker, debes unirlos a la red `gbnt-net`.

### Ejemplo en `docker-compose.yml`:

```yaml
version: '3.8'

services:
  mi-servicio:
    image: mi-usuario/mi-app:latest
    ports:
      - "8080:8080"
    networks:
      - gbnt-net
    environment:
      - OTEL_SERVICE_NAME=mi-servicio-app
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://gbnt-monitor-jaeger:4318

networks:
  gbnt-net:
    external: true
```

> 💡 **Tip para Contenedores Fuera de `gbnt-net`**: Si tu contenedor está en una red Docker aislada o en otra máquina externa, reemplaza `gbnt-monitor-jaeger` por la IP privada o pública del nodo Manager:  
> `http://<IP_DEL_MANAGER>:4318/v1/traces` o `http://172.17.0.1:4318/v1/traces`.

---

## ⚙️ 2. Variables de Entorno Estándar de OpenTelemetry (OTEL)

La mayoría de los SDKs oficiales de OpenTelemetry en cualquier lenguaje detectan de forma nativa estas variables de entorno sin necesidad de modificar el código fuente:

```bash
# Nombre único que aparecerá en el menú de servicios de Jaeger UI:
OTEL_SERVICE_NAME=mi-servicio

# Endpoint OTLP HTTP (puerto 4318):
OTEL_EXPORTER_OTLP_ENDPOINT=http://gbnt-monitor-jaeger:4318

# Protocolo (http/protobuf, http/json o grpc):
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf

# Atributos globales para todas las trazas (opcional):
OTEL_RESOURCE_ATTRIBUTES=deployment.environment=production,cluster.region=europe-1
```

---

## 💻 3. Código de Integración por Lenguaje

### 🐍 Python (OpenTelemetry HTTP Exporter)

Instala las dependencias estándar:
```bash
pip install opentelemetry-api opentelemetry-sdk opentelemetry-exporter-otlp-proto-http
```

Código de ejemplo (`main.py`):
```python
import time
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource

# 1. Configurar Resource y Provider
resource = Resource.create({"service.name": "mi-app-python"})
provider = TracerProvider(resource=resource)

# 2. Configurar el OTLP HTTP Exporter apuntando a Jaeger
exporter = OTLPSpanExporter(endpoint="http://gbnt-monitor-jaeger:4318/v1/traces")
processor = BatchSpanProcessor(exporter)
provider.add_span_processor(processor)

trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# 3. Crear Trazas y Spans
def procesar_orden():
    with tracer.start_as_current_span("POST /api/v1/checkout") as span:
        span.set_attribute("order.id", "ord_99812")
        span.set_attribute("order.amount", 199.99)
        time.sleep(0.05)  # Simulando procesamiento
        
        with tracer.start_as_current_span("payment_gateway_charge") as child_span:
            child_span.set_attribute("payment.provider", "stripe")
            time.sleep(0.03)

if __name__ == "__main__":
    procesar_orden()
```

---

### 🟢 Node.js / JavaScript (Express / NestJS)

Instala las dependencias:
```bash
npm install @opentelemetry/sdk-node @opentelemetry/exporter-trace-otlp-http @opentelemetry/resources @opentelemetry/semantic-conventions
```

Código de inicialización (`tracing.js`):
```javascript
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { Resource } = require('@opentelemetry/resources');
const { SemanticResourceAttributes } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: 'mi-app-nodejs',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'http://gbnt-monitor-jaeger:4318/v1/traces',
  }),
});

sdk.start();
console.log('✅ OpenTelemetry activado enviando trazas a Jaeger');
```

---

### 🐹 Go (Golang)

Código de inicialización (`tracer.go`):
```go
package main

import (
	"context"
	"log"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.4.0"
)

func initTracer(ctx context.Context) (*sdktrace.TracerProvider, error) {
	exporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint("gbnt-monitor-jaeger:4318"),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceNameKey.String("mi-servicio-go"),
		)),
	)
	otel.SetTracerProvider(tp)
	return tp, nil
}

func main() {
	ctx := context.Background()
	tp, err := initTracer(ctx)
	if err != nil {
		log.Fatalf("Error inicializando tracer: %v", err)
	}
	defer tp.Shutdown(ctx)

	tracer := otel.Tracer("ejemplo-go")
	_, span := tracer.Start(ctx, "operacion_base_datos")
	defer span.End()

	time.Sleep(50 * time.Millisecond)
}
```

---

## 🚦 4. Herramientas de Generación de Tráfico de Prueba

Gubernator incluye dos scripts listos para usar en `examples/example-jaeger/` para probar que Jaeger está recibiendo trazas correctamente sin escribir código:

### Generador en Python (`generate_traces.py`)
```bash
# Enviar 15 trazas de prueba a Jaeger:
python3 examples/example-jaeger/generate_traces.py --count 15 --scenario all --target otlp
```

### Generador Shell POSIX (`send_traces.sh`)
```bash
# Enviar 10 trazas usando curl:
./examples/example-jaeger/send_traces.sh 10 http://localhost:4318/v1/traces
```

---

## 🔍 5. Visualizar Trazas en la Interfaz de Gubernator

1. Entra en el Dashboard Web de Gubernator (`http://localhost:4001/`).
2. Ve a la pestaña **Jaeger** (o accede directamente a `http://localhost:16686/`).
3. En el desplegable **Service**, selecciona tu servicio (ej. `mi-servicio-app`, `checkout-frontend`, etc.).
4. Haz clic en **Find Traces**.
5. Haz clic en cualquier traza para desglosar la cascada de latencia, ver los atributos (`db.system`, `order.id`) y diagnosticar errores.
