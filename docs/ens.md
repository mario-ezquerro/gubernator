# 🛡️ Esquema Nacional de Seguridad (ENS — Real Decreto 311/2022)

Gubernator incorpora un subsistema integral de gobernanza, auditoría técnica y controles criptográficos diseñado para cumplir con las exigencias del **Esquema Nacional de Seguridad (ENS)** regulado por el **Real Decreto 311/2022** y las guías **CCN-STIC** del **Centro Criptológico Nacional (CCN-CNI)**, aplicable a entornos de categoría **BÁSICA**, **MEDIA** y **ALTA**.

---

## 🏛 1. Ámbito de Aplicación y Cumplimiento Normativo

El ENS es de cumplimiento legal obligatorio en España para:
* **Entidades del Sector Público:** Administración General del Estado, Comunidades Autónomas, Entidades Locales y organismos públicos vinculados.
* **Proveedores Tecnológicos del Sector Público:** Empresas y contratistas que tratan información pública o prestan servicios de infraestructura, computación y despliegue de contenedores a las administraciones.

Gubernator opera como orquestador soberano y autocontenido, garantizando que el clúster pueda desplegarse en entornos completamente aislados (*air-gapped*) o híbridos cumpliendo los principios de **Confidencialidad [C]**, **Integridad [I]**, **Trazabilidad [T]**, **Autenticidad [A]** y **Disponibilidad [D]**.

---

## 📋 2. Fases del ENS Implementadas en Gubernator

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       GUBERNATOR ENS SECURITY SUITE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│  FASE 1: CONTROL DE ACCESO & AUDITORÍA FORENSE INMUTABLE (v2.85.1)          │
│  - Bloqueo tras 5 intentos fallidos (15 min) con desbloqueo administrativo   │
│  - Contraseñas robustas CCN-STIC 823 (≥12 chars, mayús/minús/núm/símbolos)   │
│  - Caducidad de sesiones inactivas (15 min) y avisos legales en login       │
│  - Pista forense inmutable con cadena de hashes criptográficos SHA-256      │
│  - Suspensión temporal y reactivación de usuarios mediante switch           │
├─────────────────────────────────────────────────────────────────────────────┤
│  FASE 2: CIFRADO EN REPOSO DE COPIAS DE SEGURIDAD (v2.86.0)                 │
│  - Motor AES-256-GCM con derivación de clave PBKDF2-HMAC-SHA256             │
│  - Pipeline streaming sin archivos temporales en texto plano (.tar.gz.enc)  │
│  - Restauración autenticada con rechazo criptográfico ante manipulación     │
│  - Paridad total en Web UI y CLI (`gbnt backup create --encrypt`)           │
├─────────────────────────────────────────────────────────────────────────────┤
│  FASE 3: CUADRO DE MANDO & MOTOR DE AUDITORÍA CONTINUA (v2.87.0)            │
│  - Evaluación heurística en vivo de 11 controles técnicos del Anexo II      │
│  - 4 Tarjetas KPI: Categoría Global alcanzada, BÁSICO %, MEDIO %, ALTO %    │
│  - Exportador de informes técnicos en CommonMark para auditorías CCN-STIC   │
│  - Paridad total en CLI (`gbnt security ens` y `gbnt security ens --report`)│
├─────────────────────────────────────────────────────────────────────────────┤
│  FASE 4: MFA/TOTP OBLIGATORIO PARA CUENTAS PRIVILEGIADAS (v2.88.0)          │
│  - Directiva de obligatoriedad `op.acc.6` para roles `admin` y `operator`   │
│  - Intercepción forzada del login con asistente interactivo de enrolamiento │
│  - Generación de QR offline, clave secreta manual y 8 códigos de respaldo   │
│  - Elevación de puntuación op.acc.6 al 100% COMPLIANT en nivel MEDIO y ALTO │
├─────────────────────────────────────────────────────────────────────────────┤
│  FASE 5: REENVÍO A SIEM EN TIEMPO REAL & DETECCIÓN DE INTRUSIÓN (v2.89.0)   │
│  - Monitorización continua de eventos y telemetría en tiempo real (op.mon.2)│
│  - Formatos RFC5424 (Syslog), CEF (ArcSight) y JSON vía UDP, TCP y TLS      │
│  - Clasificación de severidad y alertas de intrusión automáticas (PRI 33/9) │
│  - Diagnóstico de sondas en vivo con medición de latencia (roundtrip ms)    │
│  - Panel de telemetría en Web UI (activos, intrusiones, fallos, latencia)   │
│  - Paridad CLI completa (`gbnt security siem status|test|enable|disable`)   │
│  - Elevación de la medida op.mon.2 del 40% al 100% COMPLIANT en MEDIO/ALTO  │
├─────────────────────────────────────────────────────────────────────────────┤
│  FASE 6: GATEKEEPER & CADENA DE SUMINISTRO DE SOFTWARE (v2.90.0)             │
│  - Control de admisión estricto Gatekeeper (`enforce`, `audit`, `disabled`) │
│  - Firmas criptográficas ECDSA P-256 (Cosign) y verificación en despliegue  │
│  - Generación y custodia de pares de claves (`gbnt security key generate`)  │
│  - Bloqueo preventivo de imágenes con CVEs CRITICAL / HIGH sin parche       │
│  - Auto-remediación asistida de imágenes vulnerables con rollback seguro    │
│  - Paridad CLI (`gbnt security policy set`, `gbnt security key [generate|rm]`)│
│  - Elevación de la medida mp.sw.2 al 100% COMPLIANT en nivel ALTO           │
├─────────────────────────────────────────────────────────────────────────────┤
│  FASE 7: PLANIFICACIÓN PERIÓDICA DE COPIAS CIFRADAS (v2.90.0)               │
│  - Motor daemon de programación periódica (cron) para copias de seguridad   │
│  - Cifrado automático en reposo AES-256-GCM + PBKDF2 (100.000 iteraciones)   │
│  - Política de retención configurable (Keep Last N) con poda automática     │
│  - Paridad CLI (`gbnt backup schedule add|ls|rm` con flags `--encrypt`)     │
│  - Elevación de op.exp.10 y mp.si.2 al 100% COMPLIANT                       │
│  - Certificación Global del Clúster Gubernator en Categoría ALTO (100%)     │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🔐 3. Matriz de Controles Técnicos Auditados (Anexo II RD 311/2022)

