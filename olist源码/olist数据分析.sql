-- ---------------------------数据分析--------------------------------
-- 1.总销售额、销售订单数、客单价
select round(sum(price + freight_value), 2) total_revenue ,
       count(distinct o.order_id) total_orders ,
       round(sum(price + freight_value)/count(distinct o.order_id), 2) avg_order_value
from orders o join order_items oi
on o.order_id = oi.order_id
where order_status = 'delivered';

-- 2.月度销售趋势 gmv  ; 月销售订单数量
select date_format(shipping_limit_date,'%Y-%m') month ,
       round(sum(price + freight_value),2) revenue ,
       count(distinct o.order_id) orders
from orders o join order_items oi
on o.order_id = oi.order_id
where o.order_status = 'delivered'
group by month
order by month;

-- 3.商品营收排名
select count(distinct product_category_name) products from products; # 查看 总共75种商品品类

select ct.product_category_name_english category,
       round(sum(price),2)  revenue,
       round(sum(price) * 100 /sum(sum(price)) over(),2) revenue_pct,
       count(distinct oi.order_id) orders,
       round(sum(price) / count(distinct oi.order_id),2) 客单价
from order_items oi
join products p on oi.product_id = p.product_id
left join category_translation ct on ct.product_category_name = p.product_category_name
join orders o on oi.order_id = o.order_id
where o.order_status = 'delivered'
group by ct.product_category_name_english
order by revenue desc
limit 10;

-- 4.地理分布收入排名 (州排名前十)
select c.customer_state state ,
       round(sum(price + freight_value),2) revenue,
       count(distinct o.order_id) orders,
       round(sum(price + freight_value) / sum(sum(price + freight_value)) over() * 100 ,2) pct
from customers c
join orders o on c.customer_id = o.customer_id
join order_items oi on o.order_id = oi.order_id
where o.order_status = 'delivered'
group by customer_state
order by revenue desc;
# limit 10;

-- 5.用户消费数
select count(distinct c.customer_unique_id) total_customers
from customers c
join orders o on c.customer_id = o.customer_id
where o.order_status = 'delivered';

-- 6.用户复购率
with customer_order_count as
(select c.customer_unique_id, count(distinct order_id) order_count
from customers c
join orders o on c.customer_id = o.customer_id
where o.order_status = 'delivered'
group by c.customer_unique_id)

select count(*) total_customers ,
       sum(case when order_count > 1 then 1 else 0 end) repeat_customers ,
       round(sum(case when order_count > 1 then 1 else 0 end) / count(*) * 100,2) r_pct,
       round(sum(case when order_count = 2 then 1 else 0 end) / count(*) * 100,2) r2_pct,
       round(sum(case when order_count > 2 then 1 else 0 end) / count(*) * 100,2) r3_pct
from customer_order_count;

-- 7.订单状态占比
SELECT
    order_status,
    COUNT(*) AS order_count,
    ROUND(COUNT(*) * 100 / (SELECT COUNT(order_id) FROM orders), 3) AS pct
FROM orders
GROUP BY order_status
ORDER BY order_count DESC;

# 8.订单支付方式分布
select payment_type 类型,
       count(*) 总数,
       round(count(*)/ sum(count(*)) over() * 100,2) 占比,
       round(avg(payment_installments),2) 平均分期,
       sum(payment_value) 金额,
       round(sum(payment_value) / sum(sum(payment_value)) over() * 100,2) 金额总占比
from payments
group by payment_type
order by 金额 desc;


-- 9.用户rfm (r:最近购买时间 , f:购买频次 , m:购买金额)
select max(order_purchase_timestamp) max_date from orders;

with c_rfm as (
select c.customer_unique_id uid ,
       datediff('2018-10-17',max(order_purchase_timestamp)) r ,
       count(distinct o.order_id) f ,
       round(sum(price + freight_value),2) m
           from customers c
               join orders o on c.customer_id = o.customer_id
               join order_items oi on o.order_id = oi.order_id
           where o.order_status = 'delivered'
           group by c.customer_unique_id
           order by m desc),

-- 由于复购率极低，仅3%左右 ，致使f指标基本失效，采用自定义f 分层用户
    rfm_score as(
select uid , r , f , m ,
       ntile(5) over (order by r desc) r_score,
       ntile(5) over (order by m) m_score,
       case
           when f = 1 then 1
           when f = 2 then 4
           when f > 2 then 5 end f_score
from c_rfm),

