-- Keep named sports as distinct reusable monster species. The v2 style key
-- leaves previously generated v1 assets immutable while new encounters use
-- the stronger signature-object concept and image prompts.

PRAGMA foreign_keys = ON;

UPDATE monster_species
SET
    style_version = 'grotesque-pixel-v2',
    updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now');

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
('species-athlete-basketball', 'sports.basketball', 'Athlete', '{"subject":"basketball","signature_objects":["basketball","basketball hoop"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-baseball', 'sports.baseball', 'Athlete', '{"subject":"baseball","signature_objects":["baseball","baseball bat"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-tennis', 'sports.tennis', 'Athlete', '{"subject":"tennis","signature_objects":["tennis ball","tennis racket"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-swimming', 'sports.swimming', 'Athlete', '{"subject":"swimming","signature_objects":["water","life ring"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-badminton', 'sports.badminton', 'Athlete', '{"subject":"badminton","signature_objects":["shuttlecock","badminton racket"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-tabletennis', 'sports.table_tennis', 'Athlete', '{"subject":"table tennis","signature_objects":["table-tennis paddle","table-tennis ball"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-volleyball', 'sports.volleyball', 'Athlete', '{"subject":"volleyball","signature_objects":["volleyball","volleyball net"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-football', 'sports.football', 'Athlete', '{"subject":"football","signature_objects":["American football","goalpost"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-soccer', 'sports.soccer', 'Athlete', '{"subject":"soccer","signature_objects":["soccer ball","goal net"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-cycling', 'sports.cycling', 'Athlete', '{"subject":"cycling","signature_objects":["bicycle wheel","cycling helmet"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-running', 'sports.running', 'Athlete', '{"subject":"running","signature_objects":["running shoe","finish-line tape"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-hiking', 'sports.hiking', 'Athlete', '{"subject":"hiking","signature_objects":["hiking boot","walking pole"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-boxing', 'sports.boxing', 'Athlete', '{"subject":"boxing","signature_objects":["boxing glove","boxing ring rope"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-golf', 'sports.golf', 'Athlete', '{"subject":"golf","signature_objects":["golf ball","golf club"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('species-athlete-yoga', 'fitness.yoga', 'Athlete', '{"subject":"yoga","signature_objects":["yoga mat"]}', 'grotesque-pixel-v2', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));

INSERT OR IGNORE INTO monster_aliases (alias, species_id, created_at)
VALUES
('basketball', 'species-athlete-basketball', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('baseball', 'species-athlete-baseball', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('tennis', 'species-athlete-tennis', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('swimming', 'species-athlete-swimming', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('badminton', 'species-athlete-badminton', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('table tennis', 'species-athlete-tabletennis', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('volleyball', 'species-athlete-volleyball', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('football', 'species-athlete-football', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('soccer', 'species-athlete-soccer', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('cycling', 'species-athlete-cycling', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('running', 'species-athlete-running', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('hiking', 'species-athlete-hiking', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('boxing', 'species-athlete-boxing', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('golf', 'species-athlete-golf', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
('yoga', 'species-athlete-yoga', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
