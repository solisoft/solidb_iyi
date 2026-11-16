# SoliDB driver for iyi

The native driver of [SoliDB](https://github.com/solisoft/solidb) for [iyi](https://iyi.dev): one TCP connection speaking
SoliDB's binary protocol (`solidb-drv-v1`, length-prefixed MessagePack).
Written in iyi alone: its standard library has sockets and no MessagePack,
so the codec is here too (`solidb_iyi/msgpack.iyi`). No dependency, no C.

Checked with iyi 0.21.0 against SoliDB 2.11.0.

## Install

```sh
iyi get github.com/solisoft/solidb_iyi --as solidb
```

That writes `require github.com/solisoft/solidb_iyi v0.1.0 as solidb` into
`iyi.mod` and fetches the newest version tag. Files then `import solidb`
for the root module, which holds `Client`.

## Use

```crystal
module app

import solidb::{Client, SolidbError}
import std/json::{Any, JSON}

db = Client.new("127.0.0.1", 6745)
db.auth("_system", "admin", "secret").or_panic
db.create_database("shop").or_panic
db.create_collection("shop", "users").or_panic

ada = db.insert("shop", "users", JSON.parse(%({"name": "Ada", "age": 36}))).or_panic
puts "stored #{ada["_key"].as_s}"

rows = db.query("shop", "FOR u IN users FILTER u.age > @age RETURN u.name",
                JSON.parse(%({"age": 30}))).or_panic
rows.as_a.each { |name| puts name.as_s }

case db.get("shop", "users", "nobody")
in SolidbError then puts "refused: #{it.message}"
in Any         then puts "found #{it.to_json}"
end
db.close
```

Values are `std/json`'s `Any`. Every call answers its value or a
`SolidbError` (`kind`: `Connection`, `Protocol`, `Server`, `Transaction`),
an ordinary member of the return type: `!` passes it on, `.or_panic` stops
on it, a `case` handles it.

| Call | Answers |
|---|---|
| `connect`, `close`, `connected?` | the connection is opened by the first call that needs it |
| `ping` | the server's clock, in milliseconds |
| `auth(db, user, password)`, `auth_with_api_key(db, key)` | nil |
| `list_databases`, `create_database(name)`, `delete_database(name)` | |
| `list_collections(db)`, `create_collection(db, name, type = nil)`, `delete_collection(db, name)`, `collection_stats(db, name)` | |
| `insert(db, coll, document, key = nil)` | the stored document |
| `bulk_insert(db, coll, documents)` | how many were stored |
| `get(db, coll, key)` | the document, or a `Server` error |
| `update(db, coll, key, document, merge = true)` | the document as stored |
| `delete(db, coll, key)` | nil |
| `list(db, coll, limit = 50, offset = 0)` | documents |
| `query(db, sdbql, bind_vars = nil, cache = true)`, `explain(db, sdbql, bind_vars = nil)` | rows; the plan |
| `create_index(db, coll, name, fields, unique = false, sparse = false)`, `list_indexes(db, coll)`, `delete_index(db, coll, name)` | |
| `begin_transaction(db, isolation_level = "read_committed")` | the transaction's id |
| `commit_transaction`, `rollback_transaction`, `in_transaction?` | |
| `request(Fields.new("…").set(name, value)…)` | any other command's data |

The server has many more commands than `Client` has methods (triggers,
scripts, roles, vector and geo indexes, columnar collections, the cluster).
`request` sends any of them; `src/driver/protocol/command.rs` in the
[SoliDB repository](https://github.com/solisoft/solidb) names each with
its fields.

```crystal
db.request(Fields.new("truncate_collection").set("database", "shop").set("collection", "logs")).or_panic
```

## What to know

- **One client, one conversation.** A `Client` is a single connection. Two
  tasks must not call the same one at once; give each its own. Logging in
  is per connection, and a client that reconnects (after `close`, or a
  lost connection) has to `auth` again.
- **Transactions.** Between `begin_transaction` and its end, `insert`,
  `update`, `delete` and `query` are staged in it; `get` and `list` read
  committed data; `bulk_insert` is refused. One transaction at a time per
  client.
- **Numbers.** Integers are `Int64`. An unsigned integer past its largest
  value is read as the nearest float.
- **Binary values** are read as the string of their bytes, and never
  written: `Any` has no binary kind.
- **Nesting.** A reply nested more than 64 arrays and maps deep is refused
  (`Protocol`): a task's stack is 256 KiB.
- **Limits.** A frame is at most 16 MiB either way, the server's own limit.

## Tests

```sh
./run_tests.sh /path/to/solidb    # starts a throwaway server on port 6799
iyi test solidb_iyi/msgpack_test.iyi  # the codec alone, no server
```

`solidb_iyi_test.iyi` passes without checking anything when `SOLIDB_TEST_PORT`
is not set.