rfm_model as(
select uid , r , f , m ,
       case when r_score >= 4 and m_score >= 4 and f_score >= 4 then '高价值活跃用户'
            when r_score <= 2 and m_score >= 4 and f_score <= 2 then'高价值流失用户'
            when r_score >= 4 and m_score <= 2 and f_score >= 4 then '低价值活跃用户'
            when r_score >= 2 and m_score <= 2 and f_score <= 2 then '低价值流失用户'
       else '一般用户' end as customer_class
from rfm_score)

-- 查看rfm分层总览
select customer_class 用户分层,
       count(*) counts,
       round(count(*) / sum(count(*)) over () * 100, 2) Percentage,
       round(sum(price + freight_value),2) 消费金额,
       round(sum(price + freight_value) / sum(sum(price + freight_value)) over () * 100,2) GMV占比
from rfm_model rfm join customers c on rfm.uid = c.customer_unique_id
join orders o on c.customer_id = o.customer_id
join order_items oi on o.order_id = oi.order_id
group by customer_class;



-- ---------------------------------- 10.归因分析-评价差异相关因素--------------------------------------------
# 1.交付订单差评率 : 12.81%
# 针对一单多评情况，取最新评价分数
WITH ranked AS (
    SELECT order_id,
           review_score,
           review_creation_date,
           review_answer_timestamp,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date DESC,
                        review_answer_timestamp DESC,
                        review_id DESC) AS rn
    FROM reviews
)

select order_status 订单状态, count(*) 订单数量, round(count(*) / sum(count(*)) over() * 100 , 3) 订单占比,
       round(avg(review_score),2) 平均评分,
       sum(case when review_score <= 2 then 1 else 0 end) 差评数,
       round(sum(case when review_score <= 2 then 1 else 0 end) / count(*) * 100 , 2) 差评率,
       round(sum(case when review_score <= 2 then 1 else 0 end) / sum(count(*)) over() * 100 , 2) 差评总占比
from orders o
    # 子查询对 一单多评 取平均评分
join ranked r -- (select order_id , avg(review_score) review_score from reviews group by order_id) r
on o.order_id = r.order_id
where r.rn = 1
group by order_status
order by 订单数量 desc;

# 2.评价分布：（1-2）：11.51% + 3.18% = 14.69%
SELECT
  review_score,
  COUNT(*) AS reviews,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct
FROM reviews
GROUP BY review_score
ORDER BY review_score;

# 3.订单状态查看
# 总交付订单数： 96470  ; 总订单数：99441
SELECT count(*)
FROM orders
WHERE order_status = 'delivered';

# 总评价数 : 99224  ;  评价订单数：98763  ; 交付订单评价数：95824
select count(*) from reviews;
select count(distinct order_id) from reviews;
SELECT COUNT(distinct o.order_id) AS delivered_with_review
FROM reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';

-- --------------------------------------------------
# 4.交付delivered 订单分布 准时：88163 ，91.89% ； 延迟：7661 ，8.11%
with order_status as (
select o.order_id , order_delivered_customer_date , order_estimated_delivery_date ,
       datediff(order_delivered_customer_date , order_estimated_delivery_date) date_diff ,
       case when order_delivered_customer_date > order_estimated_delivery_date then '延迟' else '准时' end status
from orders o
where o.order_status = 'delivered')
# 分析差评是否与配送时长有关
select status , count(status) s_count , round(count(status) * 100/ sum(count(status)) over(),2) s_per,
       round(avg(review_score) , 2) avg_score,
       sum(case when review_score <= 2 then 1 else 0 end) 差评数,
       round(sum(case when review_score <= 2 then 1 else 0 end) / count(status) * 100 , 2) 差评数占比,
       round(sum(case when review_score <= 2 then 1 else 0 end) / sum(count(status)) over() * 100, 2) 差评数总占比
from order_status os
join (select order_id, review_score,
           review_creation_date, review_answer_timestamp,
           row_number() over (partition by order_id order by review_creation_date desc , review_answer_timestamp desc) rn
    from reviews) r
