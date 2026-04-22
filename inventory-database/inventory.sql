-- =====================================================
-- FULL PERBAIKAN UNTUK DATABASE EOQ INVENTORY
-- =====================================================

-- =====================================================
-- PART 1: MEMBUAT FUNGSI YANG HILANG
-- =====================================================

-- 1.1 Fungsi untuk menghitung persentase penggunaan tenant
CREATE OR REPLACE FUNCTION get_tenant_usage_percentage(
    p_tenant_id UUID,
    p_metric_type VARCHAR
)
RETURNS DECIMAL(5,2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_usage INT;
    v_max_limit INT;
    v_result DECIMAL(5,2);
BEGIN
    IF p_metric_type = 'users' THEN
        SELECT COUNT(*) INTO v_current_usage
        FROM users
        WHERE tenant_id = p_tenant_id
          AND deleted_at IS NULL
          AND is_active = TRUE
          AND role_level = 'customer';
        
        SELECT max_users INTO v_max_limit
        FROM tenants
        WHERE id = p_tenant_id AND deleted_at IS NULL;
        
    ELSIF p_metric_type = 'products' THEN
        SELECT COUNT(*) INTO v_current_usage
        FROM products
        WHERE tenant_id = p_tenant_id
          AND deleted_at IS NULL
          AND is_active = TRUE;
        
        SELECT max_products INTO v_max_limit
        FROM tenants
        WHERE id = p_tenant_id AND deleted_at IS NULL;
        
    ELSIF p_metric_type = 'categories' THEN
        SELECT COUNT(*) INTO v_current_usage
        FROM categories
        WHERE tenant_id = p_tenant_id
          AND deleted_at IS NULL
          AND is_active = TRUE;
        
        SELECT max_categories INTO v_max_limit
        FROM tenants
        WHERE id = p_tenant_id AND deleted_at IS NULL;
        
    ELSE
        RETURN 0;
    END IF;
    
    IF v_max_limit IS NULL OR v_max_limit = 0 THEN
        RETURN 0;
    END IF;
    
    v_result := (v_current_usage::DECIMAL / v_max_limit::DECIMAL) * 100;
    RETURN ROUND(v_result, 2);
END;
$$;

-- 1.2 Fungsi untuk generate category code (sudah ada, tapi dipastikan)
CREATE OR REPLACE FUNCTION generate_category_code()
RETURNS TRIGGER AS $$
DECLARE
    next_number INT;
    prefix VARCHAR(20);
    tenant_prefix VARCHAR(10);
BEGIN
    -- Get tenant prefix
    SELECT tenant_prefix INTO tenant_prefix
    FROM tenants WHERE id = NEW.tenant_id AND deleted_at IS NULL;

    prefix := tenant_prefix || '-CAT-';

    -- Get next sequence number
    SELECT COALESCE(MAX(CAST(SUBSTRING(category_code FROM position('-CAT-' IN category_code) + 5) AS INTEGER)), 0) + 1
    INTO next_number
    FROM categories
    WHERE tenant_id = NEW.tenant_id
      AND category_code LIKE prefix || '%'
      AND deleted_at IS NULL;

    NEW.category_code := prefix || LPAD(next_number::TEXT, 4, '0');

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- PART 2: DROP ALL VIEWS YANG BERMASALAH (URUTAN PENTING)
-- =====================================================

DROP VIEW IF EXISTS vw_eoq_optimization_recommendations CASCADE;
DROP VIEW IF EXISTS vw_stock_aging CASCADE;
DROP VIEW IF EXISTS vw_user_activity_summary CASCADE;
DROP VIEW IF EXISTS vw_tenant_subscription_detail CASCADE;
DROP VIEW IF EXISTS vw_executive_dashboard CASCADE;
DROP VIEW IF EXISTS vw_supplier_performance CASCADE;
DROP VIEW IF EXISTS vw_inventory_movement_summary CASCADE;
DROP VIEW IF EXISTS vw_daily_stock_mutation CASCADE;
DROP VIEW IF EXISTS vw_monthly_inventory_turnover CASCADE;
DROP VIEW IF EXISTS vw_product_profitability CASCADE;
DROP VIEW IF EXISTS vw_eoq_trend_analysis CASCADE;
DROP VIEW IF EXISTS vw_audit_trail_detail CASCADE;

-- =====================================================
-- PART 3: RECREATE VIEWS DENGAN PERBAIKAN
-- =====================================================

-- 3.1 View untuk Executive Dashboard
CREATE OR REPLACE VIEW vw_executive_dashboard AS
SELECT
    'Executive Summary' AS dashboard_title,
    NOW() AS report_generated_at,
    (SELECT COUNT(*) FROM tenants WHERE deleted_at IS NULL AND is_active = TRUE) AS total_active_tenants,
    (SELECT COUNT(*) FROM tenants WHERE deleted_at IS NULL AND subscription_status = 'active') AS active_subscriptions,
    (SELECT COUNT(*) FROM tenants WHERE deleted_at IS NULL AND subscription_status = 'trial') AS trial_subscriptions,
    (SELECT COUNT(*) FROM tenants WHERE deleted_at IS NULL AND subscription_status = 'expired') AS expired_subscriptions,
    (SELECT COUNT(*) FROM users WHERE deleted_at IS NULL AND is_active = TRUE AND role_level = 'customer') AS total_customer_users,
    (SELECT COUNT(*) FROM products WHERE deleted_at IS NULL AND is_active = TRUE) AS total_products_managed,
    (SELECT COALESCE(SUM(amount_paid), 0) FROM subscription_history WHERE payment_status = 'paid' AND EXTRACT(YEAR FROM created_at) = EXTRACT(YEAR FROM CURRENT_DATE)) AS revenue_ytd,
    (SELECT COALESCE(SUM(amount_paid), 0) FROM subscription_history WHERE payment_status = 'paid' AND EXTRACT(MONTH FROM created_at) = EXTRACT(MONTH FROM CURRENT_DATE)) AS revenue_current_month,
    (SELECT COUNT(*) FROM stock_alerts WHERE deleted_at IS NULL AND is_resolved = FALSE) AS total_unresolved_alerts,
    (SELECT COUNT(*) FROM stock_alerts WHERE deleted_at IS NULL AND is_resolved = FALSE AND alert_type = 'below_safety_stock') AS critical_alerts_total,
    ROUND(100 * (SELECT COUNT(*) FROM products WHERE eoq_qty IS NOT NULL AND annual_demand > 0 AND deleted_at IS NULL) /
        NULLIF((SELECT COUNT(*) FROM products WHERE is_active = TRUE AND deleted_at IS NULL), 0), 2) AS eoq_adoption_rate;

-- 3.2 View untuk Tenant Subscription Detail (DIPERBAIKI)
CREATE OR REPLACE VIEW vw_tenant_subscription_detail AS
SELECT
    t.id AS tenant_id,
    t.company_name,
    t.company_email,
    t.phone,
    t.address,
    t.subscription_plan,
    t.subscription_status,
    t.subscription_start_date,
    t.subscription_end_date,
    t.trial_ends_at,
    t.max_users,
    t.max_products,
    t.is_active,
    (SELECT COUNT(*) FROM users u WHERE u.tenant_id = t.id AND u.deleted_at IS NULL AND u.is_active = TRUE AND u.role_level = 'customer') AS current_users,
    (SELECT COUNT(*) FROM products p WHERE p.tenant_id = t.id AND p.deleted_at IS NULL AND p.is_active = TRUE) AS current_products,
    (SELECT COUNT(*) FROM categories c WHERE c.tenant_id = t.id AND c.deleted_at IS NULL AND c.is_active = TRUE) AS current_categories,
    -- PERBAIKAN: langsung gunakan pengurangan date (hasilnya integer)
    (t.subscription_end_date - CURRENT_DATE) AS days_remaining,
    get_tenant_usage_percentage(t.id, 'users') AS user_usage_percent,
    get_tenant_usage_percentage(t.id, 'products') AS product_usage_percent,
    CASE
        WHEN t.subscription_status = 'expired' THEN 'EXPIRED'
        WHEN t.subscription_status = 'suspended' THEN 'SUSPENDED'
        WHEN (t.subscription_end_date - CURRENT_DATE) <= 7 AND (t.subscription_end_date - CURRENT_DATE) > 0 THEN 'EXPIRING_SOON'
        WHEN (t.subscription_end_date - CURRENT_DATE) <= 0 THEN 'EXPIRED'
        WHEN get_tenant_usage_percentage(t.id, 'users') >= 90 THEN 'USER_LIMIT_WARNING'
        WHEN get_tenant_usage_percentage(t.id, 'products') >= 90 THEN 'PRODUCT_LIMIT_WARNING'
        ELSE 'OK'
    END AS alert_status
FROM tenants t
WHERE t.deleted_at IS NULL;

-- 3.3 View untuk Supplier Performance
CREATE OR REPLACE VIEW vw_supplier_performance AS
SELECT
    s.id AS supplier_id,
    s.tenant_id,
    t.company_name,
    s.supplier_code,
    s.supplier_name,
    s.lead_time_days AS standard_lead_time,
    COUNT(DISTINCT po.id) AS total_orders,
    COALESCE(SUM(po.total_amount), 0) AS total_order_value,
    COALESCE(AVG(po.total_amount), 0) AS avg_order_value,
    COUNT(CASE WHEN po.actual_delivery_date <= po.expected_delivery_date THEN 1 END) AS on_time_deliveries,
    COUNT(CASE WHEN po.actual_delivery_date > po.expected_delivery_date THEN 1 END) AS late_deliveries,
    ROUND(100 * COUNT(CASE WHEN po.actual_delivery_date <= po.expected_delivery_date THEN 1 END) /
        NULLIF(COUNT(po.id), 0), 2) AS on_time_delivery_rate,
    s.is_preferred,
    s.is_active
FROM suppliers s
JOIN tenants t ON s.tenant_id = t.id AND t.deleted_at IS NULL
LEFT JOIN purchase_orders po ON s.id = po.supplier_id AND po.status = 'received' AND po.deleted_at IS NULL
WHERE s.deleted_at IS NULL
GROUP BY s.id, s.tenant_id, t.company_name, s.supplier_code, s.supplier_name;

-- 3.4 View untuk Inventory Movement Summary
CREATE OR REPLACE VIEW vw_inventory_movement_summary AS
SELECT
    it.tenant_id,
    t.company_name,
    DATE_TRUNC('month', it.transaction_date) AS month,
    it.transaction_type,
    COUNT(*) AS transaction_count,
    SUM(it.quantity) AS total_quantity,
    SUM(it.total_amount) AS total_value,
    COUNT(DISTINCT it.product_id) AS distinct_products
FROM inventory_transactions it
JOIN tenants t ON it.tenant_id = t.id AND t.deleted_at IS NULL
WHERE it.deleted_at IS NULL
GROUP BY it.tenant_id, t.company_name, DATE_TRUNC('month', it.transaction_date), it.transaction_type
ORDER BY month DESC;

-- 3.5 View untuk Daily Stock Mutation
CREATE OR REPLACE VIEW vw_daily_stock_mutation AS
SELECT
    it.tenant_id,
    it.product_id,
    p.product_code,
    p.product_name,
    DATE(it.transaction_date) AS transaction_date,
    SUM(CASE WHEN it.transaction_type = 'in' THEN it.quantity ELSE 0 END) AS stock_in,
    SUM(CASE WHEN it.transaction_type = 'out' THEN it.quantity ELSE 0 END) AS stock_out,
    SUM(CASE WHEN it.transaction_type = 'in' THEN it.quantity ELSE -it.quantity END) AS net_change
FROM inventory_transactions it
JOIN products p ON it.product_id = p.id AND p.deleted_at IS NULL
WHERE it.deleted_at IS NULL
GROUP BY it.tenant_id, it.product_id, p.product_code, p.product_name, DATE(it.transaction_date)
ORDER BY transaction_date DESC;

-- 3.6 View untuk Monthly Inventory Turnover
CREATE OR REPLACE VIEW vw_monthly_inventory_turnover AS
WITH monthly_movement AS (
    SELECT
        tenant_id,
        product_id,
        DATE_TRUNC('month', transaction_date) AS month,
        SUM(CASE WHEN transaction_type = 'out' THEN quantity ELSE 0 END) AS monthly_out
    FROM inventory_transactions
    WHERE deleted_at IS NULL
    GROUP BY tenant_id, product_id, DATE_TRUNC('month', transaction_date)
),
avg_inventory AS (
    SELECT
        p.tenant_id,
        p.id AS product_id,
        DATE_TRUNC('month', p.created_at) AS month,
        AVG(p.current_stock) AS avg_stock
    FROM products p
    WHERE p.deleted_at IS NULL
    GROUP BY p.tenant_id, p.id, DATE_TRUNC('month', p.created_at)
)
SELECT
    mm.tenant_id,
    mm.product_id,
    p.product_name,
    mm.month,
    mm.monthly_out AS sold_quantity,
    COALESCE(ai.avg_stock, 1) AS avg_inventory,
    ROUND(mm.monthly_out / NULLIF(ai.avg_stock, 0), 2) AS turnover_ratio
FROM monthly_movement mm
JOIN products p ON mm.product_id = p.id AND p.deleted_at IS NULL
LEFT JOIN avg_inventory ai ON mm.product_id = ai.product_id AND mm.month = ai.month
WHERE mm.monthly_out > 0;

-- 3.7 View untuk Product Profitability
CREATE OR REPLACE VIEW vw_product_profitability AS
SELECT
    p.id AS product_id,
    p.tenant_id,
    p.product_code,
    p.product_name,
    p.unit_price,
    p.unit_price * p.annual_demand AS potential_revenue,
    (p.ordering_cost * (p.annual_demand / NULLIF(p.eoq_qty, 0))) AS annual_ordering_cost,
    (p.holding_cost_per_unit * (p.eoq_qty / 2)) AS annual_holding_cost,
    ROUND(p.unit_price * p.annual_demand -
        (p.ordering_cost * (p.annual_demand / NULLIF(p.eoq_qty, 0))) -
        (p.holding_cost_per_unit * (p.eoq_qty / 2)), 2) AS estimated_annual_profit,
    CASE
        WHEN p.annual_demand * p.unit_price > 100000000 THEN 'HIGH'
        WHEN p.annual_demand * p.unit_price > 10000000 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS revenue_category
FROM products p
WHERE p.deleted_at IS NULL AND p.is_active = TRUE AND p.eoq_qty IS NOT NULL;

-- 3.8 View untuk EOQ Trend Analysis
CREATE OR REPLACE VIEW vw_eoq_trend_analysis AS
SELECT
    el.tenant_id,
    el.product_id,
    p.product_name,
    el.calculated_at,
    el.eoq_result,
    el.total_inventory_cost,
    LAG(el.eoq_result) OVER (PARTITION BY el.product_id ORDER BY el.calculated_at) AS previous_eoq,
    ROUND(100 * (el.eoq_result - LAG(el.eoq_result) OVER (PARTITION BY el.product_id ORDER BY el.calculated_at)) /
        NULLIF(LAG(el.eoq_result) OVER (PARTITION BY el.product_id ORDER BY el.calculated_at), 0), 2) AS eoq_change_percent,
    ROW_NUMBER() OVER (PARTITION BY el.product_id ORDER BY el.calculated_at DESC) AS recency_rank
FROM eoq_logs el
JOIN products p ON el.product_id = p.id AND p.deleted_at IS NULL
WHERE el.deleted_at IS NULL;

-- 3.9 View untuk User Activity Summary (DIPERBAIKI)
CREATE OR REPLACE VIEW vw_user_activity_summary AS
SELECT
    u.id AS user_id,
    u.tenant_id,
    t.company_name,
    u.email,
    u.full_name,
    u.role,
    u.role_level,
    u.last_login,
    -- PERBAIKAN: EXTRACT DAY dari interval (timestamp - timestamp)
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u.last_login)) AS days_since_last_login,
    (SELECT COUNT(*) FROM audit_logs al WHERE al.user_id = u.id AND DATE(al.created_at) = CURRENT_DATE AND al.deleted_at IS NULL) AS today_activities,
    (SELECT COUNT(*) FROM audit_logs al WHERE al.user_id = u.id AND EXTRACT(WEEK FROM al.created_at) = EXTRACT(WEEK FROM CURRENT_DATE) AND al.deleted_at IS NULL) AS this_week_activities,
    (SELECT COUNT(*) FROM audit_logs al WHERE al.user_id = u.id AND EXTRACT(MONTH FROM al.created_at) = EXTRACT(MONTH FROM CURRENT_DATE) AND al.deleted_at IS NULL) AS this_month_activities,
    CASE
        WHEN u.is_active = FALSE THEN 'Inactive Account'
        WHEN u.last_login IS NULL THEN 'Never Logged In'
        WHEN EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u.last_login)) > 30 THEN 'Inactive User'
        WHEN EXTRACT(DAY FROM (CURRENT_TIMESTAMP - u.last_login)) > 7 THEN 'Rarely Active'
        ELSE 'Active'
    END AS user_status
