package models

// StateType is the state a movie, series, season, episode or game is tracked in
type StateType string

const (
	StateTypeWant     StateType = "want"
	StateTypeWatched  StateType = "watched"
	StateTypeWatching StateType = "watching"
	StateTypePlaying  StateType = "playing"
	StateTypePlayed   StateType = "played"
	StateTypeNone     StateType = "none"
)

// String returns the state's wire value
func (s StateType) String() string {
	return string(s)
}

// NewMovieListState maps a raw list filter to a browsable movie state, defaulting to want
func NewMovieListState(value string) StateType {
	switch state := StateType(value); state {
	case StateTypeWatched:
		return state
	default:
		return StateTypeWant
	}
}

// NewGameListState maps a raw list filter to a browsable game state, defaulting to want
func NewGameListState(value string) StateType {
	switch state := StateType(value); state {
	case StateTypePlaying, StateTypePlayed:
		return state
	default:
		return StateTypeWant
	}
}

// NewSeriesListState maps a raw list filter to a browsable series state, defaulting to want
func NewSeriesListState(value string) StateType {
	switch state := StateType(value); state {
	case StateTypeWatching, StateTypeWatched:
		return state
	default:
		return StateTypeWant
	}
}
