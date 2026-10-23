; defs.inc - constants of Polonaise C64: memory map, hardware, game parameters

; ---- memory: VIC bank 3 ($c000-$ffff)
SCREEN      = $c000         ; screen RAM: characters of the text rows, colours of the bitmap rows
SPRDYN      = $c400         ; 16 sprites drawn at runtime (pointers $10..$1f)
CHARSET     = $c800         ; character set of the text rows
SPRSTAT     = $d000         ; static sprites (pointers $40..), RAM under the I/O area
BITMAP      = $e000         ; multicolor bitmap of the field (RAM under the KERNAL)
COLRAM      = $d800
SPRPTR      = SCREEN + $3f8

SPRDYN_PTR  = (SPRDYN - $c000) / 64
SPRSTAT_PTR = (SPRSTAT - $c000) / 64

D018_TEXT   = $02           ; screen $c000, characters $c800
D018_BITMAP = $08           ; screen $c000, bitmap $e000

; ---- VIC, SID, CIA
VIC         = $d000
SID         = $d400
CIA1        = $dc00
CIA2        = $dd00

; ---- modes of a character row (rowmode)
RM_BITMAP   = 0
RM_TEXT     = 1             ; text, multicolor characters with the panel colours
RM_LOGO     = 2             ; text, multicolor characters with the logo colours
RM_BLANK    = 3             ; black (invalid VIC mode)

; ---- the game (game.ts)
COLS        = 19
ROWS        = 12
CELLS       = COLS * ROWS
MAX_GUESTS  = 32
TURN_QUEUE  = 2
LOOKS       = 64
TICK_HZ     = 60
SKIP_TICKS  = TICK_HZ

LIVES_START = 3
LIVES_MAX   = 5
COMBO_TICKS = 4 * TICK_HZ
COMBO_MAX   = 5
STAR_TICKS  = 8 * TICK_HZ
STAR_EVERY  = 15 * TICK_HZ
FLEE_DISTANCE = 3

; points in units of 100
POINTS_DANCER   = 1
POINTS_SHY      = 2
POINTS_STAR     = 5
POINTS_FOLLOWER = 1
POINTS_SONG     = 10
POINTS_PERFECT  = 20

DIR_RIGHT   = 0
DIR_DOWN    = 1
DIR_LEFT    = 2
DIR_UP      = 3
DIR_NONE    = 4

TILE_FLOOR  = 0
TILE_DJ     = 1
TILE_TABLE  = 2
TILE_SPEAKER = 3
TILE_BAR    = 4

GUEST_DANCER = 0
GUEST_SHY   = 1
GUEST_STAR  = 2

PHASE_INTRO = 0
PHASE_PLAY  = 1
PHASE_CRASH = 2
PHASE_CLEARED = 3
PHASE_GAME_OVER = 4

EV_TURN     = 0
EV_GO       = 1
EV_DENY     = 2
EV_GRACE    = 3
EV_CATCH    = 4
EV_FLEE     = 5
EV_STAR     = 6
EV_STAR_GONE = 7
EV_CRASH    = 8
EV_EXTRA_LIFE = 9
EV_SONG_START = 10
EV_PLAY     = 11
EV_CLEARED  = 12
EV_GAME_OVER = 13
MAX_EVENTS  = 16

FIRST_INTRO_TICKS = 20 * TICK_HZ
INTRO_TICKS = 4 * TICK_HZ
CRASH_TICKS = 3 * TICK_HZ / 2
CLEARED_TICKS = 7 * TICK_HZ
GAME_OVER_TICKS = 6 * TICK_HZ
SPAWN_DISTANCE = 4
START_CELL  = 9 * COLS + 9

; ---- the renderer (draw.ts)
BEAT_TICKS  = 30
LIGHT_TICKS = 50
FLEE_TICKS  = 40
GUEST_STEP  = 8
SHAKE_TICKS = 20
FLASH_TICKS = 24

; ---- colours
BLACK = 0
WHITE = 1
RED = 2
CYAN = 3
PURPLE = 4
GREEN = 5
BLUE = 6
YELLOW = 7
ORANGE = 8
BROWN = 9
LRED = 10
DGREY = 11
GREY = 12
LGREEN = 13
LBLUE = 14
LGREY = 15
