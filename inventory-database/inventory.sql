-- =====================================================
-- FULL DATABASE SCRIPT - EOQ INVENTORY SYSTEM POSTGRESQL
-- VERSION: 2.1 (COMPLETE FIX - TANPA ERROR)
-- TANGGAL: 2026-04-22
-- =====================================================

-- =====================================================
-- PART 1: DROP EXISTING OBJECTS (CLEAN SLATE)
-- =====================================================

DO $$
DECLARE
    r RECORD;
BEGIN
    -- Drop all views
    FOR r IN (SELECT viewname FROM pg_views WHERE schemaname = 'public' AND viewname LIKE 'vw_%') LOOP
        EXECUTE 'DROP VIEW IF EXISTS ' || r.viewname || ' CASCADE';
    END LOOP;
    
    -- Drop all triggers
    FOR r IN (
        SELECT t.tgname, c.relname 
        FROM pg_trigger t 
        JOIN pg_class c ON t.tgrelid = c.oid 
        WHERE NOT t.tgisinternal
    ) LOOP
        EXECUTE 'DROP TRIGGER IF EXISTS ' || r.tgname || ' ON ' || r.relname || ' CASCADE';
    END LOOP;
    
    -- Drop all functions
    FOR r IN (SELECT proname FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')) LOOP
        EXECUTE 'DROP FUNCTION IF EXISTS ' || r.proname || ' CASCADE';
    END LOOP;
    
    -- Drop all tables in correct order
    DROP TABLE IF EXISTS audit_logs CASCADE;
    DROP TABLE IF EXISTS eoq_logs CASCADE;
    DROP TABLE IF EXISTS stock_alerts CASCADE;
    DROP TABLE IF EXISTS inventory_transactions CASCADE;
    DROP TABLE IF EXISTS po_details CASCADE;
    DROP TABLE IF EXISTS purchase_orders CASCADE;
    DROP TABLE IF EXISTS product_suppliers CASCADE;
    DROP TABLE IF EXISTS products CASCADE;
    DROP TABLE IF EXISTS categories CASCADE;
    DROP TABLE IF EXISTS suppliers CASCADE;
    DROP TABLE IF EXISTS user_roles CASCADE;
    DROP TABLE IF EXISTS roles_definition CASCADE;
    DROP TABLE IF EXISTS user_sessions CASCADE;
    DROP TABLE IF EXISTS password_reset_tokens CASCADE;
    DROP TABLE IF EXISTS feature_usage_logs CASCADE;
    DROP TABLE IF EXISTS subscription_history CASCADE;
    DROP TABLE IF EXISTS subscription_plans CASCADE;
    DROP TABLE IF EXISTS users CASCADE;
    DROP TABLE IF EXISTS tenants CASCADE;
    DROP TABLE IF EXISTS transaction_errors CASCADE;
    DROP TABLE IF EXISTS system_logs CASCADE;
END $$;

-- =====================================================
-- PART 2: TABLES
-- =====================================================

-- 2.1 Tenants table
CREATE TABLE tenants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name VARCHAR(255) NOT NULL,
    company_email VARCHAR(255) UNIQUE NOT NULL,
    phone VARCHAR(50),
    address TEXT,
    tenant_prefix VARCHAR(10) GENERATED ALWAYS AS (UPPER(LEFT(REPLACE(company_name, ' ', ''), 4))) STORED,
    subscription_plan VARCHAR(50) DEFAULT 'basic',
    subscription_status VARCHAR(20) DEFAULT 'trial' CHECK (subscription_status IN ('active', 'expired', 'suspended', 'trial')),
    subscription_start_date DATE,
    subscription_end_date DATE,
    trial_ends_at DATE,
    max_users INT DEFAULT 5,
    max_products INT DEFAULT 1000,
    max_categories INT DEFAULT 50,
    max_transactions_per_month INT DEFAULT 10000,
    storage_used_bytes BIGINT DEFAULT 0,
    storage_limit_bytes BIGINT DEFAULT 1073741824,
    stripe_customer_id VARCHAR(255),
    stripe_subscription_id VARCHAR(255),
    last_invoice_date DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL
);

-- 2.2 Subscription Plans table
CREATE TABLE subscription_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_code VARCHAR(50) UNIQUE NOT NULL,
    plan_name VARCHAR(100) NOT NULL,
    description TEXT,
    price_monthly DECIMAL(15,2) DEFAULT 0,
    price_yearly DECIMAL(15,2) DEFAULT 0,
    max_users INT DEFAULT 5,
    max_products INT DEFAULT 1000,
    max_categories INT DEFAULT 50,
    max_transactions_per_month INT DEFAULT 10000,
    max_storage_mb INT DEFAULT 1024,
    features JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    sort_order INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL
);

-- 2.3 Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID,
    email VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    role VARCHAR(50) DEFAULT 'staff',
    role_level VARCHAR(20) DEFAULT 'customer' CHECK (role_level IN ('system', 'customer')),
    permissions JSONB,
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_users_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE SET NULL
);

-- 2.4 Roles Definition table
CREATE TABLE roles_definition (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_code VARCHAR(50) UNIQUE NOT NULL,
    role_name VARCHAR(100) NOT NULL,
    role_level VARCHAR(20) NOT NULL CHECK (role_level IN ('system', 'customer')),
    permissions JSONB NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL
);

