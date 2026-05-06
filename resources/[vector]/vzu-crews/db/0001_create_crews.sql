-- vzu-crews 0001 — crews row.
-- Spec: VEC-22 resource-spec §3.1 (with §10 Q1 anti-grief cooldown column).
-- Forward-only: do not edit after merge.

CREATE TABLE IF NOT EXISTS crews (
  id              BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  name            VARCHAR(40)       NOT NULL,
  leader_citizenid VARCHAR(64)      NOT NULL,
  bank_cents      BIGINT            NOT NULL DEFAULT 0,
  reputation      INT               NOT NULL DEFAULT 0,
  split_policy    ENUM('equal','leader_weighted','custom') NOT NULL DEFAULT 'equal',
  split_config    JSON              NULL,
  radio_channel   INT UNSIGNED      NULL,
  status          ENUM('active','disbanded') NOT NULL DEFAULT 'active',
  created_at      DATETIME          NOT NULL DEFAULT CURRENT_TIMESTAMP,
  disbanded_at    DATETIME          NULL,
  bank_disband_locked_until DATETIME NULL,    -- §10 Q1: anti-grief cooldown after threshold withdraw
  PRIMARY KEY (id),
  UNIQUE KEY uniq_crews_name_active (name, status),
  KEY idx_crews_leader (leader_citizenid),
  KEY idx_crews_radio  (radio_channel),
  KEY idx_crews_rep    (reputation),         -- leaderboard top-N (ORDER BY reputation DESC LIMIT N uses this)
  CONSTRAINT chk_crews_bank_nonneg CHECK (bank_cents >= 0),
  CONSTRAINT chk_crews_rep_nonneg  CHECK (reputation >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
