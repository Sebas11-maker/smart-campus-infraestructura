# Smart Campus - Módulo 4: Infraestructura Cloud como Código (IaC)

Este repositorio contiene la arquitectura de red y el aprovisionamiento de infraestructura en la nube de AWS para el entorno del **Módulo 4 (Smart Campus)** de la Universidad Central del Ecuador. Toda la capa de infraestructura está automatizada utilizando **Terraform** bajo un esquema de múltiples cuentas/entornos virtuales gestionados mediante Git Workspaces y GitHub Actions.

---

## Arquitectura de Red y Cloud Integrada

La topología de red se diseñó bajo un enfoque de **Defensa en Capas (Layered Architecture)**, aislando los recursos críticos de persistencia y cómputo dentro de subredes privadas, utilizando una zona desmilitarizada (DMZ) pública para los balanceadores y puntos de acceso.

### Componentes de Infraestructura Core:
* **VPC Dedicada (`10.0.0.0/16`):** Segmentada para aislar el tráfico del módulo.
* **Subredes Públicas (DMZ):** Alojan el `Bastion Host` para administración y el `Application Load Balancer (ALB)` de cara al tráfico exterior.
* **Subredes Privadas Aisladas:** Alojan las instancias de microservicios (`Academic Risk` y `Notification`) junto con las bases de datos políglotas.
* **Persistencia Políglota Privada:** * **PostgreSQL (AWS RDS):** Base de datos relacional para reportes académicos de alta integridad.
    * **MongoDB Server (EC2 Privado):** Base de datos NoSQL indexada con ObjectId únicos para logs y auditoría de eventos.
    * **Redis Cluster (AWS ElastiCache):** Capa de almacenamiento en caché para optimización de lecturas concurrentes.

---

## Estrategia de Múltiples Entornos (Multi-Environment Setup)

El ciclo de vida de la infraestructura se divide en dos entornos lógicos aislados a través de **Terraform Workspaces**:

### Entorno de QA (`branch: qa`)
* **Despliegue Fijo Aislado:** Instancias EC2 explícitas e independientes (`Academic-Risk-Service-QA-M4` y `Notification-Service-QA-M4`).
* **Estrategia CD:** GitHub Actions despliega de forma segura mediante un salto SSH usando un **Bastion Host** público como puente de datos hacia las subredes privadas (`10.0.3.X`), permitiendo el aprovisionamiento local de Docker offline mediante el transporte de paquetes tarball comprimidos.

### Entorno de Producción (`branch: main`)
* **Alta Disponibilidad y Resiliencia:** Implementación de un **Application Load Balancer (ALB)** público que distribuye la carga elásticamente hacia un **Auto Scaling Group (ASG)** distribuido en múltiples zonas de disponibilidad (`us-east-1a` y `us-east-1b`).
* **Aprovisionamiento Inmutable (Hands-Free):** Las instancias productivas se auto-configuran al nacer mediante scripts nativos de **User Data**, instalando Docker de forma interna y descargando las imágenes estables de DockerHub (`xaandrade/`) con el tag `:prod-latest`.
* **Estrategia CD:** Actualización transparente de aplicaciones mediante **Instance Refresh** del ASG disparado de forma nativa por AWS CLI desde GitHub Actions, logrando despliegues continuos sin tiempos muertos (*Zero Downtime*).

---

## Automatización del Pipeline (Terraform CD)

El pipeline configurado en `.github/workflows/terraform.yml` realiza un despliegue continuo condicional basado en la rama destino de los commits:

* **Al impactar la rama `qa`:** El pipeline valida la sintaxis, carga las credenciales secretas de QA de AWS Academy, inicializa el backend remoto persistente en el S3 de QA, selecciona el Workspace de QA y ejecuta el `terraform apply`.
* **Al impactar la rama `main`:** El pipeline conmuta las variables de entorno, inyecta las llaves de AWS Academy de Producción, gestiona el estado dinámico en el S3 productivo de la cuenta asignada (`s3-smartcampus-uce-m4-prod`) y actualiza el Launch Template junto con el ASG elástico.

---

## Comandos de Gestión Local (Uso de Emergencia)

Para ejecutar pruebas manuales de infraestructura desde la consola local, se debe inicializar utilizando las configuraciones del backend dinámico S3:

```bash
# Inicializar apuntando al bucket correspondiente del entorno
terraform init -backend-config="bucket=s3-smartcampus-uce-m4-[entorno]" \
               -backend-config="key=global/s3/terraform.tfstate" \
               -backend-config="region=us-east-1"

# Seleccionar o crear el espacio de trabajo adecuado
terraform workspace select [qa|prod] || terraform workspace new [qa|prod]

# Validar y planificar cambios
terraform plan -var="environment=[qa|prod]"

# Aplicar cambios en la nube
terraform apply -auto-approve -var="environment=[qa|prod]"