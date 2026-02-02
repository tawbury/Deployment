-- Phase 14: Analysis Tables for Strategy Validation & Parameter Optimization
-- Created: 2026-01-29
-- Purpose: Pre-computed statistics, threshold candidates, and signal events for backtesting

-- Drop existing tables if they exist (for idempotency)
DROP TABLE IF EXISTS analysis_signal_events CASCADE;
DROP TABLE IF EXISTS analysis_threshold_candidates CASCADE;
DROP TABLE IF EXISTS analysis_rolling_stats CASCADE;

-- =====================================================
-- 1. analysis_rolling_stats (Pre-computed Rolling Statistics)
-- Purpose: Store volatility, ATR, return distributions for parameter derivation
-- =====================================================
CREATE TABLE analysis_rolling_stats (
    -- Primary Key
    symbol          VARCHAR(20) NOT NULL,
    stat_time       TIMESTAMPTZ NOT NULL,
    window_minutes  INT NOT NULL,               -- 5, 10, 30, 60, 240
    source_table    VARCHAR(20) NOT NULL,       -- 'scalp_1m_bars' or 'swing_bars_10m'

    -- Price Statistics
    price_mean      NUMERIC(15,4),
    price_stddev    NUMERIC(15,4),
    price_min       NUMERIC(15,4),
    price_max       NUMERIC(15,4),

    -- Return Statistics
    return_mean     NUMERIC(10,8),
    return_stddev   NUMERIC(10,8),
    return_skew     NUMERIC(10,6),
    return_kurtosis NUMERIC(10,6),

    -- Volatility Metrics
    atr_n           NUMERIC(15,4),              -- Average True Range
    volatility_pct  NUMERIC(10,6),              -- Annualized volatility
    high_low_range  NUMERIC(15,4),              -- max(high) - min(low)

    -- Volume Statistics
    volume_mean     BIGINT,
    volume_stddev   NUMERIC(20,4),
    vwap            NUMERIC(15,4),              -- Volume-Weighted Average Price

    -- Data Quality
    bar_count       INT,
    coverage_ratio  FLOAT,

    -- Metadata
    computed_at     TIMESTAMPTZ DEFAULT NOW(),

    PRIMARY KEY (symbol, stat_time, window_minutes, source_table)
);

CREATE INDEX IF NOT EXISTS idx_rolling_stats_time
    ON analysis_rolling_stats(stat_time DESC);

CREATE INDEX IF NOT EXISTS idx_rolling_stats_symbol_window
    ON analysis_rolling_stats(symbol, window_minutes, stat_time DESC);

CREATE INDEX IF NOT EXISTS idx_rolling_stats_volatility
    ON analysis_rolling_stats(volatility_pct DESC)
    WHERE volatility_pct IS NOT NULL;

