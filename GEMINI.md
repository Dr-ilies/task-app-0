# Project Overview

This is a multi-service task management application. It consists of a frontend, an authentication API, and a tasks API. The application is designed to be run with Docker or Podman.

## Architecture

The application is composed of four main services:

*   **Frontend:** A static web application built with HTML, CSS, and vanilla JavaScript. It is served by an Nginx web server.
*   **Authentication API:** A FastAPI application that handles user registration and login. It uses a SQLite database to store user credentials and JWT for authentication.
*   **Tasks API:** A FastAPI application that provides CRUD functionality for tasks. It connects to a PostgreSQL database and uses JWT for authentication and authorization.
*   **Database:** A PostgreSQL database used by the Tasks API to store task data.

## Building and Running

### Docker

To build and run the application with Docker, use the following command:

```bash
docker-compose up --build
```

The application will be available at `http://localhost:8080`.

### Podman

To build and run the application with Podman, first build the container images:

```bash
podman build -t auth-api:latest -f auth-api/Dockerfile ./auth-api
podman build -t tasks-api:latest -f tasks-api/Dockerfile ./tasks-api
podman build -t frontend:latest -f frontend/Dockerfile ./frontend
```

Then, deploy the application with:

```bash
podman kube play podman-deployment.yml
```

The application will be available at `http://localhost:8080`.

## Development Conventions

*   The backend services are written in Python using the FastAPI framework.
*   The frontend is a simple HTML, CSS, and JavaScript application.
*   The application is containerized using Docker.
*   The `docker-compose.yml` file defines the services and their dependencies for local development.
*   The `podman-deployment.yml` file defines the Kubernetes-like resources for deploying the application with Podman.
*   The backend services use JWT for authentication.
*   The Tasks API uses a PostgreSQL database, while the Authentication API uses a SQLite database.
*   The frontend uses Nginx as a reverse proxy to communicate with the backend services.