Gubernator evalúa de forma continua y automatizada las siguientes 11 medidas técnicas:

| Código ENS | Medida Técnica | Marco | Dimensiones | Niveles Aplicables | Mecanismo de Verificación en Gubernator |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **`org.2`** | Segregación de funciones | Organizativo | `[C] [I] [T]` | BÁSICO, MEDIO, ALTO | Matriz RBAC de 4 niveles (`admin`, `operator`, `auditor`, `readonly`) con rol exclusivo de Auditor. |
| **`op.acc.1`** | Identificación unívoca | Operacional | `[A] [T]` | BÁSICO, MEDIO, ALTO | Identificación unívoca por UUID, hashes bcrypt y tokens JWT firmados criptográficamente (HMAC-SHA256). |
| **`op.acc.2`** | Control de acceso robusto | Operacional | `[C] [I] [A]` | BÁSICO, MEDIO, ALTO | Bloqueo automático tras 5 fallos, contraseñas $\ge 12$ chars (CCN-STIC 823), timeout 15m y suspensión por switch. |
| **`op.acc.6`** | Autenticación multifactor | Operacional | `[A] [C]` | MEDIO, ALTO | Motor TOTP (RFC 6238) integrado en el backend para usuarios privilegiados. |
| **`op.exp.10`** | Copias de seguridad | Operacional | `[I] [D]` | BÁSICO, MEDIO, ALTO | Copias de seguridad de volúmenes con verificación de integridad criptográfica SHA-256. |
| **`op.mon.1`** | Registro de actividad | Operacional | `[T] [I]` | BÁSICO, MEDIO, ALTO | Pista forense inmutable sellada mediante cadena encadenada de hashes SHA-256 (`prev_hash` $\to$ `hash`). |
| **`op.mon.2`** | Monitorización continua & SIEM | Operacional | `[T] [D]` | MEDIO, ALTO | Reenvío automático de alertas y logs forenses hacia servidores SIEM (Syslog / CEF / JSON). |
| **`op.cont.2`** | Continuidad de actividad | Operacional | `[D]` | BÁSICO, MEDIO, ALTO | Clúster multi-nodo altamente disponible con auto-restart de contenedores y tolerancia a fallos. |
| **`mp.si.1`** | Comunicaciones seguras | Protección | `[C] [I]` | BÁSICO, MEDIO, ALTO | Ingress Caddy integrado con aprovisionamiento obligatorio de TLS 1.2 / 1.3 y renovación forzada. |
| **`mp.si.2`** | Cifrado en reposo | Protección | `[C] [I]` | MEDIO, ALTO | Cifrado autenticado AES-256-GCM con PBKDF2 para archivos de backup y persistencia. |
| **`mp.sw.2`** | Seguridad del software | Protección | `[I] [A]` | BÁSICO, MEDIO, ALTO | Firmas criptográficas Cosign, escaneos SBOM (CycloneDX/SPDX) y control de admisión Gatekeeper. |

