#!/bin/bash

###############################################################################
# Spotify DBus Control Script
# Control and query Spotify playback and metadata via DBus from the command line.
#
# Usage:
#   ./spotify-dbus.sh <command> [args]
#   Run './spotify-dbus.sh help' for a full list of commands and usage.
###############################################################################

########################################
# DBus Helper Functions
########################################

# Check if Spotify is running via DBus.
running() {
    if ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply \
        /org/freedesktop/DBus org.freedesktop.DBus.ListNames | grep -q org.mpris.MediaPlayer2.spotify; then
        echo "Error: Spotify is not running" >&2
        return 1
    fi
    return 0
}

# Set a property on Spotify's DBus interface.
# Usage: set_property <Property> <Value> <Type>
set_property() {
    local property="$1"
    local value="$2"
    local value_type="$3" # e.g., "string", "boolean", "double"
    dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.freedesktop.DBus.Properties.Set \
        string:"org.mpris.MediaPlayer2.Player" string:"$property" variant:"$value_type:$value"
}

# Call a method on Spotify's DBus interface.
# Usage: set_method <Method> <Value> <Type>
set_method() {
    local method="$1"
    local value="$2"
    local value_type="$3"
    dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player."$method" "$value_type:$value"
}

# Call a method with multiple values/types.
# Usage: set_method_multipleValue <Method> <type1:value1> <type2:value2> ...
set_method_multipleValue() {
    local method="$1"
    shift
    dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player."$method" "$@"
}

# Get a property from Spotify's DBus interface.
# Usage: get_property <Property>
get_property() {
    local property="$1"
    local output
    output=$(dbus-send --print-reply --session --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.freedesktop.DBus.Properties.Get \
        string:"org.mpris.MediaPlayer2.Player" string:"$property" 2>&1)
    if echo "$output" | grep -q "Error"; then
        echo "DBus error: $output" >&2
        return 1
    fi
    echo "$output" | awk '/variant/{print $NF}' | tr -d '"'
}

# Get a metadata property from Spotify.
# Usage: get_metadata_property <Property>
get_metadata_property() {
    local property="$1"
    local output
    output=$(dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.freedesktop.DBus.Properties.Get \
        string:"org.mpris.MediaPlayer2.Player" string:"Metadata" 2>&1)
    if echo "$output" | grep -q "Error"; then
        echo "DBus error: $output" >&2
        return 1
    fi
    # Try to extract value by type
    if echo "$output" | grep -A 1 "$property" | grep -q "array"; then
        echo "$output" | grep -A 2 "$property" | tail -n 1 | cut -d '"' -f 2
        return
    fi
    if echo "$output" | grep -A 1 "$property" | grep -q "int32"; then
        echo "$output" | grep -A 1 "$property" | sed s/"int32"// | grep -Eo '[+-]?[0-9]+([.][0-9]+)?'
        return
    fi
    if echo "$output" | grep -A 1 "$property" | grep -q "uint64"; then
        echo "$output" | grep -A 1 "$property" | sed s/"uint64"// | grep -Eo '[+-]?[0-9]+([.][0-9]+)?'
        return
    fi
    if echo "$output" | grep -A 1 "$property" | grep -q "double"; then
        echo "$output" | grep -A 1 "$property" | grep -Eo '[+-]?[0-9]+([.][0-9]+)?'
        return
    fi
    if echo "$output" | grep -A 1 "$property" | grep -q "string"; then
        echo "$output" | grep -A 1 "$property" | tail -n 1 | cut -d '"' -f 2
        return
    fi
    echo "Error: Property $property not found" >&2
    return 1
}

# Control playback (Play, Pause, Next, Previous, etc.)
# Usage: control_playback <Action>
control_playback() {
    local action="$1"
    dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player."$action"
}

########################################
# Metadata Query Functions
########################################

trackId()        { get_metadata_property mpris:trackid; }
length()         { get_metadata_property mpris:length; }
artUrl()         { get_metadata_property mpris:artUrl; }
album()          { get_metadata_property xesam:album; }
albumArtist()    { get_metadata_property xesam:albumArtist; }
artist()         { get_metadata_property xesam:artist; }
autoRating()     { get_metadata_property xesam:autoRating; }
discNumber()     { get_metadata_property xesam:discNumber; }
title()          { get_metadata_property xesam:title; }
trackNumber()    { get_metadata_property xesam:trackNumber; }
url()            { get_metadata_property xesam:url; }

########################################
# Playback Property Query Functions
########################################

playbackStatus() { get_property PlaybackStatus; }
position()       { get_property Position; }
rate()           { get_property Rate; }
volume()         { get_property Volume; }
loopStatus()     { get_property LoopStatus; }
shuffle()        { get_property Shuffle; }
canGoNext()      { get_property CanGoNext; }
canGoPrevious()  { get_property CanGoPrevious; }
canPlay()        { get_property CanPlay; }
canPause()       { get_property CanPause; }
canSeek()        { get_property CanSeek; }
canControl()     { get_property CanControl; }