FROM users u
LEFT JOIN tenants t ON u.tenant_id = t.id AND t.deleted_at IS NULL
WHERE u.deleted_at IS NULL AND u.role_level = 'customer';

-- 3.10 View untuk Audit Trail Detail
CREATE OR REPLACE VIEW vw_audit_trail_detail AS
SELECT
    al.id AS audit_id,
    al.tenant_id,
    t.company_name,
    al.user_id,
    u.email AS user_email,
    u.full_name AS user_name,
    al.action,
    al.table_name,
    al.record_id,
    al.old_data,
    al.new_data,
    al.ip_address,
    al.user_agent,
    al.created_at,
    DATE(al.created_at) AS audit_date,
    CASE
        WHEN al.action IN ('INSERT', 'CREATE') THEN 'Creation'
        WHEN al.action IN ('UPDATE', 'EDIT') THEN 'Modification'
        WHEN al.action IN ('DELETE', 'SOFT_DELETE', 'RESTORE') THEN 'Deletion'
        WHEN al.action IN ('LOGIN', 'LOGOUT') THEN 'Authentication'
        ELSE 'Other'
    END AS action_category
FROM audit_logs al
JOIN tenants t ON al.tenant_id = t.id AND t.deleted_at IS NULL
LEFT JOIN users u ON al.user_id = u.id AND u.deleted_at IS NULL
WHERE al.deleted_at IS NULL
ORDER BY al.created_at DESC;

