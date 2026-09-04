-- Migration number: 0001 	 2026-08-26T03:54:29.688Z

PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS monster_species (
    id TEXT PRIMARY KEY,
    canonical_tag TEXT NOT NULL COLLATE NOCASE UNIQUE,
    badge_kind TEXT NOT NULL
        CHECK (badge_kind IN ('Solver', 'Builder', 'Career', 'Athlete', 'Life')),
    visual_dna_json TEXT NOT NULL
        CHECK (json_valid(visual_dna_json)),
    style_version TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,

    CHECK (length(canonical_tag) BETWEEN 3 AND 80),
    CHECK (length(id) BETWEEN 14 AND 80),
    CHECK (id LIKE 'species-' || lower(badge_kind) || '-%'),
    CHECK (id NOT GLOB '*[^a-z0-9-]*'),
    CHECK (id NOT GLOB 'species-*-*-*')
) STRICT;

CREATE TABLE IF NOT EXISTS monster_aliases (
    alias TEXT COLLATE NOCASE PRIMARY KEY,
    species_id TEXT NOT NULL,
    created_at TEXT NOT NULL,

    FOREIGN KEY (species_id)
        REFERENCES monster_species(id)
        ON DELETE CASCADE,

    CHECK (length(alias) BETWEEN 1 AND 80),
    CHECK (alias = lower(trim(alias))),
    CHECK (alias NOT GLOB '*[^a-z0-9 _-]*'),
    CHECK (alias GLOB '*[a-z0-9]*')
) STRICT;

CREATE INDEX IF NOT EXISTS idx_monster_aliases_species
    ON monster_aliases(species_id);

CREATE TABLE IF NOT EXISTS monster_variants (
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
        REFERENCES monster_species(id)
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

CREATE INDEX IF NOT EXISTS idx_monster_variants_species_level
    ON monster_variants(species_id, level);

CREATE INDEX IF NOT EXISTS idx_monster_variants_status
    ON monster_variants(status, updated_at);

CREATE INDEX IF NOT EXISTS idx_monster_variants_stale_lease
    ON monster_variants(status, lease_expires_at);

INSERT OR IGNORE INTO monster_species (
    id,
    canonical_tag,
    badge_kind,
    visual_dna_json,
    style_version,
    created_at,
    updated_at
)
VALUES
(
    'species-solver-leetcode',
    'coding.leetcode',
    'Solver',
    '{"body":"small compact imp","colors":["indigo","cyan"],"feature":"glowing algorithm rune","temperament":"clever"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-builder-project',
    'coding.project',
    'Builder',
    '{"body":"compact forge sprite","colors":["orange","steel"],"feature":"tiny crafting hammer","temperament":"inventive"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-solver-practice',
    'coding.practice',
    'Solver',
    '{"body":"round puzzle imp","colors":["violet","gold"],"feature":"floating puzzle tiles","temperament":"curious"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-solver-statistics',
    'study.statistics',
    'Solver',
    '{"body":"soft floating wisp","colors":["blue","mint"],"feature":"chart-shaped aura","temperament":"analytical"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-solver-learning',
    'study.learning',
    'Solver',
    '{"body":"book-shaped wisp","colors":["teal","cream"],"feature":"floating pages","temperament":"focused"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-athlete-workout',
    'fitness.workout',
    'Athlete',
    '{"body":"friendly compact brute","colors":["red","charcoal"],"feature":"training wristbands","temperament":"energetic"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-career-email',
    'communication.send_email',
    'Career',
    '{"body":"small winged courier","colors":["navy","yellow"],"feature":"sealed envelope satchel","temperament":"swift"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-career-communication',
    'communication.career',
    'Career',
    '{"body":"professional courier wisp","colors":["blue","silver"],"feature":"briefcase-shaped charm","temperament":"reliable"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-life-trash',
    'chores.take_out_trash',
    'Life',
    '{"body":"clean rounded slime","colors":["green","gray"],"feature":"tiny recycling emblem","temperament":"helpful"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
),
(
    'species-life-household',
    'chores.household',
    'Life',
    '{"body":"tidy household slime","colors":["aqua","white"],"feature":"small cleaning brush","temperament":"cheerful"}',
    'pixel-v1',
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
);

INSERT OR IGNORE INTO monster_aliases (alias, species_id, created_at)
VALUES
('leetcode', 'species-solver-leetcode', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('algorithm', 'species-solver-leetcode', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('coding project', 'species-builder-project', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('project', 'species-builder-project', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('coding practice', 'species-solver-practice', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('practice', 'species-solver-practice', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('statistics', 'species-solver-statistics', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('study', 'species-solver-learning', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('learning', 'species-solver-learning', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('workout', 'species-athlete-workout', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('gym', 'species-athlete-workout', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('send email', 'species-career-email', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('email', 'species-career-email', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('career communication', 'species-career-communication', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('communication', 'species-career-communication', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('take out trash', 'species-life-trash', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('trash', 'species-life-trash', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('household chores', 'species-life-household', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('household', 'species-life-household', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