-- =====================================================
-- 2. analysis_threshold_candidates (Parameter Optimization Results)
-- Purpose: Store backtest results for entry/exit threshold combinations
-- =====================================================
CREATE TABLE analysis_threshold_candidates (
    -- Primary Key
    candidate_id    BIGSERIAL PRIMARY KEY,

    -- Target
    symbol          VARCHAR(20) NOT NULL,
    strategy_type   VARCHAR(20) NOT NULL,       -- 'scalp', 'swing', 'portfolio'
    analysis_time   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Threshold Parameters
    entry_threshold_pct     NUMERIC(10,6) NOT NULL,
    exit_threshold_pct      NUMERIC(10,6) NOT NULL,
    stop_loss_pct           NUMERIC(10,6),
    take_profit_pct         NUMERIC(10,6),
    holding_period_minutes  INT,

    -- Backtest Period
    backtest_start  TIMESTAMPTZ NOT NULL,
    backtest_end    TIMESTAMPTZ NOT NULL,

    -- Performance Metrics
    total_trades    INT,
    winning_trades  INT,
    losing_trades   INT,
    win_rate        NUMERIC(5,4),

    -- Return Metrics
    total_return_pct    NUMERIC(10,6),
    avg_return_pct      NUMERIC(10,6),
    max_return_pct      NUMERIC(10,6),
    min_return_pct      NUMERIC(10,6),

    -- Risk Metrics
    profit_factor       NUMERIC(10,4),
    sharpe_ratio        NUMERIC(10,6),
    sortino_ratio       NUMERIC(10,6),
    max_drawdown_pct    NUMERIC(10,6),
    avg_drawdown_pct    NUMERIC(10,6),

    -- Statistical Significance
    t_statistic         NUMERIC(10,6),
    p_value             NUMERIC(10,8),

    -- Configuration
    config_hash     VARCHAR(64),
    session_id      VARCHAR(50),

    -- Ranking
    rank_score      NUMERIC(10,6),
    is_optimal      BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_threshold_candidates_symbol
    ON analysis_threshold_candidates(symbol, strategy_type);

CREATE INDEX IF NOT EXISTS idx_threshold_candidates_time
    ON analysis_threshold_candidates(analysis_time DESC);

CREATE INDEX IF NOT EXISTS idx_threshold_candidates_performance
    ON analysis_threshold_candidates(sharpe_ratio DESC, win_rate DESC)
    WHERE total_trades >= 30;

CREATE INDEX IF NOT EXISTS idx_threshold_candidates_optimal
    ON analysis_threshold_candidates(symbol, is_optimal)
    WHERE is_optimal = TRUE;

-- =====================================================
-- 3. analysis_signal_events (Signal Frame Event Log)
-- Purpose: Capture events when signal conditions are met for pattern analysis
-- =====================================================
CREATE TABLE analysis_signal_events (
    -- Primary Key
    event_id        BIGSERIAL PRIMARY KEY,

    -- Event Identification
    symbol          VARCHAR(20) NOT NULL,
    event_time      TIMESTAMPTZ NOT NULL,
    source_table    VARCHAR(20) NOT NULL,

    -- Time Features
    delta_t_prev            NUMERIC(15,6),
    bucket_index            INT,
    relative_position       NUMERIC(5,4),

    -- Frequency Features
    event_count_last_n      INT,
    event_density_last_n    NUMERIC(15,6),
    same_pattern_streak     INT,

    -- Volatility Features
    value_diff_abs          NUMERIC(15,4),
    value_diff_pct          NUMERIC(10,8),
    rolling_range_n         NUMERIC(15,4),

    -- Condition Flags
    value_change_exceeds_x      BOOLEAN,
    event_frequency_exceeds_n   BOOLEAN,
    consecutive_events_ge_n     BOOLEAN,
    pattern_reappeared_within_t BOOLEAN,

    -- Condition Parameters Used
    threshold_x             NUMERIC(10,6),
    threshold_n             INT,
    threshold_streak        INT,
    threshold_t_seconds     NUMERIC(15,6),

    -- Price Context
    price_at_signal         NUMERIC(15,4),
    bid_price               NUMERIC(15,4),
    ask_price               NUMERIC(15,4),
    spread_pct              NUMERIC(10,6),

    -- Outcome Tracking (filled after signal)
    price_after_1m          NUMERIC(15,4),
    price_after_5m          NUMERIC(15,4),
    price_after_10m         NUMERIC(15,4),
    return_1m_pct           NUMERIC(10,8),
    return_5m_pct           NUMERIC(10,8),
    return_10m_pct          NUMERIC(10,8),

    -- Metadata
    config_version  VARCHAR(20) DEFAULT '1.0',
    session_id      VARCHAR(50),
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_signal_events_symbol_time
    ON analysis_signal_events(symbol, event_time DESC);

CREATE INDEX IF NOT EXISTS idx_signal_events_conditions
    ON analysis_signal_events(value_change_exceeds_x, event_frequency_exceeds_n, consecutive_events_ge_n)
    WHERE value_change_exceeds_x = TRUE OR consecutive_events_ge_n = TRUE;

CREATE INDEX IF NOT EXISTS idx_signal_events_outcome
    ON analysis_signal_events(return_5m_pct DESC)
    WHERE return_5m_pct IS NOT NULL;

-- =====================================================
-- Schema Enhancements to Existing Tables
-- =====================================================

-- Add spread columns to scalp_ticks (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'scalp_ticks' AND column_name = 'spread'
    ) THEN
        ALTER TABLE scalp_ticks ADD COLUMN spread NUMERIC(15,4);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'scalp_ticks' AND column_name = 'spread_pct'
    ) THEN
        ALTER TABLE scalp_ticks ADD COLUMN spread_pct NUMERIC(10,8);
    END IF;
END $$;

-- Add returns column to swing_bars_10m (if not exists)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'swing_bars_10m' AND column_name = 'returns_pct'
    ) THEN
        ALTER TABLE swing_bars_10m ADD COLUMN returns_pct NUMERIC(10,8);
    END IF;
