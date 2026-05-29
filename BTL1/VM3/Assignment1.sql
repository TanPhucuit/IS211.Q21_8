-- VIEW: Complete Business Information (from all 3 VMs)
CREATE VIEW V_BUSINESS_ALL AS
SELECT business_id, name, address, city, state, postal_code, latitude, longitude, 
       stars, review_count, is_open, categories, 'NV' as partition_key, 'VM1' as vm_location
FROM BUS_NV@VM1_link
UNION ALL
SELECT business_id, name, address, city, state, postal_code, latitude, longitude,
       stars, review_count, is_open, categories, 'AZ' as partition_key, 'VM2' as vm_location
FROM BUS_AZ@VM2_link
UNION ALL
SELECT business_id, name, address, city, state, postal_code, latitude, longitude,
       stars, review_count, is_open, categories, 'OTHER' as partition_key, 'VM3' as vm_location
FROM BUS_OTHER;


-- VIEW: Complete User Information (from all 3 VMs)
CREATE VIEW V_USER_ALL AS
SELECT u.user_id, u.name, u.yelping_since,
       us.review_count, us.average_stars,
       uv.useful, uv.funny, uv.cool
FROM USER_PROFILE@VM1_link u
JOIN USER_STATS@VM2_link us ON u.user_id = us.user_id
JOIN USER_VOTES uv ON u.user_id = uv.user_id;

-- VIEW: Complete Review Information (from all 3 VMs)
CREATE OR REPLACE VIEW V_REVIEW_ALL AS
SELECT review_id, user_id, business_id, stars, useful, funny, cool, review_date,
    CAST(ro.text AS VARCHAR2(4000)) AS text, 'OLD' AS period, 'VM1' AS vm_location
FROM REV_OLD_V@VM1_link ro
UNION ALL
SELECT review_id, user_id, business_id, stars, useful, funny, cool, review_date,
    CAST(rm.text AS VARCHAR2(4000)) AS text, 'MID' AS period, 'VM2' AS vm_location
FROM REV_MID_V@VM2_link rm
UNION ALL
SELECT rnc.review_id, rnc.user_id, rnc.business_id, rnc.stars, rnc.useful, rnc.funny, rnc.cool, rnc.review_date,
    rnt.text AS text, 'NEW' AS period, 'VM3' AS vm_location
FROM REV_NEW_CORE rnc
LEFT JOIN REV_NEW_TEXT_V@VM1_link rnt ON rnc.review_id = rnt.review_id;



-- Function
CREATE OR REPLACE FUNCTION fn_TongLuotDanhGia(
    p_business_id IN VARCHAR2,
    p_thang IN NUMBER,
    p_nam IN NUMBER
) RETURN NUMBER IS
    v_TongDanhGia NUMBER := 0;
    v_check NUMBER := 0;
BEGIN
    -- Kiểm tra tính hợp lệ của Tháng
    IF p_thang < 1 OR p_thang > 12 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Giá trị tháng không hợp lệ. Chỉ nhận giá trị từ 1 đến 12');
    END IF;

    -- Kiểm tra xem doanh nghiệp có tồn tại không 
    SELECT COUNT(*) 
    INTO v_check 
    FROM V_BUSINESS_ALL
    WHERE business_id = p_business_id;
    IF v_check = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Không tìm thấy doanh nghiệp ở bất kỳ bang trong hệ thống');
    ELSIF v_check > 1 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Nhiều doanh nghiệp trùng mã doanh nghiệp');
    END IF;

    -- Tính tổng lượt đánh giá theo năm của REVIEW (REVIEW phân mảnh ngang theo năm)
    IF p_nam < 2018 THEN
        -- Trước năm 2018: đánh giá nằm ở VM1 (mảnh REV_OLD)
        SELECT COUNT(review_id) 
        INTO v_TongDanhGia
        FROM REV_OLD@VM1_link
        WHERE business_id = p_business_id
          AND EXTRACT(MONTH FROM CAST(review_date AS TIMESTAMP)) = p_thang
          AND EXTRACT(YEAR FROM CAST(review_date AS TIMESTAMP)) = p_nam;
    ELSIF p_nam >= 2018 AND p_nam <= 2020 THEN
        -- 2018 -> 2020: đánh giá nằm ở VM2 (mảnh REV_MID)
        SELECT COUNT(review_id) 
        INTO v_TongDanhGia
        FROM REV_MID@VM2_link
        WHERE business_id = p_business_id
          AND EXTRACT(MONTH FROM CAST(review_date AS TIMESTAMP)) = p_thang
          AND EXTRACT(YEAR FROM CAST(review_date AS TIMESTAMP)) = p_nam;
    ELSE
        -- 2021 trở lên: đánh giá nằm ở VM3 (mảnh REV_NEW_CORE)
        SELECT COUNT(review_id) 
        INTO v_TongDanhGia
        FROM REV_NEW_CORE
        WHERE business_id = p_business_id
          AND EXTRACT(MONTH FROM CAST(review_date AS TIMESTAMP)) = p_thang
          AND EXTRACT(YEAR FROM CAST(review_date AS TIMESTAMP)) = p_nam;
    END IF;
    RETURN v_TongDanhGia;
