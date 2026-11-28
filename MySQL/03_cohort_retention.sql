-- =============================================================
-- 03_cohort_retention.sql
-- Olist 复购/留存分析（交易型 marketplace 的正确口径）
--
-- 为什么不用 DAU/WAU 留存：
--   Olist 是交易型平台，用户没有「日常活跃」概念，平均 1.03 单/人、复购率 3%。
--   按「次日/7 日回访」计算，曲线全程贴在 0.1% 附近，没有决策价值。
--   正确的留存口径是「复购」：谁回来了、隔多久、回来买什么。
--
-- 本脚本4步：
--   ① 客户首单表          ② 第二次购买与间隔
--   ③ Cohort 90 天复购矩阵 ④ 首复购间隔分布
-- =============================================================

DROP TEMPORARY TABLE IF EXISTS tmp_first_order;
DROP TEMPORARY TABLE IF EXISTS tmp_second_order;

-- -------------------------------------------------------------
-- ① 客户首单（交付口径）
-- -------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_first_order AS
SELECT
    c.customer_unique_id,
    MIN(o.order_purchase_timestamp) AS first_ts,
    COUNT(DISTINCT o.order_id)      AS n_orders
FROM customers c
JOIN orders o ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id;

-- -------------------------------------------------------------
-- ② 第二次购买时间 + 首复购间隔（严格晚于首单，避免同刻拆单被误判）
--    gap_days = 第二次购买 - 第一次购买（天），只在「有第二次购买」的客户上非空
-- -------------------------------------------------------------
CREATE TEMPORARY TABLE tmp_second_order AS
SELECT
    t.customer_unique_id,
    t.first_ts,
    t.second_ts,
    DATEDIFF(t.second_ts, t.first_ts) AS gap_days
FROM (
    SELECT
        f.customer_unique_id,
        f.first_ts,
        MIN(o.order_purchase_timestamp) AS second_ts
    FROM tmp_first_order f
    JOIN customers c ON c.customer_unique_id = f.customer_unique_id
    JOIN orders o
         ON o.customer_id = c.customer_id
        AND o.order_status = 'delivered'
        AND o.order_purchase_timestamp > f.first_ts
    GROUP BY f.customer_unique_id, f.first_ts
) t;

-- -------------------------------------------------------------
-- ③ Cohort 复购矩阵：按首购月分组，看 30 / 90 / 180 天回购率
--    分母只保留观察窗口足够的客户，避免「新客被算作没留存」
-- -------------------------------------------------------------
WITH base AS (
    SELECT
        f.customer_unique_id,
        DATE_FORMAT(f.first_ts, '%Y-%m')              AS cohort,
        DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM orders WHERE order_status = 'delivered'),
                 f.first_ts)                          AS obs_days,
        s.gap_days                                    AS gap_days
    FROM tmp_first_order f
    LEFT JOIN tmp_second_order s ON s.customer_unique_id = f.customer_unique_id
)
SELECT
    cohort                                                              AS 首购月,
    SUM(obs_days >= 90)                                                 AS 样本,
    SUM(obs_days >= 90 AND gap_days <= 90)                              AS 复购人数,
    ROUND(SUM(obs_days >= 90 AND gap_days <= 90) / NULLIF(SUM(obs_days >= 90), 0) * 100, 2)
                                                                        AS 90天复购率,
    ROUND(SUM(obs_days >= 30 AND gap_days <= 30) / NULLIF(SUM(obs_days >= 30), 0) * 100, 2)
                                                                        AS 30天复购率
FROM base
WHERE obs_days >= 30
GROUP BY cohort
ORDER BY cohort;

-- -------------------------------------------------------------
-- ④ 首复购间隔分布：决定「召回券在第几天发」
--    注意 gap_days = 0 的一档必须单列：那是「同一天再次下单」，
--    多数是拆单 / 同一购物篮分卖家结算，不是真正的复购行为。
--    如果不单列，这一档会被 (0,30] 的开区间丢掉，导致占比不足 100%。
-- -------------------------------------------------------------
SELECT
    CASE
        WHEN gap_days  = 0   THEN '0. 同日（拆单）'
        WHEN gap_days <= 30  THEN '1. 1-30天'
        WHEN gap_days <= 60  THEN '2. 31-60天'
        WHEN gap_days <= 90  THEN '3. 61-90天'
        WHEN gap_days <= 180 THEN '4. 91-180天'
        WHEN gap_days <= 365 THEN '5. 181-365天'
        ELSE '6. 365天+'
    END                                                     AS 间隔区间,
    COUNT(*)                                                AS 人数,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2)        AS 占比
FROM tmp_second_order
GROUP BY 间隔区间
ORDER BY 间隔区间;

-- 剔除同日拆单后的真实复购间隔
SELECT
    COUNT(*)                                                          AS 真实复购人数,
    ROUND(AVG(gap_days), 1)                                           AS 平均间隔,
    ROUND(SUM(gap_days <= 90) / COUNT(*) * 100, 2)                    AS 90天内复购占比
FROM tmp_second_order
WHERE gap_days > 0;
