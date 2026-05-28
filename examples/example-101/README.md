# 🏛 Ejemplo 101 — Despliegue de WordPress en Gubernator

Este ejemplo demuestra cómo desplegar un stack multi-servicio de producción (**WordPress + MySQL**) en un clúster de Gubernator, utilizando almacenamiento persistente (volúmenes de Docker), descubrimiento de servicios interno (CoreDNS) y enrutamiento externo (Caddy Ingress).

## 📋 Estructura del Stack

El archivo `docker-compose.yml` define dos servicios:
1. **`db`**: Contenedor MySQL (puerto `3306`), que almacena los datos en el volumen persistente `db_data`.
2. **`wordpress`**: Contenedor de WordPress expuesto en el puerto `8080` del host, conectado a la base de datos a través de DNS y expuesto mediante Caddy Ingress en la dirección `hello-101.gbnt.local`.

---

## 📡 Descubrimiento de Servicios y DNS

Dado que Gubernator gestiona múltiples stacks en una misma red compartida (`gbnt-net`), los servicios se aíslan y exponen en DNS usando el formato `<nombre-servicio>.<nombre-stack>.gbnt`.

Por esta razón, la variable de entorno para conectar WordPress con MySQL está configurada como:
```yaml
WORDPRESS_DB_HOST: db.wp.gbnt:3306
```
> [!IMPORTANT]
> El stack **debe** desplegarse con el nombre **`wp`** para que el nombre de DNS `db.wp.gbnt` se resuelva correctamente. Si deseas nombrarlo de otra forma, debes ajustar esta variable en el archivo `docker-compose.yml`.

---

## 🚀 Instrucciones de Despliegue

### 1. Desplegar el Stack
Ejecuta el siguiente comando en la terminal utilizando el CLI de Gubernator (o súbelo mediante el Dashboard Web en el puerto `4001`):

```bash
gbnt stack deploy -c examples/example-101/docker-compose.yml wp
```

### 2. Verificar el Despliegue
Puedes seguir el estado de los contenedores mediante el Dashboard o usando la CLI:

```bash
# Listar todos los stacks
gbnt stack ls

# Listar las tareas de contenedores activas
gbnt node ls
```

### 3. Acceso a la aplicación
* **Directo por puerto:** Puedes ingresar a WordPress desde `http://localhost:8080`.
* **A través de Ingress (Caddy):** Caddy redirige de manera transparente las peticiones desde el dominio local `http://hello-101.gbnt.local` hacia el puerto `80` del contenedor WordPress.

> [!NOTE]
> Para que el dominio `hello-101.gbnt.local` funcione en el navegador de tu máquina host, debes asegurarte de que tu sistema use el servidor DNS de Gubernator (`gbnt-coredns` en el puerto `5354`) o añadir la entrada manual a tu archivo `/etc/hosts`:
> ```text
> 127.0.0.1 hello-101.gbnt.local
> ```

> [!TIP]
> **Confiar en HTTPS Local de Caddy:**
> Si usas HTTPS local y deseas que tu host confíe en el certificado temporal generado por Caddy, descarga y confía en el certificado raíz ejecutando en tu terminal:
> ```bash
> # 1. Copiar el certificado desde el contenedor
> docker cp gbnt-caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
> 
> # 2. Instalar y confiar en macOS (Llavero / Keychain)
> sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./caddy-root.crt
> ```
