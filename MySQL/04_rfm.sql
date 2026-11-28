-- =============================================================
-- 04_rfm_8seg.sql
-- 用户rfm (r:最近购买时间 , f:购买频次 , m:购买金额)
-- 目的：用标准八分法（R / F / M 各高低）重做用户分层
-- 环境：MySQL 8.0+（依赖 CTE 与窗口函数）
-- 口径：交付订单（order_status = 'delivered'）；GMV = price + freight_value
-- 说明：F 直接二值化为「是否复购（订单数 ≥ 2）」，
--       不再用 NTILE 分 5 档——复购率仅 3%，NTILE 会把 97% 的用户压在同一档。
-- =============================================================
select max(order_purchase_timestamp) max_date from orders where order_status = 'delivered';

with c_rfm as (
select c.customer_unique_id uid,
       datediff('2018-08-29',max(order_purchase_timestamp)) r,
       count(distinct o.order_id) f,
       sum(price + freight_value) m
           from customers c
               join orders o on c.customer_id = o.customer_id
               join order_items oi on o.order_id = oi.order_id
           where o.order_status = 'delivered'
           group by c.customer_unique_id
           order by m desc),

-- 由于复购率极低，仅3%左右，致使f指标基本失效，采用自定义f 分层用户
rfm_score as(
select uid , r , f , m ,
       ntile(5) over (order by r desc, uid) r_score,
       ntile(5) over (order by m, uid) m_score,
       case
           when f = 1 then 1
           when f = 2 then 4
           when f > 2 then 5 end f_score
from c_rfm
),

flagged as(
select
    uid , r , f , m ,
    case when r_score >= 4 then '高' else '低' end r_level,
    case when f_score >= 4 then '高' else '低' end f_level,
    case when m_score >= 4 then '高' else '低' end m_level
from rfm_score
),

labeled as(
select *,
       case
           when r_level = '高' and f_level = '高' and m_level = '高' then '重要价值客户'
           when r_level = '低' and f_level = '高' and m_level = '高' then '重要保持客户'
           when r_level = '高' and f_level = '低' and m_level = '高' then '重要发展客户'
           when r_level = '低' and f_level = '低' and m_level = '高' then '重要挽留客户'
           when r_level = '高' and f_level = '高' and m_level = '低' then '一般价值客户'
           when r_level = '低' and f_level = '高' and m_level = '低' then '一般保持客户'
           when r_level = '高' and f_level = '低' and m_level = '低' then '一般发展客户'
           else '一般流失客户'
       end as segment
from flagged)

-- 查看rfm分层总览
select segment 用户分层,
       concat(t.r_level, '/', t.f_level, '/', t.m_level) R_F_M,
       users 人数,
       round(users / sum(users) over () * 100, 2) 用户占比,
       round(gmv, 2) GMV,
       round(gmv / sum(gmv) over () * 100,2) GMV占比,
       round(gmv / users, 2) 人均GMV,
       round(avg_r, 2) 平均最近购买天数,
       round(avg_f, 2) 平均订单数
from (
    select
        segment,
        r_level, f_level, m_level,
        count(*) users,
        sum(m) gmv,
        avg(r) avg_r,
        avg(f) avg_f
    from labeled l
    group by  segment, r_level, f_level, m_level
    ) t
order by GMV desc;