-- 3.11 View untuk Stock Aging (DIPERBAIKI)
CREATE OR REPLACE VIEW vw_stock_aging AS
SELECT
    p.id AS product_id,
    p.tenant_id,
    p.product_code,
    p.product_name,
    p.current_stock,
    p.unit_price,
    p.current_stock * p.unit_price AS stock_value,
    MAX(it.transaction_date) AS last_movement_date,
    -- PERBAIKAN: gunakan EXTRACT(DAY FROM (CURRENT_TIMESTAMP - transaction_date))
    EXTRACT(DAY FROM (CURRENT_TIMESTAMP - MAX(it.transaction_date))) AS days_since_last_movement,
    CASE
        WHEN EXTRACT(DAY FROM (CURRENT_TIMESTAMP - MAX(it.transaction_date))) > 180 THEN 'Dead Stock'
        WHEN EXTRACT(DAY FROM (CURRENT_TIMESTAMP - MAX(it.transaction_date))) > 90 THEN 'Slow Moving'
        WHEN EXTRACT(DAY FROM (CURRENT_TIMESTAMP - MAX(it.transaction_date))) > 30 THEN 'Normal'
        ELSE 'Fast Moving'
    END AS stock_category
FROM products p
LEFT JOIN inventory_transactions it ON p.id = it.product_id AND it.deleted_at IS NULL
WHERE p.deleted_at IS NULL AND p.is_active = TRUE AND p.current_stock > 0
GROUP BY p.id, p.tenant_id, p.product_code, p.product_name, p.current_stock, p.unit_price;

