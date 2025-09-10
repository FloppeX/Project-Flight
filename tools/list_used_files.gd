extends SceneTree

# Usage (from project root):
# godot --headless --script tools/list_used_files.gd --example res://example/Example1_Simple.tscn --out res://used_files.txt

var start_scene: String = "res://example/Example1_Simple.tscn"
var out_file: String = "res://used_files.txt"

var visited: = {}              # String -> bool
var to_visit: Array[String] = []

var tscn_regex := RegEx.new()
var preload_regex := RegEx.new()
var load_regex := RegEx.new()

func _initialize() -> void:
    # Parse command line args
    var args := OS.get_cmdline_user_args()
    for i in range(args.size()):
        if args[i] == "--example" and i + 1 < args.size():
            start_scene = args[i + 1]
        elif args[i] == "--out" and i + 1 < args.size():
            out_file = args[i + 1]

    # Compile regex
    # ext_resource(path="res://path.ext")
    tscn_regex.compile('ext_resource\s*\([^\)]*path="(res://[^"]+)"')
    preload_regex.compile('preload\(\s*"(res://[^"]+)"\s*\)')
    load_regex.compile('load\(\s*"(res://[^"]+)"\s*\)')

    to_visit.append(start_scene)

func _process(_delta: float) -> void:
    while to_visit.size() > 0:
        var path: String = to_visit.pop_back()
        if path in visited:
            continue
        visited[path] = true

        var ext := path.get_extension().to_lower()
        if ext == "tscn":
            _scan_tscn(path)
        elif ext == "gd":
            _scan_gd(path)
        else:
            # Non-text asset; nothing to scan further
            pass

    _write_results()
    quit()

func _scan_tscn(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("Cannot open: %s" % path)
        return
    var text := file.get_as_text()
    file.close()

    # ext_resource references (scenes, scripts, textures, meshes, etc.)
    for m in tscn_regex.search_all(text):
        var ref_path: String = m.get_string(1)
        _enqueue(ref_path)

    # Embedded script lines inside tscn sometimes include script="res://..."
    var script_idx := 0
    while true:
        var idx := text.find('script="res://', script_idx)
        if idx == -1:
            break
        var end_idx := text.find('"', idx + 8)
        if end_idx == -1:
            break
        var ref: String = text.substr(idx + 8, end_idx - (idx + 8))
        _enqueue(ref)
        script_idx = end_idx + 1

    # Instance paths can also be directly in nodes in some cases via PackedScene resources
    # Those are usually covered by ext_resource, so we skip additional heuristics here.

func _scan_gd(path: String) -> void:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        push_warning("Cannot open: %s" % path)
        return
    var text := file.get_as_text()
    file.close()

    for m in preload_regex.search_all(text):
        _enqueue(m.get_string(1))
    for m in load_regex.search_all(text):
        _enqueue(m.get_string(1))

func _enqueue(path: String) -> void:
    # Normalize .import indirections to the source asset if present
    # We enqueue as-is; Godot’s import system will include .import files automatically on export.
    if not (path in visited):
        to_visit.append(path)

    # If this is a scene or script, we’ll parse it later

func _write_results() -> void:
    var keys := visited.keys()
    keys.sort()

    var f := FileAccess.open(out_file, FileAccess.WRITE)
    if f == null:
        push_error("Failed to open output: %s" % out_file)
        return
    for k in keys:
        f.store_line(String(k))
    f.close()