---

## 🔒 4. Cifrado en Reposo de Copias de Seguridad (ENS `mp.si.2`, `op.exp.10`)

Las copias de seguridad generadas por Gubernator pueden cifrarse mediante autenticación criptográfica en streaming:

* **Algoritmo:** **AES-256-GCM** (Galois/Counter Mode con AEAD).
* **Derivación de Clave:** **PBKDF2-HMAC-SHA256** con $\ge 100.000$ iteraciones y salt aleatorio de 32 bytes por copia.
* **Integridad de Bloques:** Chunks de 64 KB con datos de autenticación adicionales (AAD) ligados al número de secuencia del bloque para prevenir ataques de truncamiento o sustitución.
* **Extensión y Encabezado:** Cabecera mágica `GBNTENC1` y extensión `.tar.gz.enc`.

### Creación y Restauración desde CLI
```bash
# Crear copia de seguridad cifrada con contraseña
gbnt backup create /var/contenedores/mi-servicio/data \
  --name backup-seguro \
  --encrypt \
  --password "MiContraseñaRobusta123!#"

# Listar copias verificando el estado de cifrado
gbnt backup ls

# Restaurar copia cifrada
gbnt backup restore bkp-7f8a9b2c \
  --target /var/contenedores/mi-servicio/data \
  --password "MiContraseñaRobusta123!#"
```

---

## 👥 5. Control de Acceso y Suspensión Temporal de Usuarios (`op.acc.2`)

* **Bloqueo Automático tras 5 Intentos Fallidos:** Protege contra ataques de fuerza bruta. Durante los 15 minutos de bloqueo, la API y Web rechazan la autenticación con código `423 Locked`.
* **Desbloqueo Inmediato:** El administrador puede pulsar el botón **Desbloquear Cuenta** (`Icons.lock_open`) en la tabla de usuarios locales.
* **Suspensión Temporal con Switch:**
  * En la tabla de usuarios locales, cada fila cuenta con un **Switch interactivo** en la columna *Status*.
  * Permite suspender temporalmente el acceso del usuario (`⏸️ Suspendido`) sin eliminar sus datos, roles o configuraciones.
  * También puede gestionarse desde el diálogo de edición con la tarjeta explicativa *"Cuenta Activa / Suspendida"*.
  * La cuenta principal `admin` cuenta con protección contra suspensión accidental.

---

## 🖥️ 6. Cuadro de Mando de Cumplimiento en el Web Dashboard

Accesible desde el menú lateral **Security & Directory** $\to$ pestaña **Cumplimiento ENS (RD 311/2022)**:

1. **4 Tarjetas KPI en Tiempo Real:**
   * **Categoría Global Alcanzada:** `ALTO`, `MEDIO`, `BÁSICO` o `INSUFICIENTE`.
   * **Puntuación Nivel BÁSICO (%):** Barra de progreso con umbral de superación.
   * **Puntuación Nivel MEDIO (%):** Porcentaje ponderado de medidas operacionales y de protección.
   * **Puntuación Nivel ALTO (%):** Requisitos avanzados (MFA, SIEM, firmas Cosign).
