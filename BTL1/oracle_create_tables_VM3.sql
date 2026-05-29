-- ============================================================================
-- YELP DATASET - VM3 (OTHER STATES NODE) - ORACLE DATABASE SCHEMA
-- Tables: CATEGORY (replicated), BUS_OTHER, USER_VOTES, REV_NEW_CORE
-- ============================================================================

-- ============================================================================
-- PART 1: CATEGORY TABLE (Full Replication on VM3)
-- ============================================================================

CREATE TABLE CATEGORY (
    category_id     NUMBER(6) PRIMARY KEY,
    category_name   VARCHAR2(255) NOT NULL,
    created_date    DATE DEFAULT SYSDATE
);

CREATE INDEX idx_category_name ON CATEGORY(category_name);

-- ============================================================================
-- PART 2: BUSINESS TABLE - VM3 ONLY (Other States)
-- ============================================================================

CREATE TABLE BUS_OTHER (
    business_id     VARCHAR2(22) PRIMARY KEY,
    name            VARCHAR2(500) NOT NULL,
    address         VARCHAR2(255),
    city            VARCHAR2(100),
    state           VARCHAR2(2),
    postal_code     VARCHAR2(20),
    latitude        DECIMAL(10,7),
    longitude       DECIMAL(10,7),
    stars           DECIMAL(3,1),
    review_count    NUMBER(6),
    is_open         NUMBER(1),
    categories      VARCHAR2(1000),
    created_date    DATE DEFAULT SYSDATE
);

CREATE INDEX idx_bus_other_state ON BUS_OTHER(state);
CREATE INDEX idx_bus_other_stars ON BUS_OTHER(stars);
CREATE INDEX idx_bus_other_city ON BUS_OTHER(city);

-- ============================================================================
-- PART 3: USER TABLE - VM3 ONLY (Votes/Engagement)
-- ============================================================================

CREATE TABLE USER_PROFILE (
    user_id         VARCHAR2(22) PRIMARY KEY,
    name            VARCHAR2(255) NOT NULL,
    yelping_since   DATE,
    created_date    DATE DEFAULT SYSDATE
);

CREATE INDEX idx_user_profile_name ON USER_PROFILE(name);

CREATE TABLE USER_VOTES (
    user_id         VARCHAR2(22) PRIMARY KEY,
    useful          NUMBER(8),
    funny           NUMBER(8),
    cool            NUMBER(8),
    created_date    DATE DEFAULT SYSDATE,
    FOREIGN KEY (user_id) REFERENCES USER_PROFILE(user_id)
);

CREATE INDEX idx_user_votes_useful ON USER_VOTES(useful);
CREATE INDEX idx_user_votes_funny ON USER_VOTES(funny);
CREATE INDEX idx_user_votes_cool ON USER_VOTES(cool);

-- ============================================================================
-- PART 4: REVIEW TABLE - VM3 ONLY (New Core Reviews 2021+)
-- ============================================================================

CREATE TABLE REV_NEW_CORE (
    review_id       VARCHAR2(22) PRIMARY KEY,
    user_id         VARCHAR2(22) NOT NULL,
    business_id     VARCHAR2(22) NOT NULL,
    stars           DECIMAL(2,1),
    useful          NUMBER(6),
    funny           NUMBER(6),
    cool            NUMBER(6),
    review_date     DATE,
    created_date    DATE DEFAULT SYSDATE,
    FOREIGN KEY (user_id) REFERENCES USER_PROFILE(user_id)
);

CREATE INDEX idx_rev_new_core_user ON REV_NEW_CORE(user_id);
CREATE INDEX idx_rev_new_core_business ON REV_NEW_CORE(business_id);
CREATE INDEX idx_rev_new_core_date ON REV_NEW_CORE(review_date);
CREATE INDEX idx_rev_new_core_stars ON REV_NEW_CORE(stars);

-- ============================================================================
-- PART 5: VIEWS FOR DISTRIBUTED QUERIES (Data from all 3 VMs via DBLink)
-- ============================================================================

-- VIEW: Complete Business Information (from all 3 VMs)
CREATE VIEW V_BUSINESS_ALL_VM123 AS
SELECT business_id, name, address, city, state, postal_code, latitude, longitude, 
       stars, review_count, is_open, categories, 'NV' as partition_key, 'VM1' as vm_location
