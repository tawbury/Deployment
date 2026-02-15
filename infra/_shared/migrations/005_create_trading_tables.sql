-- =====================================================
-- Trading Tables (QTS ETEDA 피드백 루프 지원)
-- 생성일: 2026-02-15
-- =====================================================

-- 1. feedback_data: 실행 피드백 (슬리피지, 품질, 시장 충격)
CREATE TABLE IF NOT EXISTS feedback_data (
    time                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    symbol              VARCHAR(20) NOT NULL,
    strategy_tag        VARCHAR(50),
    order_id            VARCHAR(100),
    slippage_bps        NUMERIC(10,4),
    quality_score       NUMERIC(5,4),
    impact_bps          NUMERIC(10,4),
    fill_latency_ms     NUMERIC(10,2),
    fill_ratio          NUMERIC(5,4),
    filled_qty          NUMERIC(20,4),
    fill_price          NUMERIC(15,4),
    original_qty        NUMERIC(20,4),
    volatility          NUMERIC(10,6),
    spread_bps          NUMERIC(10,4),
    depth               INT,
    order_type          VARCHAR(20)
);

CREATE INDEX IF NOT EXISTS idx_feedback_symbol_time
    ON feedback_data(symbol, time DESC);
CREATE INDEX IF NOT EXISTS idx_feedback_strategy
    ON feedback_data(symbol, strategy_tag, time DESC);

-- 2. decision_log: 의사결정 감사 추적
CREATE TABLE IF NOT EXISTS decision_log (
    time                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cycle_id            VARCHAR(100) NOT NULL,
    symbol              VARCHAR(20) NOT NULL,
    action              VARCHAR(10) NOT NULL,
    strategy_tag        VARCHAR(50),
    price               NUMERIC(15,4),
    qty                 INT,
    signal_confidence   NUMERIC(5,4),
    risk_score          NUMERIC(5,4),
    operating_state     VARCHAR(20),
    feedback_applied    BOOLEAN DEFAULT FALSE,
    feedback_slippage_bps NUMERIC(10,4),
    feedback_quality_score NUMERIC(5,4),
    capital_blocked     BOOLEAN DEFAULT FALSE,
    approved            BOOLEAN DEFAULT FALSE,
    reason              TEXT,
    act_status          VARCHAR(20),
    metadata            JSONB
);

CREATE INDEX IF NOT EXISTS idx_decision_log_symbol
    ON decision_log(symbol, time DESC);
CREATE INDEX IF NOT EXISTS idx_decision_log_cycle
    ON decision_log(cycle_id);

-- 3. execution_logs: 실행 스테이지 레이턴시 추적
CREATE TABLE IF NOT EXISTS execution_logs (
    time                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    order_id            VARCHAR(100) NOT NULL,
    symbol              VARCHAR(20) NOT NULL,
    stage               VARCHAR(50) NOT NULL,
    latency_ms          NUMERIC(10,2),
    success             BOOLEAN,
    error_code          VARCHAR(50)
);

CREATE INDEX IF NOT EXISTS idx_execution_logs_time
    ON execution_logs(time DESC);
CREATE INDEX IF NOT EXISTS idx_execution_logs_order
    ON execution_logs(order_id);

-- 4. positions: 실시간 포지션 관리
CREATE TABLE IF NOT EXISTS positions (
    symbol              VARCHAR(20) PRIMARY KEY,
    qty                 NUMERIC(20,4) NOT NULL DEFAULT 0,
    avg_price           NUMERIC(15,4) NOT NULL DEFAULT 0,
    market              VARCHAR(20),
    exposure_value      NUMERIC(20,4),
    exposure_pct        NUMERIC(5,4),
    unrealized_pnl      NUMERIC(20,4),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- 5. t_ledger: 매매 원장
CREATE TABLE IF NOT EXISTS t_ledger (
    id                  BIGSERIAL PRIMARY KEY,
    timestamp           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    symbol              VARCHAR(20) NOT NULL,
    side                VARCHAR(10) NOT NULL,
    qty                 NUMERIC(20,4) NOT NULL,
    price               NUMERIC(15,4) NOT NULL,
    amount              NUMERIC(20,4),
    fee                 NUMERIC(15,4) DEFAULT 0,
    strategy_tag        VARCHAR(50),
    order_id            VARCHAR(100),
    broker              VARCHAR(50)
);

CREATE INDEX IF NOT EXISTS idx_t_ledger_symbol
    ON t_ledger(symbol, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_t_ledger_time
    ON t_ledger(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_t_ledger_strategy
    ON t_ledger(strategy_tag, timestamp DESC);

-- =====================================================
-- 호환성 뷰 (QTS TimescaleDBAdapter 호환)
-- =====================================================

-- QTS가 tick_data로 접근할 수 있도록 뷰 생성
CREATE OR REPLACE VIEW tick_data AS
SELECT
    event_time AS time,
    symbol,
    last_price AS price,
    volume,
    bid_price AS bid,
    ask_price AS ask,
    'scalp' AS source
FROM scalp_ticks;

-- QTS가 ohlcv_1m으로 접근할 수 있도록 뷰 생성
CREATE OR REPLACE VIEW ohlcv_1m AS
SELECT
    bar_time AS bucket,
    symbol,
    open, high, low, close, volume
FROM scalp_1m_bars;
