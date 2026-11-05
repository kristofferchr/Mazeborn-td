class_name SafeConfig
extends RefCounted
## ConfigFile load and save that cannot lose a file: save() writes
## "<path>.tmp" and renames it over the file, so a crash mid-write leaves the
## old file; load() keeps a file it cannot read as "<path>.bak" before anything
## can overwrite it. Used for progress.cfg (Progress) and settings.cfg
## (UserSettings).


## Loads path into cfg. A missing file gives ERR_FILE_NOT_FOUND; a file that
## does not parse is copied to "<path>.bak" and its error returned.
static func load_into(cfg: ConfigFile, path: String) -> Error:
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var err := cfg.load(path)
	if err != OK:
		backup(path)
	return err


## Saves cfg to path through a temp file and a rename.
static func save(cfg: ConfigFile, path: String) -> Error:
	var tmp := path + ".tmp"
	var err := cfg.save(tmp)
	if err != OK:
		return err
	var from := ProjectSettings.globalize_path(tmp)
	var to := ProjectSettings.globalize_path(path)
	err = DirAccess.rename_absolute(from, to)
	if err != OK and FileAccess.file_exists(path):
		# Some platforms do not rename over an existing file.
		DirAccess.remove_absolute(to)
		err = DirAccess.rename_absolute(from, to)
	return err


## Copies path to "<path>.bak".
static func backup(path: String) -> Error:
	var to := ProjectSettings.globalize_path(path + ".bak")
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(path), to)