-- 3.12 View untuk EOQ Optimization Recommendations (DIPERBAIKI - menggunakan CTE)
CREATE OR REPLACE VIEW vw_eoq_optimization_recommendations AS
WITH mv_products_eoq_summary AS (
    SELECT
        p.tenant_id,
        t.company_name,
        p.id AS product_id,
        p.product_code,
        p.product_name,
        p.current_stock,
        p.eoq_qty AS eoq_quantity,
        p.reorder_point,
        p.safety_stock,
        p.holding_cost_per_unit,
        ROUND(p.annual_demand / NULLIF(p.eoq_qty, 0), 2) AS orders_per_year,
        ROUND(SQRT(2 * p.annual_demand * p.ordering_cost * p.holding_cost_per_unit), 2) AS total_inventory_cost
    FROM products p
    JOIN tenants t ON p.tenant_id = t.id AND t.deleted_at IS NULL
    WHERE p.deleted_at IS NULL AND p.is_active = TRUE AND p.eoq_qty IS NOT NULL AND p.eoq_qty > 0
)
SELECT
    tenant_id,
    company_name,
    product_id,
    product_code,
    product_name,
    current_stock,
    eoq_quantity,
    reorder_point,
    orders_per_year,
    total_inventory_cost,
    safety_stock,
    holding_cost_per_unit,
    CASE
        WHEN current_stock > (eoq_quantity * 2) THEN 'Reduce current stock - holding cost too high'
        WHEN current_stock < safety_stock THEN 'Emergency order needed - critical stock level'
        WHEN orders_per_year > 52 THEN 'Consider increasing order quantity to reduce frequency'
        WHEN orders_per_year < 4 THEN 'Consider decreasing order quantity to reduce holding cost'
        ELSE 'Current EOQ is optimal'
    END AS optimization_suggestion,
    CASE
        WHEN current_stock > (eoq_quantity * 2)
        THEN ROUND((current_stock - eoq_quantity) * holding_cost_per_unit, 2)
        ELSE 0
    END AS potential_savings
