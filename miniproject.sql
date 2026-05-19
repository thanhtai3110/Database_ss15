CREATE DATABASE IF NOT EXISTS social_network;
USE social_network;

-- =====================================
-- 1. TABLE USERS
-- =====================================
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =====================================
-- 2. TABLE POSTS
-- =====================================
CREATE TABLE posts (
    post_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    like_count INT DEFAULT 0,
    comment_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_posts_user
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
);

-- =====================================
-- 3. TABLE COMMENTS
-- =====================================
CREATE TABLE comments (
    comment_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT NOT NULL,
    user_id INT NOT NULL,
    content TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_comments_post
    FOREIGN KEY (post_id)
    REFERENCES posts(post_id),

    CONSTRAINT fk_comments_user
    FOREIGN KEY (user_id)
    REFERENCES users(user_id)
);

-- =====================================
-- 4. TABLE FRIENDS
-- =====================================
CREATE TABLE friends (
    friendship_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    friend_id INT NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_friends_user
    FOREIGN KEY (user_id)
    REFERENCES users(user_id),

    CONSTRAINT fk_friends_friend
    FOREIGN KEY (friend_id)
    REFERENCES users(user_id),

    CONSTRAINT unique_friendship
    UNIQUE(user_id, friend_id)
);

-- =====================================
-- 5. TABLE LIKES
-- =====================================
CREATE TABLE likes (
    like_id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    post_id INT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_likes_user
    FOREIGN KEY (user_id)
    REFERENCES users(user_id),

    CONSTRAINT fk_likes_post
    FOREIGN KEY (post_id)
    REFERENCES posts(post_id),

    CONSTRAINT unique_user_post_like
    UNIQUE(user_id, post_id)
);

-- =====================================
-- 6. TABLE POST LOGS
-- =====================================
CREATE TABLE post_logs (
    log_id INT PRIMARY KEY AUTO_INCREMENT,
    post_id INT,
    deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    message VARCHAR(255)
);

-- =====================================
-- FULLTEXT SEARCH
-- =====================================
ALTER TABLE posts
ADD FULLTEXT(content);

-- =====================================
-- VIEW USER INFO
-- Không lấy password vì bảo mật
-- =====================================
CREATE VIEW view_user_info AS
SELECT
    user_id,
    username,
    email,
    created_at
FROM users;

-- =====================================
-- TRIGGER KIỂM SOÁT KẾT BẠN
-- =====================================
DELIMITER //

