# Tidal's v2 APIs: Playlist Folders and Favorites

Findings from probing Tidal's two v2 APIs (November 2026) with the library's login, whose token has the scopes `r_usr w_usr` and the access tier `INTERNAL`. Every test created its own folders, playlists and favorites and removed them afterwards.

There are two different v2 APIs:

- **`https://api.tidal.com/v2`**, private like v1, used by Tidal's own apps. Plain JSON, form or query parameters. It has the playlist folders (`my-collection`), and favorite mixes (`favorites/mixes`).
- **`https://openapi.tidal.com/v2`**, Tidal's official API in the JSON:API format (`application/vnd.api+json`), described in the [OpenAPI spec](https://tidal-music.github.io/tidal-api-reference/tidal-api-oas.json). Most of it accepts the library's token.

## Playlist folders (`api.tidal.com/v2/my-collection/playlists`)

All changes are `PUT` with query parameters and answer `200` with the new item or `204`. Folders and playlists are named by TRNs: `trn:folder:<uuid>`, `trn:playlist:<uuid>`.

| Request | Does |
|---|---|
| `GET …/folders?folderId=root\|<uuid>&limit=50&order=DATE\|NAME&orderDirection=ASC\|DESC` | One folder's folders and playlists, with `totalNumberOfItems` and a `cursor` for the next page |
| `GET …/folders/flattened?…` | All folders and playlists, each with its `parent` (`null` at the root) |
| `GET /v2/my-collection/playlists?…` | The same as `folders?folderId=root` |
| `PUT …/folders/create-folder?name=&folderId=` | Creates a folder. It always lands at the root, `folderId` is ignored |
| `PUT …/folders/create-playlist?name=&description=&isPublic=&folderId=` | Creates a playlist in a folder |
| `PUT …/folders/move?trns=a,b&folderId=root\|<uuid>` | Moves folders and playlists, several at once |
| `PUT …/folders/rename?trn=trn:folder:<uuid>&name=` | Renames a folder |
| `PUT …/folders/add-favorites?uuids=&folderId=` | Adds another user's playlist as a favorite, into a folder |
| `PUT …/folders/remove?trns=` | Deletes folders, **deletes** own playlists and removes favorite playlists of others |

- The listing contains own playlists and favorite playlists of others. A favorite added to a folder is a v1 favorite as well, and vice versa.
- Folders can be nested by moving one into another; tested three levels deep.
- A playlist or folder is in exactly one folder. Moving it takes it out of the old one.
- There's no order of its own within a folder: listings are sorted by `DATE` or `NAME`. `addedAt` is when the item was moved into its folder, so moving them one by one, oldest first, restores the order by date.
- **The API doesn't protect the tree.** It accepts a move that makes a cycle (A in C, C in B, B in A), and deleting a folder that isn't empty leaves its contents pointing to the deleted folder. Such items are missing from `folders?folderId=root` and only show up in `flattened` and v1, until they're moved to the root again. So a client has to check for cycles itself and empty a folder before deleting it.
- Folder items have the fields `trn`, `itemType` (`FOLDER`, `PLAYLIST`), `addedAt`, `lastModifiedAt`, `name`, `parent` and `data`. A folder's `data` has `id`, `name`, `createdAt` and `totalNumberOfItems`, a playlist's `data` is the playlist as in v1, with `created` and `lastUpdated`.
- The official API's `userCollectionFolders` didn't accept the folder IDs of `my-collection` (`INVALID_RESOURCE_ID`) nor `root`.

## Favorites (`openapi.tidal.com/v2/userCollection…/me/relationships/items`)

`userCollectionTracks`, `userCollectionVideos`, `userCollectionAlbums`, `userCollectionArtists` and `userCollectionPlaylists` are the same favorites as v1's.

- `POST` adds up to 50 items: `{"data": [{"id": "19823990", "type": "tracks", "meta": {"addedAt": "2015-03-04T10:00:00Z"}}]}`. **`addedAt` sets the date the favorite was added**, which v1 then reports as `created`. This works for all five kinds, so a restore can keep the original dates and order.
- IDs Tidal doesn't know don't fail the request: the answer lists them in `meta.skipped` with `reason: NOT_FOUND`, and adds the others. An ID that isn't a number fails it with `400`.
- Adding a favorite again lists it as `ALREADY_PRESENT` and keeps its date.
- `DELETE` with the same body, without `meta`, removes them. IDs that aren't favorites are accepted.
- `GET` lists the IDs with `meta.addedAt`, 20 per page, with `links.next` as cursor. `include=items` adds the tracks, but without album or artist names, which need further requests.

## Other findings

- `GET openapi.tidal.com/v2/tracks?filter[isrc]=` finds all tracks of a recording, like v1's `/tracks?isrc=`.
- `GET openapi.tidal.com/v2/playlists/{uuid}/relationships/items` lists a playlist's items 20 per page, with `meta.itemId` and `meta.addedAt` per item.
- Favorite mixes are only in the private v2 API: `GET /v2/favorites/mixes` and `/v2/favorites/mixes/ids`, `PUT /v2/favorites/mixes/add` and `/remove` with `mixIds`. v1 has no `favorites/mixes` (`404`).
- No rate limit headers were sent.
