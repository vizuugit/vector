-- vzu-crews 0002 — crew_members rows.
-- Spec: VEC-22 resource-spec §3.2.
-- Active membership filter is `left_at IS NULL`; idx_crew_members_active makes it O(1).
-- Forward-only: do not edit after merge.

CREATE TABLE IF NOT EXISTS crew_members (
  crew_id      BIGINT UNSIGNED NOT NULL,
  citizenid    VARCHAR(64)     NOT NULL,
  role         ENUM('leader','member') NOT NULL DEFAULT 'member',
  split_weight SMALLINT UNSIGNED NOT NULL DEFAULT 100,
  joined_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
  left_at      DATETIME        NULL,
  PRIMARY KEY (crew_id, citizenid),
  KEY idx_crew_members_active (citizenid, left_at),
  CONSTRAINT fk_crew_members_crew FOREIGN KEY (crew_id) REFERENCES crews(id) ON DELETE CASCADE,
  CONSTRAINT chk_crew_members_weight CHECK (split_weight <= 1000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