EXCEPTION
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
        RAISE;
END fn_TongLuotDanhGia;
/

---	Test case 1 (input sai giá trị tháng):
SELECT fn_TongLuotDanhGia('tUFrWirKiKi_TAnsVWINQQ', 13, 2018) AS review_count FROM dual;

---	Test case 2 (doanh nghiệp không tồn tại)
SELECT fn_TongLuotDanhGia ('INVALID_ID_9999', 7, 2018) AS review_count FROM dual;

---	Test case 3 (hợp lệ - tính tổng đánh giá của cơ sở Target tại Tucson trong tháng 12/2018):
SELECT fn_TongLuotDanhGia ('tUFrWirKiKi_TAnsVWINQQ', 12, 2018) AS review_count FROM dual;




--Store Procedure 1 (Thêm đánh giá)
CREATE OR REPLACE PROCEDURE sp_ThemDanhGia(
    p_review_id IN VARCHAR2,
    p_user_id IN VARCHAR2,
    p_business_id IN VARCHAR2,
    p_stars IN NUMBER,
    p_review_date IN DATE,
    p_text IN CLOB 
) AS 
    v_check NUMBER := 0;
    v_year  NUMBER;
    v_bus_state VARCHAR2(10);
    v_bus_stars NUMBER := 0; 
    v_bus_reviews NUMBER := 0;
BEGIN
    v_year := EXTRACT(YEAR FROM p_review_date);

    -- Kiểm tra mã đánh giá đã tồn tại trong hệ thống chưa
    SELECT COUNT(*) 
    INTO v_check 
    FROM V_REVIEW_ALL
    WHERE review_id = p_review_id;
    IF v_check > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Lỗi: Đánh giá đã tồn tại trong hệ thống');
    END IF;

 -- Kiểm tra mã doanh nghiệp đã tồn tại trong hệ thống chưa
    SELECT COUNT(*)
    INTO v_check
    FROM V_BUSINESS_ALL
    WHERE business_id = p_business_id;
    IF v_check = 0 THEN
         RAISE_APPLICATION_ERROR(-20002, 'Lỗi: Doanh nghiệp không tồn tại' );
    END IF;

