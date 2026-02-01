# Control de Versiones y CI/CD - Parte II

## Descripción general

Esta práctica implementa un flujo completo de **CI/CD (Integración y Despliegue Continuo)** para una aplicación **Python Flask**, contenedorizada con **Docker**, orquestada con **Docker Compose** y desplegada automáticamente en **AWS EC2** usando **GitHub Actions**.[web:10]

El objetivo es que cada cambio en el código provoque la siguiente acciones:
1. La construcción de una nueva imagen Docker.
2. La subida de esa imagen a **DockerHub**.
3. El despliegue de la nueva versión en una instancia **EC2** de AWS.

# 1. Prueba de la aplicación Flask en local

Antes de comenzar, se recomienda reiniciar los servicios de Docker y red en la máquina virtual:

```bash
sudo systemctl restart docker.service
sudo systemctl restart networking.service
```

## 1.1. Crear y activar entorno virtual 

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## 1.2. Ejecutar la aplicación Flask

```bash
python src/app.py
```

## 1.3. Verificar funcionamiento

```bash
curl http://localhost:5000
# o desde el navegador:
# http://localhost:5000
```

# 2. Ejecución en modo producción (Gunicorn)

En un entorno de producción donde se recomienda servir la aplicación Flask con Gunicorn como servidor WSGI.

```bash
gunicorn --chdir src app:app --bind 0.0.0.0:5000

    --chdir src: cambia al directorio src.

    app:app: módulo app.py y objeto app.

    --bind 0.0.0.0:5000: expone la app en el puerto 5000.
```
# 3. Creación de la imagen Docker
## 3.1. Dockerfile

Creamos un archivo llamado Dockerfile en la raíz del proyecto con el siguiente contenido:
```
text
FROM python:3-slim

WORKDIR /app

COPY ./requirements.txt ./
RUN pip install -r requirements.txt

COPY src .

CMD gunicorn --bind 0.0.0.0:5000 app:app
```
Esta imagen:
    Instala dependencias desde requirements.txt.
    Copia el código del directorio src.
    Lanza la aplicación con Gunicorn en el puerto 5000.

## 3.2. Construir la imagen

Desde el directorio donde está el Dockerfile:

```bash
docker build -t <usuario_dockerhub>/galeria:latest .
```

# 4. Prueba de la imagen con Docker directamente

Ejecutamos el contenedor con la imagen recién creada:

```bash
docker run -d -p 80:5000 --name testgaleria <usuario_dockerhub>/galeria
curl http://localhost/status
# o navegador http://localhost
docker stop testgaleria && docker rm testgaleria
```

# 5. Prueba con Docker Compose
## 5.1. Archivo docker-compose.yml

Creamos un archivo docker-compose.yml en la raíz del proyecto:

```
text
services:
  galeria:
    container_name: galeria
    image: <usuario_dockerhub>/galeria:latest
    ports:
      - 80:5000
    restart: always
```

## 5.2. Levantar y detener el servicio

```bash
docker compose up -d
curl http://localhost
# o navegador → http://localhost
docker compose down
```

Este archivo permite levantar la aplicación con un solo comando y reiniciarla automáticamente si el contenedor se detiene.
## 6. Subida de la imagen a DockerHub

Una vez verificada la imagen localmente, súbela a DockerHub:

```bash
docker push <usuario_dockerhub>/galeria:latest
```

De esta forma la imagen estará disponible en un registro remoto para ser utilizada por otros entornos y por el pipeline de CI/CD.

# 7. Configuración de secretos en GitHub

Para no exponer credenciales en el repositorio se utilizan GitHub Secrets, que almacenan de forma segura datos sensibles.

Ruta en GitHub:
    Settings / Security / Secrets and variables / Actions

## 7.1. Secretos para DockerHub

Crea estos secretos:
    DOCKERHUB_USERNAME: tu usuario de DockerHub.
    DOCKERHUB_TOKEN: token de acceso generado en DockerHub (Account Settings / Security).

## 7.2. Secretos para AWS EC2

Crea además:
    AWS_USERNAME: usuario administrador de la instancia EC2(admin).
    AWS_HOSTNAME: IP pública o hostname de la instancia.
    AWS_PRIVATEKEY: contenido del fichero de clave privada SSH (por ejemplo, vockey.pem).

En los workflows, estos secretos se referencian con ${{ secrets.NOMBRE_DEL_SECRETO }}.

# 8. Workflow de GitHub Actions (Build & Push a DockerHub)

Crea el directorio .github/workflows y dentro un archivo docker.yml con este contenido:
```
text
name: Docker CI/CD

on:
  push:
    branches: [ main ]
    paths:
      - src/**
  pull_request:
    branches: [ main ]
    paths:
      - src/**

jobs:
  build:
    name: Build and Push Docker Image
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Login to DockerHub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}

      - name: Build and Push Docker Image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ secrets.DOCKERHUB_USERNAME }}/galeria:latest
```

Este job:
    Hacemos checkout del código.
    Iniciamos sesión en DockerHub.
    Construimos la imagen usando el Dockerfile.
    Publicamos la imagen en DockerHub con la etiqueta latest.

## 8.1. Prueba del workflow

    Creamos una rama nueva en local
    Modificamos un archivo dentro de src (por ejemplo, index.html).
    Hacemos commit y push de esa rama.
    Abrimos un Pull Request hacia main (si se usa PR).
    Revisamos la pestaña Actions y confirma que el job build termina correctamente y que hay una nueva imagen en DockerHub.

# 9. Despliegue en AWS EC2 con GitHub Actions

Para automatizar el despliegue en AWS EC2, se añade un segundo job que solo se ejecuta si el job build ha sido exitoso (needs: build).

Este job:
    Copia el archivo docker-compose.yml a la instancia EC2.
    Ejecuta los comandos docker compose para actualizar el despliegue.

## 9.1. Extensión del workflow con el job aws

En el mismo archivo .github/workflows/docker.yml, añade:
```
text
jobs:
  build:
    # ... (job anterior)

  aws:
    name: Deploy image to AWS
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Copy docker-compose.yml to EC2
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ secrets.AWS_HOSTNAME }}
          username: ${{ secrets.AWS_USERNAME }}
          key: ${{ secrets.AWS_PRIVATEKEY }}
          source: "docker-compose.yml"
          target: /home/admin

      - name: Deploy Docker Services on EC2
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.AWS_HOSTNAME }}
          username: ${{ secrets.AWS_USERNAME }}
          key: ${{ secrets.AWS_PRIVATEKEY }}
          script: |
            sleep 60
            docker compose down --rmi all
            docker compose up -d
```

    appleboy/scp-action: transfiere el archivo docker-compose.yml a la instancia EC2 mediante SCP.
    appleboy/ssh-action: ejecuta comandos remotos vía SSH para parar y volver a levantar los servicios con la nueva imagen.
    sleep 60: espera para asegurar que la nueva imagen está disponible en DockerHub antes de hacer el docker compose up.

## 9.2. Prueba del despliegue en AWS

    Modificamos de nuevo el código dentro de src.
    Hacemos commit y push a la rama main.
    Verificamos en Actions que se ejecutan correctamente los jobs build y aws.
    Accedemos a la IP pública o hostname de tu instancia EC2 en el navegador y comprueba que los cambios están desplegados.


<img width="1033" height="430" alt="Screenshot from 2026-02-01 15-42-29" src="https://github.com/user-attachments/assets/3b13d5c8-c559-42e1-b797-03297f64fa90" />


    