FROM BUS_NV@VM1
UNION ALL
SELECT business_id, name, address, city, state, postal_code, latitude, longitude,
       stars, review_count, is_open, categories, 'AZ' as partition_key, 'VM2' as vm_location
FROM BUS_AZ@VM2
UNION ALL
SELECT business_id, name, address, city, state, postal_code, latitude, longitude,
       stars, review_count, is_open, categories, 'OTHER' as partition_key, 'VM3' as vm_location
FROM BUS_OTHER;

-- VIEW: Complete User Information (from all 3 VMs)
CREATE VIEW V_USER_COMPLETE_VM123 AS
SELECT u.user_id, u.name, u.yelping_since,
       us.review_count, us.average_stars,
       uv.useful, uv.funny, uv.cool
FROM USER_PROFILE@VM1 u
JOIN USER_STATS@VM2 us ON u.user_id = us.user_id
JOIN USER_VOTES uv ON u.user_id = uv.user_id;

-- VIEW: Complete Review Information (from all 3 VMs)
CREATE VIEW V_REVIEW_ALL_VM123 AS
SELECT review_id, user_id, business_id, stars, useful, funny, cool, review_date, text, 'OLD' as time_period, 'VM1' as vm_location
FROM REV_OLD@VM1
UNION ALL
SELECT review_id, user_id, business_id, stars, useful, funny, cool, review_date, text, 'MID' as time_period, 'VM2' as vm_location
FROM REV_MID@VM2
UNION ALL
SELECT rnc.review_id, rnc.user_id, rnc.business_id, rnc.stars, rnc.useful, rnc.funny, rnc.cool, 
       rnc.review_date, rnt.text, 'NEW' as time_period, 'VM3' as vm_location
FROM REV_NEW_CORE rnc
LEFT JOIN REV_NEW_TEXT@VM1 rnt ON rnc.review_id = rnt.review_id;

-- ============================================================================
-- PART 6: METADATA TABLES
-- ============================================================================

CREATE TABLE DISTRIBUTED_NODES (
    node_id         NUMBER(2) PRIMARY KEY,
    vm_name         VARCHAR2(20),
    db_link_name    VARCHAR2(50),
    host_ip         VARCHAR2(15),
    port            NUMBER(5),
    service_name    VARCHAR2(50),
    status          VARCHAR2(10),
    created_date    DATE DEFAULT SYSDATE
);

INSERT INTO DISTRIBUTED_NODES VALUES (1, 'VM1', 'VM1@YELP', '192.168.x.x', 1521, 'yelp_vm1', 'ACTIVE', SYSDATE);
INSERT INTO DISTRIBUTED_NODES VALUES (2, 'VM2', 'VM2@YELP', '192.168.x.x', 1521, 'yelp_vm2', 'ACTIVE', SYSDATE);
INSERT INTO DISTRIBUTED_NODES VALUES (3, 'VM3', 'VM3@YELP', '192.168.x.x', 1521, 'yelp_vm3', 'ACTIVE', SYSDATE);

COMMIT;

CREATE TABLE PARTITIONING_METADATA (
    table_name      VARCHAR2(50),
    partition_type  VARCHAR2(20),
    partition_key   VARCHAR2(50),
    vm_location     VARCHAR2(10),
    row_count       NUMBER(10),
    size_mb         DECIMAL(12,2),
    last_updated    DATE DEFAULT SYSDATE,
    PRIMARY KEY (table_name, vm_location)
);

INSERT INTO PARTITIONING_METADATA VALUES ('CATEGORY', 'REPLICATION', 'N/A', 'VM3', 1000, 0.02, SYSDATE);
INSERT INTO PARTITIONING_METADATA VALUES ('BUSINESS', 'HORIZONTAL', 'state', 'VM3', 8807, 1.51, SYSDATE);
INSERT INTO PARTITIONING_METADATA VALUES ('USER', 'VERTICAL', 'user_id', 'VM3', 50000, 1.56, SYSDATE);
INSERT INTO PARTITIONING_METADATA VALUES ('REVIEW', 'HYBRID', 'year+vertical', 'VM3', 69358, 6.62, SYSDATE);

COMMIT;

-- ============================================================================
-- VM3 SETUP COMPLETE
-- ============================================================================
SELECT 'VM3 Schema creation completed successfully!' as status FROM dual;