-- Kiểm tra mã người dùng đã tồn tại trong hệ thống chưa
     SELECT COUNT(*)
     INTO v_check
     FROM V_USER_ALL
     WHERE user_id = p_user_id;
     IF v_check = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Lỗi: Người dùng không tồn tại');
     END IF;

    -- Phân bổ dữ liệu dựa vào năm
    IF v_year <= 2020 THEN
        RAISE_APPLICATION_ERROR(-20004, 'Lỗi: Không được thêm đánh giá quá khứ');
    END IF;
    
    IF p_stars < 1 OR p_stars > 5 THEN
        RAISE_APPLICATION_ERROR(-20005, 'Lỗi: Sao đánh giá phải từ 1 đến 5');
    END IF;
    
    IF  v_year > 2020 THEN
        --Nếu từ 2021 trở đi  các thuộc tính ko phải text lưu ở REV_NEW_CORE ở VM3
        INSERT INTO REV_NEW_CORE (review_id, user_id, business_id, stars, review_date) VALUES (p_review_id, p_user_id, p_business_id, p_stars, p_review_date);

        -- Lưu Text ở mảnh REV_NEW_TEXT ở VM1
        INSERT INTO REV_NEW_TEXT@VM1_link (review_id, Text) VALUES (p_review_id, p_text);
    END IF;
    -- cập nhật lại cột review_count ở VM2
    UPDATE USER_STATS@VM2_link
    SET review_count = NVL(review_count, 0) + 1
    WHERE user_id = p_user_id;

    BEGIN 
        -- Lấy thông tin hiện tại của Business để tính toán 
        SELECT state, stars, review_count 
        INTO v_bus_state, v_bus_stars, v_bus_reviews 
        FROM V_BUSINESS_ALL
        WHERE business_id = p_business_id;
        -- Tính điểm trung bình (số sao = (Tổng sao cũ + sao mới) / Tổng lượt review mới)  
        v_bus_stars := ROUND(((NVL(v_bus_stars,0)*NVL(v_bus_reviews,0))+p_stars)
/(NVL(v_bus_reviews,0)+1), 2); 
        -- cập nhật lại số review thêm 1 
        v_bus_reviews := NVL(v_bus_reviews, 0) + 1; 
        -- Cập nhật vào đúng mảnh Business theo bang 
        IF v_bus_state = 'NV' THEN 
            UPDATE BUS_NV@VM1_link
            SET stars = v_bus_stars, review_count = v_bus_reviews 
            WHERE business_id = p_business_id; 
        ELSIF v_bus_state = 'AZ' THEN 
            UPDATE BUS_AZ@VM2_link 
            SET stars = v_bus_stars, review_count = v_bus_reviews 
            WHERE business_id = p_business_id; 
        ELSE 
            UPDATE BUS_OTHER
            SET stars = v_bus_stars, review_count = v_bus_reviews 
            WHERE business_id = p_business_id; 
        END IF; 
        EXCEPTION 
        WHEN NO_DATA_FOUND THEN 
            RAISE_APPLICATION_ERROR(-20006, 'Lỗi: Không tìm thấy doanh nghiệp để cập nhật review.'); 
    END;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Thêm thành công đánh giá mới ID: ' || p_review_id); 
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20007, 'Lỗi hệ thống khi thêm đánh giá: ' || SQLERRM);
END sp_ThemDanhGia;
/


-- -	Test case 1 (Thêm thành công):
BEGIN
       sp_ThemDanhGia ('RV1', '-AJV31rH5tZmKI0f0rlQnA', 'Si6LXSR9gvAbmgO5DzV2cw', 5, TO_DATE('23-AUG-26','DD-MON-YY'), 'good');
END;
/


select * from v_business_all where business_id='Si6LXSR9gvAbmgO5DzV2cw';
select * from v_review_all where user_id='-AJV31rH5tZmKI0f0rlQnA';

-- -	Test case 2 (review đã tồn tại)
BEGIN
       sp_ThemDanhGia ('JBWZmBy69VMggxj3eYn17Q', '-AJV31rH5tZmKI0f0rlQnA', 'Si6LXSR9gvAbmgO5DzV2cw', 3, '23-AUG-17', 'normalize');
END;
/

-- -	Test case 3: thêm review vào năm trước 2020 báo lỗi vì không được thêm dữ liệu quá khứ
BEGIN
      sp_ThemDanhGia ('RV2', '-AJV31rH5tZmKI0f0rlQnA', 'Si6LXSR9gvAbmgO5DzV2cw', 5, TO_DATE('23-AUG-19', 'DD-MON-YY'), 'good');
END;
/


-- Store Proceduce 2 (Ẩn đanh giá nếu vi phạm cộng đồng)
CREATE OR REPLACE PROCEDURE sp_anreviewvpcd(
    p_user_id IN VARCHAR2,
    p_review_id IN VARCHAR2,
    p_review_date IN DATE
) AS 
    v_check_u NUMBER := 0;
    v_check_r NUMBER := 0;
    v_year NUMBER:=EXTRACT(YEAR FROM p_review_date);
