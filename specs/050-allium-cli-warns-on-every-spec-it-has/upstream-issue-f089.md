# Draft issue for juxt/allium-tools (not filed)

**Title:** `check`: status assignment through an untyped trigger parameter is credited to no entity when two entities share the field name

**Body:**

allium 3.6.1 (also 3.2.3). Minimal repro:

```
-- allium: 3
entity Resp {
  status: ok | refused
}
entity PushItem {
  status: ok | refused
}
rule R {
  when: SyncPush(item)
  ensures: item.status = refused
}
```

`allium check` reports:

```
warning allium.status.unreachableValue Status 'refused' in entity 'PushItem' is never assigned by any rule ensures clause.
```

Rule `R` assigns it. The `Resp` warnings are correct, since nothing assigns `Resp.status`.

What we measured:

- Remove `Resp`, or rename its field (`state: ok | refused`), and the `PushItem` warning goes away.
  So it looks like `item.status` is resolved by field name alone. When two entities match, the
  assignment is credited to neither of them.
- Naming the binding after the entity (`push_item`, `pushItem`) makes no difference.
- The documented `surface … context item: PushItem` + `provides: SyncPush(item)` does not help.
- `provides: SyncPush(item: PushItem)` silences it on 3.6.1. We could not find that typed form in
  the language reference, so we have not adopted it.

Expected: either credit the assignment to every entity the field could belong to, or say that the
binding is ambiguous. A false "never assigned" is worse than either, because the natural reaction
is to delete a status value the spec needs.

Related: #18 (overlapping status values, closed 2026-06-11).

Found in a real spec: a sync endpoint with a `SyncPullResponse.status` and a `SyncPushItem.status`
produced four false warnings.