# Listen for Seeked signals (shows position updates).
seeked() {
    echo "Listening for Seeked signal..."
    dbus-monitor "interface='org.mpris.MediaPlayer2.Player',member='Seeked'" |
    while read -r line; do
        if echo "$line" | grep -q "int64"; then
            echo "Seeked to position: $(echo "$line" | awk '{print $NF}')"
        fi
    done
}

########################################
# Playback Control Functions
########################################

play()        { control_playback "Play"; }
pause()       { control_playback "Pause"; }
playpause()   { control_playback "PlayPause"; }
next()        { control_playback "Next"; }
previous()    { control_playback "Previous"; }
stop()        { control_playback "Stop"; }

# Set the playback volume (0-100).
set_volume() {
    local volume="$1"
    if [[ "$volume" -lt 0 || "$volume" -gt 100 ]]; then
        echo "Invalid volume value. Use a number between 0 and 100." >&2
        return 1
    fi
    set_property "Volume" "$volume" "double"
}

# Set the position in the current track (microseconds).
set_position() {
    local position="$1"
    local max_length
    max_length=$(length)
    if [[ "$position" -lt 0 || "$position" -gt "$max_length" ]]; then
        echo "Invalid position value. Use a number between 0 and $max_length." >&2
        return 1
    fi
    local track_id
    track_id=$(trackId)
    set_method_multipleValue "SetPosition" objpath:"$track_id" int64:"$position"
}

# Set playback rate (0.5-2.0).
set_rate() {
    local rate="$1"
    if (( $(echo "$rate < 0.5" | bc -l) )) || (( $(echo "$rate > 2.0" | bc -l) )); then
        echo "Invalid rate value. Use a number between 0.5 and 2.0." >&2
        return 1
    fi
    set_property "Rate" "$rate" "double"
}

# Seek by a relative offset (microseconds).
seek() {
    local offset="$1"
    if [[ ! "$offset" =~ ^-?[0-9]+$ ]]; then
        echo "Invalid offset value. Use an integer (positive or negative)." >&2
        return 1
    fi
    local current_position track_length new_position
    current_position=$(position)
    track_length=$(length)
    new_position=$((current_position + offset))
    if [[ "$new_position" -gt "$track_length" ]]; then
        echo "Offset exceeds track length. Skipping to next track." >&2
        next
        return 0
    fi
    if [[ "$new_position" -lt 0 ]]; then
        echo "Offset is less than 0. Skipping to previous track." >&2
        previous
        return 0
    fi
    set_method "Seek" "$offset" "int64"
}

# Load a context URI (e.g., playlist, album).
loadContextUri() {
    local uri="$1"
    if [[ -z "$uri" ]]; then
        echo "Invalid URI. Provide a valid URI to load." >&2
        return 1
    fi
    dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.LoadContextUri \
        string:"$uri"
}

# Open a specific URI (track, album, etc.).
openUri() {
    local uri="$1"
    if [[ -z "$uri" ]]; then
        echo "Invalid URI. Provide a valid URI to open." >&2
        return 1
    fi
    dbus-send --print-reply --dest=org.mpris.MediaPlayer2.spotify \
        /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player.OpenUri \
        string:"$uri"
}

########################################
# Loop and Shuffle Controls
########################################

# Set the LoopStatus property ("None", "Track", "Playlist").
set_loopStatus() {
    local status="$1"
    if [[ "$status" != "None" && "$status" != "Track" && "$status" != "Playlist" ]]; then
        echo "Invalid LoopStatus value. Use 'None', 'Track', or 'Playlist'." >&2
        return 1
    fi
    set_property "LoopStatus" "$status" "string"
}
loopTrack()     { set_loopStatus "Track"; }
loopPlaylist()  { set_loopStatus "Playlist"; }
loopNone()      { set_loopStatus "None"; }
loopToggle() {
    case "$(loopStatus)" in
        None)    loopTrack ;;
        Track)   loopPlaylist ;;
        *)       loopNone ;;
    esac
}

# Set the Shuffle property ("true" or "false").
set_shuffle() {
    local shuffle="$1"
    if [[ "$shuffle" != "true" && "$shuffle" != "false" ]]; then
        echo "Invalid Shuffle value. Use 'true' or 'false'." >&2
        return 1
    fi
    set_property "Shuffle" "$shuffle" "boolean"
}
shuffleOn()     { set_shuffle "true"; }
shuffleOff()    { set_shuffle "false"; }
shuffleToggle() {
    if [[ "$(shuffle)" == "true" ]]; then
        shuffleOff
    else
        shuffleOn
    fi
}

########################################
# Helper and Formatting Functions
########################################

