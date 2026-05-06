-- vector-crews 0003 — crew_cosmetic_unlocks.
-- Spec: VEC-22 resource-spec §3.3.
-- Table ships in Phase 1 to keep migration ordering stable; unlock logic ships in Phase 2.
-- Forward-only: do not edit after merge.

CREATE TABLE IF NOT EXISTS crew_cosmetic_unlocks (
  crew_id              BIGINT UNSIGNED NOT NULL,
  sku                  VARCHAR(80)     NOT NULL,
  unlocked_at          DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  unlocked_by_citizenid VARCHAR(64)    NULL,
  source_tag           VARCHAR(40)     NULL,  -- 'rep_milestone' | 'tebex_vip' | 'event'
  PRIMARY KEY (crew_id, sku),
  KEY idx_unlocks_sku (sku),
  CONSTRAINT fk_unlocks_crew FOREIGN KEY (crew_id) REFERENCES crews(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
