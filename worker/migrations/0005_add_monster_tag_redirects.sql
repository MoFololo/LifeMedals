-- Preserve an open-ended taxonomy while teaching the catalog that alternate
-- AI-generated canonical tags can refer to an already-known monster species.

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS monster_tag_redirects (
    alias_tag TEXT COLLATE NOCASE PRIMARY KEY,
    species_id TEXT NOT NULL,
    created_at TEXT NOT NULL,

    FOREIGN KEY (species_id)
        REFERENCES monster_species(id)
        ON DELETE CASCADE,

    CHECK (length(alias_tag) BETWEEN 3 AND 80),
    CHECK (alias_tag = lower(trim(alias_tag))),
    CHECK (alias_tag NOT GLOB '*[^a-z0-9_.]*'),
    CHECK (alias_tag LIKE '%.%')
) STRICT;

CREATE INDEX IF NOT EXISTS idx_monster_tag_redirects_species
    ON monster_tag_redirects(species_id);
