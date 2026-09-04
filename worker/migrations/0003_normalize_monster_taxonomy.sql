-- Remove monster names, keep aliases English-only, add the Life medal family,
-- and replace opaque species UUIDs with stable categorized identifiers.

PRAGMA foreign_keys = ON;

CREATE TABLE monster_species_id_map_v3 (
    old_id TEXT PRIMARY KEY,
    new_id TEXT NOT NULL UNIQUE
) STRICT;

WITH source AS (
    SELECT
        id AS old_id,
        canonical_tag,
        CASE
            WHEN canonical_tag IN ('chores.take_out_trash', 'chores.household') THEN 'Life'
            ELSE badge_kind
        END AS normalized_badge,
        json_extract(
            '["' || replace(canonical_tag, '.', '","') || '"]',
            '$[#-1]'
        ) AS final_component
    FROM monster_species
), described AS (
    SELECT
        old_id,
        canonical_tag,
        normalized_badge,
        CASE canonical_tag
            WHEN 'coding.leetcode' THEN 'leetcode'
            WHEN 'coding.project' THEN 'project'
            WHEN 'coding.practice' THEN 'practice'
            WHEN 'study.statistics' THEN 'statistics'
            WHEN 'study.learning' THEN 'learning'
            WHEN 'fitness.workout' THEN 'workout'
            WHEN 'communication.send_email' THEN 'email'
            WHEN 'communication.career' THEN 'communication'
            WHEN 'chores.take_out_trash' THEN 'trash'
            WHEN 'chores.household' THEN 'household'
            ELSE replace(
                CASE
                    WHEN final_component LIKE 'take_out_%' THEN substr(final_component, 10)
                    WHEN final_component LIKE 'send_%' THEN substr(final_component, 6)
                    WHEN final_component LIKE 'write_%' THEN substr(final_component, 7)
                    WHEN final_component LIKE 'open_%' THEN substr(final_component, 6)
                    WHEN final_component LIKE 'close_%' THEN substr(final_component, 7)
                    WHEN final_component LIKE 'toggle_%' THEN substr(final_component, 8)
                    WHEN final_component LIKE 'enable_%' THEN substr(final_component, 8)
                    WHEN final_component LIKE 'disable_%' THEN substr(final_component, 9)
                    WHEN final_component LIKE 'start_%' THEN substr(final_component, 7)
                    WHEN final_component LIKE 'stop_%' THEN substr(final_component, 6)
                    WHEN final_component LIKE 'complete_%' THEN substr(final_component, 10)
                    WHEN final_component LIKE 'finish_%' THEN substr(final_component, 8)
                    ELSE final_component
                END,
                '_',
                ''
            )
        END AS description
    FROM source
), candidates AS (
    SELECT
        old_id,
        canonical_tag,
        lower(normalized_badge) AS medal_type,
        description,
        'species-' || lower(normalized_badge) || '-' || description AS base_id,
        row_number() OVER (
            PARTITION BY lower(normalized_badge), description
            ORDER BY canonical_tag
        ) AS collision_order
    FROM described
)
INSERT INTO monster_species_id_map_v3 (old_id, new_id)
SELECT
    old_id,
    CASE
        WHEN collision_order = 1 THEN base_id
        ELSE 'species-' || medal_type || '-' ||
            replace(
                json_extract(
                    '["' || replace(canonical_tag, '.', '","') || '"]',
                    '$[#-2]'
                ),
                '_',
                ''
            ) || description
    END
FROM candidates;

CREATE TABLE monster_species_v3 (
    id TEXT PRIMARY KEY,
    canonical_tag TEXT NOT NULL COLLATE NOCASE UNIQUE,
    badge_kind TEXT NOT NULL
        CHECK (badge_kind IN ('Solver', 'Builder', 'Career', 'Athlete', 'Life')),
    visual_dna_json TEXT NOT NULL
        CHECK (json_valid(visual_dna_json)),
    style_version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    concept_status TEXT NOT NULL DEFAULT 'pending'
        CHECK (concept_status IN ('pending', 'generating', 'ready', 'failed')),
    concept_description TEXT,
    concept_model TEXT,
    concept_prompt_version TEXT,
    concept_generation_attempts INTEGER NOT NULL DEFAULT 0,
    concept_lease_expires_at TEXT,
    concept_failure_code TEXT,
    concept_generated_at TEXT,

    CHECK (length(canonical_tag) BETWEEN 3 AND 80),
    CHECK (length(id) BETWEEN 14 AND 80),
    CHECK (id LIKE 'species-' || lower(badge_kind) || '-%'),
    CHECK (id NOT GLOB '*[^a-z0-9-]*'),
    CHECK (id NOT GLOB 'species-*-*-*')
) STRICT;

INSERT INTO monster_species_v3 (
    id,
    canonical_tag,
    badge_kind,
    visual_dna_json,
    style_version,
    created_at,
    updated_at,
    concept_status,
    concept_description,
    concept_model,
    concept_prompt_version,
    concept_generation_attempts,
    concept_lease_expires_at,
    concept_failure_code,
    concept_generated_at
)
SELECT
    id_map.new_id,
    species.canonical_tag,
    CASE
        WHEN species.canonical_tag IN ('chores.take_out_trash', 'chores.household') THEN 'Life'
        ELSE species.badge_kind
    END,
    species.visual_dna_json,
    species.style_version,
    species.created_at,
    species.updated_at,
    species.concept_status,
    species.concept_description,
    species.concept_model,
    species.concept_prompt_version,
    species.concept_generation_attempts,
    species.concept_lease_expires_at,
    species.concept_failure_code,
    species.concept_generated_at
