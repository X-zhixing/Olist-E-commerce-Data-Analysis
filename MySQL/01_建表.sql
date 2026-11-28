-- ---------------------------创建数据库----------------------------------
show databases;
create database olist;
use olist;

-- -----------------------------创建表------------------------------------
-- 客户表
CREATE TABLE customers (
    customer_id VARCHAR(32) PRIMARY KEY,
    customer_unique_id VARCHAR(32),
    customer_zip_code_prefix INT,
    customer_city VARCHAR(50),
    customer_state CHAR(2)
);

-- 订单表
CREATE TABLE orders (
    order_id VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(32),
    order_status VARCHAR(20),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- 订单明细表
CREATE TABLE order_items (
    order_id VARCHAR(32),
    order_item_id INT,
    product_id VARCHAR(32),
    seller_id VARCHAR(32),
    shipping_limit_date DATETIME,
    price DECIMAL(10,2),
    freight_value DECIMAL(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

-- 商品表
CREATE TABLE products (
  product_id VARCHAR(32) PRIMARY KEY,
  product_category_name VARCHAR(100),
  product_name_lenght INT,
  product_description_lenght INT,
  product_photos_qty INT,
  product_weight_g INT,
  product_length_cm INT,
  product_height_cm INT,
  product_width_cm INT
);

-- 卖家表
CREATE TABLE sellers (
    seller_id VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix INT,
    seller_city VARCHAR(50),
    seller_state CHAR(2)
);

-- 支付表
CREATE TABLE payments (
    order_id VARCHAR(32),
    payment_sequential INT,
    payment_type VARCHAR(20),
    payment_installments INT,
    payment_value DECIMAL(10,2)
);

-- 评价表
CREATE TABLE reviews (
  review_id VARCHAR(32),
  order_id VARCHAR(32),
  review_score INT,
  review_comment_title TEXT,
  review_comment_message TEXT,
  review_creation_date DATETIME,
  review_answer_timestamp DATETIME,
  INDEX idx_order (order_id),
  INDEX idx_review (review_id)
);


-- 类目翻译表
CREATE TABLE category_translation (
    product_category_name VARCHAR(50) PRIMARY KEY,
    product_category_name_english VARCHAR(50)
);

-- 地理维度表
CREATE TABLE olist_geolocation (
  geolocation_zip_code_prefix VARCHAR(5) NOT NULL, -- 邮编前缀，用VARCHAR防止前导零丢失
  geolocation_lat DECIMAL(10, 6) NOT NULL,         -- 纬度
  geolocation_lng DECIMAL(10, 6) NOT NULL,         -- 经度
  geolocation_city VARCHAR(100) NOT NULL,          -- 城市
  geolocation_state CHAR(2) NOT NULL,              -- 州 (如 SP, RJ)
  INDEX idx_zip (geolocation_zip_code_prefix),     -- 高频关联字段建索引
  INDEX idx_state (geolocation_state)
);

-- ---------------------------------数据导入--------------------------------------
set global local_infile = 1;
show global variables like 'local_infile';

-- customers
load data local infile 'C:/Users/24253/Desktop/练习项目/Olist数据分析/原表/olist_customers_dataset.csv'
into table customers
fields terminated by ','
optionally enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

-- "C:\Users\24253\Desktop\olist_orders_dataset.csv"
load data local infile 'C:/Users/24253/Desktop/olist_orders_dataset.csv'
into table orders
fields terminated by ','
optionally enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

-- "C:\Users\24253\Desktop\练习项目\Olist数据分析\原表\olist_order_items_dataset.csv"
load data local infile 'C:/Users/24253/Desktop/练习项目/Olist数据分析/原表/olist_order_items_dataset.csv'
into table order_items
fields terminated by ','
lines terminated by '\n'
ignore 1 rows ;

-- "C:\Users\24253\Desktop\练习项目\archive\olist_products_dataset.csv"
load data local infile 'C:/Users/24253/Desktop/练习项目/Olist数据分析/olist_products_dataset.csv'
into table products
fields terminated by ','
lines terminated by '\n'
ignore 1 rows;

-- olist_sellers_dataset.csv
load data local infile 'C:/Users/24253/Desktop/练习项目/Olist数据分析/原表/olist_sellers_dataset.csv'
into table sellers
fields terminated by ','
optionally enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

-- "C:\Users\24253\Desktop\练习项目\archive\olist_order_payments_dataset.csv"
load data local infile 'C:/Users/24253/Desktop/olist_order_payments_dataset.csv'
into table payments
fields terminated by ','
optionally enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

-- "C:\Users\24253\Desktop\练习项目\Olist数据分析\原表\olist_order_reviews_dataset.csv"
load data local infile 'C:/Users/24253/Desktop/练习项目/Olist数据分析/原表/olist_order_reviews_dataset.csv'
into table reviews
fields terminated by ','
optionally enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

-- "C:\Users\24253\Desktop\练习项目\archive\product_category_name_translation.csv"
load data local infile 'C:/Users/24253/Desktop/练习项目/archive/product_category_name_translation.csv'
into table category_translation
fields terminated by ','
lines terminated by '\n'
ignore 1 rows;

-- "C:\Users\24253\Desktop\练习项目\Olist数据分析\原表\olist_geolocation_dataset.csv"
load data local infile 'C:/Users/24253/Desktop/练习项目/Olist数据分析/原表/olist_geolocation_dataset.csv'
into table olist_geolocation
fields terminated by ','
optionally enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

-- -----------------------------数据预处理--------------------------------
-- 1.检查订单表中配送时间的缺失情况(pandas处理)
select count(*) total_cnt ,
       sum(case when order_approved_at is null then 1 else 0 end) approve_at,
       sum(case when order_estimated_delivery_date is null then 1 else 0 end) est_date
from orders;


-- ===============================索引优化=========================================
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_purchase ON orders(order_purchase_timestamp);
CREATE INDEX idx_orders_status ON orders(order_status);
CREATE INDEX idx_items_product ON order_items(product_id);
CREATE INDEX idx_items_seller ON order_items(seller_id);
CREATE INDEX idx_customers_unique ON customers(customer_unique_id);