2. **Filtros Rápidos:** `Todas`, `BÁSICO`, `MEDIO`, `ALTO` y `⚠️ Requieren Acción`.
3. **Acordeón de Evidencias:** Cada medida muestra en monospace la evidencia técnica extraída en vivo y recomendaciones CCN-STIC para corregir deficiencias.
4. **Exportación de Informe Técnico:**
   * Botón **Exportar Informe**: abre un visor integrado en CommonMark.
   * Permite copiar al portapapeles o descargar directamente el archivo `informe-cumplimiento-ens-YYYYMMDD.md`.

---

## 🔑 7. Autenticación Multifactor (MFA/TOTP) Obligatoria para Cuentas Privilegiadas (`op.acc.6`)

El ENS exige que el acceso a funciones de administración o configuración requiera de autenticación multifactor.

* **Directiva `MFAEnforcePrivileged`:**
  * Configurable desde la Web UI (pestaña *Security & Directory* $\to$ *SIEM & Forensic Audit Trail*).
  * Aplica de forma selectiva a roles privilegiados (`admin`, `operator`), manteniendo el acceso fluido para roles de auditoría o consulta si así se desea.
* **Flujo de Intercepción Forzada en Login:**
  * Cuando un administrador u operador sin MFA configurado introduce sus credenciales correctas, el sistema no emite la sesión final.
  * Se responde con `mfa_required: true` y `mfa_configured: false`, suministrando un token temporal restringido (`mfa_token`, 5 minutos de validez) y el payload criptográfico inicial.
* **Asistente de Enrolamiento en Pantalla:**
  * La pantalla de login detecta el estado y despliega el código QR generado offline, la clave secreta manual en Base32 y los 8 códigos de recuperación de un solo uso.
  * El usuario debe escanear el QR en su aplicación TOTP (Google Authenticator, Microsoft Authenticator, 1Password, etc.) e ingresar el primer código de 6 dígitos.
* **Endpoint Autenticado de Completitud (`POST /api/auth/mfa/setup-complete`):**
  * Verifica el código TOTP contra el secreto en tiempo real.
  * Persiste `mfa_enabled = true` y los códigos de respaldo en la base de datos.
  * Emite el evento forense `MFA_ENABLED` y otorga el token de sesión definitivo (`gbnt_session`).
* **Incentivo en la Puntuación de Cumplimiento:**
  * La activación de la directiva o el enrolamiento del 100% de las cuentas privilegiadas eleva inmediatamente la medida `op.acc.6` al **100% (COMPLIANT)**, permitiendo certificar el clúster en categoría **MEDIO** y **ALTO**.

---

---

## 📡 9. Monitorización Continua, Detección de Intrusión y Reenvío a SIEM (`op.mon.2`)

El ENS exige en sus niveles **MEDIO** y **ALTO** la detección activa de intrusiones, eventos anómalos y la centralización de pistas de auditoría en sistemas de monitorización (SIEM / Syslog).

* **Formatos y Protocolos Soportados:**
  * **RFC5424 (Syslog):** Formato estándar IETF con encabezados estructurados (`PRI`, `TIMESTAMP`, `HOSTNAME`, `APP-NAME`, `STRUCTURED-DATA`).
  * **CEF (Common Event Format):** Formato nativo para integración directa con plataformas SIEM líderes (Splunk, ArcSight, QRadar, Wazuh).
  * **JSON:** Payload estructurado con metadatos extendidos para ingesta en OpenSearch, Elasticsearch o Loki.
  * **Protocolos de Red:** **UDP** (baja sobrecarga), **TCP** (entrega confiable) y **TLS** (canal seguro cifrado).
