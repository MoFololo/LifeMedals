-- Migration number: 0002 	 2026-08-26T05:04:16.451Z

ALTER TABLE monster_species ADD COLUMN concept_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (concept_status IN ('pending', 'generating', 'ready', 'failed'));
ALTER TABLE monster_species ADD COLUMN concept_description TEXT;
ALTER TABLE monster_species ADD COLUMN concept_model TEXT;
ALTER TABLE monster_species ADD COLUMN concept_prompt_version TEXT;
ALTER TABLE monster_species ADD COLUMN concept_generation_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE monster_species ADD COLUMN concept_lease_expires_at TEXT;
ALTER TABLE monster_species ADD COLUMN concept_failure_code TEXT;
ALTER TABLE monster_species ADD COLUMN concept_generated_at TEXT;

CREATE INDEX IF NOT EXISTS idx_monster_species_concept_status
    ON monster_species(concept_status, updated_at);

-- A new style version makes existing pixel-v1 assets immutable history while
-- forcing every species to receive an AI-authored concept before new artwork.
UPDATE monster_species
SET
    concept_status = 'pending',
    style_version = 'grotesque-doodle-v1',
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now');