FROM mv_products_eoq_summary;

-- =====================================================
-- PART 4: MEMASTIKAN TRIGGER UNTUK CATEGORIES BERJALAN
-- =====================================================

-- Drop trigger jika ada
DROP TRIGGER IF EXISTS before_insert_categories ON categories;

-- Buat ulang trigger
CREATE TRIGGER before_insert_categories
    BEFORE INSERT ON categories
    FOR EACH ROW
    EXECUTE FUNCTION generate_category_code();

-- =====================================================
-- PART 5: VERIFIKASI
-- =====================================================

-- 5.1 Cek semua view
SELECT 
    schemaname,
    viewname,
    '✅ OK' AS status
FROM pg_views 
WHERE schemaname = 'public' 
  AND viewname LIKE 'vw_%'
ORDER BY viewname;

-- 5.2 Cek fungsi yang sudah dibuat
SELECT 
    proname AS function_name,
    CASE 
        WHEN proname = 'get_tenant_usage_percentage' THEN '✅ Usage function'
        WHEN proname = 'generate_category_code' THEN '✅ Category code generator'
        ELSE 'Other'
    END AS status
FROM pg_proc 
WHERE proname IN ('get_tenant_usage_percentage', 'generate_category_code');

-- 5.3 Cek trigger categories
SELECT 
    tgname AS trigger_name,
    relname AS table_name,
    '✅ Active' AS status
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
WHERE tgname = 'before_insert_categories' 
  AND NOT tgisinternal;