END $$;

-- =====================================================
-- Trigger for computing swing returns
-- =====================================================
CREATE OR REPLACE FUNCTION compute_swing_returns()
RETURNS TRIGGER AS $$
DECLARE
    prev_close NUMERIC(15,4);
BEGIN
    SELECT close INTO prev_close
    FROM swing_bars_10m
    WHERE symbol = NEW.symbol
      AND bar_time < NEW.bar_time
    ORDER BY bar_time DESC
    LIMIT 1;

    IF prev_close IS NOT NULL AND prev_close > 0 THEN
        NEW.returns_pct := (NEW.close - prev_close) / prev_close;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_compute_swing_returns ON swing_bars_10m;
CREATE TRIGGER trg_compute_swing_returns
    BEFORE INSERT ON swing_bars_10m
    FOR EACH ROW
    EXECUTE FUNCTION compute_swing_returns();

-- =====================================================
-- Additional Composite Indexes for Performance
-- =====================================================

-- Covering index for swing OHLCV scans
CREATE INDEX IF NOT EXISTS idx_swing_10m_covering
    ON swing_bars_10m(symbol, bar_time DESC)
    INCLUDE (open, high, low, close, volume);

-- Quality-filtered swing index
CREATE INDEX IF NOT EXISTS idx_swing_10m_quality_filter
    ON swing_bars_10m(symbol, bar_time DESC)
    WHERE quality_flag = 'normal' AND mitigation_level = 0;

-- Coverage-based scalp_1m_bars index
CREATE INDEX IF NOT EXISTS idx_scalp_1m_high_coverage
    ON scalp_1m_bars(symbol, bar_time DESC, coverage_ratio)
    WHERE coverage_ratio >= 0.75;

-- =====================================================
-- Materialized View for Rolling Statistics (Hourly)
-- =====================================================
DROP MATERIALIZED VIEW IF EXISTS mv_rolling_stats_hourly;

CREATE MATERIALIZED VIEW mv_rolling_stats_hourly AS
WITH base_data AS (
    SELECT
        symbol,
        bar_time,
        open, high, low, close, volume,
        LAG(close) OVER (PARTITION BY symbol ORDER BY bar_time) as prev_close,
        (high - low) as true_range
    FROM swing_bars_10m
    WHERE bar_time >= NOW() - INTERVAL '90 days'
      AND quality_flag = 'normal'
),
returns AS (
    SELECT
        symbol,
        bar_time,
        close,
        volume,
        true_range,
        (close - prev_close) / NULLIF(prev_close, 0) as returns
    FROM base_data
    WHERE prev_close IS NOT NULL AND prev_close > 0
)
SELECT
    symbol,
    DATE_TRUNC('hour', bar_time) as stat_hour,
    10 as window_minutes,
    'swing_bars_10m'::VARCHAR(20) as source_table,
    AVG(close) as price_mean,
    STDDEV(close) as price_stddev,
    MIN(close) as price_min,
    MAX(close) as price_max,
    AVG(returns) as return_mean,
    STDDEV(returns) as return_stddev,
    STDDEV(returns) * SQRT(252 * 6.5 * 6) as volatility_pct,
    AVG(true_range) as atr_n,
    AVG(volume) as volume_mean,
    STDDEV(volume) as volume_stddev,
    COUNT(*) as bar_count,
    1.0::FLOAT as coverage_ratio
FROM returns
GROUP BY symbol, DATE_TRUNC('hour', bar_time);

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_rolling_stats
    ON mv_rolling_stats_hourly(symbol, stat_hour);

-- =====================================================
-- Migration Log Update
-- =====================================================
INSERT INTO migration_log (migration_name, status, details)
VALUES ('004_create_analysis_tables', 'success', 'Phase 14: Analysis tables for strategy validation');