BEGIN
    -- Kiểm tra người dùng có tồn tại trong hệ thống không
    SELECT COUNT(*) INTO v_check_u
    FROM V_USER_ALL
    WHERE user_id = p_user_id;
    IF v_check_u = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'Lỗi: Không tìm thấy người dùng.');
    END IF;
    -- Kiểm tra đánh giá có tồn tại và là đánh giá của người dùng nhập vào không
    SELECT COUNT(*) INTO v_check_r
    FROM V_REVIEW_ALL
    WHERE review_id = p_review_id AND user_id = p_user_id;
    IF v_check_r = 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'Lỗi: Đánh giá không tồn tại hoặc không thuộc về người dùng này.');
    END IF;
    
    -- Ẩn review ở VM1
    IF v_year < 2018 THEN
        UPDATE REV_OLD
        SET "text" = '[Nội dung bị ẩn do người dùng vi phạm tiêu chuẩn cộng đồng]'
        WHERE user_id = p_user_id and review_id = p_review_id;

    -- Ẩn review ở VM2
    ELSIF v_year >= 2018 AND v_year <= 2020  THEN 
        UPDATE REV_MID@VM2_link
        SET "text" = '[Nội dung bị ẩn do người dùng vi phạm tiêu chuẩn cộng đồng]'
        WHERE user_id = p_user_id and review_id = p_review_id;

    -- Ẩn review ở VM3 nhưng join 2 mảnh dọc để ẩn review theo id
    ELSE 
        UPDATE REV_NEW_TEXT
        SET "text" = '[Nội dung bị ẩn do người dùng vi phạm tiêu chuẩn cộng đồng]'
        WHERE review_id IN (
            SELECT review_id
            FROM REV_NEW_CORE 
            WHERE user_id = p_user_id and review_id = p_review_id
        );
    END IF;
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Thành công: Đã ẩn nội dung đánh giá: ' || p_review_id || ' của User ' || p_user_id);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20002, 'Lỗi khi thực hiện ẩn đánh giá: ' || SQLERRM);
END sp_anreviewvpcd;
/ 
-- Cấp quyền cho Quản lý thực hiện
GRANT EXECUTE ON sp_anreviewvpcd TO QuanLy;






--- Trigger 1
CREATE OR REPLACE TRIGGER trg_dongbo_category
BEFORE INSERT OR UPDATE OR DELETE ON CATEGORY
FOR EACH ROW
BEGIN
    RAISE_APPLICATION_ERROR( -20099, 'CATEGORY chỉ được cập nhật tại VM1');
END;
/

--	Test case 1: Thêm một doanh nghiệp.
BEGIN
    INSERT INTO CATEGORY (category_id, category_name) VALUES ('100', 'Tiệm ăn uống Khu Rừng Nhỏ ');
END;
/

-- Test case 2: Xóa một thể loại
BEGIN
    DELETE FROM CATEGORY 
    WHERE category_id = '100';
    COMMIT; 
    DBMS_OUTPUT.PUT_LINE('Đã xóa thể loại có mã 100 tại 3 máy ảo.');
END;
/



-- Trigger 2
CREATE OR REPLACE TRIGGER trg_DanhGia
BEFORE INSERT OR UPDATE OF review_date, stars ON REV_NEW_CORE
FOR EACH ROW 
DECLARE
v_today DATE := TRUNC(SYSDATE);
BEGIN
    -- Lấy ngày hiện tại
    SELECT SYSDATE INTO v_today FROM DUAL;
    -- Kiểm tra ngày đánh giá không được vượt quá ngày hiện tại
    IF TRUNC(:NEW.review_date) > v_today THEN
    RAISE_APPLICATION_ERROR(-20001, 'Lỗi: Ngày đánh giá không được vượt quá ngày hiện tại.');
    END IF;
    -- Hàm TRUNC kiểm tra xem có phải là số nguyên ko và stars phải trong khoảng [1,5]
    IF :NEW.stars < 1 OR :NEW.stars > 5 OR TRUNC(:NEW.stars) <> :NEW.stars THEN RAISE_APPLICATION_ERROR(-20002, 'Lỗi: Số sao đánh giá bắt buộc phải là số nguyên từ 1 đến 5.'); 
    END IF; 
END; 
/

-- Test case 1 (hợp lệ): Thêm một đánh giá mới vào ngày hiện tại và đánh giá 4 sao.
BEGIN
    INSERT INTO REV_NEW_CORE (review_id, user_id, business_id, stars, review_date) VALUES ('KU_O5udG6zpxOg-VcAEo11', 'mh_-eMZ6K5RLWhZyISBhwA', 'cPepkJeRMtHapc_b2Oe_dw', 4, SYSDATE);
    COMMIT; 
    DBMS_OUTPUT.PUT_LINE('Thành công: Thêm đánh giá thành công.'); 
END; 
/

-- Test case 2: Thêm đánh giá có ngày đánh giá lớn hơn ngày hiện tại  Báo lỗi.
BEGIN
    INSERT INTO REV_NEW_CORE (review_id, user_id, business_id, stars, review_date) VALUES ('KU_O5udG6zpxOg-VcAEo12', 'mh_-eMZ6K5RLWhZyISBhwA', 'cPepkJeRMtHapc_b2Oe_dw', 4, SYSDATE + 10);
END;
/