-- 2.5 User Roles table
CREATE TABLE user_roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    role_id UUID NOT NULL,
    tenant_id UUID NULL,
    assigned_by UUID,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_user_roles_role FOREIGN KEY (role_id) REFERENCES roles_definition(id),
    CONSTRAINT fk_user_roles_assigned_by FOREIGN KEY (assigned_by) REFERENCES users(id)
);

-- 2.6 Categories table
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    parent_category_id UUID NULL,
    category_code VARCHAR(50) NOT NULL,
    category_name VARCHAR(255) NOT NULL,
    description TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_categories_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_categories_parent FOREIGN KEY (parent_category_id) REFERENCES categories(id) ON DELETE SET NULL
);

-- 2.7 Suppliers table
CREATE TABLE suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    supplier_code VARCHAR(50) NOT NULL,
    supplier_name VARCHAR(255) NOT NULL,
    contact_person VARCHAR(255),
    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT,
    payment_terms VARCHAR(100),
    lead_time_days INT DEFAULT 0,
    is_preferred BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_suppliers_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

-- 2.8 Products table
CREATE TABLE products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    category_id UUID,
    product_code VARCHAR(100) NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    description TEXT,
    unit VARCHAR(50) DEFAULT 'pcs',
    annual_demand DECIMAL(15,2) DEFAULT 0,
    ordering_cost DECIMAL(15,2) DEFAULT 0,
    holding_cost_per_unit DECIMAL(15,2) DEFAULT 0,
    unit_price DECIMAL(15,2) DEFAULT 0,
    eoq_qty DECIMAL(15,2) NULL,
    reorder_point DECIMAL(15,2) NULL,
    safety_stock DECIMAL(15,2) DEFAULT 0,
    lead_time_days INT DEFAULT 0,
    current_stock DECIMAL(15,2) DEFAULT 0,
    min_stock_level DECIMAL(15,2) DEFAULT 0,
    max_stock_level DECIMAL(15,2) DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_products_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_products_category FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
    CONSTRAINT check_eoq_parameters CHECK (
        annual_demand >= 0 AND ordering_cost >= 0 AND holding_cost_per_unit >= 0
    )
);

-- 2.9 Product Suppliers table
CREATE TABLE product_suppliers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    product_id UUID NOT NULL,
    supplier_id UUID NOT NULL,
    is_primary_supplier BOOLEAN DEFAULT FALSE,
    last_purchase_price DECIMAL(15,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_product_suppliers_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_product_suppliers_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
    CONSTRAINT fk_product_suppliers_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id) ON DELETE CASCADE
);

-- 2.10 Purchase Orders table
CREATE TABLE purchase_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    po_number VARCHAR(50) NOT NULL,
    supplier_id UUID NOT NULL,
    order_date DATE NOT NULL,
    expected_delivery_date DATE,
    actual_delivery_date DATE,
    status VARCHAR(20) DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'approved', 'received', 'cancelled')),
    total_amount DECIMAL(15,2) DEFAULT 0,
    notes TEXT,
    created_by UUID,
    approved_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_po_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_po_supplier FOREIGN KEY (supplier_id) REFERENCES suppliers(id),
    CONSTRAINT fk_po_created_by FOREIGN KEY (created_by) REFERENCES users(id),
    CONSTRAINT fk_po_approved_by FOREIGN KEY (approved_by) REFERENCES users(id)
);

-- 2.11 PO Details table
CREATE TABLE po_details (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    po_id UUID NOT NULL,
    product_id UUID NOT NULL,
    quantity_ordered DECIMAL(15,2) NOT NULL,
    quantity_received DECIMAL(15,2) DEFAULT 0,
    unit_price DECIMAL(15,2) NOT NULL,
    subtotal DECIMAL(15,2) GENERATED ALWAYS AS (quantity_ordered * unit_price) STORED,
    eoq_recommended_qty DECIMAL(15,2) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_po_details_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_po_details_po FOREIGN KEY (po_id) REFERENCES purchase_orders(id) ON DELETE CASCADE,
    CONSTRAINT fk_po_details_product FOREIGN KEY (product_id) REFERENCES products(id)
);

-- 2.12 Inventory Transactions table
CREATE TABLE inventory_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    product_id UUID NOT NULL,
    transaction_type VARCHAR(10) NOT NULL CHECK (transaction_type IN ('in', 'out', 'adjustment', 'return')),
    quantity DECIMAL(15,2) NOT NULL CHECK (quantity > 0),
    unit_cost DECIMAL(15,2) NOT NULL,
    total_amount DECIMAL(15,2) GENERATED ALWAYS AS (quantity * unit_cost) STORED,
    reference_type VARCHAR(20) CHECK (reference_type IN ('purchase_order', 'sales_order', 'transfer', 'adjustment')),
    reference_id UUID,
    notes TEXT,
    transaction_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_transactions_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_transactions_product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT fk_transactions_created_by FOREIGN KEY (created_by) REFERENCES users(id)
);