on r.order_id = os.order_id
where rn = 1
group by status;


# 配送时长 与 评分 的具体关系
with order_status as (
select o.order_id , order_delivered_customer_date , order_estimated_delivery_date ,
       datediff(order_delivered_customer_date , order_estimated_delivery_date) date_diff ,
       case when order_delivered_customer_date > order_estimated_delivery_date then '延迟' else '准时' end status
from orders o
where o.order_status = 'delivered'),

ranked as(
    select order_id, review_score,
           review_creation_date, review_answer_timestamp,
           row_number() over (partition by order_id order by review_creation_date desc , review_answer_timestamp desc) rn
    from reviews
    )

select
    case when date_diff <= -7 then '1. 提前7+天'
        when date_diff <= -3 then '2. 提前3-7天'
        when date_diff < 0 then '3. 提前1-3天'
        when date_diff = 0 then '4. 准时准点'
        when date_diff <= 3 then '5. 延迟1-3天'
        when date_diff <= 7 then '6. 延迟4-7天'
        when date_diff > 7 then '7. 延迟7+天' end 到货偏差,
    count(*) 订单数量, round(avg(review_score) , 2) 平均评分
from order_status os
join ranked r
on r.order_id = os.order_id
where rn = 1
group by 到货偏差
order by 到货偏差;

-- -----------------------------供给侧--------------------------------
# 1.卖家评分分析
# 一单多评取最迟
with last_reviews as (
    select order_id, review_score from
    (select order_id, review_score,
    row_number() over (partition by order_id order by review_creation_date desc , review_answer_timestamp desc) rn
    from reviews ) t
        where rn = 1),

# 商品聚合
order_base as (
    select distinct o.order_id, oi.seller_id,
           max(case when order_delivered_customer_date > order_estimated_delivery_date then 1 else 0 end) late
    from orders o
    join order_items oi on o.order_id = oi.order_id
    where order_status = 'delivered'
    group by o.order_id, oi.seller_id
)

select s.seller_id, s.seller_state,
       -- 基于有评价订单指标
       count(distinct case when lr.review_score is not null then ob.order_id end) as 有评价订单数,
       round(avg(lr.review_score),2) 平均评分,
       sum(if(lr.review_score <= 2, 1, 0)) 有评价差评订单数,
       round(avg(if(lr.review_score <= 2, 1, 0)) * 100,2) 有评价差评订单占比,
       -- 基于所有订单指标
       count(distinct ob.order_id) 总订单数, sum(late) 延迟订单数, round(avg(late) * 100,2) 延迟占比
from sellers s
join order_base ob on ob.seller_id = s.seller_id
left join last_reviews lr on lr.order_id = ob.order_id
group by s.seller_id
having count(distinct ob.order_id) >= 20
order by 平均评分, 有评价差评订单占比 desc, 延迟占比 desc;

# 2.区域评分分析
-- ============================================================
-- Olist 地理分布 × 配送时效 × 评分分析
-- 最终版 v6
-- 数据库：MySQL 8.0+
-- 说明：临时表只在同一连接内有效，请在同一脚本内一次性执行
-- ============================================================


-- ------------------------------------------------------------
-- 1. 订单级基础表
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_order_base;

CREATE TABLE tmp_order_base AS
SELECT
    o.order_id,
    c.customer_state,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    CASE WHEN o.order_delivered_customer_date >= o.order_purchase_timestamp
         THEN DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)
         ELSE NULL END AS delivery_days,
    CASE WHEN o.order_delivered_carrier_date >= o.order_approved_at
         THEN DATEDIFF(o.order_delivered_carrier_date, o.order_approved_at)
         ELSE NULL END AS seller_days,
    CASE WHEN o.order_delivered_customer_date >= o.order_delivered_carrier_date
         THEN DATEDIFF(o.order_delivered_customer_date, o.order_delivered_carrier_date)
         ELSE NULL END AS carrier_days,
    CASE WHEN DATE(o.order_delivered_customer_date) > DATE(o.order_estimated_delivery_date)
         THEN 1 ELSE 0 END AS is_delayed,
    lr.review_score
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN (
    SELECT order_id, review_score
    FROM (
        SELECT order_id, review_score,
               ROW_NUMBER() OVER (
                   PARTITION BY order_id
                   ORDER BY review_creation_date DESC,
                            review_answer_timestamp DESC,
                            review_id DESC
               ) AS rn
        FROM reviews
    ) t
    WHERE rn = 1
) lr ON o.order_id = lr.order_id
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp IS NOT NULL
  AND o.order_approved_at IS NOT NULL
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_estimated_delivery_date IS NOT NULL;


