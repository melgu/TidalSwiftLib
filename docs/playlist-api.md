# Tidal Playlist API: Items, Videos and Positions

Findings from probing the v1 playlist endpoints (November 2026) with a temporary playlist holding a track, a video and another track.

## Reading

| Endpoint | Returns | Page size |
|---|---|---|
| `GET /playlists/{uuid}/items` | `{ "type": "track" \| "video", "cut": null, "item": {…} }` per entry | at most 100, larger answers `400` "Too big page, max page size is [100]" |
| `GET /playlists/{uuid}/tracks` | tracks only | 999 accepted |

- `/tracks` doesn't leave videos out: it returns each one as its "Audio from video" track, with a different ID (e.g. video 24114562 comes back as track 53507597, version "Audio from video", quality `LOW`). So positions in `/tracks` and `/items` match.
- Each entry carries `dateAdded`, `index` and `itemUuid`. `index` is a sort key in steps of 100000 that isn't renumbered after a removal, so it isn't the position. `itemUuid` is unique per entry, also for duplicates.
- Both lists are paged with `limit` and `offset`, and `totalNumberOfItems` gives the total. The library fetches all pages and advances by the `limit` Tidal answers with.

## Writing

- `POST /playlists/{uuid}/items` with `trackIds` takes video IDs too, since tracks and videos share one number space.
- Positions for `DELETE /playlists/{uuid}/items/{index}` and `POST /playlists/{uuid}/items/{index}?toIndex=` count videos.
- `toIndex` is the position the item ends up at: moving index 0 of `[a, b, c, a]` to 2 gives `[b, c, a, a]`.