* **Clasificación Automática de Severidad & Detección de Intrusión:**
  * Eventos críticos como bloqueo de cuentas por fuerza bruta (`AUTH_LOCKOUT`), manipulación de la cadena forense (`AUDIT_CHAIN_COMPROMISED`), rechazo por política de admisión (`SECURITY_GATEKEEPER_BLOCKED`) o intentos de acceso a cuentas suspendidas son clasificados automáticamente como **Alertas de Intrusión**.
  * En **CEF**, reciben **severidad 9 o 10** y categoría `cat=IntrusionAlert`.
  * En **RFC5424**, reciben **`PRI 33`** (`auth.alert`) con el flag estructurado `intrusion="true" level="critical"`.
  * En **JSON**, se etiquetan con `"is_intrusion": true` y `"severity": "CRITICAL"`.
* **Telemetría y Diagnóstico de Conexión en Vivo:**
  * Métricas en tiempo real: Eventos transmitidos, alertas de intrusión, fallos de entrega y estampa temporal de la última transmisión.
  * Estados del enlace: `🟢 ACTIVO`, `🟡 PREPARADO`, `🟠 DEGRADADO`, `🔴 INALCANZABLE`, `⚪ DESHABILITADO`.
  * Medición de latencia de red (roundtrip en milisegundos) en pruebas de sonda.

---

## 💻 10. Comandos CLI para Auditoría ENS & Gestión de SIEM

```bash
# Ver la tabla resumen de cumplimiento ENS
gbnt security ens

# Exportar el informe técnico oficial de auditoría en Markdown
gbnt security ens --report > informe-auditoria-ens.md

# Consultar el estado operativo y telemetría de reenvío a SIEM
gbnt security siem status

# Enviar una sonda de prueba de conectividad al colector SIEM (mide latencia)
gbnt security siem test

# Enviar sonda a un host o puerto alternativo
gbnt security siem test --host 192.168.1.50 --port 514 --proto UDP --format RFC5424

# Habilitar el reenvío a SIEM (eleva op.mon.2 al 100% COMPLIANT)
gbnt security siem enable --host 192.168.1.50 --port 514 --proto UDP --format RFC5424

# Deshabilitar el reenvío a SIEM
gbnt security siem disable

# Consultar el estado en formato JSON vía API
curl -s http://localhost:4001/api/security/ens/status | jq .
```

---

## 🛡️ 11. Gatekeeper & Cadena de Suministro de Software (Fase 6 — `mp.sw.2`)

La medida **`mp.sw.2`** del ENS (Seguridad del Software) exige garantizar la procedencia, integridad y ausencia de vulnerabilidades críticas conocidas en las imágenes de contenedores desplegadas en el clúster.

### Componentes del Subsistema
1. **Control de Admisión Gatekeeper:** Intercepta cada intento de despliegue (`POST /v1/stack/deploy`, `redeploy`, etc.) evaluando:
   * **Modos de Operación:**
     * `enforce`: Bloquea terminantemente el despliegue si la imagen no posee una firma criptográfica válida o contiene vulnerabilidades inaceptables.
     * `audit`: Permite el despliegue pero registra una alerta forense de severidad `HIGH` / `CRITICAL` en la pista de auditoría SHA-256.
     * `disabled`: Admisión sin restricciones.
   * **Bloqueo por Severidad CVE:** Bloqueo configurable en nivel `critical`, `high` o `none`.
   * **Política de Vulnerabilidades sin Parche:** Opción `--allow-unfixed` para permitir o denegar software con CVEs que aún no poseen corrección oficial del proveedor.
2. **Firmas Criptográficas Cosign (ECDSA P-256):**
   * Generación y custodia de claves criptográficas dentro del propio clúster (`gbnt security key generate`).
   * Firma digital de los digests inmutables SHA-256 de las imágenes (`gbnt image sign <imagen>`).
   * Verificación en tiempo de ejecución (`gbnt image verify <imagen>`).
3. **Software Bill of Materials (SBOM) & Escaneo de Vulnerabilidades:**
   * Generación de manifiestos estándar **CycloneDX JSON** y **SPDX JSON** (`gbnt sbom <imagen>`).
   * Escaneo estático de paquetes y librerías con puntuación CVSS y clasificación de severidad.

