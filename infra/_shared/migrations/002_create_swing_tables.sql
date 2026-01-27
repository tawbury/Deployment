-- Phase 13: Swing (Track A) 테이블 생성 및 스키마 수정
-- 생성 날짜: 2026-01-22
-- 설명: REST API 10분 봉 데이터 저장 (bid/ask 필드 추가)

-- =====================================================
-- 1. swing_bars_10m 테이블 (10분 봉 데이터)
-- =====================================================
CREATE TABLE IF NOT EXISTS swing_bars_10m (
    symbol          VARCHAR(20) NOT NULL,
    bar_time        TIMESTAMPTZ NOT NULL,
    open            NUMERIC(15,4),
    high            NUMERIC(15,4),
    low             NUMERIC(15,4),
    close           NUMERIC(15,4),
    volume          BIGINT,
    bid_price       NUMERIC(15,4),
    ask_price       NUMERIC(15,4),
    session_id      VARCHAR(50) NOT NULL,
    schema_version  VARCHAR(10) DEFAULT '1.0',
    mitigation_level INT DEFAULT 0,
    quality_flag    VARCHAR(20) DEFAULT 'normal',
    PRIMARY KEY (symbol, bar_time)
);

CREATE INDEX IF NOT EXISTS idx_swing_10m_symbol ON swing_bars_10m(symbol);
CREATE INDEX IF NOT EXISTS idx_swing_10m_time ON swing_bars_10m(bar_time DESC);
CREATE INDEX IF NOT EXISTS idx_swing_10m_session ON swing_bars_10m(session_id);
CREATE INDEX IF NOT EXISTS idx_swing_10m_bid_ask ON swing_bars_10m(symbol, bar_time, bid_price, ask_price);

-- =====================================================
-- 메타데이터 업데이트
-- =====================================================
INSERT INTO migration_log (migration_name, status)
VALUES ('002_create_swing_tables', 'success');
