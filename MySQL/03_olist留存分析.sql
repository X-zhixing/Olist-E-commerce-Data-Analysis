-- -----------------------------------用户留存---------------------------------
WITH first_pur AS (
    SELECT
        c.customer_unique_id,
        MIN(DATE(o.order_purchase_timestamp)) AS first_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
),
pur_date AS (
    SELECT DISTINCT
        c.customer_unique_id,
        DATE(o.order_purchase_timestamp) AS pur_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
),
data_end AS (
    SELECT MAX(DATE(order_purchase_timestamp)) AS max_date
    FROM orders
    WHERE order_status = 'delivered'
),
customer_gap AS (
    SELECT
        f.customer_unique_id,
        f.first_date,
        DATEDIFF(de.max_date, f.first_date) AS observation_days,
        MIN(DATEDIFF(p.pur_date, f.first_date)) AS first_return_gap
    FROM first_pur f
    CROSS JOIN data_end de
    LEFT JOIN pur_date p
        ON f.customer_unique_id = p.customer_unique_id
       AND p.pur_date > f.first_date
    GROUP BY f.customer_unique_id, f.first_date, de.max_date
)
SELECT
    -- ===== 口径 A：各自分母（描述性，回答"能被观察 N 天的客户中，N 天内回访比例"）=====
    COUNT(CASE WHEN observation_days >= 30 THEN 1 END) AS eligible_30,
    COUNT(CASE WHEN observation_days >= 60 THEN 1 END) AS eligible_60,
    COUNT(CASE WHEN observation_days >= 90 THEN 1 END) AS eligible_90,
    COUNT(CASE WHEN observation_days >= 30 AND first_return_gap <= 30 THEN 1 END) AS retained_30,
    COUNT(CASE WHEN observation_days >= 60 AND first_return_gap <= 60 and first_return_gap >= 30 THEN 1 END) AS retained_60,
    COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 90 and first_return_gap >= 60 THEN 1 END) AS retained_90,
    ROUND(COUNT(CASE WHEN observation_days >= 30 AND first_return_gap <= 30 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 30 THEN 1 END), 0) * 100, 2) AS retention_30_pct_A,
    ROUND(COUNT(CASE WHEN observation_days >= 60 AND first_return_gap <= 60 and first_return_gap >= 30 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 60 THEN 1 END), 0) * 100, 2) AS retention_60_pct_A,
    ROUND(COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 90 and first_return_gap >= 60 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 90 THEN 1 END), 0) * 100, 2) AS retention_90_pct_A,

    -- ===== 口径 B：统一 cohort（观察窗口 ≥90 天的客户），可跨窗口比较 =====
    COUNT(CASE WHEN observation_days >= 90 THEN 1 END) AS cohort_90_size,
    COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 30 THEN 1 END) AS cohort_90_retained_30,
    COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 60 THEN 1 END) AS cohort_90_retained_60,
    COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 90 THEN 1 END) AS cohort_90_retained_90,
    ROUND(COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 30 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 90 THEN 1 END), 0) * 100, 2) AS retention_30_pct_B,
    ROUND(COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 60 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 90 THEN 1 END), 0) * 100, 2) AS retention_60_pct_B,
    ROUND(COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 90 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 90 THEN 1 END), 0) * 100, 2) AS retention_90_pct_B,

    -- ===== 参考：总客户数与截断排除数 =====
    COUNT(*) AS total_customers,
    COUNT(CASE WHEN observation_days < 30 THEN 1 END) AS excluded_lt_30,
    COUNT(CASE WHEN observation_days < 90 THEN 1 END) AS excluded_lt_90
FROM customer_gap;


-- ------------------------同期群分析-------------------------------
WITH first_pur AS (
    SELECT
        c.customer_unique_id,
        MIN(DATE(o.order_purchase_timestamp)) AS first_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
    GROUP BY c.customer_unique_id
),
pur_date AS (
    SELECT DISTINCT
        c.customer_unique_id,
        DATE(o.order_purchase_timestamp) AS pur_date
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp IS NOT NULL
),
data_end AS (
    SELECT MAX(DATE(order_purchase_timestamp)) AS max_date
    FROM orders
    WHERE order_status = 'delivered'
),
customer_gap AS (
    SELECT
        f.customer_unique_id,
        f.first_date,
        DATE_FORMAT(f.first_date, '%Y-%m') AS cohort_month,
        DATEDIFF(de.max_date, f.first_date) AS observation_days,
        MIN(DATEDIFF(p.pur_date, f.first_date)) AS first_return_gap
    FROM first_pur f
    CROSS JOIN data_end de
    LEFT JOIN pur_date p
        ON f.customer_unique_id = p.customer_unique_id
       AND p.pur_date > f.first_date
    GROUP BY f.customer_unique_id, f.first_date, de.max_date
)
SELECT
    cohort_month,
    COUNT(*) AS cohort_size,
    COUNT(CASE WHEN observation_days >= 30 THEN 1 END) AS eligible_30,
    COUNT(CASE WHEN observation_days >= 30 AND first_return_gap <= 30 THEN 1 END) AS retained_30,
    ROUND(COUNT(CASE WHEN observation_days >= 30 AND first_return_gap <= 30 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 30 THEN 1 END), 0) * 100, 2) AS retention_30_pct,
    COUNT(CASE WHEN observation_days >= 90 THEN 1 END) AS eligible_90,
    COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 90 THEN 1 END) AS retained_90,
    ROUND(COUNT(CASE WHEN observation_days >= 90 AND first_return_gap <= 90 THEN 1 END)
          / NULLIF(COUNT(CASE WHEN observation_days >= 90 THEN 1 END), 0) * 100, 2) AS retention_90_pct
FROM customer_gap
GROUP BY cohort_month
ORDER BY cohort_month;
