-- ---------------------------数据分析--------------------------------
-- 1.总销售额、销售订单数、客单价
select round(sum(price + freight_value), 2) total_revenue ,
       count(distinct o.order_id) total_orders ,
       round(sum(price + freight_value)/count(distinct o.order_id), 2) avg_order_value
from orders o join order_items oi
on o.order_id = oi.order_id
where order_status = 'delivered';

-- 2.月度销售趋势 gmv  ; 月销售订单数量
select date_format(order_purchase_timestamp,'%Y-%m') month ,
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
group by c.customer_unique_id
)

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

-- 8.订单支付方式分布
select payment_type 类型,
       count(*) 总数,
       round(count(*)/ sum(count(*)) over() * 100,3) 占比,
       round(avg(payment_installments),2) 平均分期,
       sum(payment_value) 金额,
       round(sum(payment_value) / sum(sum(payment_value)) over() * 100,2) 金额总占比
from payments
group by payment_type
order by 金额 desc;



-- ---------------------------------- 归因分析-评价差异相关因素--------------------------------------------
-- 1.交付订单差评率 : 12.81%
-- 针对一单多评情况，取最新评价分数
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
join ranked r
on o.order_id = r.order_id
where r.rn = 1
group by order_status
order by 订单数量 desc;

--  2.评价分布：（1-2）：11.51% + 3.18% = 14.69%
SELECT
  review_score,
  COUNT(*) AS reviews,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS pct
FROM reviews
GROUP BY review_score
ORDER BY review_score;

-- 3.订单状态查看
-- 总交付订单数： 96470  ; 总订单数：99441
SELECT count(*)
FROM orders
WHERE order_status = 'delivered';
-- 总评价数 : 99224  ;  评价订单数：98763  ; 交付订单评价数：95824
select count(*) from reviews;
select count(distinct order_id) from reviews;
SELECT COUNT(distinct o.order_id) AS delivered_with_review
FROM reviews r
JOIN orders o ON r.order_id = o.order_id
WHERE o.order_status = 'delivered';


-- ==============================================================
-- 交付 delivered 订单分布
-- 总交付订单：96470 ， 准时：89936 ，93.23% ； 延迟：6534 ，6.77%
-- 有评价订单：95824 ， 准时：89443 ，93.34% ； 延迟：6381 ，6.66%
-- ==============================================================

-- ① 订单状态统计
with order_status as (
select o.order_id , order_delivered_customer_date , order_estimated_delivery_date ,
       datediff(order_delivered_customer_date , order_estimated_delivery_date) date_diff ,
       case when date(order_delivered_customer_date) > date(order_estimated_delivery_date) then '延迟' else '准时' end status
from orders o
where o.order_status = 'delivered'
),
    -- 一单多评取最新
ranked as(
    select *
    from(
    select order_id, review_score,
           review_creation_date, review_answer_timestamp,
           row_number() over (partition by order_id order by review_creation_date desc , review_answer_timestamp desc) rn
    from reviews) r
    where rn = 1
)
    -- 分析差评是否与配送准时有关
select
    status 订单状态,
    -- 总交付订单
    count(os.order_id) 总订单数, round(count(os.order_id) * 100/ sum(count(os.order_id)) over(),2) 总订单数占比,
    -- 有评价交付订单
    count(r.order_id) 有评价订单数 , round(count(r.order_id) * 100/ sum(count(r.order_id)) over(),2) 有评价订单数占比,
    round(avg(review_score) , 2) 平均评分,
    sum(case when review_score <= 2 then 1 else 0 end) 差评数,
    round(sum(case when review_score <= 2 then 1 else 0 end) / count(r.order_id) * 100 , 2) 差评数占比,
    round(sum(case when review_score <= 2 then 1 else 0 end) / sum(count(r.order_id)) over() * 100, 2) 差评数总占比
from order_status os
left join ranked r on r.order_id = os.order_id
group by status;



-- ② 配送时长 与 评分 的具体关系 (分桶处理)
with order_status as (
select o.order_id , order_delivered_customer_date , order_estimated_delivery_date ,
       datediff(order_delivered_customer_date , order_estimated_delivery_date) date_diff ,
       case when date(order_delivered_customer_date) > date(order_estimated_delivery_date) then '延迟' else '准时' end status
from orders o
where o.order_status = 'delivered'),

ranked as(
    select *
    from(
        select order_id, review_score,
               review_creation_date, review_answer_timestamp,
               row_number() over (partition by order_id order by review_creation_date desc , review_answer_timestamp desc) rn
        from reviews) r
    where rn = 1
    )
-- 因为需要求取平均评分，所以此处用有评价交付订单数
select
    case
        when date_diff <= -7 then '1. 提前7+天'
        when date_diff <= -3 then '2. 提前3-7天'
        when date_diff < 0 then '3. 提前1-3天'
        when date_diff = 0 then '4. 准时准点'
        when date_diff <= 3 then '5. 延迟1-3天'
        when date_diff <= 7 then '6. 延迟4-7天'
        when date_diff > 7 then '7. 延迟7+天' end 到货偏差,
    count(*) 订单数, count(r.review_score) 有评分订单数, round(avg(review_score), 2) 平均评分
from order_status os
left join ranked r
on r.order_id = os.order_id
group by 到货偏差
order by 到货偏差;