### Comandos CLI para Gatekeeper y Claves
```bash
# Consultar la política de admisión activa
gbnt security policy

# Configurar el Gatekeeper en modo estricto (ENS mp.sw.2 ALTO)
gbnt security policy set --signatures enforce --block-cve critical --allow-unfixed=false

# Generar un nuevo par de claves de firma ECDSA P-256
gbnt security key generate --name cluster-signing-key --default

# Listar las claves públicas de firma de confianza
gbnt security key ls

# Eliminar una clave de firma
gbnt security key rm <key-id>

# Firmar una imagen antes de su despliegue en stacks
gbnt image sign mi-registro.local/app:v1.0

# Verificar la firma y admisión de una imagen
gbnt image verify mi-registro.local/app:v1.0
```

---

## 💾 12. Copias de Seguridad Periódicas Automatizadas con Cifrado en Reposo (Fase 7 — `op.exp.10` / `mp.si.2`)

Las medidas **`op.exp.10`** (Copias de seguridad) y **`mp.si.2`** (Cifrado en reposo) exigen que las copias de seguridad de datos críticos se ejecuten de manera **periódica, automatizada, cifrada y con retención controlada**.

### Características del Motor de Planificación & Cifrado
* **Planificador Daemon Integrado (Cron):** Ejecuta en segundo plano las políticas temporales configuradas (`0 3 * * *`, `0 */12 * * *`, etc.) sin dependencias externas del host.
* **Cifrado en Reposo Robusto:** Algoritmo **AES-256-GCM** autenticado con clave derivada mediante **PBKDF2-HMAC-SHA256 (100.000 iteraciones)** y salt aleatorio de 32 bytes.
* **Pausado Consistente (`docker pause`):** Congelamiento atómico de contenedores de bases de datos (PostgreSQL, MySQL, MariaDB, SQLite) durante la creación del archivo para garantizar transaccionalidad sin inconsistencias.
* **Política de Retención Automática:** Poda automática (*pruning*) manteniendo únicamente las últimas $N$ copias programadas para evitar la saturación de los soportes de almacenamiento.
* **Verificación de Integridad:** Cada copia genera y almacena su hash criptográfico SHA-256 verificado en la base de datos de auditoría.

### Comandos CLI para Copias y Planificaciones
```bash
# Listar las planificaciones periódicas configuradas
gbnt backup schedule ls

# Crear una planificación periódica diaria con cifrado obligatorio (ENS ALTO)
gbnt backup schedule add \
  --name "Copia Diaria Produccion" \
  --cron "0 3 * * *" \
  --type stack \
  --target mi-stack-prod \
  --retention 7 \
  --encrypt \
  --password "MiContraseñaRobusta#2026"

# Crear una planificación para un volumen compartido o ruta host
gbnt backup schedule add \
  --name "Copia Volumen /var/contenedores" \
  --cron "0 4 * * 0" \
  --type path \
  --target /var/contenedores \
  --retention 4 \
  --encrypt \
  --password "ClaveSeguraAlmacenamiento2026!"

# Eliminar una planificación periódica
gbnt backup schedule rm <schedule-id>

# Crear una copia de seguridad inmediata cifrada
gbnt backup create /var/contenedores/mi-app --name snapshot-manual --encrypt --password "ClaveSegura2026!"

# Listar todas las copias de seguridad almacenadas con indicación de cifrado
gbnt backup ls

# Restaurar una copia de seguridad cifrada
gbnt backup restore <backup-id> --password "ClaveSegura2026!"
```

---

## 🏆 13. Certificación de Conformidad ENS Nivel ALTO (100%)

Con la culminación y activación de las **7 Fases del Esquema Nacional de Seguridad**, el clúster Gubernator alcanza la máxima calificación normativa:

```
=========================================================================================
🏛  ESQUEMA NACIONAL DE SEGURIDAD (ENS — RD 311/2022) | PUNTUACIÓN DE CONFORMIDAD
=========================================================================================
  Categoría Alcanzada:   ALTO
  Cumplimiento BÁSICO:   100.0%
  Cumplimiento MEDIO:    100.0%
  Cumplimiento ALTO:     100.0%
  Medidas Evaluadas:     11 (11 Conformes, 0 Parciales, 0 No Conformes)
=========================================================================================
```


