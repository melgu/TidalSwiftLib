# Account Backup and Restore

`Session.backup()` saves the favorites, the own playlists and the folders of the playlists of an account as an `AccountBackup`, which `restorePlan(for:options:)` compares with an account and `restore(_:)` writes back.

The favorites and folders come from three APIs: v1 for reading favorites and playlists, Tidal's official API (`openapi.tidal.com`) for adding favorites with their date, and the private v2 API for folders and favorite mixes. See [v2-api.md](v2-api.md).

## Tidal's v1 favorites API

Findings from probing the v1 favorites endpoints (November 2026):

- `POST /users/{id}/favorites/{tracks|videos|albums|artists|playlists}` takes several comma-separated IDs (`trackIds`, `videoIds`, `albumIds`, `artistIds`, `uuids`). Favorites added together get the same date, so their order gets lost. One by one, each gets its own date, at about 150 ms per request.
- A single ID Tidal doesn't know fails the whole request with `404` and adds none of them. The message doesn't always fit: unknown tracks answer "Album not found".
- Adding a favorite again answers `200` and keeps its original date.
- `DELETE /users/{id}/favorites/tracks/1,2,3` removes several at once. IDs that aren't favorites are accepted.
- v1 can't set the date a favorite was added. Tidal's official API can, so the restore adds favorites there.

## Format

- Version 2 added the favorite mixes (`favorites.mixes`) and the folders (`folders`). Both are optional, so backups of version 1 can still be read. A restore of such a backup leaves mixes and folders as they are, also with override, as it doesn't know them.
- `folders` lists each folder with its `parent` (nil at the root) and the playlists in it, own ones and favorites of others, by UUID. Playlists at the root aren't listed. Folders come parents first.
- Tidal allows folders whose parent was deleted and cycles of folders. The backup puts such folders at the root, breaking a cycle where it closes.

## Restoring

- The plan is computed first and changes nothing, so a dry run and the restore use the same comparison.
- Without override, a restore only adds: missing favorites, missing playlists, the items a playlist is missing, at its end, and missing folders. Playlists and folders at the root are put into their folder of the backup, but nothing is taken out of a folder. With override, it also removes favorites the backup doesn't have, replaces title, description and items of playlists that differ, renames folders, and moves folders and playlists to where the backup has them, the root included. Deleting own playlists and folders the backup doesn't have is a separate option. The contents of a deleted folder are moved to the root first, as Tidal leaves them behind otherwise.
- Favorites are added in batches of 50 with their date from the backup, so their order is kept as well. Mixes can't get a date, so they're added one by one, oldest first, and get the date of the restore.
- Own playlists are found by their UUID, and else by their title if exactly one playlist in the backup and one in the account have it. A playlist that a restore created again has a new UUID, so a second restore finds it by its title instead of creating it twice. Folders are found the same way, by their ID or by their name within the same parent.
- New folders are created at the root, as Tidal ignores a parent there, and then moved. Playlists are moved into folders one by one, oldest first, as a folder lists its items by when they were put into it. Before moving folders around, override moves them to the root, and every move into a folder is checked against the tree, as Tidal accepts moves that put a folder into itself.
- Tracks Tidal no longer knows are replaced by another track of the same recording, found by their ISRC, as in a playlist import. The replacement gets the original's date. With override, such a replacement isn't removed as a favorite the backup doesn't have.
- The restore goes in this order: own playlists, favorites, folders. When Tidal rejects a change, it stops. The changes before it are made, so restoring again continues with what is still missing.
