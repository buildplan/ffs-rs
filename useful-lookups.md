## Useful lookups

- List collections and their numeric IDs (dictionary)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id AS collection_id, name FROM syncstorage_rs.collections ORDER BY id;"
```

- Per-user collection timestamps (via user_collections)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT uc.user_id, c.name AS collection, uc.modified
   FROM syncstorage_rs.user_collections uc
   JOIN syncstorage_rs.collections c ON c.id = uc.collection
 ORDER BY uc.modified DESC
 LIMIT 50;"
```

- BSO counts per named collection (join id→name)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT c.name AS collection, COUNT(*) AS bso_count
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
 GROUP BY c.name
 ORDER BY bso_count DESC;"
```

- Recent writes across all collections

```bash
docker compose exec firefox-mariadb mariadb -u sync -p\"${MYSQL_PASSWORD}\" -e \
\"SELECT b.id, c.name AS collection, b.modified
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
 ORDER BY b.modified DESC
 LIMIT 50;\"
```

- Recent batch uploads (server-side batching visibility)

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT id, user_id, started_at, finished_at, error
   FROM syncstorage_rs.batch_uploads
 ORDER BY started_at DESC
 LIMIT 20;"
```

- Items within a recent batch (replace :BATCH_ID)

```bash
BATCH_ID=1
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT item_id, collection, size
   FROM syncstorage_rs.batch_upload_items
  WHERE batch_id = ${BATCH_ID}
  LIMIT 50;"
```

- Verify the single user on tokenserver maps to your node and has recent per-collection activity

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT u.uid, FROM_UNIXTIME(u.created_at) AS created_at, n.node
   FROM tokenserver_rs.users u
   JOIN tokenserver_rs.nodes n ON n.id = u.nodeid
 ORDER BY u.created_at DESC
 LIMIT 10;"
```


### Clean-ups and tips

- The extra “syncstorage” database is unused; leave it or drop if you are certain it’s empty and not referenced:

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "SHOW TABLES IN syncstorage;"
```

- If you want to sample BSOs for a particular collection name (e.g., “history”):

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT b.id, b.modified
   FROM syncstorage_rs.bso b
   JOIN syncstorage_rs.collections c ON c.id = b.collection
  WHERE c.name = 'history'
  ORDER BY b.modified DESC
  LIMIT 20;"
```

- Node capacity sanity (matches what you saw):

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e \
"SELECT SUM(current_load) AS total_load, SUM(capacity) AS total_capacity
   FROM tokenserver_rs.nodes;"
```

If any query errors on column names, run:

```bash
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "DESCRIBE syncstorage_rs.user_collections;"
docker compose exec firefox-mariadb mariadb -u sync -p"${MYSQL_PASSWORD}" -e "DESCRIBE syncstorage_rs.bso;"
```
