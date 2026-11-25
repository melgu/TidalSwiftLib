# Account Backup and Restore

`Session.backup()` saves the favorites and the own playlists of an account as an `AccountBackup`, which `restorePlan(for:options:)` compares with an account and `restore(_:)` writes back.

## Tidal's favorites API

Findings from probing the v1 favorites endpoints (November 2026):

- `POST /users/{id}/favorites/{tracks|videos|albums|artists|playlists}` takes several comma-separated IDs (`trackIds`, `videoIds`, `albumIds`, `artistIds`, `uuids`). Favorites added together get the same date, so their order gets lost. One by one, each gets its own date, at about 150 ms per request.
- A single ID Tidal doesn't know fails the whole request with `404` and adds none of them. The message doesn't always fit: unknown tracks answer "Album not found".
- Adding a favorite again answers `200` and keeps its original date.
- `DELETE /users/{id}/favorites/tracks/1,2,3` removes several at once. IDs that aren't favorites are accepted.
- The date a favorite was added can't be set, so a restore gives all restored favorites the date of the restore.

## Restoring

- The plan is computed first and changes nothing, so a dry run and the restore use the same comparison.
- Without override, a restore only adds: missing favorites, missing playlists, and the items a playlist is missing, at its end. With override, it also removes favorites the backup doesn't have and replaces title, description and items of playlists that differ. Deleting own playlists the backup doesn't have is a separate option.
- Favorites are added oldest first and one by one, so the newest ends up on top as before.
- Own playlists are found by their UUID, and else by their title if exactly one playlist in the backup and one in the account have it. A playlist that a restore created again has a new UUID, so a second restore finds it by its title instead of creating it twice.
- Tracks Tidal no longer knows are replaced by another track of the same recording, found by their ISRC, as in a playlist import. With override, such a replacement isn't removed as a favorite the backup doesn't have.
- When Tidal rejects a change, the restore stops. The changes before it are made, so restoring again continues with what is still missing.
