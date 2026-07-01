---
title: SQL 优化实战
date: 2024-05-20 10:00:00
tags: [MySQL, SQL, 性能优化]
categories: 数据库
---

## 1. 发现问题

### 慢查询日志

```sql
-- 开启慢查询日志
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 1;  -- 超过1秒记录
-- 查看慢查询配置
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';
```

### 实时监控

```sql
-- 查看当前运行的查询
SHOW PROCESSLIST;
SHOW FULL PROCESSLIST;
-- 查看状态变量
SHOW STATUS LIKE 'Threads_running';
SHOW STATUS LIKE 'Slow_queries';
```

---

## 2. 分析 SQL — EXPLAIN

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 100;
```

### 关键字段解读：

| 字段 | 关注点 |
| --- | --- |
| type | all → 全表扫描（需优化）；ref/range → 较好；const → 最优 |
| key | 实际使用的索引，NULL = 没走索引 |
| rows | 预估扫描行数，越小越好 |
| Extra | Using filesort / Using temporary → 需优化 |

```sql
-- 更详细的执行计划
EXPLAIN FORMAT=JSON SELECT ...;
-- 实际执行统计（MySQL 8.0+）
EXPLAIN ANALYZE SELECT ...;
```

---

## 3. 索引优化（最高优先级）

### 建索引原则

```sql
-- 为 WHERE / JOIN / ORDER BY / GROUP BY 字段建索引
CREATE INDEX idx_user_created ON orders(user_id, created_at);
-- 覆盖索引：让索引包含所有查询字段，避免回表
CREATE INDEX idx_cover ON orders(user_id, status, amount);
SELECT status, amount FROM orders WHERE user_id = 100;  -- 直接从索引取数据
```

### 常见索引失效场景

```sql
-- ❌ 对索引列做函数运算
WHERE DATE(created_at) = '2024-01-01'
-- ✅ 改为范围查询
WHERE created_at >= '2024-01-01' AND created_at < '2024-01-02'
-- ❌ 隐式类型转换（user_id是int，传了字符串）
WHERE user_id = '100'
-- ❌ LIKE 前缀通配
WHERE name LIKE '%张'
-- ✅ 后缀通配才走索引
WHERE name LIKE '张%'
-- ❌ 联合索引未遵循最左前缀
-- 索引: (a, b, c)
WHERE b = 1 AND c = 2  -- 跳过a，不走索引
```

---

## 4. SQL 语句优化

```sql
-- ❌ SELECT * 避免全字段查询
SELECT * FROM orders WHERE user_id = 100;
-- ✅ 只查需要的字段
SELECT id, status, amount FROM orders WHERE user_id = 100;
-- ❌ 大量数据 IN 查询
WHERE id IN (SELECT user_id FROM black_list)
-- ✅ 改用 EXISTS 或 JOIN
WHERE EXISTS (SELECT 1 FROM black_list WHERE black_list.user_id = orders.user_id)
-- ❌ 深分页（offset大时性能极差）
SELECT * FROM orders LIMIT 1000000, 10;
-- ✅ 游标分页
SELECT * FROM orders WHERE id > 1000000 LIMIT 10;
-- ❌ OR 可能导致索引失效
WHERE user_id = 1 OR shop_id = 2
-- ✅ 改用 UNION ALL
SELECT * FROM orders WHERE user_id = 1
UNION ALL
SELECT * FROM orders WHERE shop_id = 2;
```

---

## 5. 表结构优化

```sql
-- 字段类型选择
-- ✅ 用 INT 而非 VARCHAR 做主键
-- ✅ 状态字段用 TINYINT 而非 VARCHAR
-- ✅ 金额用 DECIMAL(10,2) 而非 FLOAT（精度问题）
-- ✅ 时间用 DATETIME 或 TIMESTAMP，而非字符串
-- 大表按时间/范围分区
ALTER TABLE orders PARTITION BY RANGE (YEAR(created_at)) (
PARTITION p2023 VALUES LESS THAN (2024),
PARTITION p2024 VALUES LESS THAN (2025),
PARTITION p_future VALUES LESS THAN MAXVALUE
);
```

---

## 6. 配置参数调优

my.cnf 关键参数

InnoDB 缓冲池（设为物理内存的 60%~80%）

innodb_buffer_pool_size = 8G

连接数

max_connections = 500
thread_cache_size = 50

查询缓存（MySQL 8.0 已移除，不建议开）

query_cache_type = 0

慢查询

slow_query_log = 1
long_query_time = 1

---

## 7. 架构层面优化

### 单机瓶颈 → 分层处理

读多写少
├── 主从复制 → 读写分离（写主库，读从库）
└── 加缓存层（Redis）缓存热点数据

数据量大
├── 分库分表（ShardingSphere / MyCat）
└── 冷热数据分离（归档历史数据）

连接数瓶颈
└── 连接池（Druid / HikariCP）

---

## 优化优先级总结

1️⃣   索引优化          ← 收益最大，首先做
2️⃣   SQL 语句改写      ← 消除全表扫描、回表
3️⃣   表结构设计        ← 字段类型、分区
4️⃣   配置参数调整      ← buffer pool等
5️⃣   架构升级          ← 读写分离、分库分表（成本最高）

💡 黄金法则：先用 EXPLAIN 找出慢的原因，再针对性优化，而不是盲目加索引或改配置。

## 覆盖索引是什么意思

### 覆盖索引（Covering Index）

### 核心概念

覆盖索引：查询所需的所有字段都能从索引中直接获取，不需要回表查询原始数据行。

---

### 理解"回表"

先理解 InnoDB 的存储结构：

主键索引（聚簇索引）
├── 叶子节点存储的是：完整的数据行
└── 通过主键可以直接拿到所有字段

普通索引（二级索引）
├── 叶子节点存储的是：索引字段值 + 主键ID
└── 拿到主键ID后，还要再去主键索引查一次 → 这就是"回表"

---

### 图示对比

#### 普通查询（需要回表）

索引: idx_user_id(user_id)

```text
SQL:  SELECT id, status, amount FROM orders WHERE user_id = 100;
```
执行过程：
user_id 索引树
└─→ 找到 user_id=100 的行，拿到主键 id=5,8,12...
↓  回表！
主键索引树
└─→ 用 id=5 查完整行，取出 status, amount
└─→ 用 id=8 查完整行，取出 status, amount
└─→ ...  （每条记录都要回表一次）

#### 覆盖索引（不回表）

索引: idx_cover(user_id, status, amount)

```text
SQL:  SELECT id, status, amount FROM orders WHERE user_id = 100;
```
执行过程：
(user_id, status, amount) 索引树
└─→ 找到 user_id=100 的所有记录
└─→ 索引叶子节点上已经有 status、amount 的值
└─→ 直接返回！不需要再查主键索引 ✅

---

### EXPLAIN 怎么判断走了覆盖索引

```sql
EXPLAIN SELECT id, status, amount FROM orders WHERE user_id = 100;
```
看 Extra 列：

| Extra 值 | 含义 |
| --- | --- |
| Using index | ✅ 走了覆盖索引，不需要回表 |
| Using index condition | 部分覆盖，还有回表 |
| 空 / Using where | ❌ 没有覆盖，需要回表 |

---
实际例子

```sql
-- 表结构
CREATE TABLE orders (
    id      BIGINT PRIMARY KEY,
    user_id INT,
    status  TINYINT,
    amount  DECIMAL(10,2),
    remark  TEXT,          -- 大字段
    ...
);

