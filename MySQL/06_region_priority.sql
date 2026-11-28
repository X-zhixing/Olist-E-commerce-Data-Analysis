-- =============================================================
-- 06_region_priority.sql
-- 区域治理：分档（描述）与优先级（决策）用同一套阈值
--
-- 背景：原 02_analysis.sql 里存在两套阈值——
--   · 分档：≥15% 高 / 8–15% 中 / <8% 低
--   · 优先级：≥12% 视为高延迟
-- 同一份数据两套标准，会出现「中延迟区（8–15%）」被标成 P0 的矛盾，
-- 看板配色和明细表标签对不上。
--
-- 统一口径：高延迟 = 延迟率 ≥ 12%（≈ 平台均值 6.77% 的 1.8 倍）
--           中延迟 = 8% – 12%
--           低延迟 = < 8%
-- 说明：12% 能把 24 个州切成 7 / 8 / 9 三档（接近三等分）；
--       原来的 15% 只切出 3 个州，导致 12 个州挤在中间档，失去区分作用。
-- 影响：P0–P3 的归属不发生变化，只有「中延迟」标签改成「高延迟」。
-- =============================================================

WITH order_base AS (
    SELECT
        o.order_id,
        c.customer_state,
        CASE WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date)
             THEN 1 ELSE 0 END                                        AS is_late,
        lr.review_score
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    LEFT JOIN (
        SELECT order_id, review_score
        FROM (
            SELECT order_id, review_score,
                   ROW_NUMBER() OVER (PARTITION BY order_id
                                      ORDER BY review_creation_date DESC,
                                               review_answer_timestamp DESC,
                                               review_id DESC) AS rn
            FROM reviews
        ) t
        WHERE rn = 1
    ) lr ON lr.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date  IS NOT NULL
      AND o.order_estimated_delivery_date  IS NOT NULL
),

state_metrics AS (
    SELECT
        customer_state                                   AS state,
        COUNT(*)                                         AS total_orders,
        SUM(is_late)                                     AS delayed_orders,
        ROUND(AVG(is_late) * 100, 2)                     AS late_rate_pct,
        COUNT(review_score)                              AS reviewed_orders,
        ROUND(AVG(review_score), 2)                      AS avg_score,
        ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(review_score), 0) * 100, 2) AS low_score_pct
    FROM order_base
    GROUP BY customer_state
    HAVING COUNT(*) >= 100
),

scored AS (
    SELECT
        *,
        -- ① 分档：纯描述，颜色用
        CASE WHEN late_rate_pct >= 12 THEN '高延迟区（≥12%）'
             WHEN late_rate_pct >= 8  THEN '中延迟区（8–12%）'
             ELSE '低延迟区（<8%）' END                  AS late_band,
        -- ② 优先级：决策用，与分档共用同一条 12% 线
        CASE
            WHEN late_rate_pct >= 12 AND total_orders >= 1000 THEN 'P0：高延迟+高单量'
            WHEN late_rate_pct >= 12 AND total_orders <  1000 THEN 'P1：高延迟+低单量'
            WHEN late_rate_pct <  12 AND (avg_score < 4.0 OR low_score_pct > 15)
                                                              THEN 'P2：低延迟但低评分'
            ELSE 'P3：健康区域'
        END                                              AS priority
    FROM state_metrics
)

SELECT
    state                                                   AS 州,
    total_orders                                            AS 订单量,
    delayed_orders                                          AS 延迟订单,
    late_rate_pct                                           AS 延迟率,
    late_band                                               AS 延迟分档,
    avg_score                                               AS 平均评分,
    low_score_pct                                           AS 差评率,
    priority                                                AS 优先级,
    -- 一致性校验：P0/P1 必须落在「高延迟区」，P3 不应落在「高延迟区」
    CASE WHEN (priority LIKE 'P0%' OR priority LIKE 'P1%') AND late_band NOT LIKE '高延迟区%'
              THEN '✗ 标签冲突'
         WHEN priority LIKE 'P3%' AND late_band LIKE '高延迟区%'
              THEN '✗ 标签冲突'
         ELSE '✓' END                                       AS 口径校验
FROM scored
ORDER BY late_rate_pct DESC;


-- -------------------------------------------------------------
-- 校验：跑完上面那张表，下面这条必须返回 0 行
-- -------------------------------------------------------------
# SELECT COUNT(*) AS conflict_rows
# FROM scored
# WHERE (priority LIKE 'P0%' OR priority LIKE 'P1%') AND late_rate_pct < 12;