-- ------------------------------------------------------------
-- 2. 订单 × 卖家级基础表
-- ------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_order_seller;

CREATE TABLE tmp_order_seller AS
SELECT DISTINCT
    ob.order_id,
    oi.seller_id,
    ob.customer_state,
    ob.delivery_days,
    ob.seller_days,
    ob.carrier_days,
    ob.is_delayed,
    ob.review_score
FROM tmp_order_base ob
JOIN order_items oi ON ob.order_id = oi.order_id;


-- ------------------------------------------------------------
-- 3. 收货地（客户所在州）时效指标
-- ------------------------------------------------------------
SELECT
    customer_state AS state,
    COUNT(*)                          AS total_orders,
    COUNT(delivery_days)              AS delivery_days_n,
    COUNT(seller_days)                AS seller_days_n,
    COUNT(carrier_days)               AS carrier_days_n,
    ROUND(AVG(delivery_days), 1)      AS avg_delivery_days,
    ROUND(AVG(seller_days), 1)        AS avg_seller_days,
    ROUND(AVG(carrier_days), 1)       AS avg_carrier_days,
    SUM(is_delayed)                   AS delayed_orders,
    ROUND(AVG(is_delayed) * 100, 2)   AS late_rate_pct
FROM tmp_order_base
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC;


-- ------------------------------------------------------------
-- 4. 收货地（客户所在州）评分指标
-- ------------------------------------------------------------
SELECT
    customer_state AS state,
    COUNT(review_score)                       AS reviewed_orders,
    ROUND(AVG(review_score), 2)               AS avg_score,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
          / NULLIF(COUNT(review_score), 0) * 100, 2) AS low_score_pct
FROM tmp_order_base
WHERE review_score IS NOT NULL
GROUP BY customer_state
HAVING COUNT(review_score) >= 100
ORDER BY avg_score;


-- ------------------------------------------------------------
-- 5. 按延迟率分档
-- ------------------------------------------------------------
WITH state_metrics AS (
    SELECT
        customer_state AS state,
        COUNT(*)                          AS total_orders,
        SUM(is_delayed)                   AS delayed_orders,
        AVG(is_delayed) * 100             AS late_rate_pct,
        COUNT(review_score)               AS reviewed_orders,
        AVG(review_score)                 AS avg_score
    FROM tmp_order_base
    GROUP BY customer_state
    HAVING COUNT(*) >= 100
),
state_with_zone AS (
    SELECT
        *,
        CASE
            WHEN late_rate_pct >= 15 THEN '高延迟区（≥15%）'
            WHEN late_rate_pct >= 8  THEN '中延迟区（8-15%）'
            ELSE '低延迟区（<8%）'
        END AS zone
    FROM state_metrics
)
SELECT
    zone,
    COUNT(*)                                AS states,
    SUM(total_orders)                       AS total_orders,
    SUM(delayed_orders)                     AS delayed_orders,
    ROUND(SUM(delayed_orders) / NULLIF(SUM(total_orders), 0) * 100, 2)             AS weighted_late_rate_pct,
    ROUND(AVG(late_rate_pct), 2)                                                  AS simple_avg_late_rate_pct,
    SUM(reviewed_orders)                    AS reviewed_orders,
    ROUND(SUM(avg_score * reviewed_orders) / NULLIF(SUM(reviewed_orders), 0), 2) AS weighted_avg_score,
    ROUND(AVG(avg_score), 2)                                                      AS simple_avg_score
FROM state_with_zone
GROUP BY zone
ORDER BY weighted_late_rate_pct DESC;


