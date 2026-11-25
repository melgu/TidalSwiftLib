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
- Tidal answers a rejected change with a status code, not a network error, so the library checks it. A single ID Tidal doesn't know fails the whole `POST /playlists/{uuid}/items` with `404` "Track not found", and none of the IDs are added. Some tracks that can't be streamed (`allowStreaming: false`) are still accepted, others not, and `GET /tracks/{id}` answers `404` for both, so it can't tell beforehand which IDs will fail.
- 500 IDs in one request work. Import sends 100 at a time and splits a rejected batch into halves until it has found the unknown IDs.
- With `onDupes=FAIL`, Tidal leaves out the IDs already in the playlist and adds the others. The answer lists them in `addedItemIds`.
- `DELETE /playlists/{uuid}/items/0,2,5` removes several positions at once. The positions are those before the removal. A position the playlist doesn't have fails the request with `400` "Invalid indices".

## Finding a track again

`GET /tracks?isrc={isrc}` returns all tracks of a recording, e.g. on its album, on compilations and under new IDs. Searching for the ISRC with `/search` doesn't find them. Videos have no ISRC.