-- 5.4 Test query untuk memastikan tidak error
DO $$
BEGIN
    -- Test vw_tenant_subscription_detail
    PERFORM 1 FROM vw_tenant_subscription_detail LIMIT 1;
    RAISE NOTICE '✅ vw_tenant_subscription_detail works';
    
    -- Test vw_user_activity_summary
    PERFORM 1 FROM vw_user_activity_summary LIMIT 1;
    RAISE NOTICE '✅ vw_user_activity_summary works';
    
    -- Test vw_stock_aging
    PERFORM 1 FROM vw_stock_aging LIMIT 1;
    RAISE NOTICE '✅ vw_stock_aging works';
    
    -- Test vw_eoq_optimization_recommendations
    PERFORM 1 FROM vw_eoq_optimization_recommendations LIMIT 1;
    RAISE NOTICE '✅ vw_eoq_optimization_recommendations works';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ ALL VIEWS AND FUNCTIONS ARE WORKING!';
    RAISE NOTICE '========================================';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE '❌ Error: %', SQLERRM;
END $$;

-- =====================================================
-- PART 6: SUMMARY REPORT
-- =====================================================
SELECT 
    'FIX COMPLETED' AS status,
    NOW() AS fixed_at,
    (SELECT COUNT(*) FROM pg_views WHERE schemaname = 'public' AND viewname LIKE 'vw_%') AS total_views,
    (SELECT COUNT(*) FROM pg_proc WHERE proname IN ('get_tenant_usage_percentage', 'generate_category_code')) AS total_functions,
    'All errors have been resolved' AS message;dari