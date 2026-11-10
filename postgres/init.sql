-- Create user db

CREATE DATABASE user_db;
CREATE USER user_db_user WITH PASSWORD 'user_db_password';

\connect user_db;

CREATE TABLE users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    name     VARCHAR(255) NOT NULL
);

CREATE TABLE watchlist (
    id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id  BIGINT NOT NULL REFERENCES users(id),
    movie_id BIGINT NOT NULL,
    UNIQUE (user_id, movie_id)
);

GRANT ALL PRIVILEGES ON ALL TABLES in SCHEMA public TO user_db_user;

-- Create movie db

 CREATE DATABASE movie_db;
 CREATE USER movie_db_user WITH PASSWORD 'movie_db_password';

\connect movie_db;

CREATE TABLE movie (
    id            BIGINT          PRIMARY KEY,
    title         VARCHAR(500)    NOT NULL,
    vote_average  DOUBLE PRECISION,
    vote_count    INTEGER,
    release_date  DATE,
    revenue       BIGINT,
    runtime       INTEGER,
    backdrop_path VARCHAR(500),
    budget        BIGINT,
    homepage      TEXT,
    overview      TEXT,
    popularity    DOUBLE PRECISION,
    poster_path   VARCHAR(500),
    genres        TEXT[],
    themes        TEXT[]
);

COPY movie
FROM '/docker-entrypoint-initdb.d/movie.csv'
WITH (FORMAT CSV, HEADER, DELIMITER ',');

GRANT ALL PRIVILEGES ON ALL TABLES in SCHEMA public TO movie_db_user;