-- 建覆盖索引（把查询需要的字段都放进去）
CREATE INDEX idx_cover ON orders(user_id, status, amount);
-- ✅ 走覆盖索引（查的字段都在索引里）
SELECT id, status, amount FROM orders WHERE user_id = 100;
-- ❌ 不走覆盖索引（remark 不在索引里，必须回表）
SELECT id, status, amount, remark FROM orders WHERE user_id = 100;
```
注意：id（主键）不需要加到索引里，因为二级索引的叶子节点天然存了主键值。

---
适合用覆盖索引的场景

```sql
-- 场景1：列表页只展示部分字段（很常见）
SELECT id, title, price FROM product WHERE category_id = 10 ORDER BY created_at DESC;
-- 建索引：(category_id, created_at, title, price)

-- 场景2：统计计数
SELECT COUNT(*) FROM orders WHERE user_id = 100 AND status = 1;
-- 建索引：(user_id, status)  → COUNT 不需要回表

-- 场景3：分页查询（先用覆盖索引拿 ID，再 JOIN 取完整数据）
SELECT o.*
FROM orders o
INNER JOIN (
    SELECT id FROM orders WHERE user_id = 100 LIMIT 100000, 10
) tmp ON o.id = tmp.id;
-- 子查询走覆盖索引，只取 10 个 ID 再回表，性能大幅提升
```

---
注意事项

✅ 优点
- 减少 IO（不用读数据页，只读索引页）
- 索引文件比数据文件小，更容易缓存在内存中
- 对大表、高频查询效果显著

⚠️ 缺点
- 索引字段越多 → 索引越大 → 写入时维护成本越高
- 不要为了覆盖索引把所有字段都加进去（那还不如全表扫描）
- 适合：查询频繁 + 字段固定 + 数据量大 的场景

---
一句话总结

覆盖索引 = 查询需要什么字段，索引里就有什么字段，不用再去数据行取数据，省掉了"回表"这一步。

## EXPLAIN 中的 filtered 字段详解

### 基本含义

filtered 是一个百分比值（0~100），表示：

经过 WHERE 条件过滤后，预计保留的行数占 rows 的百分比

实际参与后续处理的行数 ≈ rows × (filtered / 100)

---
举例说明

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 100 AND status = 1;

+----+-------+------+------+---------+------+----------+-------------+
| id | type  | key  | rows | filtered | Extra                        |
+----+-------+------+------+----------+------------------------------+
|  1 | ref   | idx_user_id | 1000 | 10.00 | Using where         |
+----+-------+------+------+----------+------------------------------+
```