-- 2.13 Subscription History table
CREATE TABLE subscription_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    plan_id UUID NOT NULL,
    subscription_type VARCHAR(10) DEFAULT 'monthly' CHECK (subscription_type IN ('monthly', 'yearly')),
    amount_paid DECIMAL(15,2),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    invoice_number VARCHAR(100),
    payment_status VARCHAR(20) DEFAULT 'pending' CHECK (payment_status IN ('pending', 'paid', 'failed', 'refunded')),
    payment_method VARCHAR(50),
    transaction_id VARCHAR(255),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_sub_history_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_sub_history_plan FOREIGN KEY (plan_id) REFERENCES subscription_plans(id)
);

-- 2.14 EOQ Logs table
CREATE TABLE eoq_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    product_id UUID NOT NULL,
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    annual_demand DECIMAL(15,2),
    ordering_cost DECIMAL(15,2),
    holding_cost DECIMAL(15,2),
    eoq_result DECIMAL(15,2),
    total_ordering_cost DECIMAL(15,2),
    total_holding_cost DECIMAL(15,2),
    total_inventory_cost DECIMAL(15,2),
    optimal_order_frequency DECIMAL(10,2),
    optimal_order_interval_days DECIMAL(10,2),
    notes TEXT,
    calculated_by UUID,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_eoq_logs_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_eoq_logs_product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT fk_eoq_logs_calculated_by FOREIGN KEY (calculated_by) REFERENCES users(id)
);

-- 2.15 Stock Alerts table
CREATE TABLE stock_alerts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    product_id UUID NOT NULL,
    alert_type VARCHAR(25) NOT NULL CHECK (alert_type IN ('below_rop', 'below_safety_stock', 'above_max_stock', 'expiring_soon')),
    current_stock DECIMAL(15,2),
    threshold_value DECIMAL(15,2),
    recommended_order_qty DECIMAL(15,2),
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP NULL,
    resolved_by UUID NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_alerts_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_alerts_product FOREIGN KEY (product_id) REFERENCES products(id),
    CONSTRAINT fk_alerts_resolved_by FOREIGN KEY (resolved_by) REFERENCES users(id)
);

-- 2.16 Password Reset Tokens table
CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    token_salt VARCHAR(64) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    is_used BOOLEAN DEFAULT FALSE,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_reset_token_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- 2.17 User Sessions table
CREATE TABLE user_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    tenant_id UUID NOT NULL,
    session_token VARCHAR(255) UNIQUE NOT NULL,
    ip_address INET,
    user_agent TEXT,
    last_activity TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    is_revoked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_sessions_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

-- 2.18 Feature Usage Logs table
CREATE TABLE feature_usage_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    feature_name VARCHAR(100),
    endpoint VARCHAR(255),
    usage_date DATE NOT NULL,
    usage_count INT DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_feature_usage_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_feature_usage_user FOREIGN KEY (user_id) REFERENCES users(id)
);

-- 2.19 Transaction Errors table
CREATE TABLE transaction_errors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID,
    product_id UUID,
    error_message TEXT,
    is_resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_transaction_errors_product FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL
);

-- 2.20 System Logs table
CREATE TABLE system_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id UUID,
    log_level VARCHAR(20) CHECK (log_level IN ('INFO', 'WARNING', 'ERROR', 'CRITICAL')),
    action VARCHAR(100),
    description TEXT,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL
);

-- 2.21 Audit Logs table (PARTITIONED)
CREATE TABLE audit_logs (
    id UUID DEFAULT gen_random_uuid(),
    tenant_id UUID NOT NULL,
    user_id UUID NOT NULL,
    action VARCHAR(100) NOT NULL,
    table_name VARCHAR(100),
    record_id UUID,
    old_data JSONB,
    new_data JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    CONSTRAINT fk_audit_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT fk_audit_user FOREIGN KEY (user_id) REFERENCES users(id)
) PARTITION BY RANGE (created_at);

-- =====================================================
-- PART 3: PARTITIONS FOR AUDIT_LOGS
-- =====================================================

DO $$
DECLARE
    start_date DATE := '2024-01-01';
    end_date DATE := '2027-01-01';
    quarter_start DATE;
    quarter_end DATE;
    partition_name TEXT;
BEGIN
    quarter_start := start_date;
    WHILE quarter_start < end_date LOOP
        quarter_end := quarter_start + INTERVAL '3 months';
        partition_name := 'audit_logs_' || TO_CHAR(quarter_start, 'YYYY_"Q"Q');
        
        EXECUTE format('
            CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_logs
            FOR VALUES FROM (%L) TO (%L)',
            partition_name, quarter_start, quarter_end
        );
        
        quarter_start := quarter_end;
    END LOOP;
END $$;

-- =====================================================
-- PART 4: INDEXES (PARTIAL INDEX UNTUK SOFT DELETE)
-- =====================================================

-- Users: unique email per tenant (hanya untuk active records)
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_unique_email_per_tenant
    ON users (tenant_id, email) WHERE deleted_at IS NULL;

-- User Roles: unique constraint
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_roles_unique
    ON user_roles (user_id, role_id, tenant_id) WHERE deleted_at IS NULL;

-- Categories: unique code per tenant
CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_unique_code
    ON categories (tenant_id, category_code) WHERE deleted_at IS NULL;