-- Test case 3: Thêm đánh giá có số sao nằm ngoài khoảng 1 đến 5  Báo lỗi.
BEGIN
    INSERT INTO REV_NEW_CORE (review_id, user_id, business_id, stars, review_date) VALUES ('KU_O5udG6zpxOg-VcAEo13', 'mh_-eMZ6K5RLWhZyISBhwA', 'cPepkJeRMtHapc_b2Oe_dw', 6, SYSDATE);
END;
/


-- Test case 4: Sửa ngày đánh giá thành ngày lớn hơn hiện tại  Báo lỗi.
BEGIN
    UPDATE REV_MID@VM1_link
    SET review_date = SYSDATE + 5
    WHERE review_id = 'KU_O5udG6zpxOg-VcAEodg';
END;
/











-------------------------MẤT TÍNH NHẤT QUÁN DỮ LIỆU -------------------------------
----------------------------- LOST UPDATE ------------------------------------
-- VM2 cập nhật lại review_count là 14 thì VM3 cập nhật tiếp phải ra 9 nhưng do ko có cơ chế khóa nên ra 10
-- --> mất tính nhất quán 
-- VM2
DECLARE
   v_count NUMBER;
BEGIN
    SELECT us.review_count INTO v_count -- 15
    FROM USER_STATS us
    WHERE us.user_id = 'r9OnOogWUKW8RXzfa3MsZQ'
      AND EXISTS (
          SELECT 1 FROM REV_NEW_CORE@VM3_link r_new
          INNER JOIN BUS_OTHER@VM3_link b_oth ON r_new.business_id = b_oth.business_id
          WHERE r_new.user_id = us.user_id AND r_new.stars >= 4
      );

    DBMS_LOCK.SLEEP(4);
    
    UPDATE USER_STATS
    SET review_count = v_count - 1 -- 14
    WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';
    COMMIT;
END;
/


rollback;
ALTER SESSION SET ISOLATION_LEVEL = READ COMMITTED;
-- VM3
DECLARE
   v_count NUMBER;
BEGIN
    SELECT us.review_count INTO v_count -- 15
    FROM USER_STATS@VM2_link us
    WHERE us.user_id = 'r9OnOogWUKW8RXzfa3MsZQ'
      AND EXISTS (
          SELECT 1 FROM REV_NEW_CORE r_new
          INNER JOIN BUS_OTHER b_oth ON r_new.business_id = b_oth.business_id
          WHERE r_new.user_id = us.user_id AND r_new.stars >= 4
      );
    
    DBMS_LOCK.SLEEP(4);
    
    UPDATE USER_STATS@VM2_link
    SET review_count = v_count - 5  -- 10
    WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';
    COMMIT;
END;
/

-- CÁCH GIẢI QUYẾT: thêm cơ chế khóa ở SELECT là FOR UPDATE tương tự UPDLOCK và HOLDLOCK trong SQL
--> VM2 giữ khóa trc, thực hiện cập nhật xuống 14 thì Vm3 mới dc đọc gái trị 14 và cập nhật xuống 9
-- VM2
DECLARE
   v_count NUMBER;
BEGIN
    SELECT us.review_count INTO v_count -- 15
    FROM USER_STATS us
    WHERE us.user_id = 'r9OnOogWUKW8RXzfa3MsZQ'
      AND EXISTS (
          SELECT 1 FROM REV_NEW_CORE@VM3_link r_new
          INNER JOIN BUS_OTHER@VM3_link b_oth ON r_new.business_id = b_oth.business_id
          WHERE r_new.user_id = us.user_id AND r_new.stars >= 4
      )
    FOR UPDATE;

    DBMS_LOCK.SLEEP(4);
    
    UPDATE USER_STATS
    SET review_count = v_count - 1 -- 14
    WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';
    COMMIT;
END;
/

-- VM3
DECLARE
   v_count NUMBER;
BEGIN
    SELECT us.review_count INTO v_count -- 15
    FROM USER_STATS@VM2_link us
    WHERE us.user_id = 'r9OnOogWUKW8RXzfa3MsZQ'
      AND EXISTS (
          SELECT 1 FROM REV_NEW_CORE r_new
          INNER JOIN BUS_OTHER b_oth ON r_new.business_id = b_oth.business_id
          WHERE r_new.user_id = us.user_id AND r_new.stars >= 4
      )
    FOR UPDATE;
    
    DBMS_LOCK.SLEEP(4);
    
    UPDATE USER_STATS@VM2_link
    SET review_count = v_count - 5  -- 10
    WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';
    COMMIT;
END;
/

