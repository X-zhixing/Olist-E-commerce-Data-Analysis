-- -----------------------------供给侧--------------------------------
# 1.卖家评分分析
# 一单多评取最迟
drop temporary table if exists sellers_segment;
create temporary table sellers_segment as
with last_reviews as (
    select order_id, review_score from(
            select order_id, review_score,
                   row_number() over (partition by order_id order by review_creation_date desc , review_answer_timestamp desc) rn
            from reviews ) t
    where rn = 1
),

# 商品聚合
order_base as (
    select o.order_id, oi.seller_id, sum(oi.price + oi.freight_value) gmv,
           max(case when date(order_delivered_customer_date) > date(order_estimated_delivery_date) then 1 else 0 end) late
    from orders o
    join order_items oi on o.order_id = oi.order_id
    where order_status = 'delivered'
    group by o.order_id, oi.seller_id
),

sellers as(
select s.seller_id, s.seller_state,  sum(ob.gmv) GMV,
       -- 基于有评价订单指标
       count(distinct case when lr.review_score is not null then ob.order_id end) as 有评价订单数,
       round(avg(lr.review_score),2) 平均评分,
       sum(if(lr.review_score <= 2, 1, 0)) 有评价差评订单数,
       round(sum(if(lr.review_score <= 2, 1, 0)) / nullif(count(lr.review_score), 0) * 100,2) 差评率,
       -- 基于所有订单指标
       count(distinct ob.order_id) 总订单数, sum(late) 延迟订单数, round(avg(late) * 100,2) 延迟占比
from sellers s
join order_base ob on ob.seller_id = s.seller_id
left join last_reviews lr on lr.order_id = ob.order_id
group by s.seller_id
# having count(distinct ob.order_id) >= 20
order by 平均评分, 差评率 desc, 延迟占比 desc
)
-- 卖家分层
select *,
       case
           when 总订单数 >= 20 and 平均评分 >= 4 and 延迟占比 < 8 and 差评率 < 12 then '明星卖家'
           when 总订单数 >= 20 and (平均评分 < 3.5 or 延迟占比 > 20 or 差评率 > 20) then '问题卖家'
           when 总订单数 < 20 then '长尾卖家'
           else '常规卖家' end 卖家分层
from sellers;

-- ① 汇总
select
    卖家分层, count(*) 数量,
    round(sum(GMV), 2) GMV, round(sum(GMV)/ sum(sum(GMV)) over() * 100, 2) GMV占比
from sellers_segment
group by 卖家分层;

-- ② 精细化处理
drop temporary table if exists seller_action;
create temporary table seller_action as
with ranked as (
    select *,
           case
               when percent_rank() over (order by GMV) > 0.5 then '大' else '小' end 规模
    from sellers_segment
    where 总订单数 >= 20
)
select *,
    case
        when 卖家分层 = '明星卖家' and 规模 = '大' then '资源倾斜（金牌卖家）'
        when 卖家分层 = '明星卖家' and 规模 = '小' then '扶持培育（银牌卖家）'
        when 卖家分层 = '常规卖家' and 规模 = '大' then '定向改善（最大盘，占 34.6% GMV）'
        when 卖家分层 = '常规卖家' and 规模 = '小' then '自动化管理'
        when 卖家分层 = '问题卖家' and 规模 = '大' then '限期整改（占 7.6% GMV，不可直接清退）'
        when 卖家分层 = '问题卖家' and 规模 = '小' then '降权或清退（仅占 1.5% GMV）'
        else '引导合并或自然淘汰' end 建议动作
from ranked;

-- 精细化汇总
select
    count(*) 卖家数, sum(总订单数) 订单数, round(avg(平均评分), 2) 平均评分,
    sum(GMV) GMV, round(sum(GMV) / (select sum(GMV) from sellers_segment) * 100, 2) GMV占比,
    建议动作
from seller_action
group by 建议动作
order by GMV desc;

-- ③ 长尾卖家汇总
select
    count(*)                                                        as 长尾卖家数,
    round(sum(gmv), 2)                                              as gmv,
    round(sum(gmv) / (select sum(gmv) from tmp_seller_base) * 100, 2) as gmv占比,
    round(sum(gmv) / count(*), 0)                                   as 人均gmv
from tmp_seller_base
where not (orders >= 20 and reviewed >= 5);

-- ---------------------------------FineBI可视化数据处理---------------------------------------
-- 地理坐标计算
select geolocation_state, avg(geolocation_lat) lat, avg(geolocation_lng) lng
from olist_geolocation og
group by geolocation_state;
