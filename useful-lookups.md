# Useful DB Lookups (MariaDB)

Tip: prefer mariadb over mysql inside the linuxserver/mariadb container.

## Quick connect

```bash
# Shell into container
docker compose exec firefox-mariadb bash
```

```bash
# Connect non-interactively (examples below use this form)
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "SELECT 1;"
```

```bash
# Or interactive
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}"
```


## Tokenserver: service, node, users

- Services

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, service, pattern FROM tokenserver_rs.services;"
```

- Node status and capacity

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, service, node, capacity, available, current_load, downed, backoff
 FROM tokenserver_rs.nodes;"
```

- Users count and mapping to node

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT COUNT(*) AS users_count FROM tokenserver_rs.users;"

docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT u.uid, u.email, FROM_UNIXTIME(u.created_at) AS created_at, n.node
   FROM tokenserver_rs.users u
   JOIN tokenserver_rs.nodes n ON n.id = u.nodeid
 ORDER BY u.created_at DESC
 LIMIT 20;"
```


## Syncstorage: collections and BSOs

- Collection dictionary (id → name)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id AS collection_id, name
   FROM syncstorage_rs.collections
 ORDER BY id;"
```

- BSO counts per collection (numeric id)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT collection, COUNT(*) AS bso_count
   FROM syncstorage_rs.bso
 GROUP BY collection
 ORDER BY bso_count DESC;"
```

- BSO counts per collection (human-readable name)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT c.name AS collection, COUNT(*) AS bso_count
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
 GROUP BY c.name
 ORDER BY bso_count DESC;"
```

- Recent BSOs (joined with collection names)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT b.id, c.name AS collection, b.modified
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
 ORDER BY b.modified DESC
 LIMIT 50;"
```

- Recent BSOs within a specific collection (e.g., history)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT b.id, b.modified
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
  WHERE c.name = 'history'
  ORDER BY b.modified DESC
  LIMIT 20;"
```


## Per-user collection timestamps

Note: In this schema, user/collection timestamps are tracked via user_collections, but columns are named user (not user_id) and collection (the id). Use:

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.user AS user_pk, c.name AS collection, uc.modified
   FROM syncstorage_rs.user_collections uc
   JOIN syncstorage_rs.collections c ON c.id = uc.collection
 ORDER BY uc.modified DESC
 LIMIT 50;"
```

- For a specific collection (e.g., bookmarks)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.user AS user_pk, c.name AS collection, uc.modified
   FROM syncstorage_rs.user_collections uc
   JOIN syncstorage_rs.collections c ON c.id = uc.collection
  WHERE c.name = 'bookmarks'
 ORDER BY uc.modified DESC
 LIMIT 20;"
```


## Batch uploads visibility

- Recent batches

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, user_id, started_at, finished_at, error
   FROM syncstorage_rs.batch_uploads
 ORDER BY started_at DESC
 LIMIT 20;"
```

- Items for a batch (replace :BATCH_ID)

```bash
BATCH_ID=1
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT item_id, collection, size
   FROM syncstorage_rs.batch_upload_items
  WHERE batch_id = ${BATCH_ID}
  LIMIT 50;"
```


## Schema inspection helpers

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


## Common pitfalls

- Use mariadb, not mysql (the latter is deprecated in this image).
- For multi-line SQL in bash, prefer a quoted single string, or use a heredoc:

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" <<'SQL'
USE syncstorage_rs;
SELECT c.name, COUNT(*) AS bso_count
  FROM bso b JOIN collections c ON c.id = b.collection
 GROUP BY c.name ORDER BY bso_count DESC;
SQL
```

- In this schema, user_collections uses column name user (not user_id).

