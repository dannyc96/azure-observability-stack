"""Orders API: a small, deliberately boring FastAPI service whose job is to
emit realistic telemetry (traces, metrics, logs) into Application Insights so
the dashboards and alert rules in this repo have something real to show.

Instrumentation notes:
- configure_azure_monitor() wires the OpenTelemetry SDK to Application
  Insights using APPLICATIONINSIGHTS_CONNECTION_STRING. When the variable is
  absent (local dev without Azure), the app runs uninstrumented instead of
  crashing on startup.
- FastAPI auto-instrumentation gives every request a server span; the code
  below adds a custom counter (orders_created) and a custom child span
  (validate-order) on top, because real services always need domain-level
  telemetry that auto-instrumentation cannot invent for you.
"""

import asyncio
import logging
import os
import random
import uuid
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException
from opentelemetry import metrics, trace
from pydantic import BaseModel, Field

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("orders-api")

# ---------------------------------------------------------------------------
# Telemetry setup
# ---------------------------------------------------------------------------
if os.environ.get("APPLICATIONINSIGHTS_CONNECTION_STRING"):
    # Imported lazily so local dev without the connection string never touches
    # the Azure exporter code path.
    from azure.monitor.opentelemetry import configure_azure_monitor

    configure_azure_monitor()
    logger.info("Azure Monitor OpenTelemetry exporter configured")
else:
    logger.warning(
        "APPLICATIONINSIGHTS_CONNECTION_STRING not set; telemetry export disabled"
    )

tracer = trace.get_tracer("orders-api")
meter = metrics.get_meter("orders-api")

# Custom business metric: shows up in Application Insights as the custom
# metric `orders_created` and feeds the dedicated dashboard panel.
orders_created_counter = meter.create_counter(
    name="orders_created",
    description="Number of orders accepted by POST /orders",
    unit="1",
)

# ---------------------------------------------------------------------------
# App and models
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Orders API",
    description="Demo workload for the azure-observability-stack portfolio repo.",
    version="1.0.0",
)


class OrderIn(BaseModel):
    sku: str = Field(min_length=1, max_length=64, examples=["WIDGET-001"])
    quantity: int = Field(gt=0, le=10_000, examples=[3])
    customer_id: str = Field(min_length=1, max_length=64, examples=["cust-42"])


class Order(OrderIn):
    id: str
    created_at: datetime


# In-memory store. This is a demo app: state is per-replica and vanishes on
# restart, which is exactly what we want (no database to deploy, nothing to
# clean up). Do not copy this pattern into a real service.
ORDERS: dict[str, Order] = {}


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.get("/healthz")
async def healthz() -> dict[str, str]:
    """Liveness/readiness probe target and availability test endpoint."""
    return {"status": "ok"}


@app.get("/orders")
async def list_orders() -> list[Order]:
    return list(ORDERS.values())


@app.post("/orders", status_code=201)
async def create_order(payload: OrderIn) -> Order:
    # Custom child span: in a real service this wraps the interesting work
    # (validation, pricing, an outbound call) so slow orders are attributable
    # to a specific step in the trace waterfall, not just "POST /orders".
    with tracer.start_as_current_span("validate-order") as span:
        span.set_attribute("order.sku", payload.sku)
        span.set_attribute("order.quantity", payload.quantity)
        # Simulated validation cost so the span has visible duration.
        await asyncio.sleep(random.uniform(0.005, 0.02))

    order = Order(
        id=str(uuid.uuid4()),
        created_at=datetime.now(timezone.utc),
        **payload.model_dump(),
    )
    ORDERS[order.id] = order

    orders_created_counter.add(1, {"sku": payload.sku})
    logger.info("order created: %s (sku=%s)", order.id, payload.sku)
    return order


@app.get("/orders/{order_id}")
async def get_order(order_id: str) -> Order:
    order = ORDERS.get(order_id)
    if order is None:
        raise HTTPException(status_code=404, detail="order not found")
    return order


# ---------------------------------------------------------------------------
# Failure simulation: exists purely so the alert rules and dashboard error
# panels can be demonstrated on demand (see scripts/generate-traffic.sh).
# ---------------------------------------------------------------------------
@app.get("/simulate/error")
async def simulate_error() -> None:
    """Always returns 500. Drives the failure-rate alert during demos."""
    logger.error("simulated failure requested")
    raise HTTPException(status_code=500, detail="simulated internal error")


@app.get("/simulate/latency")
async def simulate_latency() -> dict[str, float]:
    """Sleeps 1-3 seconds. Drives the p95 latency alert during demos."""
    delay = random.uniform(1.0, 3.0)
    with tracer.start_as_current_span("artificial-delay") as span:
        span.set_attribute("delay.seconds", round(delay, 3))
        await asyncio.sleep(delay)
    return {"slept_seconds": round(delay, 3)}
