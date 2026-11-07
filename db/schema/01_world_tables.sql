CREATE TABLE place (
    place_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL,
    x DOUBLE PRECISION NOT NULL,
    y DOUBLE PRECISION NOT NULL
);

CREATE TABLE home (
    home_id SERIAL PRIMARY KEY,
    place_id INT NOT NULL UNIQUE REFERENCES place,
    family_name TEXT NOT NULL
);

CREATE TABLE actor (
    actor_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('villager', 'player')),
    job TEXT,
    home_id INT REFERENCES home
);

CREATE TABLE item (
    item_id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);
