# Useful DB Lookups (MariaDB)

Applies to this setup:

* Container names: firefox-mariadb, firefox-syncserver
* Databases: syncstorage_rs, tokenserver_rs
* Tables present:
  * syncstorage_rs: bso, collections, user_collections, batch_uploads, batch_upload_items
  * tokenserver_rs: users, nodes, services
* Client: mariadb (preferred over mysql)

Tip: Use mariadb in the linuxserver/mariadb container. Supply the password via environment variable MYSQL_PASSWORD.

## Connect helpers

```bash
# Shell into DB container
docker compose exec firefox-mariadb bash
```

```bash
# One-off non-interactive
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "SELECT 1;"
```

```bash
# Interactive
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}"
```

## Schema discovery

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "SHOW DATABASES;"
```

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "USE tokenserver_rs; SHOW TABLES;"
```

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "USE syncstorage_rs; SHOW TABLES;"
```

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "DESCRIBE syncstorage_rs.user_collections;"
```

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "DESCRIBE syncstorage_rs.bso;"
```

Expected user_collections columns (per your DB):

* userid BIGINT (PK)
* collection INT (PK) → joins to collections.id
* last_modified BIGINT
* total_bytes BIGINT NULL
* count INT NULL

-----

## Tokenserver (who’s connected, where)

* Services configured

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, service, pattern FROM tokenserver_rs.services;"
```

* Node status and capacity

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, service, node, capacity, available, current_load, downed, backoff
 FROM tokenserver_rs.nodes;"
```

* Users count

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT COUNT(*) AS users_count FROM tokenserver_rs.users;"
```

* Recent users mapped to node

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT u.uid, u.email, FROM_UNIXTIME(u.created_at) AS created_at, n.node
   FROM tokenserver_rs.users u
   JOIN tokenserver_rs.nodes n ON n.id = u.nodeid
 ORDER BY u.created_at DESC
 LIMIT 20;"
```

* Capacity summary

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT SUM(current_load) AS total_load, SUM(capacity) AS total_capacity
   FROM tokenserver_rs.nodes;"
```

-----

## Syncstorage (collections, BSOs, activity)

* Collection dictionary (id → name)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id AS collection_id, name
   FROM syncstorage_rs.collections
 ORDER BY id;"
```

* BSO counts per collection (numeric id)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT collection, COUNT(*) AS bso_count
   FROM syncstorage_rs.bso
 GROUP BY collection
 ORDER BY bso_count DESC;"
```

* BSO counts per collection (human-readable)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT c.name AS collection, COUNT(*) AS bso_count
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
 GROUP BY c.name
 ORDER BY bso_count DESC;"
```

* Recent BSOs with collection name (human-readable time)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT b.id, c.name AS collection,
        FROM_UNIXTIME(b.modified/1000) AS modified_ts,
        b.modified AS modified_ms
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
 ORDER BY b.modified DESC
 LIMIT 50;"
```

* Recent BSOs within a specific collection (e.g., history)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT b.id,
        FROM_UNIXTIME(b.modified/1000) AS modified_ts,
        b.modified AS modified_ms
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
  WHERE c.name = 'history'
  ORDER BY b.modified DESC
  LIMIT 20;"
```

-----

## Per-user collection state

* Recent per-user per-collection last_modified (human-readable time)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.userid, c.name AS collection,
        FROM_UNIXTIME(uc.last_modified/1000) AS modified_ts,
        uc.last_modified AS modified_ms,
        uc.count AS bso_count, uc.total_bytes
   FROM syncstorage_rs.user_collections uc
   JOIN syncstorage_rs.collections c ON c.id = uc.collection
 ORDER BY uc.last_modified DESC
 LIMIT 50;"
```

* For a specific collection (bookmarks)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.userid, c.name AS collection,
        FROM_UNIXTIME(uc.last_modified/1000) AS modified_ts,
        uc.last_modified AS modified_ms
   FROM syncstorage_rs.user_collections uc
   JOIN syncstorage_rs.collections c ON c.id = uc.collection
  WHERE c.name = 'bookmarks'
 ORDER BY uc.last_modified DESC
 LIMIT 20;"
```

* Per-user totals (count/bytes) and last_modified

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.userid, c.name AS collection,
        uc.count AS bso_count, uc.total_bytes, uc.last_modified
   FROM syncstorage_rs.user_collections uc
   JOIN syncstorage_rs.collections c ON c.id = uc.collection
 ORDER BY uc.userid, c.name;"
```

* Distinct users present in user_collections

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT DISTINCT userid
   FROM syncstorage_rs.user_collections
 ORDER BY userid;"
```

-----

## Batch uploads

Note: These tables may be empty unless clients used server-side multi-part uploads. If empty, use “Recent BSOs” and “Per-user collection state” to inspect activity.

Your schema:

* batch_uploads(batch BIGINT, userid BIGINT, collection INT)
* batch_upload_items(batch BIGINT, userid BIGINT, id VARCHAR(64), sortindex INT, payload MEDIUMTEXT, payload_size INT, ttl_offset INT)
* Recent batches (by batch id, with item counts)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT bu.batch,
        bu.userid,
        c.name AS collection,
        COALESCE(COUNT(bi.id), 0) AS items
   FROM syncstorage_rs.batch_uploads bu
   LEFT JOIN syncstorage_rs.batch_upload_items bi
          ON bi.batch = bu.batch AND bi.userid = bu.userid
   JOIN syncstorage_rs.collections c
          ON c.id = bu.collection
 GROUP BY bu.batch, bu.userid, c.name
 ORDER BY bu.batch DESC
 LIMIT 20;"
```

* Batches for a specific user (discover batch ids)

```bash
USERID=4
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT bu.batch, c.name AS collection,
        (SELECT COUNT(*) FROM syncstorage_rs.batch_upload_items bi
          WHERE bi.batch = bu.batch AND bi.userid = bu.userid) AS item_count
   FROM syncstorage_rs.batch_uploads bu
   JOIN syncstorage_rs.collections c ON c.id = bu.collection
  WHERE bu.userid = ${USERID}
  ORDER BY bu.batch DESC;"
```

* Items for a batch (set BATCH and USERID)

```bash
BATCH=1
USERID=4
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, sortindex, payload_size, ttl_offset
   FROM syncstorage_rs.batch_upload_items
  WHERE batch = ${BATCH} AND userid = ${USERID}
  ORDER BY id
  LIMIT 50;"
```

* Show raw rows (quick probe)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT * FROM syncstorage_rs.batch_uploads LIMIT 5;
 SELECT * FROM syncstorage_rs.batch_upload_items LIMIT 5;"
```

-----

## Tips and pitfalls

* Always use mariadb inside the container; mysql is deprecated in this image.
* When sending SQL via stdin (heredoc or pipe), add -T to disable TTY allocation.

Heredoc (multi-line SQL):

```bash
docker compose exec -T firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" <<'SQL'
USE syncstorage_rs;
SELECT c.name, COUNT(*) AS bso_count
  FROM bso b JOIN collections c ON c.id = b.collection
 GROUP BY c.name
 ORDER BY bso_count DESC;
SQL
```

One-liner via pipe:

```bash
echo "USE syncstorage_rs; SELECT c.name, COUNT(*) AS bso_count FROM bso b JOIN collections c ON c.id = b.collection GROUP BY c.name ORDER BY bso_count DESC;" \
| docker compose exec -T firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}"
```

* If any query errors on column names, run DESCRIBE on the table to confirm fields and adjust:

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "DESCRIBE syncstorage_rs.user_collections;"
```

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "DESCRIBE syncstorage_rs.bso;"
```