FROM monster_species species
JOIN monster_species_id_map_v3 id_map ON id_map.old_id = species.id;

CREATE TABLE monster_aliases_v3 (
    alias TEXT COLLATE NOCASE PRIMARY KEY,
    species_id TEXT NOT NULL,
    created_at TEXT NOT NULL,

    FOREIGN KEY (species_id)
        REFERENCES monster_species_v3(id)
        ON DELETE CASCADE,

    CHECK (length(alias) BETWEEN 1 AND 80),
    CHECK (alias = lower(trim(alias))),
    CHECK (alias NOT GLOB '*[^a-z0-9 _-]*'),
    CHECK (alias GLOB '*[a-z0-9]*')
) STRICT;

INSERT INTO monster_aliases_v3 (alias, species_id, created_at)
SELECT lower(trim(aliases.alias)), id_map.new_id, aliases.created_at
FROM monster_aliases aliases
JOIN monster_species_id_map_v3 id_map ON id_map.old_id = aliases.species_id
WHERE aliases.alias = lower(trim(aliases.alias))
  AND aliases.alias NOT GLOB '*[^a-z0-9 _-]*'
  AND aliases.alias GLOB '*[a-z0-9]*';

INSERT OR IGNORE INTO monster_aliases_v3 (alias, species_id, created_at)
SELECT
    CASE species.canonical_tag
        WHEN 'communication.send_email' THEN 'email'
        WHEN 'chores.take_out_trash' THEN 'trash'
        ELSE replace(
            json_extract(
                '["' || replace(species.canonical_tag, '.', '","') || '"]',
                '$[#-1]'
            ),
            '_',
            ' '
        )
    END,
    id_map.new_id,
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
FROM monster_species species
JOIN monster_species_id_map_v3 id_map ON id_map.old_id = species.id;

CREATE TABLE monster_variants_v3 (
    id TEXT PRIMARY KEY,
    species_id TEXT NOT NULL,
    level INTEGER NOT NULL
        CHECK (level BETWEEN 1 AND 9),
    status TEXT NOT NULL
        CHECK (status IN ('pending', 'generating', 'ready', 'failed')),
    image_object_key TEXT,
    image_content_type TEXT,
    image_byte_size INTEGER
        CHECK (image_byte_size IS NULL OR image_byte_size > 0),
    image_content_hash TEXT,
    model TEXT,
    prompt_version TEXT NOT NULL,
    style_version TEXT NOT NULL,
    generation_attempts INTEGER NOT NULL DEFAULT 0,
    queue_enqueued_at TEXT,
    lease_expires_at TEXT,
    failure_code TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,

    FOREIGN KEY (species_id)
        REFERENCES monster_species_v3(id)
        ON DELETE CASCADE,

    UNIQUE (species_id, level, style_version),

    CHECK (
        status <> 'ready'
        OR (
            image_object_key IS NOT NULL
            AND image_content_type IS NOT NULL
            AND image_byte_size IS NOT NULL
            AND image_content_hash IS NOT NULL
        )
    )
) STRICT;

INSERT INTO monster_variants_v3 (
    id,
    species_id,
    level,
    status,
    image_object_key,
    image_content_type,
    image_byte_size,
    image_content_hash,
    model,
    prompt_version,
    style_version,
    generation_attempts,
    queue_enqueued_at,
    lease_expires_at,
    failure_code,
    created_at,
    updated_at
)
SELECT
    variants.id,
    id_map.new_id,
    variants.level,
    variants.status,
    variants.image_object_key,
    variants.image_content_type,
    variants.image_byte_size,
    variants.image_content_hash,
    variants.model,
    variants.prompt_version,
    variants.style_version,
    variants.generation_attempts,
    variants.queue_enqueued_at,
    variants.lease_expires_at,
    variants.failure_code,
    variants.created_at,
    variants.updated_at
FROM monster_variants variants
JOIN monster_species_id_map_v3 id_map ON id_map.old_id = variants.species_id;

DROP TABLE monster_aliases;
DROP TABLE monster_variants;
DROP TABLE monster_species;

ALTER TABLE monster_species_v3 RENAME TO monster_species;
ALTER TABLE monster_aliases_v3 RENAME TO monster_aliases;
ALTER TABLE monster_variants_v3 RENAME TO monster_variants;

CREATE INDEX idx_monster_species_concept_status
    ON monster_species(concept_status, updated_at);
CREATE INDEX idx_monster_aliases_species
    ON monster_aliases(species_id);
CREATE INDEX idx_monster_variants_species_level
    ON monster_variants(species_id, level);
CREATE INDEX idx_monster_variants_status
    ON monster_variants(status, updated_at);
CREATE INDEX idx_monster_variants_stale_lease
    ON monster_variants(status, lease_expires_at);

DROP TABLE monster_species_id_map_v3;