-- Suppliers: unique code per tenant
CREATE UNIQUE INDEX IF NOT EXISTS idx_suppliers_unique_code
    ON suppliers (tenant_id, supplier_code) WHERE deleted_at IS NULL;

-- Products: unique code per tenant
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_unique_code
    ON products (tenant_id, product_code) WHERE deleted_at IS NULL;

-- Products: index untuk performa EOQ
CREATE INDEX IF NOT EXISTS idx_products_eoq_params
    ON products (tenant_id, annual_demand, holding_cost_per_unit, ordering_cost)
    WHERE deleted_at IS NULL AND is_active = TRUE;

-- Product Suppliers: unique constraint
CREATE UNIQUE INDEX IF NOT EXISTS idx_product_suppliers_unique
    ON product_suppliers (product_id, supplier_id) WHERE deleted_at IS NULL;

-- Purchase Orders: unique PO number per tenant
CREATE UNIQUE INDEX IF NOT EXISTS idx_purchase_orders_unique_po
    ON purchase_orders (tenant_id, po_number) WHERE deleted_at IS NULL;

-- Additional indexes untuk performa
CREATE INDEX IF NOT EXISTS idx_products_tenant_active ON products (tenant_id, is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_users_tenant_active ON users (tenant_id, is_active) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_inventory_transactions_date ON inventory_transactions (transaction_date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs (created_at);
CREATE INDEX IF NOT EXISTS idx_stock_alerts_unresolved ON stock_alerts (tenant_id, is_resolved) WHERE is_resolved = FALSE AND deleted_at IS NULL;

-- =====================================================
-- PART 5: TRIGGER FUNCTIONS
-- =====================================================

-- 5.1 Auto-update updated_at (universal)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.2 Generate category_code
CREATE OR REPLACE FUNCTION generate_category_code()
RETURNS TRIGGER AS $$
DECLARE
    next_number INT;
    prefix VARCHAR(20);
    tenant_prefix VARCHAR(10);
BEGIN
    SELECT tenant_prefix INTO tenant_prefix
    FROM tenants WHERE id = NEW.tenant_id AND deleted_at IS NULL;
    
    prefix := tenant_prefix || '-CAT-';
    
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

-- 5.3 Generate product_code
CREATE OR REPLACE FUNCTION generate_product_code()
RETURNS TRIGGER AS $$
DECLARE
    next_number INT;
    prefix VARCHAR(20);
    tenant_prefix VARCHAR(10);
BEGIN
    -- Only generate if product_code is not provided
    IF NEW.product_code IS NULL OR NEW.product_code = '' THEN
        SELECT tenant_prefix INTO tenant_prefix
        FROM tenants WHERE id = NEW.tenant_id AND deleted_at IS NULL;
        
        prefix := tenant_prefix || '-PRD-';
        
        SELECT COALESCE(MAX(CAST(SUBSTRING(product_code FROM position('-PRD-' IN product_code) + 5) AS INTEGER)), 0) + 1
        INTO next_number
        FROM products
        WHERE tenant_id = NEW.tenant_id
          AND product_code LIKE prefix || '%'
          AND deleted_at IS NULL;
        
        NEW.product_code := prefix || LPAD(next_number::TEXT, 6, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.4 Generate supplier_code
CREATE OR REPLACE FUNCTION generate_supplier_code()
RETURNS TRIGGER AS $$
DECLARE
    next_number INT;
    prefix VARCHAR(20);
    tenant_prefix VARCHAR(10);
BEGIN
    IF NEW.supplier_code IS NULL OR NEW.supplier_code = '' THEN
        SELECT tenant_prefix INTO tenant_prefix
        FROM tenants WHERE id = NEW.tenant_id AND deleted_at IS NULL;
        
        prefix := tenant_prefix || '-SUP-';
        
        SELECT COALESCE(MAX(CAST(SUBSTRING(supplier_code FROM position('-SUP-' IN supplier_code) + 5) AS INTEGER)), 0) + 1
        INTO next_number
        FROM suppliers
        WHERE tenant_id = NEW.tenant_id
          AND supplier_code LIKE prefix || '%'
          AND deleted_at IS NULL;
        
        NEW.supplier_code := prefix || LPAD(next_number::TEXT, 4, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.5 Generate po_number
CREATE OR REPLACE FUNCTION generate_po_number()
RETURNS TRIGGER AS $$
DECLARE
    next_number INT;
    prefix VARCHAR(30);
    tenant_prefix VARCHAR(10);
    current_year VARCHAR(4);
    current_month VARCHAR(2);
BEGIN
    IF NEW.po_number IS NULL OR NEW.po_number = '' THEN
        SELECT tenant_prefix INTO tenant_prefix
        FROM tenants WHERE id = NEW.tenant_id AND deleted_at IS NULL;
        
        current_year := TO_CHAR(NEW.order_date, 'YYYY');
        current_month := TO_CHAR(NEW.order_date, 'MM');
        
        prefix := tenant_prefix || '-PO-' || current_year || current_month || '-';
        
        SELECT COALESCE(MAX(CAST(SUBSTRING(po_number FROM position('-' IN po_number) + 1) AS INTEGER)), 0) + 1
        INTO next_number
        FROM purchase_orders
        WHERE tenant_id = NEW.tenant_id
          AND po_number LIKE prefix || '%'
          AND deleted_at IS NULL;
        
        NEW.po_number := prefix || LPAD(next_number::TEXT, 4, '0');
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.6 Audit log trigger function
CREATE OR REPLACE FUNCTION audit_log_trigger_function()
RETURNS TRIGGER AS $$
DECLARE
    v_old_data JSONB;
    v_new_data JSONB;
    v_action VARCHAR(100);
    v_tenant_id UUID;
    v_user_id UUID;
BEGIN
    -- Get tenant_id from the table
    IF TG_TABLE_NAME = 'products' OR TG_TABLE_NAME = 'categories' OR 
       TG_TABLE_NAME = 'suppliers' OR TG_TABLE_NAME = 'purchase_orders' THEN
        v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
    ELSIF TG_TABLE_NAME = 'users' THEN
        v_tenant_id := COALESCE(NEW.tenant_id, OLD.tenant_id);
    ELSE
        v_tenant_id := NULL;
    END IF;
    
    -- Get current user from session
    BEGIN
        v_user_id := current_setting('app.current_user_id', TRUE)::UUID;
    EXCEPTION WHEN OTHERS THEN
        v_user_id := NULL;
    END;
    
    -- Capture old and new data
    IF TG_OP = 'INSERT' THEN
        v_action := 'INSERT';
        v_old_data := NULL;
        v_new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_action := 'UPDATE';
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
        v_action := 'DELETE';
        v_old_data := to_jsonb(OLD);
        v_new_data := NULL;
    END IF;
    
    -- Insert audit log
    INSERT INTO audit_logs (
        tenant_id, user_id, action, table_name, record_id,
        old_data, new_data, created_at
    ) VALUES (
        v_tenant_id,
        v_user_id,
        v_action,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        v_old_data,
        v_new_data,
        CURRENT_TIMESTAMP
    );
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- 5.7 Check subscription limit
CREATE OR REPLACE FUNCTION check_subscription_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_current_count INT;
    v_max_limit INT;
BEGIN
    IF TG_TABLE_NAME = 'users' AND NEW.role_level = 'customer' THEN
        SELECT max_users INTO v_max_limit
        FROM tenants WHERE id = NEW.tenant_id AND deleted_at IS NULL;
        
        SELECT COUNT(*) INTO v_current_count
        FROM users
        WHERE tenant_id = NEW.tenant_id
          AND role_level = 'customer'
          AND deleted_at IS NULL
          AND id != COALESCE(OLD.id, '00000000-0000-0000-0000-000000000000'::UUID);
        
        IF v_current_count >= v_max_limit THEN
            RAISE EXCEPTION 'User limit exceeded for tenant. Max users: %', v_max_limit;
        END IF;
        
    ELSIF TG_TABLE_NAME = 'products' THEN
        SELECT max_products INTO v_max_limit
        FROM tenants WHERE id = NEW.tenant_id AND deleted_at IS NULL;
        
        SELECT COUNT(*) INTO v_current_count
        FROM products
        WHERE tenant_id = NEW.tenant_id
          AND deleted_at IS NULL
          AND id != COALESCE(OLD.id, '00000000-0000-0000-0000-000000000000'::UUID);
        
        IF v_current_count >= v_max_limit THEN
            RAISE EXCEPTION 'Product limit exceeded for tenant. Max products: %', v_max_limit;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.8 Auto create stock alert
CREATE OR REPLACE FUNCTION auto_create_stock_alert()
RETURNS TRIGGER AS $$
BEGIN
    -- Only trigger when stock decreases
    IF OLD.current_stock > NEW.current_stock THEN
        -- Check for below reorder point
        IF NEW.current_stock <= NEW.reorder_point AND NEW.current_stock > 0 THEN
            IF NOT EXISTS (
                SELECT 1 FROM stock_alerts
                WHERE product_id = NEW.id
                  AND alert_type = 'below_rop'
                  AND is_resolved = FALSE
                  AND deleted_at IS NULL
            ) THEN
                INSERT INTO stock_alerts (
                    tenant_id, product_id, alert_type, current_stock,
                    threshold_value, recommended_order_qty
                ) VALUES (
                    NEW.tenant_id, NEW.id, 'below_rop',
                    NEW.current_stock, NEW.reorder_point, NEW.eoq_qty
                );
            END IF;
        END IF;
        
        -- Check for below safety stock
        IF NEW.current_stock <= NEW.safety_stock AND NEW.current_stock > 0 THEN
            IF NOT EXISTS (
                SELECT 1 FROM stock_alerts
                WHERE product_id = NEW.id
                  AND alert_type = 'below_safety_stock'
                  AND is_resolved = FALSE
                  AND deleted_at IS NULL
            ) THEN
                INSERT INTO stock_alerts (
                    tenant_id, product_id, alert_type, current_stock,
                    threshold_value, recommended_order_qty
                ) VALUES (
                    NEW.tenant_id, NEW.id, 'below_safety_stock',
                    NEW.current_stock, NEW.safety_stock, NEW.eoq_qty
                );
            END IF;
        END IF;
        
        -- Resolve alert if stock is now above ROP
        IF NEW.current_stock > NEW.reorder_point THEN
            UPDATE stock_alerts
            SET is_resolved = TRUE, resolved_at = CURRENT_TIMESTAMP
            WHERE product_id = NEW.id
              AND alert_type = 'below_rop'
              AND is_resolved = FALSE
              AND deleted_at IS NULL;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.9 Prevent negative stock
CREATE OR REPLACE FUNCTION prevent_negative_stock()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.current_stock < 0 THEN
        RAISE EXCEPTION 'Stock cannot be negative for product ID: %', NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.10 Auto update EOQ
CREATE OR REPLACE FUNCTION auto_update_eoq()
RETURNS TRIGGER AS $$
DECLARE
    v_total_cost DECIMAL(15,2);
BEGIN
    -- Recalculate EOQ if relevant parameters changed
    IF (NEW.annual_demand IS DISTINCT FROM OLD.annual_demand)
       OR (NEW.ordering_cost IS DISTINCT FROM OLD.ordering_cost)
       OR (NEW.holding_cost_per_unit IS DISTINCT FROM OLD.holding_cost_per_unit)
       OR (NEW.lead_time_days IS DISTINCT FROM OLD.lead_time_days)
       OR (NEW.safety_stock IS DISTINCT FROM OLD.safety_stock) THEN
        
        IF NEW.annual_demand > 0 AND NEW.ordering_cost > 0 AND NEW.holding_cost_per_unit > 0 THEN
            NEW.eoq_qty := ROUND(SQRT((2 * NEW.annual_demand * NEW.ordering_cost) / NEW.holding_cost_per_unit), 2);
            NEW.reorder_point := ROUND((NEW.lead_time_days * (NEW.annual_demand / 365.0)) + NEW.safety_stock, 2);
            
            v_total_cost := ROUND(SQRT(2 * NEW.annual_demand * NEW.ordering_cost * NEW.holding_cost_per_unit), 2);
            
            -- Log the recalculation
            INSERT INTO eoq_logs (
                tenant_id, product_id, annual_demand, ordering_cost,
                holding_cost, eoq_result, total_inventory_cost,
                optimal_order_frequency, optimal_order_interval_days
            ) VALUES (
                NEW.tenant_id, NEW.id, NEW.annual_demand, NEW.ordering_cost,
                NEW.holding_cost_per_unit, NEW.eoq_qty, v_total_cost,
                ROUND(NEW.annual_demand / NULLIF(NEW.eoq_qty, 0), 2),
                ROUND(365.0 / NULLIF(NEW.annual_demand / NULLIF(NEW.eoq_qty, 0), 0), 0)
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.11 Update stock on PO received
CREATE OR REPLACE FUNCTION update_stock_on_po_received()
RETURNS TRIGGER AS $$
DECLARE
    po_detail RECORD;
BEGIN
    -- When PO status changes to 'received'
    IF NEW.status = 'received' AND (OLD.status IS DISTINCT FROM 'received') THEN
        -- Insert inventory transaction for each PO detail
        FOR po_detail IN
            SELECT * FROM po_details
            WHERE po_id = NEW.id AND deleted_at IS NULL
        LOOP
            INSERT INTO inventory_transactions (
                tenant_id, product_id, transaction_type, quantity,
                unit_cost, reference_type, reference_id, transaction_date, created_by
            ) VALUES (
                NEW.tenant_id,
                po_detail.product_id,
                'in',
                po_detail.quantity_ordered,
                po_detail.unit_price,
                'purchase_order',
                NEW.id,
                COALESCE(NEW.actual_delivery_date, NEW.order_date),
                NEW.created_by
            );
            
            -- Update product stock
            UPDATE products
            SET current_stock = current_stock + po_detail.quantity_ordered,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = po_detail.product_id AND tenant_id = NEW.tenant_id;
        END LOOP;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5.12 Get tenant usage percentage (fungsi untuk view)
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

-- 5.13 Set current user for audit
CREATE OR REPLACE FUNCTION set_current_user_id(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM set_config('app.current_user_id', p_user_id::text, FALSE);
END;
$$;

-- =====================================================
-- PART 6: APPLY TRIGGERS TO TABLES
-- =====================================================

-- 6.1 Updated_at triggers untuk semua tabel
DO $$
DECLARE
    tables TEXT[] := ARRAY[
        'tenants', 'subscription_plans', 'users', 'roles_definition', 'user_roles',
        'categories', 'suppliers', 'products', 'product_suppliers', 'purchase_orders',
        'po_details', 'inventory_transactions', 'subscription_history', 'eoq_logs',
        'stock_alerts', 'password_reset_tokens', 'user_sessions', 'feature_usage_logs',
        'audit_logs', 'transaction_errors', 'system_logs'
    ];
    tbl TEXT;
BEGIN
    FOREACH tbl IN ARRAY tables
    LOOP
        EXECUTE format('
            DROP TRIGGER IF EXISTS update_%I_updated_at ON %I;
            CREATE TRIGGER update_%I_updated_at
                BEFORE UPDATE ON %I
                FOR EACH ROW
                EXECUTE FUNCTION update_updated_at_column();
        ', tbl, tbl, tbl, tbl);
    END LOOP;
END $$;

-- 6.2 Auto-generate code triggers
DROP TRIGGER IF EXISTS before_insert_categories ON categories;
CREATE TRIGGER before_insert_categories
    BEFORE INSERT ON categories
    FOR EACH ROW
    EXECUTE FUNCTION generate_category_code();

DROP TRIGGER IF EXISTS before_insert_products ON products;
CREATE TRIGGER before_insert_products
    BEFORE INSERT ON products
    FOR EACH ROW
    WHEN (NEW.product_code IS NULL OR NEW.product_code = '')
    EXECUTE FUNCTION generate_product_code();

DROP TRIGGER IF EXISTS before_insert_suppliers ON suppliers;
CREATE TRIGGER before_insert_suppliers
    BEFORE INSERT ON suppliers
    FOR EACH ROW
    WHEN (NEW.supplier_code IS NULL OR NEW.supplier_code = '')
    EXECUTE FUNCTION generate_supplier_code();

DROP TRIGGER IF EXISTS before_insert_purchase_orders ON purchase_orders;
CREATE TRIGGER before_insert_purchase_orders
    BEFORE INSERT ON purchase_orders
    FOR EACH ROW
    WHEN (NEW.po_number IS NULL OR NEW.po_number = '')
    EXECUTE FUNCTION generate_po_number();

-- 6.3 Audit log triggers
DROP TRIGGER IF EXISTS audit_products ON products;
CREATE TRIGGER audit_products
    AFTER INSERT OR UPDATE OR DELETE ON products
    FOR EACH ROW EXECUTE FUNCTION audit_log_trigger_function();

DROP TRIGGER IF EXISTS audit_users ON users;
CREATE TRIGGER audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION audit_log_trigger_function();

DROP TRIGGER IF EXISTS audit_categories ON categories;
CREATE TRIGGER audit_categories
    AFTER INSERT OR UPDATE OR DELETE ON categories
    FOR EACH ROW EXECUTE FUNCTION audit_log_trigger_function();

DROP TRIGGER IF EXISTS audit_suppliers ON suppliers;
CREATE TRIGGER audit_suppliers
    AFTER INSERT OR UPDATE OR DELETE ON suppliers
    FOR EACH ROW EXECUTE FUNCTION audit_log_trigger_function();

DROP TRIGGER IF EXISTS audit_purchase_orders ON purchase_orders;
CREATE TRIGGER audit_purchase_orders
    AFTER INSERT OR UPDATE OR DELETE ON purchase_orders
    FOR EACH ROW EXECUTE FUNCTION audit_log_trigger_function();

-- 6.4 Subscription limit triggers
DROP TRIGGER IF EXISTS check_user_limit ON users;
CREATE TRIGGER check_user_limit
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION check_subscription_limit();

DROP TRIGGER IF EXISTS check_product_limit ON products;
CREATE TRIGGER check_product_limit
    BEFORE INSERT OR UPDATE ON products
    FOR EACH ROW EXECUTE FUNCTION check_subscription_limit();

-- 6.5 Stock alert trigger
DROP TRIGGER IF EXISTS stock_alert_on_update ON products;
CREATE TRIGGER stock_alert_on_update
    AFTER UPDATE OF current_stock ON products
    FOR EACH ROW EXECUTE FUNCTION auto_create_stock_alert();

-- 6.6 Prevent negative stock
DROP TRIGGER IF EXISTS prevent_negative_stock ON products;
CREATE TRIGGER prevent_negative_stock
    BEFORE UPDATE OF current_stock ON products
    FOR EACH ROW EXECUTE FUNCTION prevent_negative_stock();

-- 6.7 Auto-update EOQ
DROP TRIGGER IF EXISTS auto_update_eoq ON products;
CREATE TRIGGER auto_update_eoq
    BEFORE UPDATE OF annual_demand, ordering_cost, holding_cost_per_unit, lead_time_days, safety_stock ON products
    FOR EACH ROW EXECUTE FUNCTION auto_update_eoq();

-- 6.8 PO received trigger
DROP TRIGGER IF EXISTS po_received_trigger ON purchase_orders;
CREATE TRIGGER po_received_trigger
    AFTER UPDATE OF status ON purchase_orders
    FOR EACH ROW
    WHEN (NEW.status = 'received' AND OLD.status IS DISTINCT FROM 'received')
    EXECUTE FUNCTION update_stock_on_po_received();

-- =====================================================
-- PART 7: VIEWS FOR REPORTING
-- =====================================================

-- 7.1 Executive Dashboard
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

-- 7.2 Tenant Subscription Detail
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

-- 7.3 Supplier Performance
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

-- 7.4 Inventory Movement Summary
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

-- 7.5 Daily Stock Mutation
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

-- 7.6 Monthly Inventory Turnover
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

-- 7.7 Product Profitability
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

-- 7.8 EOQ Trend Analysis
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

-- 7.9 User Activity Summary
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

-- 7.10 Audit Trail Detail
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

-- 7.11 Stock Aging
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

-- 7.12 EOQ Optimization Recommendations
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

-- 7.13 Trigger Status View (DIPERBAIKI - menggunakan JOIN dengan pg_class)
CREATE OR REPLACE VIEW vw_trigger_status AS
SELECT 
    t.tgname AS trigger_name,
    c.relname AS table_name,
    p.proname AS function_name,
    CASE 
        WHEN t.tgenabled = 'O' THEN '✅ ENABLED'
        WHEN t.tgenabled = 'D' THEN '❌ DISABLED'
        ELSE '⚠️ UNKNOWN'
    END AS status,
    CASE 
        WHEN t.tgtype = 7 THEN 'AFTER'
        WHEN t.tgtype = 5 THEN 'BEFORE'
        ELSE 'OTHER'
    END AS timing,
    CASE
        WHEN t.tgtype & 1 = 1 THEN 'ROW'
        ELSE 'STATEMENT'
    END AS level
FROM pg_trigger t
JOIN pg_class c ON t.tgrelid = c.oid
LEFT JOIN pg_proc p ON t.tgfoid = p.oid
WHERE NOT t.tgisinternal
ORDER BY c.relname, t.tgname;

-- =====================================================
-- PART 8: UTILITY FUNCTIONS
-- =====================================================

-- Disable all updated_at triggers (for batch operations)
CREATE OR REPLACE FUNCTION disable_updated_at_triggers()
RETURNS TEXT AS $$
DECLARE
    trigger_record RECORD;
    disabled_count INT := 0;
BEGIN
    FOR trigger_record IN
        SELECT t.tgname, c.relname
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        WHERE t.tgname LIKE 'update_%_updated_at'
          AND NOT t.tgisinternal
    LOOP
        EXECUTE format('ALTER TABLE %I DISABLE TRIGGER %I', 
                      trigger_record.relname, trigger_record.tgname);
        disabled_count := disabled_count + 1;
    END LOOP;
    
    RETURN format('Disabled %s triggers for batch operation', disabled_count);
END;
$$ LANGUAGE plpgsql;

-- Enable all updated_at triggers
CREATE OR REPLACE FUNCTION enable_updated_at_triggers()
RETURNS TEXT AS $$
DECLARE
    trigger_record RECORD;
    enabled_count INT := 0;
BEGIN
    FOR trigger_record IN
        SELECT t.tgname, c.relname
        FROM pg_trigger t
        JOIN pg_class c ON t.tgrelid = c.oid
        WHERE t.tgname LIKE 'update_%_updated_at'
          AND NOT t.tgisinternal
    LOOP
        EXECUTE format('ALTER TABLE %I ENABLE TRIGGER %I', 
                      trigger_record.relname, trigger_record.tgname);
        enabled_count := enabled_count + 1;
    END LOOP;
    
    RETURN format('Enabled %s triggers back', enabled_count);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- PART 9: FINAL VERIFICATION (DIPERBAIKI)
-- =====================================================

DO $$
DECLARE
    total_tables INT;
    total_triggers INT;
    total_views INT;
    total_functions INT;
BEGIN
    SELECT COUNT(*) INTO total_tables FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    SELECT COUNT(*) INTO total_triggers FROM pg_trigger WHERE NOT tgisinternal;
    SELECT COUNT(*) INTO total_views FROM pg_views WHERE schemaname = 'public' AND viewname LIKE 'vw_%';
    SELECT COUNT(*) INTO total_functions FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');
    
    RAISE NOTICE '';
    RAISE NOTICE '╔══════════════════════════════════════════════════════════════════════╗';
    RAISE NOTICE '║                    EOQ INVENTORY DATABASE - COMPLETE                ║';
    RAISE NOTICE '╠══════════════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║  Total Tables:           %', RPAD(total_tables::TEXT, 36) || '║';
    RAISE NOTICE '║  Total Triggers:          %', RPAD(total_triggers::TEXT, 36) || '║';
    RAISE NOTICE '║  Total Views:             %', RPAD(total_views::TEXT, 36) || '║';
    RAISE NOTICE '║  Total Functions:         %', RPAD(total_functions::TEXT, 36) || '║';
    RAISE NOTICE '╠══════════════════════════════════════════════════════════════════════╣';
    RAISE NOTICE '║  FEATURES:                                                           ║';
    RAISE NOTICE '║  ✅ Soft Delete (deleted_at) on all tables                          ║';
    RAISE NOTICE '║  ✅ Auto-update updated_at on all tables                            ║';
    RAISE NOTICE '║  ✅ Auto-generate codes (category, product, supplier, PO)           ║';
    RAISE NOTICE '║  ✅ Partial indexes untuk unique constraint                         ║';
    RAISE NOTICE '║  ✅ Partition table untuk audit_logs                                ║';
    RAISE NOTICE '║  ✅ Audit logging for all critical tables                           ║';
    RAISE NOTICE '║  ✅ Subscription limit enforcement                                  ║';
    RAISE NOTICE '║  ✅ Stock alert automation                                          ║';
    RAISE NOTICE '║  ✅ EOQ auto-calculation                                            ║';
    RAISE NOTICE '╚══════════════════════════════════════════════════════════════════════╝';
    RAISE NOTICE '';
    RAISE NOTICE '🎯 Database siap digunakan!';
    RAISE NOTICE '💡 Gunakan SELECT * FROM vw_trigger_status; untuk cek semua trigger';
    RAISE NOTICE '💡 Gunakan disable_updated_at_triggers() untuk batch operation besar';
END $$;

-- =====================================================
-- END OF COMPLETE DATABASE SCRIPT
-- =====================================================