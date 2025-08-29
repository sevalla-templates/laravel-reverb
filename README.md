# Deploying Laravel with Reverb on Sevalla

This repository includes a `Dockerfile` that packages a Laravel application with Reverb and runs it on Sevalla.

## Architecture

On Sevalla, every app has a **default web process** that serves HTTP requests. In this example, the app is built from the repository’s `Dockerfile`, and the web process runs three services:

- **PHP-FPM** — runs your PHP application.
- **NGINX** — listens on `localhost:8080` and forwards `/app` requests to `localhost:8000` (Reverb).
- **Reverb** — runs on `localhost:8000`.

All services are managed by **supervisord**.  
Default start command:

```bash
supervisord -c /etc/supervisord.conf
```

## Steps

### 1) Prepare your repository

1. Install **Reverb** in your Laravel project.
2. Copy this repository’s `Dockerfile` into the **root** of your Laravel project.

### 2) Create Sevalla resources

1. Create a **database**.
2. Create a **new application** and connect your repository (create it now, deploy later).

### 3) Configure the Sevalla app

#### A. Create a process to run DB migrations

1. Go to **App → Processes** and create a **Job** process.
2. Set the start command to:

   ```bash
   php artisan migrate --force
   ```

#### B. Allow internal connections between the app and database

1. Go to **App → Networking** and scroll to **Connected services**.
2. Click **Add connection**, select the database you created, and enable **Add environment variables to the application** in the modal.

#### C. Set environment variables

Set the following in **App → Environment variables**. Fill in any empty values for your setup.

> Notes
> - `DB_URL` is automatically added if you completed step **B**.
> - Set `APP_URL` and `ASSET_URL` to your Sevalla app URL (e.g., `https://your-app.sevalla.app` or your custom domain).
> - Set `VITE_REVERB_HOST` to your Sevalla app URL without protocol (e.g., `your-app.sevalla.app` or your custom domain).
> - `REVERB_APP_ID`, `REVERB_APP_KEY`, and `REVERB_APP_SECRET` can be random values.
> - Ensure `APP_KEY` is set (e.g., via `php artisan key:generate`).
> - In production, keep `APP_DEBUG=false`.

```dotenv
APP_NAME=Laravel
APP_ENV=production
APP_DEBUG=false
APP_KEY=
APP_URL=
ASSET_URL=

DB_CONNECTION=
DB_URL=

BROADCAST_CONNECTION=reverb
REVERB_APP_ID=
REVERB_APP_KEY=
REVERB_APP_SECRET=
REVERB_HOST=localhost
REVERB_PORT=8000 # <-- Must match the Reverb port in Dockerfile
REVERB_SCHEME=http # <-- inside the container it should be http. The client can still use https because Sevalla web process manages TLS.

VITE_APP_NAME=${APP_NAME}
VITE_REVERB_APP_KEY=${REVERB_APP_KEY}
VITE_REVERB_HOST=
VITE_REVERB_SCHEME=https
```

#### D. Use the Dockerfile build

Go to **App → Settings → Build** and change **Build environment** to **Dockerfile**.

#### E. Create worker process (optional)
If you want to run Laravel queues, create a **Worker** process.

1. Go to **App → Processes** and create a **Background worker** process.
2. Set start command to `php artisan queue:work`

### 4) Deploy 🚀

Trigger a new deployment from Sevalla. Once deployed, your Laravel app, NGINX, and Reverb will run inside the web process under supervisord.
