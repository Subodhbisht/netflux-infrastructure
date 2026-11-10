# Netflux Infrastructure

Docker Compose setup that runs the whole **Netflux** stack locally: a PostgreSQL database, three Spring Boot microservices, and an OpenResty (nginx + Lua) API gateway that serves the frontend and checks JWTs.

## Architecture

```
                         ┌──────────────────────────────────────────┐
  Browser ──► :80 ──────►│  api-gateway (OpenResty)                 │
                         │   /                → netflux-frontend    │
                         │   /api/users/login|register (public)     │
                         │   /api/users/**     ─┐                   │
                         │   /api/movies/**     ├ JWT checked (Lua) │
                         │   /api/recommendations/** ┘              │
                         └──────┬───────────────┬───────────────┬───┘
                                │               │               │
                        user-service     movie-service   recommendation-service
                         (:8080)           (:8080)          (:8080)
                                │               │        calls user + movie
                                └───────┬───────┘        services over HTTP
                                        ▼
                                postgres (user_db, movie_db)
```

| Service | Source repo | Purpose |
|---|---|---|
| `postgres` | — (`postgres:latest`) | Creates `user_db` and `movie_db` and loads the movie dataset on first start |
| `user-service` | `user-account-service` | Registration, login (issues RS256 JWTs), watchlist |
| `movie-service` | `movie-service` | Movie details and search by title/genre |
| `recommendation-service` | `recommendation-service` | Home page recommendations, built from the user and movie services |
| `api-gateway` | — (`openresty/openresty:alpine`) | Serves the static frontend, routes `/api/*`, validates JWTs |

### Authentication flow

1. `user-service` signs JWTs with `auth/private.pem` (mounted at `/app/private.pem`).
2. The gateway loads `auth/public.pem` when it starts and checks the RS256 signature of every protected request (`nginx/scripts/jwt.lua`).
3. If the token is valid, the `sub` claim is passed to the backend as the **`X-User-Id`** header. Backend services trust this header and do not parse JWTs themselves.
4. A missing, malformed or invalid token gets **401** from the gateway.

## Repository layout

```
netflux-infrastructure/
├── docker-compose.yaml     # All services
├── run-netflux-mnw.sh      # Build with Maven Wrapper + start (recommended)
├── run-netflux.sh          # Same, using a locally installed `mvn`
├── auth/
│   ├── private.pem         # RSA private key – used by user-service to sign JWTs
│   └── public.pem          # RSA public key  – used by the gateway to verify JWTs
├── nginx/
│   ├── conf/nginx.conf     # Gateway routing
│   └── scripts/jwt.lua     # JWT verification
└── postgres/
    ├── init.sql            # Creates databases, users, tables; imports movies
    └── movie.csv           # Movie dataset (~40 MB)
```

## Prerequisites

- **Docker** with Docker Compose v2 (`docker compose ...`)
- **JDK 25** (the services target Java 25; the Maven Wrapper downloads Maven itself)
- **Git**
- Port **80** free on your machine

## Running locally

### 1. Clone all repositories side by side

Compose and the run scripts use relative paths (`../movie-service` etc.), so every repo **must** sit in the same parent folder, with these exact folder names:

```bash
mkdir netflux && cd netflux

git clone https://github.com/Subodhbisht/movie-service.git          movie-service
git clone https://github.com/Subodhbisht/user-account-service.git   user-account-service
git clone https://github.com/Subodhbisht/Recommendation-service.git recommendation-service
git clone https://github.com/Subodhbisht/netflux-frontend.git       netflux-frontend
git clone https://github.com/Subodhbisht/netflux-frontend.git       netflux-infrastructure
```

> Note: the recommendation repo is named `Recommendation-service` on GitHub. Clone it into lowercase `recommendation-service` as shown above.

Resulting layout:

```
netflux/
├── movie-service/
├── user-account-service/
├── recommendation-service/
├── netflux-frontend/
└── netflux-infrastructure/
```

### 2. Build and start

```bash
cd netflux-infrastructure
chmod +x run-netflux-mnw.sh
./run-netflux-mnw.sh
```

The script:
1. Builds each service JAR with `./mvnw clean package`
2. Builds the Docker images (`docker compose build`)
3. Starts everything in the foreground (`docker compose up`)

The first start takes longer because Postgres imports the movie dataset. Some services may restart a few times while Postgres comes up (`restart: on-failure`). That is expected.

### 3. Open the app

Go to **http://localhost**, register an account, and log in.

### Stopping

```bash
# Ctrl+C in the terminal running compose, then:
docker compose down        # stop and remove containers
docker compose down -v     # also remove volumes (forces a fresh DB import next time)
```

## Useful commands

```bash
docker compose ps                        # container status
docker compose logs -f user-service      # follow one service's logs
docker compose logs -f api-gateway       # gateway / JWT errors

# Rebuild a single service after code changes
(cd ../movie-service && ./mvnw clean package)
docker compose up -d --build movie-service

# Open a psql shell
docker compose exec postgres psql -U postgres -d movie_db
```

Frontend changes need no rebuild. `../netflux-frontend` is mounted straight into the gateway, so a browser refresh picks them up.

## API overview (through the gateway)

| Method | Path | Auth | Backend |
|---|---|---|---|
| POST | `/api/users/register` | public | user-service |
| POST | `/api/users/login` | public | user-service |
| GET | `/api/users/watchlist` | JWT | user-service |
| POST | `/api/users/watchlist` | JWT | user-service |
| DELETE | `/api/users/watchlist/{movieId}` | JWT | user-service |
| GET | `/api/movies/{id}` | JWT | movie-service |
| GET | `/api/movies/search?title=…&limit=…` | JWT | movie-service |
| GET | `/api/movies/search?genre=…&limit=…` | JWT | movie-service |
| GET | `/api/recommendations/home` | JWT | recommendation-service |

## Configuration

Credentials are set in `docker-compose.yaml` and `postgres/init.sql`. They are **for local development only**:

| Database | User | Password |
|---|---|---|
| `postgres` (superuser) | `postgres` | `password` |
| `user_db` | `user_db_user` | `user_db_password` |
| `movie_db` | `movie_db_user` | `movie_db_password` |

### Generating a new RSA key pair

The keys in `auth/` are development keys. To make your own:

```bash
openssl genpkey -algorithm RSA -out auth/private.pem -pkeyopt rsa_keygen_bits:2048
openssl rsa -in auth/private.pem -pubout -out auth/public.pem
```

Restart `user-service` and `api-gateway` afterwards. Tokens issued before the change will stop working.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `failed to read dockerfile: open Dockerfile: no such file or directory` | A sibling repo is missing or in a folder with the wrong name. Check the layout in step 1. |
| `bind: address already in use` on port 80 | Another process is using port 80. Stop it, or change `"80:80"` to e.g. `"8081:80"` and open http://localhost:8081. |
| Movies table is empty / init SQL didn't run | `init.sql` runs only on a **fresh** database. Run `docker compose down -v` and start again. |
| Every API call returns 401 | Token expired or the keys don't match. Log out and log in again, and make sure `private.pem`/`public.pem` are a matching pair. |
| Page loads without styles | Check DevTools → Network for 404s. Missing static files fall back to `index.html` (served as `text/html`). |
