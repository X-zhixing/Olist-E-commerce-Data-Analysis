-- =============================================================
-- 07_cross_state.sql
-- 同州 vs 跨州：差异识别 + 差评率差的分解
--
-- 要回答：跨州订单差评率高，是因为「更慢」，还是「即使同样准时也更差」？
-- 方法：先切 2×2（同/跨 × 准时/延迟），再用 Kitagawa 分解，把差评率差拆成
--       「结构效应（延迟率不同）」+「率效应（同状态下体验不同）」。
--
-- 口径：交付订单；延迟按「签收日 > 承诺日」比较；差评 = 评分 ≤ 2；
--       一单多卖家时，任一卖家与客户不同州即记为跨州。
-- 用法：整段执行，会依次返回 汇总 / 2×2 / 分解 三张结果。
-- =============================================================

DROP TEMPORARY TABLE IF EXISTS tmp_cross_base;

CREATE TEMPORARY TABLE tmp_cross_base AS
SELECT
    o.order_id,
    c.customer_state,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
    CASE WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date)
         THEN 1 ELSE 0 END                                               AS is_late,
    lr.review_score,
    MAX(CASE WHEN s.seller_state <> c.customer_state THEN 1 ELSE 0 END)  AS is_cross
FROM orders o
JOIN customers c    ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id   = o.order_id
JOIN sellers s      ON s.seller_id   = oi.seller_id
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
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL
GROUP BY o.order_id, c.customer_state, delivery_days, is_late, lr.review_score;


-- -------------------------------------------------------------
-- ① 汇总对比
-- -------------------------------------------------------------
SELECT
    CASE WHEN is_cross = 1 THEN '跨州' ELSE '同州' END                     AS 类型,
    COUNT(*)                                                               AS 订单数,
    ROUND(AVG(is_late) * 100, 2)                                           AS 延迟率,
    ROUND(AVG(review_score), 2)                                            AS 平均评分,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
          / NULLIF(COUNT(review_score), 0) * 100, 2)                       AS 差评率,
    ROUND(AVG(delivery_days), 1)                                           AS 平均配送天数
FROM tmp_cross_base
GROUP BY is_cross
ORDER BY 类型 DESC;


-- -------------------------------------------------------------
-- ② 2×2：把「延迟」这一层拆出来，看四个格子的差评率
-- -------------------------------------------------------------
SELECT
    CASE WHEN is_cross = 1 THEN '跨州' ELSE '同州' END    AS 类型,
    CASE WHEN is_late = 1 THEN '延迟' ELSE '准时' END     AS 到货状态,
    COUNT(*)                                              AS 订单数,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
          / NULLIF(COUNT(review_score), 0) * 100, 2)      AS 差评率,
    ROUND(AVG(review_score), 2)                           AS 平均评分,
    ROUND(AVG(delivery_days), 1)                          AS 平均配送天数
FROM tmp_cross_base
GROUP BY is_cross, is_late
ORDER BY 类型 DESC, 到货状态;
