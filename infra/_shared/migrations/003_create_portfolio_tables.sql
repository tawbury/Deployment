-- Phase 13: Portfolio 및 리밸런싱 관련 테이블 생성
-- 생성 날짜: 2026-01-22
-- 설명: 포트폴리오 추적, 리밸런싱 계획 및 주문 관리

-- =====================================================
-- 1. portfolio_policy 테이블 (포트폴리오 정책)
-- =====================================================
CREATE TABLE IF NOT EXISTS portfolio_policy (
    policy_id           VARCHAR(50) PRIMARY KEY,
    policy_name         VARCHAR(100) NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    rebalance_threshold FLOAT DEFAULT 0.05,
    rebalance_frequency VARCHAR(20) DEFAULT 'monthly',
    is_active           BOOLEAN DEFAULT TRUE
);

-- =====================================================
-- 2. target_weights 테이블 (목표 비중)
-- =====================================================
CREATE TABLE IF NOT EXISTS target_weights (
    policy_id           VARCHAR(50) NOT NULL,
    symbol              VARCHAR(20) NOT NULL,
    target_weight       FLOAT NOT NULL,
    updated_at          TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (policy_id, symbol),
    FOREIGN KEY (policy_id) REFERENCES portfolio_policy(policy_id)
);

CREATE INDEX IF NOT EXISTS idx_target_weights_policy ON target_weights(policy_id);

-- =====================================================
-- 3. portfolio_snapshot 테이블 (포트폴리오 스냅샷)
-- =====================================================
CREATE TABLE IF NOT EXISTS portfolio_snapshot (
    snapshot_id         BIGSERIAL PRIMARY KEY,
    policy_id           VARCHAR(50) NOT NULL,
    snapshot_time       TIMESTAMPTZ NOT NULL,
    total_value         NUMERIC(20,4),
    cash                NUMERIC(20,4),
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    FOREIGN KEY (policy_id) REFERENCES portfolio_policy(policy_id)
);

CREATE INDEX IF NOT EXISTS idx_portfolio_snapshot_policy ON portfolio_snapshot(policy_id);
CREATE INDEX IF NOT EXISTS idx_portfolio_snapshot_time ON portfolio_snapshot(snapshot_time DESC);

-- =====================================================
-- 4. portfolio_positions 테이블 (포지션 현황)
-- =====================================================
CREATE TABLE IF NOT EXISTS portfolio_positions (
    position_id         BIGSERIAL PRIMARY KEY,
    snapshot_id         BIGINT NOT NULL,
    symbol              VARCHAR(20) NOT NULL,
    quantity            BIGINT,
    market_price        NUMERIC(15,4),
    market_value        NUMERIC(20,4),
    current_weight      FLOAT,
    target_weight       FLOAT,
    weight_diff         FLOAT,
    FOREIGN KEY (snapshot_id) REFERENCES portfolio_snapshot(snapshot_id)
);

CREATE INDEX IF NOT EXISTS idx_portfolio_positions_snapshot ON portfolio_positions(snapshot_id);
CREATE INDEX IF NOT EXISTS idx_portfolio_positions_symbol ON portfolio_positions(symbol);

-- =====================================================
-- 5. rebalance_plan 테이블 (리밸런싱 계획)
-- =====================================================
CREATE TABLE IF NOT EXISTS rebalance_plan (
    plan_id             BIGSERIAL PRIMARY KEY,
    policy_id           VARCHAR(50) NOT NULL,
    snapshot_id         BIGINT NOT NULL,
    status              VARCHAR(20) DEFAULT 'pending',
    reason              TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    FOREIGN KEY (policy_id) REFERENCES portfolio_policy(policy_id),
    FOREIGN KEY (snapshot_id) REFERENCES portfolio_snapshot(snapshot_id)
);

CREATE INDEX IF NOT EXISTS idx_rebalance_plan_policy ON rebalance_plan(policy_id);
CREATE INDEX IF NOT EXISTS idx_rebalance_plan_status ON rebalance_plan(status);

-- =====================================================
-- 6. rebalance_orders 테이블 (리밸런싱 주문)
-- =====================================================
CREATE TABLE IF NOT EXISTS rebalance_orders (
    order_id            BIGSERIAL PRIMARY KEY,
    plan_id             BIGINT NOT NULL,
    symbol              VARCHAR(20) NOT NULL,
    side                VARCHAR(10) NOT NULL,
    target_qty          BIGINT,
    order_type          VARCHAR(20) DEFAULT 'MARKET',
    status              VARCHAR(20) DEFAULT 'pending',
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    FOREIGN KEY (plan_id) REFERENCES rebalance_plan(plan_id)
);

CREATE INDEX IF NOT EXISTS idx_rebalance_orders_plan ON rebalance_orders(plan_id);
CREATE INDEX IF NOT EXISTS idx_rebalance_orders_symbol ON rebalance_orders(symbol);

-- =====================================================
-- 7. rebalance_execution 테이블 (리밸런싱 체결 기록)
-- =====================================================
CREATE TABLE IF NOT EXISTS rebalance_execution (
    exec_id             BIGSERIAL PRIMARY KEY,
    order_id            BIGINT NOT NULL,
    filled_qty          BIGINT,
    filled_price        NUMERIC(15,4),
    exec_time           TIMESTAMPTZ,
    commission          NUMERIC(20,4),
    slippage            NUMERIC(20,4),
    status              VARCHAR(20),
    error_msg           TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    FOREIGN KEY (order_id) REFERENCES rebalance_orders(order_id)
);

CREATE INDEX IF NOT EXISTS idx_rebalance_execution_order ON rebalance_execution(order_id);
CREATE INDEX IF NOT EXISTS idx_rebalance_execution_time ON rebalance_execution(exec_time DESC);

-- =====================================================
-- 메타데이터 업데이트
-- =====================================================
INSERT INTO migration_log (migration_name, status)
VALUES ('003_create_portfolio_tables', 'success');
