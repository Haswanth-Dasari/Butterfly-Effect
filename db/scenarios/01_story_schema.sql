-- Story scenarios (Mystery, Drama, Survival...) are DATA: a scenario is rows in these tables plus
-- rows in `rule`. Nothing here is specific to one story. Playing a story = a playthrough, and a
-- playthrough is a branch of the village (so every player gets their own world, and rewind still works).

CREATE TABLE scenario (
    scenario_key   TEXT PRIMARY KEY,
    title          TEXT NOT NULL,
    tagline        TEXT NOT NULL DEFAULT '',
    genre          TEXT NOT NULL DEFAULT '',
    protagonist_id INT  NOT NULL REFERENCES actor,
    slice_end_day  INT  NOT NULL CHECK (slice_end_day >= 1),
    cold_open      TEXT NOT NULL DEFAULT '',   -- flash-forward shown before day 1 (lines separated by newlines)
    goal           TEXT NOT NULL DEFAULT '',   -- the one-line objective, always on screen
    deadline_day   INT  NOT NULL DEFAULT 12 CHECK (deadline_day >= 1)
);

-- The seven questions of a case ("the Chain of Seven").
CREATE TABLE case_link (
    link_key     TEXT PRIMARY KEY,
    scenario_key TEXT NOT NULL REFERENCES scenario,
    title        TEXT NOT NULL,
    question     TEXT NOT NULL,
    ord          INT  NOT NULL
);

CREATE TABLE clue (
    clue_key     TEXT PRIMARY KEY,
    scenario_key TEXT NOT NULL REFERENCES scenario,
    title        TEXT NOT NULL,
    kind         TEXT NOT NULL CHECK (kind IN ('observation', 'testimony', 'physical', 'document', 'rumour')),
    day          INT  NOT NULL CHECK (day >= 1),
    journal      TEXT NOT NULL
);

-- A clue can bear on several links, with a weight. Link strength = LEAST(3, SUM(weight)); 3 = "Proven".
CREATE TABLE clue_link (
    clue_key TEXT NOT NULL REFERENCES clue,
    link_key TEXT NOT NULL REFERENCES case_link,
    weight   INT  NOT NULL CHECK (weight BETWEEN 1 AND 3),
    PRIMARY KEY (clue_key, link_key)
);

CREATE TABLE story_day (
    scenario_key TEXT NOT NULL REFERENCES scenario,
    day          INT  NOT NULL CHECK (day >= 1),
    title        TEXT NOT NULL,
    intro        TEXT NOT NULL,
    outro        TEXT NOT NULL DEFAULT '',   -- the hook that ends the day (shown by the Evening Bell)
    PRIMARY KEY (scenario_key, day)
);

-- A beat is a scene with choices. day = the tick on which it is available.
-- requires_beats / forbids_beats entries are 'beat' (any choice made) or 'beat:option' (that choice made).
CREATE TABLE story_beat (
    beat_key       TEXT PRIMARY KEY,
    scenario_key   TEXT NOT NULL REFERENCES scenario,
    day            INT  NOT NULL CHECK (day >= 1),
    phase          TEXT NOT NULL CHECK (phase IN ('morning', 'day', 'night')),
    ord            INT  NOT NULL DEFAULT 0,
    title          TEXT NOT NULL,
    body           TEXT NOT NULL,
    costs_action   BOOLEAN NOT NULL DEFAULT TRUE,
    max_picks      INT  NOT NULL DEFAULT 1 CHECK (max_picks >= 1),
    requires_beats TEXT[] NOT NULL DEFAULT '{}',
    forbids_beats  TEXT[] NOT NULL DEFAULT '{}',
    focus          TEXT                         -- where the map looks while this scene is on screen
);

CREATE TABLE story_option (
    beat_key    TEXT NOT NULL REFERENCES story_beat,
    option_key  TEXT NOT NULL,
    label       TEXT NOT NULL,
    result_text TEXT NOT NULL,
    ord         INT  NOT NULL DEFAULT 0,
    react_actor INT,                          -- who reacts on the map...
    react_line  TEXT,                         -- ...and what they say
    PRIMARY KEY (beat_key, option_key)
);

-- An ending is reached when the protagonist's state flag is >= 1.
CREATE TABLE story_ending (
    scenario_key TEXT NOT NULL REFERENCES scenario,
    ending_key   TEXT NOT NULL,
    title        TEXT NOT NULL,
    text         TEXT NOT NULL,
    flag         TEXT NOT NULL,
    PRIMARY KEY (scenario_key, ending_key)
);

-- The villain's nightly agenda is data. Each witness has a base threat to him, plus extra threat for things
-- the PLAYER has done (state flags). Each night in story_night he acts on the most threatening witness who
-- is not protected (see wick_pick_target).
CREATE TABLE story_witness (
    scenario_key TEXT NOT NULL REFERENCES scenario,
    actor_id     INT  NOT NULL REFERENCES actor,
    label        TEXT NOT NULL,
    base_threat  INT  NOT NULL CHECK (base_threat >= 0),
    PRIMARY KEY (scenario_key, actor_id)
);
CREATE TABLE story_witness_factor (
    scenario_key TEXT NOT NULL,
    actor_id     INT  NOT NULL,
    flag         TEXT NOT NULL,                       -- a key in the player's state; counts when >= 1
    weight       INT  NOT NULL CHECK (weight > 0),
    PRIMARY KEY (scenario_key, actor_id, flag),
    FOREIGN KEY (scenario_key, actor_id) REFERENCES story_witness
);
CREATE TABLE story_night (
    scenario_key TEXT NOT NULL REFERENCES scenario,
    after_day    INT  NOT NULL CHECK (after_day >= 1),   -- he acts in the night that follows this day
    PRIMARY KEY (scenario_key, after_day)
);

-- One row per story being played. The branch IS the playthrough's private village.
CREATE TABLE playthrough (
    branch_id    INT PRIMARY KEY REFERENCES branch,
    scenario_key TEXT NOT NULL REFERENCES scenario,
    actor_id     INT NOT NULL REFERENCES actor,
    trait        TEXT NOT NULL CHECK (trait IN ('kind', 'sharp', 'quiet')),
    guided       BOOLEAN NOT NULL DEFAULT FALSE,
    pronouns     TEXT NOT NULL DEFAULT 'they' CHECK (pronouns IN ('she', 'he', 'they')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

