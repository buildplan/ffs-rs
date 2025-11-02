CREATE DATABASE IF NOT EXISTS syncstorage_rs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS tokenserver_rs CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES ON syncstorage_rs.* TO 'sync'@'%';
GRANT ALL PRIVILEGES ON tokenserver_rs.* TO 'sync'@'%';
FLUSH PRIVILEGES;