-- ------------------------------------------------------------
-- 6. 卖家所在州：时效 + 评分（订单粒度）
-- 注意：一单多卖家时取字母序最大的 seller_state，
--       SP 可能被系统性高估。如需精确归因，改为按金额最大卖家。
-- ------------------------------------------------------------
WITH order_seller_state AS (
    SELECT
        os.order_id,
        MAX(s.seller_state)      AS seller_state,
        MAX(os.seller_days)      AS seller_days,
        MAX(os.delivery_days)    AS delivery_days,
        MAX(os.carrier_days)     AS carrier_days,
        MAX(os.is_delayed)       AS is_delayed,
        MAX(os.review_score)     AS review_score
    FROM tmp_order_seller os
    JOIN sellers s ON os.seller_id = s.seller_id
    GROUP BY os.order_id
)
SELECT
    seller_state,
    COUNT(*)                          AS total_orders,
    COUNT(delivery_days)              AS delivery_days_n,
    COUNT(seller_days)                AS seller_days_n,
    COUNT(carrier_days)               AS carrier_days_n,
    ROUND(AVG(delivery_days), 1)      AS avg_delivery_days,
    ROUND(AVG(seller_days), 1)        AS avg_seller_days,
    ROUND(AVG(carrier_days), 1)       AS avg_carrier_days,
    ROUND(AVG(is_delayed) * 100, 2)   AS late_rate_pct,
    COUNT(review_score)               AS reviewed_orders,
    ROUND(AVG(review_score), 2)       AS avg_score
FROM order_seller_state
GROUP BY seller_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC;


-- ------------------------------------------------------------
-- 7. 跨州 vs 同州（订单粒度）
-- ------------------------------------------------------------
WITH order_cross AS (
    SELECT
        ob.order_id,
        MAX(ob.delivery_days)  AS delivery_days,
        MAX(ob.seller_days)    AS seller_days,
        MAX(ob.carrier_days)   AS carrier_days,
        MAX(ob.is_delayed)     AS is_delayed,
        MAX(ob.review_score)   AS review_score,
        MAX(CASE WHEN ob.customer_state != s.seller_state THEN 1 ELSE 0 END) AS is_cross_state
    FROM tmp_order_base ob
    JOIN order_items oi ON ob.order_id = oi.order_id
    JOIN sellers s ON oi.seller_id = s.seller_id
    GROUP BY ob.order_id
)
SELECT
    CASE WHEN is_cross_state = 1 THEN '跨州' ELSE '同州' END AS order_type,
    COUNT(*)                          AS total_orders,
    COUNT(delivery_days)              AS delivery_days_n,
    COUNT(seller_days)                AS seller_days_n,
    COUNT(carrier_days)               AS carrier_days_n,
    ROUND(AVG(delivery_days), 1)      AS avg_delivery_days,
    ROUND(AVG(seller_days), 1)        AS avg_seller_days,
    ROUND(AVG(carrier_days), 1)       AS avg_carrier_days,
    ROUND(AVG(is_delayed) * 100, 2)   AS late_rate_pct,
    COUNT(review_score)               AS reviewed_orders,
    ROUND(AVG(review_score), 2)       AS avg_score,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
          / NULLIF(COUNT(review_score), 0) * 100, 2) AS low_score_pct
FROM order_cross
GROUP BY order_type;


-- ------------------------------------------------------------
-- 8. 按客户州拆解跨州影响（订单粒度）
-- ------------------------------------------------------------
WITH order_cross AS (
    SELECT
        ob.order_id,
        ob.customer_state,
        MAX(ob.delivery_days)  AS delivery_days,
        MAX(ob.is_delayed)     AS is_delayed,
        MAX(ob.review_score)   AS review_score,
        MAX(CASE WHEN ob.customer_state != s.seller_state THEN 1 ELSE 0 END) AS is_cross_state
    FROM tmp_order_base ob
    JOIN order_items oi ON ob.order_id = oi.order_id
    JOIN sellers s ON oi.seller_id = s.seller_id
    GROUP BY ob.order_id, ob.customer_state
)
SELECT
    customer_state,
    COUNT(*)                                AS total_orders,
    ROUND(AVG(is_cross_state) * 100, 1)     AS cross_state_pct,
    ROUND(AVG(CASE WHEN is_cross_state = 0 THEN delivery_days END), 1) AS same_state_days,
    ROUND(AVG(CASE WHEN is_cross_state = 1 THEN delivery_days END), 1) AS cross_state_days,
    ROUND(AVG(is_delayed) * 100, 2)         AS late_rate_pct,
    COUNT(review_score)                     AS reviewed_orders,
    ROUND(AVG(review_score), 2)             AS avg_score
