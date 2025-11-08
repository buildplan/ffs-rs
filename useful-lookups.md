# Useful DB Lookups (MariaDB)

Applies to this setup:

- Container names: firefox-mariadb, firefox-syncserver
- Databases: syncstorage_rs, tokenserver_rs
- Tables present:
    - syncstorage_rs: bso, collections, user_collections, batch_uploads, batch_upload_items
    - tokenserver_rs: users, nodes, services
- Client: mariadb (preferred over mysql)

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

* Recent BSOs with collection name

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT b.id, c.name AS collection, b.modified
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
 ORDER BY b.modified DESC
 LIMIT 50;"
```

* Recent BSOs within a specific collection (e.g., history)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT b.id, b.modified
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
  WHERE c.name = 'history'
  ORDER BY b.modified DESC
  LIMIT 20;"
```


-----

## Per-user collection state

* Recent per-user per-collection last_modified

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.userid, c.name AS collection, uc.last_modified
   FROM syncstorage_rs.user_collections uc
   JOIN syncstorage_rs.collections c ON c.id = uc.collection
 ORDER BY uc.last_modified DESC
 LIMIT 50;"
```

* For a specific collection (bookmarks)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.userid, c.name AS collection, uc.last_modified
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

* Recent batches

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, user_id, started_at, finished_at, error
   FROM syncstorage_rs.batch_uploads
 ORDER BY started_at DESC
 LIMIT 20;"
```

* Items for a specific batch (replace BATCH_ID)

```bash
BATCH_ID=1
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT item_id, collection, size
   FROM syncstorage_rs.batch_upload_items
  WHERE batch_id = ${BATCH_ID}
  LIMIT 50;"
```


-----

## Tips and pitfalls

* Always use mariadb client inside the container; mysql is deprecated in this image.
* When running multi-line SQL, prefer a single quoted string or a heredoc to avoid shell parsing issues:

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" <<'SQL'
USE syncstorage_rs;
SELECT c.name, COUNT(*) AS bso_count
  FROM bso b JOIN collections c ON c.id = b.collection
 GROUP BY c.name
 ORDER BY bso_count DESC;
SQL
```

* If any query errors on column names, run DESCRIBE on the table to confirm fields and adjust.