解读：
- rows = 1000：索引扫描预估 1000 行（user_id = 100 的行）
- filtered = 10.00：经过 status = 1 过滤后，预计只保留 100 行
- 实际处理行数 = 1000 × 10% = 100 行

---
### filtered 值的高低说明什么

filtered 值     含义
─────────────────────────────────────────────────────
100%          WHERE 条件全部由索引完成，无需额外过滤
→ 最理想，索引精准命中

50%           索引扫描的行中有一半被过滤掉
→ 还算OK

10% 以下      索引扫描了很多行，但大部分被 WHERE 丢掉
→ 说明过滤条件没有走索引，效率低

接近 0%       几乎扫描的所有行都被过滤掉
→ 严重浪费，需要优化

---
### 结合具体场景理解

场景1：filtered = 100%（最优）

```sql
-- 索引: (user_id, status)
SELECT * FROM orders WHERE user_id = 100 AND status = 1;
-- rows=50, filtered=100.00
-- 说明：联合索引同时过滤了两个条件，索引扫描的50行全部保留
```
场景2：filtered 低（需优化）

```sql
-- 索引: idx_user_id(user_id)  -- 只有user_id的索引
SELECT * FROM orders WHERE user_id = 100 AND status = 1;
-- rows=1000, filtered=10.00
-- 说明：
--   索引只能过滤 user_id，扫了1000行
--   status=1 的条件只能在内存里逐行过滤（Using where）
--   1000行里只有10%是status=1的 → 浪费了900次IO
```
优化方案：把 status 加入联合索引

```sql
-- 建联合索引后
CREATE INDEX idx_user_status ON orders(user_id, status);
-- rows=100, filtered=100.00  ← 直接精准
```

---
### filtered 在 JOIN 中更关键

```sql
EXPLAIN SELECT * FROM orders o JOIN users u ON o.user_id = u.id
WHERE o.status = 1;

+----+-------+--------+-------+----------+
| id | table | type   | rows  | filtered |
+----+-------+--------+-------+----------+
```
|  1 | o     | ALL    | 10000 |   10.00  |  ← 驱动表
|  1 | u     | eq_ref | 1     |  100.00  |  ← 被驱动表
+----+-------+--------+-------+----------+

- 驱动表 o：扫描 10000 行，过滤后剩 1000 行（10000 × 10%）
- 被驱动表 u：要执行 1000 次关联查询
- filtered 越低 → JOIN 次数越多 → 性能越差

MySQL 优化器会根据 rows × filtered 的结果来决定 JOIN 顺序，选择结果集小的表作为驱动表。

---
### filtered 不准确的情况

filtered 是估算值，依赖统计信息，可能不准：

```sql
-- 强制重新收集统计信息
ANALYZE TABLE orders;
```

```sql
-- 查看统计信息
SHOW TABLE STATUS LIKE 'orders';
```
场景                          filtered 可能失真
──────────────────────────────────────────────
数据分布极度不均匀              估算偏差大
统计信息过期（大量增删改后）    需要 ANALYZE TABLE
使用了函数/表达式              优化器难以估算

---
### 总结

filtered 的作用：
┌─────────────────────────────────────────────────┐
│  衡量 WHERE 条件"被索引承担了多少"               │
│                                                  │
│  filtered 高（→100%）                            │
│    索引精准，过滤效率高，几乎没有浪费             │
│                                                  │
│  filtered 低（→0%）                              │
│    索引扫了很多行，大部分被 WHERE 丢掉            │
│    → 考虑把过滤字段加入联合索引                  │
└─────────────────────────────────────────────────┘

优化目标：让 rows × (filtered/100) 尽可能小
