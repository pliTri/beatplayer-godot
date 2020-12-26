extends AudioStreamPlayer
class_name BeatPlayer
# # brief
# beatplayer is simple stream player for rhythm games which wraps AudioStreamPlayer.
#
# - interpolated playback position with process() → don't manually enable or disable processing.
# - knowledge of bpm and beat
# - supports minus playback position

var playback_position: float setget _set_playback_position, get_playback_position
var _playback_position_last_known: float = 0
var _playback_position_interpolated: float = 0 # interpolated position by physics_process or process

export(float) var bpm: float = 100.0 # this can be set anytime since this value dosesn't affect other variables

export(float) var music_offset: float = 0.0 # beat calculation offset where music starts in second. does not affect to playback position
var beat: float setget set_beat, get_beat # calculated value!

export(float) var lerp_val: float = 0.5
export(float) var pop_filter: float = 0.8

##################
# setter, getter #
##################

func set_beat(beat: float):
	var beat_per_second: float = (bpm / 60.0)
	self.playback_position = beat / beat_per_second
func get_beat():
	var beat_per_second: float = (bpm / 60.0)
	return (self.playback_position) * beat_per_second

# this doesn't set seek
func _set_playback_position(playback_position: float) -> void:
	_playback_position_last_known = playback_position
	_playback_position_interpolated = playback_position
	
func get_playback_position() -> float: return _playback_position_interpolated

############
# utillity #
############

func beat_to_playback(beat: float) -> float:
	var beat_per_second: float = (bpm / 60.0)
	return beat / beat_per_second
	
func playback_to_beat(playback_pos: float) -> float:
	var beat_per_second: float = (bpm / 60.0)
	return (playback_pos) * beat_per_second

##################################
# overrides of AudioStreamPlayer #
##################################

func play(from_position: float = 0.0) -> void:
	play_from_music_offset(from_position - music_offset)

func play_from_music_offset(from_position: float = 0.0):
	if self.stream == null:
		return
		
	_prevent_loop()
	
	self.playback_position = from_position
	if from_position + music_offset >= 0.0:
		.play(from_position + music_offset)
	set_process(true)

func seek(to_position: float) -> void:
	self.playback_position = to_position
	if to_position + music_offset < 0.0:
		set_process(true)
		.stop()
	else:
		.seek(to_position + music_offset)

func seek_to_beat(beat: float) -> void:
	self.beat = beat # this calls setter and changes playback_position
	self.seek(self.playback_position)
	
func stop() -> void:
	.stop()
	set_process(false)
	
#####################
# overrides of Node #
#####################

func _ready() -> void:
	var error: int = connect("finished", self, "__finished_beatplayer")
	if error != OK:
		print_debug(error)
	
	set_process(false) # it seems like AudioStreamPlayer automatically sets processing to true

func _process(delta: float) -> void:
	_interpolate_playback_position(delta)

###############
# own methods #
###############

# raw playback position with considering latency (Godot 3.2)
# https://docs.godotengine.org/en/latest/tutorials/audio/sync_with_audio.html
func _get_playback_position_with_latency() -> float:
	return .get_playback_position() \
			+ AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()

# playback position zero considering latency (Godot 3.2)
# https://docs.godotengine.org/en/latest/tutorials/audio/sync_with_audio.html
func _latency_zero() -> float:
	return AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()

func _interpolate_playback_position(delta: float) -> void:
	# update new virtual playback position
	_playback_position_interpolated += delta
	
	if _playback_position_interpolated >= - _latency_zero():
		# if processing but not playing, play it
		if not playing:
			.play(0)
			return

		# if actual playback pos is changed, apply it
		var super_pos: float = _get_playback_position_with_latency() - music_offset
		if super_pos != _playback_position_last_known and super_pos != 0.0: # 0.0 when started. we ignore that
			_playback_position_last_known = super_pos
			
			# when popped up value occured
			if pop_filter != 0.0 and abs(_playback_position_interpolated - super_pos) > pop_filter:
				return
			
			# update _playback_position_interpolated by [lerp or not]
			if lerp_val != 0.0:
				var lerp_pos: float = lerp(super_pos, _playback_position_interpolated, pow(lerp_val, delta))
				_playback_position_interpolated = lerp_pos
			else:
				_playback_position_interpolated = super_pos

func __finished_beatplayer() -> void:
	self.playback_position = .get_playback_position()
	set_process(false)
	
func _prevent_loop():
	var stream = .get_stream()
	if stream is AudioStreamOGGVorbis:
		var stream_ogg: AudioStreamOGGVorbis = stream as AudioStreamOGGVorbis
		if stream_ogg != null: stream_ogg.loop = false
	
	if stream is AudioStreamSample:
		var stream_sample: AudioStreamSample = stream as AudioStreamSample
		if stream_sample != null: stream_sample.loop_mode = AudioStreamSample.LOOP_DISABLED
