extends Node

## Persistent music across hub screens. Menu track keeps playing until a match starts.

const MENU_MUSIC_PATH := "res://assets/music/menu_music.mp3"
const GAME_MUSIC_PATH := "res://assets/music/game_music.mp3"

enum Mode { NONE, MENU, GAME }

var _player: AudioStreamPlayer
var _mode: Mode = Mode.NONE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.volume_db = 0.0
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_player)
	# Hub / loading boot into menu music
	play_menu_music()

func play_menu_music() -> void:
	if _mode == Mode.MENU and _player.playing:
		return
	_play(MENU_MUSIC_PATH, Mode.MENU)

func play_game_music() -> void:
	if _mode == Mode.GAME and _player.playing:
		return
	_play(GAME_MUSIC_PATH, Mode.GAME)

func stop() -> void:
	_mode = Mode.NONE
	if _player:
		_player.stop()
		_player.stream = null

func _play(path: String, mode: Mode) -> void:
	var stream := load(path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_mode = mode
	_player.stream = stream
	_player.play()