CREATE TRIGGER tg_before_friend_insert
BEFORE INSERT ON friends
FOR EACH ROW
BEGIN

    -- Tự kết bạn
    IF NEW.user_id = NEW.friend_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot friend yourself';
    END IF;

    -- Trùng dữ liệu
    IF EXISTS (
        SELECT 1
        FROM friends
        WHERE user_id = NEW.user_id
        AND friend_id = NEW.friend_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Friendship already exists';
    END IF;

    -- Đảo chiều
    IF EXISTS (
        SELECT 1
        FROM friends
        WHERE user_id = NEW.friend_id
        AND friend_id = NEW.user_id
    ) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Reverse friendship already exists';
    END IF;

END //

DELIMITER ;

-- =====================================
-- TRIGGER LIKE INSERT
-- =====================================
DELIMITER //

CREATE TRIGGER tg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN

    UPDATE posts
    SET like_count = like_count + 1
    WHERE post_id = NEW.post_id;

END //

DELIMITER ;

-- =====================================
-- TRIGGER LIKE DELETE
-- =====================================
DELIMITER //

CREATE TRIGGER tg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN

    UPDATE posts
    SET like_count =
        CASE
            WHEN like_count > 0 THEN like_count - 1
            ELSE 0
        END
    WHERE post_id = OLD.post_id;

END //

DELIMITER ;

-- =====================================
-- TRIGGER COMMENT INSERT
-- =====================================
DELIMITER //

CREATE TRIGGER tg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN

    UPDATE posts
    SET comment_count = comment_count + 1
    WHERE post_id = NEW.post_id;

END //

DELIMITER ;

-- =====================================
-- TRIGGER COMMENT DELETE
-- =====================================
DELIMITER //

CREATE TRIGGER tg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN

    UPDATE posts
    SET comment_count =
        CASE
            WHEN comment_count > 0 THEN comment_count - 1
            ELSE 0
        END
    WHERE post_id = OLD.post_id;

END //

DELIMITER ;

-- =====================================
-- TRIGGER LOG DELETE POST
-- =====================================
DELIMITER //

CREATE TRIGGER tg_after_post_delete
AFTER DELETE ON posts
FOR EACH ROW
BEGIN

    INSERT INTO post_logs(post_id, message)
    VALUES (
        OLD.post_id,
        CONCAT('Post ', OLD.post_id, ' deleted')
    );

END //

DELIMITER ;

-- =====================================
-- PROCEDURE ADD USER
-- Kiểm tra username + email
-- =====================================
DELIMITER //

CREATE PROCEDURE sp_add_user(
    IN p_username VARCHAR(50),
    IN p_password VARCHAR(255),
    IN p_email VARCHAR(100)
)
BEGIN

    -- Kiểm tra username
    IF EXISTS (
        SELECT 1
        FROM users
        WHERE username = p_username
    ) THEN

        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Username already exists';

    -- Kiểm tra email
    ELSEIF EXISTS (
        SELECT 1
        FROM users
        WHERE email = p_email
    ) THEN

        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Email already exists';

    ELSE

        INSERT INTO users(username, password, email)
        VALUES (
            p_username,
            SHA2(p_password, 256),
            p_email
        );

    END IF;

END //

DELIMITER ;

-- =====================================
-- PROCEDURE USER ACTIVITY REPORT
-- Dùng LEFT JOIN 
-- =====================================
DELIMITER //

CREATE PROCEDURE sp_user_activity_report()
BEGIN

    SELECT
        u.user_id,
        u.username,

        COUNT(DISTINCT p.post_id) AS total_posts,
        COUNT(DISTINCT l.like_id) AS total_likes,
        COUNT(DISTINCT c.comment_id) AS total_comments

    FROM users u

    LEFT JOIN posts p
        ON u.user_id = p.user_id

    LEFT JOIN likes l
        ON p.post_id = l.post_id

    LEFT JOIN comments c
        ON p.post_id = c.post_id

    GROUP BY u.user_id, u.username;

END //

DELIMITER ;

-- =====================================
-- PROCEDURE DELETE USER
-- =====================================
DELIMITER //

CREATE PROCEDURE sp_delete_user(
    IN p_user_id INT
)
BEGIN

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
    END;

    START TRANSACTION;

    -- Xóa likes
    DELETE FROM likes
    WHERE user_id = p_user_id;

    -- Xóa comments
    DELETE FROM comments
    WHERE user_id = p_user_id;

    -- Xóa friends
    DELETE FROM friends
    WHERE user_id = p_user_id
       OR friend_id = p_user_id;

    -- Xóa posts
    DELETE FROM posts
    WHERE user_id = p_user_id;

    -- Xóa user
    DELETE FROM users
    WHERE user_id = p_user_id;

    COMMIT;

END //

DELIMITER ;

-- =====================================
-- PROCEDURE SEARCH POSTS
-- =====================================
DELIMITER //

CREATE PROCEDURE sp_search_posts(
    IN p_keyword VARCHAR(100)
)
BEGIN

    SELECT *
    FROM posts
    WHERE MATCH(content)
    AGAINST(p_keyword IN NATURAL LANGUAGE MODE);

END //

DELIMITER ;

-- =====================================


INSERT INTO users(username, password, email)
VALUES
('tai', SHA2('123456',256), 'tai@gmail.com'),
('nam', SHA2('123456',256), 'nam@gmail.com'),
('linh', SHA2('123456',256), 'linh@gmail.com');

INSERT INTO posts(user_id, content)
VALUES
(1, 'Hello world'),
(2, 'Learning MySQL'),
(3, 'Social network project');

INSERT INTO likes(user_id, post_id)
VALUES
(1,1),
(2,1),
(3,2);

INSERT INTO comments(user_id, post_id, content)
VALUES
(1,1,'Nice post'),
(2,1,'Good job'),
(3,2,'Interesting');

INSERT INTO friends(user_id, friend_id, status)
VALUES
(1,2,'accepted'),
(1,3,'pending');