# Format seconds as HH:MM:SS or MM:SS.
format_time() {
    local secs="$1"
    if [[ $secs -ge 3600 ]]; then
        printf "%02d:%02d:%02d" $((secs / 3600)) $(( (secs % 3600) / 60 )) $((secs % 60))
    else
        printf "%02d:%02d" $((secs / 60)) $((secs % 60))
    fi
}

# Show position in seconds, formatted.
position_sec() { format_time "$(( $(position) / 1000000 ))"; }
length_sec()   { format_time "$(( $(length) / 1000000 ))"; }
progress()     { echo "$(position_sec)/$(length_sec)"; }

########################################
# Help Function
########################################

show_help() {
    cat <<EOF
Spotify DBus Control Script

Usage: $0 <command> [args]

Playback control:
  play              Start playback
  pause             Pause playback
  playpause         Toggle play/pause
  next              Next track
  previous          Previous track
  stop              Stop playback

Playback properties:
  playbackStatus    Show playback status
  position          Show position (microseconds)
  rate              Show playback rate
  volume            Show volume (0-100)
  loopStatus        Show loop status (None, Track, Playlist)
  shuffle           Show shuffle status (true/false)
  canGoNext         Can go to next track?
  canGoPrevious     Can go to previous track?
  canPlay           Can play?
  canPause          Can pause?
  canSeek           Can seek?
  canControl        Can control?

Metadata:
  trackId           Show track ID
  length            Show track length (microseconds)
  artUrl            Show artwork URL
  album             Show album name
  albumArtist       Show album artist
  artist            Show artist name
  autoRating        Show auto rating
  discNumber        Show disc number
  title             Show track title
  trackNumber       Show track number
  url               Show track URL

Setters:
  set_volume <v>        Set volume (0-100)
  set_position <pos>    Set position (microseconds)
  set_rate <rate>       Set playback rate (0.5-2.0)
  seek <offset>         Seek by offset (microseconds)
  loadContextUri <uri>  Load context URI (playlist/album)
  openUri <uri>         Open specific URI (track/album)

Loop and shuffle:
  set_loopStatus <val>  Set loop status (None, Track, Playlist)
  loopTrack             Set loop to track
  loopPlaylist          Set loop to playlist
  loopNone              Disable looping
  loopToggle            Toggle loop status
  set_shuffle <val>     Set shuffle (true/false)
  shuffleOn             Enable shuffle
  shuffleOff            Disable shuffle
  shuffleToggle         Toggle shuffle

Formatting:
  position_sec          Show position (formatted)
  length_sec            Show length (formatted)
  progress              Show progress (position/length)

Signals:
  seeked                Listen for Seeked signals

help                    Show this help message

EOF
}

########################################
# Main Function and Argument Handling
########################################

main() {
    if [[ "$1" == "help" || "$1" == "--help" || "$1" == "-h" ]]; then
        show_help
        return 0
    fi

    if ! running; then
        echo "Spotify is not running. Please start Spotify." >&2
        return 1
    fi

    case "$1" in
        (play) play ;;
        (pause) pause ;;
        (playpause) playpause ;;
        (next) next ;;
        (previous) previous ;;
        (stop) stop ;;
        (trackId) trackId ;;
        (length) length ;;
        (artUrl) artUrl ;;
        (album) album ;;
        (albumArtist) albumArtist ;;
        (artist) artist ;;
        (autoRating) autoRating ;;
        (discNumber) discNumber ;;
        (title) title ;;
        (trackNumber) trackNumber ;;
        (url) url ;;
        (playbackStatus) playbackStatus ;;
        (position) position ;;
        (rate) rate ;;
        (volume) volume ;;
        (loopStatus) loopStatus ;;
        (shuffle) shuffle ;;
        (canGoNext) canGoNext ;;
        (canGoPrevious) canGoPrevious ;;
        (canPlay) canPlay ;;
        (canPause) canPause ;;
        (canSeek) canSeek ;;
        (canControl) canControl ;;
        (seeked) seeked ;;
        (set_volume) set_volume "$2" ;;
        (set_position) set_position "$2" ;;
        (set_rate) set_rate "$2" ;;
        (seek) seek "$2" ;;
        (loadContextUri) loadContextUri "$2" ;;
        (openUri) openUri "$2" ;;
        (set_loopStatus) set_loopStatus "$2" ;;
        (loopTrack) loopTrack ;;
        (loopPlaylist) loopPlaylist ;;
        (loopNone) loopNone ;;
        (loopToggle) loopToggle ;;
        (set_shuffle) set_shuffle "$2" ;;
        (shuffleOn) shuffleOn ;;
        (shuffleOff) shuffleOff ;;
        (shuffleToggle) shuffleToggle ;;
        (position_sec) position_sec ;;
        (length_sec) length_sec ;;
        (progress) progress ;;
        (help|--help|-h) show_help ;;
        (""|*) show_help ;;
    esac
}

main "$@"