FROM order_cross
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY cross_state_pct DESC;


-- ------------------------------------------------------------
-- 9. 州内评分差：准时 vs 延迟
-- ------------------------------------------------------------
SELECT
    customer_state AS state,
    COUNT(*)                                AS reviewed_orders,
    SUM(is_delayed)                         AS delayed_orders,
    ROUND(AVG(CASE WHEN is_delayed = 0 THEN review_score END), 2) AS on_time_score,
    ROUND(AVG(CASE WHEN is_delayed = 1 THEN review_score END), 2) AS delayed_score,
    ROUND(AVG(CASE WHEN is_delayed = 0 THEN review_score END) -
          AVG(CASE WHEN is_delayed = 1 THEN review_score END), 2) AS score_gap
FROM tmp_order_base
WHERE review_score IS NOT NULL
GROUP BY customer_state
HAVING COUNT(*) >= 100
   AND SUM(is_delayed) >= 20
ORDER BY score_gap DESC;


-- ------------------------------------------------------------
-- 10. 优先级矩阵
-- 注意：分档用 15/8，优先级矩阵用 12，阈值有意不同
-- ------------------------------------------------------------
WITH state_metrics AS (
    SELECT
        customer_state AS state,
        COUNT(*)                          AS total_orders,
        SUM(is_delayed)                   AS delayed_orders,
        AVG(is_delayed) * 100             AS late_rate_pct,
        COUNT(review_score)               AS reviewed_orders,
        AVG(review_score)                 AS avg_score,
        ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)
              / NULLIF(COUNT(review_score), 0) * 100, 2) AS low_score_pct
    FROM tmp_order_base
    GROUP BY customer_state
    HAVING COUNT(*) >= 100
)
SELECT
    state,
    total_orders,
    reviewed_orders,
    ROUND(late_rate_pct, 2)             AS late_rate_pct,
    ROUND(avg_score, 2)                 AS avg_score,
    low_score_pct,
    delayed_orders,
    CASE
        WHEN late_rate_pct >= 12 AND total_orders >= 1000 THEN 'P0：高延迟+高单量'
        WHEN late_rate_pct >= 12 AND total_orders <  1000 THEN 'P1：高延迟+低单量'
        WHEN late_rate_pct <  12 AND (avg_score < 4.0 OR low_score_pct > 15) THEN 'P2：低延迟但低评分'
        ELSE 'P3：健康区域'
    END AS priority
FROM state_metrics
ORDER BY
    CASE
        WHEN late_rate_pct >= 12 AND total_orders >= 1000 THEN 1
        WHEN late_rate_pct >= 12 AND total_orders <  1000 THEN 2
        WHEN late_rate_pct <  12 AND (avg_score < 4.0 OR low_score_pct > 15) THEN 3
        ELSE 4
    END,
    late_rate_pct DESC;


-- ------------------------------------------------------------
-- 11. 卖家州 → 客户州 延迟矩阵（订单 × 卖家粒度）
-- 注意：late_rate_pct 是"卖家-订单对"的延迟率，
--       同一订单有多个卖家时会被重复计入，不是订单延迟率。
--       LIMIT 50 只展示延迟率最高的 50 条链路，不代表全部。
-- ------------------------------------------------------------
SELECT
    s.seller_state,
    os.customer_state,
    COUNT(*)                                AS order_seller_pairs,
    ROUND(AVG(os.is_delayed) * 100, 2)      AS late_rate_pct,
    COUNT(os.review_score)                  AS reviewed_pairs,
    ROUND(AVG(os.review_score), 2)          AS avg_score
FROM tmp_order_seller os
JOIN sellers s ON os.seller_id = s.seller_id
GROUP BY s.seller_state, os.customer_state
HAVING COUNT(*) >= 50
ORDER BY late_rate_pct DESC, order_seller_pairs DESC, s.seller_state, os.customer_state
LIMIT 50;

-- ---------------------------------FineBI可视化数据处理---------------------------------------
-- 地理坐标计算
select geolocation_state, avg(geolocation_lat) lat, avg(geolocation_lng) lng
from olist_geolocation og
group by geolocation_state;