----------------------------- Unrepeatable Read --------------------------------
ROLLBACK;
-- VM2 select 2 lần ra 2 dữ liệu khác nhau sau khi VM3 chỉnh sửa 
-- --> Trong cùng một tài khoản người dùng, lần 1 đọc khác lần 2 đọc khác --> Dữ liệu không nhất quán
-- VM2
ALTER SESSION SET ISOLATION_LEVEL = READ COMMITTED;
-- Lần đọc 1: Thống kê doanh nghiệp có nhiều đánh giá tiêu cực nhất và tính trung bình số sao doanh nghiệp nhận được
SELECT *
FROM (
    SELECT 
        b.business_id, b.review_count AS bus_review_count, AVG(r.stars) AS avg_rating, COUNT(r.review_id) AS total_negative_reviews
    FROM REV_NEW_CORE@VM3_link r
    INNER JOIN BUS_OTHER@VM3_link b ON r.business_id = b.business_id
    WHERE r.stars < 3 AND b.review_count > 500
    GROUP BY b.business_id, b.review_count
    ORDER BY total_negative_reviews DESC
)
WHERE ROWNUM = 1;
-- KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', bus_review_count= 1223, avg_rating: 1.455, total_negative_reviews=90

-- VM3
UPDATE BUS_OTHER
SET review_count = review_count + 20
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw';
UPDATE REV_NEW_CORE
SET stars = 2
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw' and review_id ='5GIiA6qhAQn0ZfXwlzAUVg';
COMMIT;

select * from REV_NEW_CORE
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw';
-- Lần đọc 2: Thực thi lại chính xác như lần 1 nhưng kết quả lại khác 
SELECT *
FROM (
    SELECT 
        b.business_id, b.review_count AS bus_review_count, AVG(r.stars) AS avg_rating, COUNT(r.review_id) AS total_negative_reviews
    FROM REV_NEW_CORE@VM3_link r
    INNER JOIN BUS_OTHER@VM3_link b ON r.business_id = b.business_id
    WHERE r.stars < 3 AND b.review_count > 500
    GROUP BY b.business_id, b.review_count
    ORDER BY total_negative_reviews DESC
)
WHERE ROWNUM = 1;
-- KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', bus_review_count= 1243, avg_rating: 1.4615, total_negative_reviews=91
-- số lượng review tiêu cực tăng 1 vì cập nhật lại 1 review từ 4 sao về 2 sao

-- reset
UPDATE BUS_OTHER
SET review_count = review_count - 20
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw';
UPDATE REV_NEW_CORE
SET stars = 4
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw' and review_id ='5GIiA6qhAQn0ZfXwlzAUVg';
COMMIT;

-- GIẢI QUYẾT
-- vì read commited sẽ snapshot theo từng statemnent nên Vm3 update thì 2 lần select kết quả ko đồng nhất
-- Dùng serializable sẽ snapshot theo toàn transaction để đóng băng snapshot đã select
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Lần đọc 1: Thống kê doanh nghiệp có nhiều đánh giá tiêu cực nhất và tính trung bình số sao doanh nghiệp nhận được
SELECT *
FROM (
    SELECT 
        b.business_id, b.review_count AS bus_review_count, AVG(r.stars) AS avg_rating, COUNT(r.review_id) AS total_negative_reviews
    FROM REV_NEW_CORE@VM3_link r
    INNER JOIN BUS_OTHER@VM3_link b ON r.business_id = b.business_id
    WHERE r.stars < 3 AND b.review_count > 500
    GROUP BY b.business_id, b.review_count
    ORDER BY total_negative_reviews DESC
)
WHERE ROWNUM = 1;
-- KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', bus_review_count= 1223, avg_rating: 1.455, total_negative_reviews=90

-- VM3
UPDATE BUS_OTHER
SET review_count = review_count + 20
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw';
UPDATE REV_NEW_CORE
SET stars = 2
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw' and review_id ='5GIiA6qhAQn0ZfXwlzAUVg';
COMMIT;

