# Real-Time Data Streaming & Big Data Analytics Stack

Event streaming, high-speed columnar data warehousing, and topic management on Gubernator.

## 🏛️ Components
1. **`kafka`**: Apache Kafka 3.7 running modern **KRaft mode** (no ZooKeeper dependency).
2. **`clickhouse`**: Column-oriented database engine capable of real-time analytical queries over billions of rows.
3. **`kafka-ui`**: Intuitive management interface for topics, consumer groups, message payloads, and schema registry.

## 🚀 Gubernator Features Utilized
* **Caddy Ingress**: Web UI accessible at `http://ui.analytics.gbnt.local` and ClickHouse HTTP interface at `http://clickhouse.analytics.gbnt.local`.
* **CoreDNS Resolution**: Kafka cluster internal broker resolution via `kafka.analytics.gbnt.local:9092`.
* **Granaries Shared Storage**: Data persistence in `/var/contenedores/kafka` and `/var/contenedores/clickhouse`.

## 💻 Quick Deploy
```bash
gbnt examples deploy kafka-clickhouse
```
