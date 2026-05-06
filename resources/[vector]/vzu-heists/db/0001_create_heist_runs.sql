-- vzu-heists 0001 — heist_runs operational state.
-- Spec: VEC-23 resource-spec §5.2, §5.3.
-- Audit log lives in Loki, not here. This table is operational state only.

CREATE TABLE IF NOT EXISTS heist_runs (
  id                BIGINT UNSIGNED  NOT NULL AUTO_INCREMENT,
  crew_id           BIGINT UNSIGNED  NOT NULL,
  template_key      VARCHAR(64)      NOT NULL,
  template_version  INT UNSIGNED     NOT NULL,
  status            ENUM(
                      'brief','prep','execute','escape','settle',
                      'done','aborted','forfeit','reconcile'
                    )                NOT NULL,
  bucket_id         INT UNSIGNED     NULL,
  payout_cents      BIGINT UNSIGNED  NULL,
  reputation_points INT UNSIGNED     NULL,
  abort_reason      VARCHAR(64)      NULL,
  started_at        DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  ended_at          DATETIME(3)      NULL,
  settled_at        DATETIME(3)      NULL,
  PRIMARY KEY (id),
  KEY ix_heist_runs_crew_status     (crew_id, status),
  KEY ix_heist_runs_template_status (template_key, status),
  KEY ix_heist_runs_started_at      (started_at),
  KEY ix_heist_runs_settled_at      (settled_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