select * from REV_NEW_CORE@VM3_link
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw';
-- Lần đọc 2: Thực thi lại chính xác như lần 1 nhưng kết quả giống lần 1
SELECT *
FROM (
    SELECT 
        b.business_id, b.review_count AS bus_review_count, AVG(r.stars) AS avg_rating, COUNT(r.review_id) AS total_negative_reviews
    FROM REV_NEW_CORE@VM3_link r
    INNER JOIN BUS_OTHER@VM3_link b ON r.business_id = b.business_id
    WHERE r.stars < 3 AND b.review_count > 500
    GROUP BY b.business_id, b.review_count
    ORDER BY total_negative_reviews DESC
)
WHERE ROWNUM = 1;
-- KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', bus_review_count= 1223, avg_rating: 1.455, total_negative_reviews=90
-- số lượng review tiêu cực tăng 1 vì cập nhật lại 1 review từ 4 sao về 2 sao
COMMIt;
-- reset
UPDATE BUS_OTHER@VM3_link
SET review_count = review_count - 20
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw';
UPDATE REV_NEW_CORE@VM3_link
SET stars = 4
WHERE business_id = 'SJIQFKTW6uUsOo29w9IHxw' and review_id ='5GIiA6qhAQn0ZfXwlzAUVg';
COMMIT;

----------------------------- PHANTOM READ ------------------------------------
ROLLBACK;
-- truy vấn lần đầu 1 và lần 2 có kết quả khác nhau do có thêm bản ghi mới
-- --> mất tính nhất quán 
ALTER SESSION SET ISOLATION_LEVEL = READ COMMITTED;
-- VM3
-- Lần đọc 1: Thống kê doanh nghiệp có hơn 500 đánh giá và có số lượng review tích cực (>4 sao)(số lượng đánh giá lớn hơn 50) nhiều nhất 
SELECT * 
FROM (
    SELECT b.business_id, b.review_count, COUNT(r.review_id) AS total_positive_reviews
    FROM REV_NEW_CORE r
    INNER JOIN BUS_OTHER b ON r.business_id = b.business_id
    WHERE r.stars >= 4 AND b.review_count > 100
    GROUP BY b.business_id, b.review_count
    HAVING COUNT(r.review_id) > 50
    ORDER BY total_positive_reviews DESC
    )
WHERE ROWNUM = 1;
-- KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', Bus_count = 1223, total_positive = 469

-- VM2: Sang VM2 thực hiện INSERT bản ghi mới và COMMIT
INSERT INTO REV_NEW_CORE@VM3_link (review_id, user_id, stars, business_id, review_date) 
VALUES ('RV001', '4Umzq2_FQE4t0Yrq266-DQ', 5, 'SJIQFKTW6uUsOo29w9IHxw', SYSDATE);
COMMIT;

-- VM3
-- Lần đọc 2: Thực hiện lại câu lệnh đếm tổng hợp trên
SELECT * 
FROM (
    SELECT b.business_id, b.review_count, COUNT(r.review_id) AS total_positive_reviews
    FROM REV_NEW_CORE r
    INNER JOIN BUS_OTHER b ON r.business_id = b.business_id
    WHERE r.stars >= 4 AND b.review_count > 100
    GROUP BY b.business_id, b.review_count
    HAVING COUNT(r.review_id) > 50
    ORDER BY total_positive_reviews DESC
    )
WHERE ROWNUM = 1;
-- KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', Bus_count = 1223, total_positive = 470

-- reset data
DELETE FROM  REV_NEW_CORE
WHERE review_id = 'RV001';
COMMIT;
-- CÁCH GIẢI QUYẾT:
-- vì read commited sẽ snapshot theo từng statemnent nên Vm3 update thì 2 lần select kết quả ko đồng nhất; 
-- serializable sẽ snapshot theo toàn transaction để đóng băng snapshot đã select
rollback;
ALTER SESSION SET ISOLATION_LEVEL = SERIALIZABLE;
-- VM3
SELECT * 
FROM (
    SELECT b.business_id, b.review_count, COUNT(r.review_id) AS total_positive_reviews
    FROM REV_NEW_CORE r
    INNER JOIN BUS_OTHER b ON r.business_id = b.business_id
    WHERE r.stars >= 4 AND b.review_count > 100
    GROUP BY b.business_id, b.review_count
    HAVING COUNT(r.review_id) > 50
    ORDER BY total_positive_reviews DESC
    )
WHERE ROWNUM = 1;
--VM2
INSERT INTO REV_NEW_CORE@VM3_link (review_id, user_id, stars, business_id, review_date) 
VALUES ('RV006', '4Umzq2_FQE4t0Yrq266-DQ', 5, 'SJIQFKTW6uUsOo29w9IHxw', SYSDATE);
COMMIT;
--VM3
SELECT * 
FROM (
    SELECT b.business_id, b.review_count, COUNT(r.review_id) AS total_positive_reviews
    FROM REV_NEW_CORE r
    INNER JOIN BUS_OTHER b ON r.business_id = b.business_id
    WHERE r.stars >= 4 AND b.review_count > 100
    GROUP BY b.business_id, b.review_count
    HAVING COUNT(r.review_id) > 50
    ORDER BY total_positive_reviews DESC
    )
WHERE ROWNUM = 1; 
-- KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', Bus_count = 1223, total_positive = 469
COMMIT; 
-- sau khi commit select lại KQ: business_id = 'SJIQFKTW6uUsOo29w9IHxw', Bus_count = 1223, total_positive = 470


----------------------------- DEADLOCK ------------------------------------
-- VM2
-- Tiến trình 1: Cập nhật User
UPDATE USER_STATS 
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE@VM3_link 
    WHERE user_id = USER_STATS.user_id AND stars >= 4
)
WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';


--VM3
-- Tiến trình 2: Cập nhật Doanh nghiệp
UPDATE BUS_OTHER 
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE 
    WHERE business_id = BUS_OTHER.business_id
)
WHERE business_id = 'n7AQvGvNHlmun3kqXeBKVQ';


--VM2
UPDATE BUS_OTHER@VM3_link
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE 
    WHERE business_id = BUS_OTHER.business_id
)
WHERE business_id = 'n7AQvGvNHlmun3kqXeBKVQ';
--VM3
UPDATE USER_STATS@VM2_link
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE
    WHERE user_id = USER_STATS.user_id AND stars >= 4
)
WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';


--- GIẢI QUYẾT
-- VM2
-- Tiến trình 1: Cập nhật User
UPDATE USER_STATS 
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE@VM3_link 
    WHERE user_id = USER_STATS.user_id AND stars >= 4
)
WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';
COMMIT;

--VM3
-- Tiến trình 2: Cập nhật Doanh nghiệp
UPDATE BUS_OTHER 
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE 
    WHERE business_id = BUS_OTHER.business_id
)
WHERE business_id = 'n7AQvGvNHlmun3kqXeBKVQ';
COMMIT;

--VM2
-- Tiến trình 3:
UPDATE BUS_OTHER@VM3_link
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE 
    WHERE business_id = BUS_OTHER.business_id
)
WHERE business_id = 'n7AQvGvNHlmun3kqXeBKVQ';
COMMIT;

--VM3
-- Tiến trình 4: 
SET review_count = (
    SELECT COUNT(*) 
    FROM REV_NEW_CORE
    WHERE user_id = USER_STATS.user_id AND stars >= 4
)
WHERE user_id = 'r9OnOogWUKW8RXzfa3MsZQ';
COMMIT;






----QUERY
EXPLAIN PLAN FOR
SELECT
    u.name AS UserName, 
    b.name AS BusinessName,
 	c.stars, 
    t.text 
FROM 
    (SELECT * FROM USER_PROFILE@VM1_link) u,
    (SELECT * FROM BUS_OTHER) b, 
    (SELECT * FROM REV_NEW_CORE) c,
    (SELECT * FROM REV_NEW_TEXT@VM1_link) t
WHERE 
    u.user_id = c.user_id 
    AND t.review_id = c.review_id
    AND c.business_id = b.business_id 
    AND c.stars = 5 
    AND c.review_date >= TO_DATE('01-01-2022', 'DD-MM-YYYY')
    AND c.review_date < TO_DATE('01-01-2023', 'DD-MM-YYYY');




SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

ALTER SYSTEM FLUSH SHARED_POOL;

CREATE INDEX idx_user_id_lookup ON USER_PROFILE (user_id, name);--Chạy tại máy 1

EXPLAIN PLAN FOR
SELECT
    u.name AS UserName, 
    b.name AS BusinessName,
    c.stars, 
    t.text 
FROM 
    (
    SELECT user_id, business_id, stars, review_id 
    FROM REV_NEW_CORE
    WHERE stars = 5 
    AND review_date >= TO_DATE('01-01-2022', 'DD-MM-YYYY')
    AND review_date < TO_DATE('01-01-2023', 'DD-MM-YYYY')
    ) c
JOIN
	(SELECT review_id, text FROM REV_NEW_TEXT@VM1_link) t 
    ON t.review_id = c.review_id
JOIN 
    (SELECT business_id, name FROM BUS_OTHER) b 
    ON c.business_id = b.business_id
JOIN 
	(SELECT user_id, name FROM USER_PROFILE@VM1_link) u 
    ON u.user_id = c.user_id
