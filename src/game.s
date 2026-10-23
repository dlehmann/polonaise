; game.s - the game logic, a port of game.ts: a conga line on a disco dance floor,
; steered like Snake. It runs in ticks of 1/60 s; game_tick takes the input of
; one tick and reports what happened in it as events (for the sounds and effects).
;
; Cells are numbered y * COLS + x (0..227); $ff is "no cell" (-1 in game.ts).
; Scores are counted in units of 100 points (24 bits).

NO_CELL = $ff

.segment "BSS"
rng:        .res 4
phase:      .res 1
timer:      .res 2
done:       .res 1
song:       .res 1
score:      .res 3
lives:      .res 1
extra_lives: .res 1
song_crashes: .res 1
tile:       .res CELLS
length:     .res 1
body:       .res CELLS
look:       .res CELLS
moving:     .res 1
dir:        .res 1
queue:      .res TURN_QUEUE
queue_n:    .res 1
step_timer: .res 1
grace:      .res 1
steps:      .res 1
g_active:   .res MAX_GUESTS
g_type:     .res MAX_GUESTS
g_cell:     .res MAX_GUESTS
g_from:     .res MAX_GUESTS
g_moved:    .res MAX_GUESTS
g_look:     .res MAX_GUESTS
g_age_lo:   .res MAX_GUESTS
g_age_hi:   .res MAX_GUESTS
g_top:      .res 1              ; the guest slots in use are below this
star_timer: .res 2
combo:      .res 1
combo_timer: .res 1
dropped:    .res 1
bonus_followers: .res 1
bonus_song: .res 2
bonus_perfect: .res 1
bonus_total: .res 2

; occupation of the cells: a member of the line / the guest slot + 1
memb:       .res CELLS
gmap:       .res CELLS
cand:       .res CELLS          ; candidate cells of spawn_cell

; the parameters of the current song (song_set)
song_target: .res 1
song_step:  .res 1
song_guests: .res 1
song_shy:   .res 1
song_layout: .res 1

; events of the last tick
ev_n:       .res 1
ev_type:    .res MAX_EVENTS
ev_cell:    .res MAX_EVENTS
ev_count:   .res MAX_EVENTS
ev_index:   .res MAX_EVENTS
ev_points:  .res MAX_EVENTS * 2     ; lo, hi interleaved

; temporaries of the logic
gt_d:       .res 1
gt_a:       .res 1
gt_slot:    .res 1
gt_target:  .res 1
gt_cell:    .res 1
gt_best:    .res 1
gt_bestd:   .res 1
gt_bestf:   .res 1
gt_head:    .res 1
gt_i:       .res 1
gt_k:       .res 1
gt_n:       .res 1
gt_dist:    .res 1
gt_ahead:   .res 1
gt_count:   .res 1
gt_type:    .res 1
gt_look:    .res 1
gt_pts:     .res 2
gt_e:       .res 1
gt_c:       .res 1
gt_nfree:   .res 1
rnd:        .res 3
mul:        .res 4

.segment "RODATA"

step_ticks: .byte 10, 9, 9, 8, 8, 7, 7, 6, 6, 6, 6
STEP_MIN = 5
shy_percent: .byte 0, 25, 30, 35, 40, 45, 50
; extra lives at 15000, 40000, 80000, 150000 points
extra_lo:   .byte <150, <400, <800, <1500
extra_hi:   .byte >150, >400, >800, >1500
EXTRA_COUNT = 4

dir_dx:     .byte 1, 0, $ff, 0
dir_dy:     .byte 0, 1, 0, $ff

; the floor layouts, one per song (repeating): '.' floor, 'D' DJ desk, 'T' high table,
; 'S' speaker, 'B' bar counter
.define EMPTY "..................."
layouts:
        .byte EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY
        .byte ".......DDDDD.......", EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY
        .byte ".......DDDDD.......", EMPTY, EMPTY, "....T.........T....", EMPTY, EMPTY, EMPTY, EMPTY
        .byte "....T.........T....", EMPTY, EMPTY, EMPTY
        .byte "SS.....DDDDD.....SS", "SS...............SS", EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY, EMPTY
        .byte EMPTY, "SS...............SS", "SS...............SS"
        .byte ".......DDDDD.......", EMPTY, EMPTY, EMPTY, "...T...........T...", EMPTY, EMPTY
        .byte "...T...........T...", EMPTY, EMPTY, EMPTY, ".....BBBBBBBBB....."
        .byte "SS.....DDDDD.....SS", "SS...............SS", EMPTY, EMPTY, EMPTY, "........TTT........"
        .byte "........TTT........", EMPTY, EMPTY, EMPTY, "SS...............SS", "SS...............SS"
        .byte ".......DDDDD.......", EMPTY, EMPTY, ".....B.......B.....", ".....B.......B....."
        .byte ".....B.......B.....", ".....B.......B.....", ".....B.......B.....", ".....B.......B....."
        .byte EMPTY, EMPTY, EMPTY
        .byte "SS.....DDDDD.....SS", "SS...............SS", "..T......T......T..", EMPTY, EMPTY
        .byte ".....T.......T.....", EMPTY, EMPTY, EMPTY, EMPTY, "..T......T......T..", EMPTY
LAYOUTS = 8

layout_lo:
.repeat LAYOUTS, i
        .byte <(layouts + i * CELLS)
.endrepeat
layout_hi:
.repeat LAYOUTS, i
        .byte >(layouts + i * CELLS)
.endrepeat

; x and y of each cell
cell_x:
.repeat CELLS, i
        .byte i .mod COLS
.endrepeat
cell_y:
.repeat CELLS, i
        .byte i / COLS
.endrepeat

.segment "CODE"

; ---------------------------------------------------------------- parameters

; The parameters of song A into song_* (A >= 1).
song_set:
        sta gt_n
        ; target = min(8 + 2 (n - 1), 24)
        cmp #9
        bcc @t
        lda #24
        bne @t2
@t:     asl
        clc
        adc #6
@t2:    sta song_target
        ; step ticks
        ldx gt_n
        cpx #12
        bcc @s
        lda #STEP_MIN
        bne @s2
@s:     lda step_ticks - 1, x
@s2:    sta song_step
        ; guests = min(3 + (n - 1) / 2, 6)
        lda gt_n
        sec
        sbc #1
        lsr
        clc
        adc #3
        cmp #6
        bcc @g
        lda #6
@g:     sta song_guests
        ; shy percent
        ldx gt_n
        cpx #7
        bcc @h
        ldx #7
@h:     lda shy_percent - 1, x
        sta song_shy
        ; layout = (n - 1) % 8
        lda gt_n
        sec
        sbc #1
        and #7
        sta song_layout
        rts

; The target of song A (for the summary of the next song).
song_target_of:
        cmp #9
        bcc @t
        lda #24
        rts
@t:     asl
        clc
        adc #6
        rts

; ---------------------------------------------------------------- random numbers

; rng = rng * 1664525 + 1013904223; rnd = rng >> 8 (24 bits).
random:
        ; mul = rng * $0019660d (32 bits)
        lda #0
        sta mul
        sta mul + 1
        sta mul + 2
        sta mul + 3
        ldx #32
        lda rng
        sta rnd_m
        lda rng + 1
        sta rnd_m + 1
        lda rng + 2
        sta rnd_m + 2
        lda rng + 3
        sta rnd_m + 3
        lda #$0d
        sta rnd_c
        lda #$66
        sta rnd_c + 1
        lda #$19
        sta rnd_c + 2
        lda #$00
        sta rnd_c + 3
@bit:   lsr rnd_c + 3
        ror rnd_c + 2
        ror rnd_c + 1
        ror rnd_c
        bcc @nadd
        clc
        lda mul
        adc rnd_m
        sta mul
        lda mul + 1
        adc rnd_m + 1
        sta mul + 1
        lda mul + 2
        adc rnd_m + 2
        sta mul + 2
        lda mul + 3
        adc rnd_m + 3
        sta mul + 3
@nadd:  asl rnd_m
        rol rnd_m + 1
        rol rnd_m + 2
        rol rnd_m + 3
        lda rnd_c
        ora rnd_c + 1
        ora rnd_c + 2
        ora rnd_c + 3
        beq @done
        dex
        bne @bit
@done:  clc
        lda mul
        adc #$5f                ; 1013904223 = $3c6ef35f
        sta rng
        lda mul + 1
        adc #$f3
        sta rng + 1
        sta rnd
        lda mul + 2
        adc #$6e
        sta rng + 2
        sta rnd + 1
        lda mul + 3
        adc #$3c
        sta rng + 3
        sta rnd + 2
        rts

.segment "BSS"
rnd_m:      .res 4
rnd_c:      .res 4
rnd_n:      .res 1
.segment "CODE"

; A = random() % A (A >= 1).
rand_mod:
        sta rnd_n
        jsr random
        ; remainder of the 24 bit rnd by rnd_n
        lda #0
        ldx #24
@l:     asl rnd
        rol rnd + 1
        rol rnd + 2
        rol
        bcs @sub
        cmp rnd_n
        bcc @n
@sub:   sbc rnd_n
@n:     dex
        bne @l
        rts

; ---------------------------------------------------------------- cells

; The neighbour of cell A in direction X, or NO_CELL outside the field (or A = NO_CELL).
next_cell:
        cmp #NO_CELL
        beq @out
        cpx #DIR_NONE
        beq @same
        tay
        lda cell_x, y
        clc
        adc dir_dx, x
        cmp #COLS
        bcs @out                ; also -1
        lda cell_y, y
        clc
        adc dir_dy, x
        cmp #ROWS
        bcs @out
        tya
        cpx #DIR_RIGHT
        beq @r
        cpx #DIR_LEFT
        beq @l
        cpx #DIR_DOWN
        beq @d
        sec
        sbc #COLS
        rts
@d:     clc
        adc #COLS
        rts
@r:     clc
        adc #1
        rts
@l:     sec
        sbc #1
        rts
@same:  rts
@out:   lda #NO_CELL
        rts

; A = the Manhattan distance of the cells X and Y.
distance:
        lda cell_x, x
        sec
        sbc cell_x, y
        bcs @x
        eor #$ff
        adc #1
@x:     sta dist_t
        lda cell_y, x
        sec
        sbc cell_y, y
        bcs @y
        eor #$ff
        adc #1
@y:     clc
        adc dist_t
        rts

.segment "BSS"
dist_t:     .res 1
.segment "CODE"

; Z clear if the cell A is blocked by furniture or the line (A kept).
cell_blocked:
        tax
        lda tile, x
        ora memb, x
        php
        txa
        plp
        rts

; Carry set if cell A is inside the field and empty.
cell_free:
        cmp #NO_CELL
        beq @no
        tax
        lda tile, x
        ora memb, x
        ora gmap, x
        bne @no
        txa
        sec
        rts
@no:    clc
        rts

; ---------------------------------------------------------------- events

; Adds an event: A type, gt_e cell, ev_c count, ev_i index, gt_pts points.
event:
        ldx ev_n
        cpx #MAX_EVENTS
        bcs @full
        sta ev_type, x
        lda gt_e
        sta ev_cell, x
        lda ev_c
        sta ev_count, x
        lda ev_i
        sta ev_index, x
        txa
        asl
        tax
        lda gt_pts
        sta ev_points, x
        lda gt_pts + 1
        sta ev_points + 1, x
        inc ev_n
@full:  lda #0
        sta ev_c
        sta ev_i
        sta gt_pts
        sta gt_pts + 1
        rts

.segment "BSS"
ev_c:       .res 1
ev_i:       .res 1
.segment "CODE"

; An event at the leader's cell without further values.
event_head:
        ldx body
        stx gt_e
        jmp event

set_phase:
        sta phase
        lda #0
        sta timer
        sta timer + 1
        rts

; ---------------------------------------------------------------- score

; Adds gt_pts (units of 100) to the score and hands out extra lives.
add_score:
        clc
        lda score
        adc gt_pts
        sta score
        lda score + 1
        adc gt_pts + 1
        sta score + 1
        lda score + 2
        adc #0
        sta score + 2
@extra: ldx extra_lives
        cpx #EXTRA_COUNT
        bcs @done
        lda score + 2
        bne @got
        lda score + 1
        cmp extra_hi, x
        bcc @done
        bne @got
        lda score
        cmp extra_lo, x
        bcc @done
@got:   inc extra_lives
        lda lives
        cmp #LIVES_MAX
        bcs @extra
        inc lives
        lda lives
        sta ev_c
        lda #0
        sta gt_pts              ; the event has no points; keep the sum below safe
        sta gt_pts + 1
        lda #EV_EXTRA_LIFE
        jsr event_head
        jmp @extra
@done:  lda #0
        sta gt_pts
        sta gt_pts + 1
        rts

; ---------------------------------------------------------------- guests

; A random free cell away from the leader and not right in front of it; NO_CELL if none.
spawn_cell:
        lda #NO_CELL
        ldx moving
        beq @na
        lda body
        ldx dir
        jsr next_cell
@na:    sta gt_ahead
        ; first with the distance, then without
        lda #SPAWN_DISTANCE
        jsr collect_cells
        bne @pick
        lda #0
        jsr collect_cells
        bne @pick
        lda #NO_CELL
        rts
@pick:  lda gt_count
        jsr rand_mod
        tax
        lda cand, x
        rts

; Collects the free cells at least A away from the leader (not gt_ahead) into cand;
; their number in gt_count (and Z clear if there are any).
collect_cells:
        sta cc_min
        lda #0
        sta gt_count
        ldx #0
@c:     lda tile, x
        ora memb, x
        ora gmap, x
        bne @next
        cpx gt_ahead
        beq @next
        lda cc_min
        beq @ok
        stx cc_x
        ldy body
        jsr distance
        ldx cc_x
        cmp cc_min
        bcc @next
@ok:    txa
        ldy gt_count
        sta cand, y
        inc gt_count
@next:  inx
        cpx #CELLS
        bne @c
        lda gt_count
        rts

.segment "BSS"
cc_min:     .res 1
cc_x:       .res 1
.segment "CODE"

; Puts a guest of type gt_type on cell A (look gt_look, or a random one if 0).
; Returns the slot in A, or $ff (also in gt_slot).
add_guest:
        sta gt_cell
        ldx #0
@f:     lda g_active, x
        beq @found
        inx
        cpx #MAX_GUESTS
        bne @f
        beq @none
@found: lda gt_cell
        cmp #NO_CELL
        beq @none
        stx gt_slot
        lda gt_look
        bne @l
        lda #LOOKS - 1
        jsr rand_mod
        clc
        adc #1
@l:     ldx gt_slot
        sta g_look, x
        lda #1
        sta g_active, x
        lda gt_type
        sta g_type, x
        lda gt_cell
        sta g_cell, x
        sta g_from, x
        tay
        txa
        clc
        adc #1
        sta gmap, y
        lda #TICK_HZ
        sta g_moved, x
        lda #0
        sta g_age_lo, x
        sta g_age_hi, x
        inx
        cpx g_top
        bcc @t
        stx g_top
@t:     dex
        txa
        rts
@none:  lda #$ff
        sta gt_slot
        rts

; Removes the guest X from the floor.
remove_guest:
        lda #0
        sta g_active, x
        ldy g_cell, x
        sta gmap, y
        rts

; Keeps at least the song's number of guests (without stars) on the floor.
fill_guests:
        ldx #0
        stx gt_n
@c:     lda g_active, x
        beq @nc
        lda g_type, x
        cmp #GUEST_STAR
        beq @nc
        inc gt_n
@nc:    inx
        cpx g_top
        bcc @c
@add:   lda gt_n
        cmp song_guests
        bcs @done
        lda #100
        jsr rand_mod
        ldx #GUEST_DANCER
        cmp song_shy
        bcs @t
        ldx #GUEST_SHY
@t:     stx fg_type
        jsr spawn_cell
        ldx fg_type
        stx gt_type
        ldx #0
        stx gt_look
        jsr add_guest
        cmp #$ff
        beq @done
        inc gt_n
        bne @add
@done:  rts

.segment "BSS"
fg_type:    .res 1
.segment "CODE"

; ---------------------------------------------------------------- songs

; Starts a game at song 1 with the seed in rng (0 becomes $3141).
game_new:
        lda rng
        ora rng + 1
        ora rng + 2
        ora rng + 3
        bne @s
        lda #$41
        sta rng
        lda #$31
        sta rng + 1
@s:     lda #PHASE_INTRO
        sta phase
        lda #0
        sta timer
        sta timer + 1
        sta done
        sta score
        sta score + 1
        sta score + 2
        sta extra_lives
        sta song_crashes
        sta grace
        sta steps
        sta combo
        sta combo_timer
        sta dropped
        sta ev_n
        ldx #MAX_GUESTS - 1
@g:     sta g_active, x
        dex
        bpl @g
        lda #LIVES_START
        sta lives
        lda #1
        sta song
        jmp start_song

; Jumps to song A (the demo of the title screen).
game_start_at:
        sta song
        lda #0
        sta ev_n
        ; fall through

; Sets up the floor of the current song: furniture, the lone leader, fresh guests.
start_song:
        lda song
        jsr song_set
        ldx song_layout
        lda layout_lo, x
        sta ptr
        lda layout_hi, x
        sta ptr + 1
        ldy #0
@t:     lda (ptr), y
        ldx #TILE_FLOOR
        cmp #'D'
        bne @1
        ldx #TILE_DJ
@1:     cmp #'T'
        bne @2
        ldx #TILE_TABLE
@2:     cmp #'S'
        bne @3
        ldx #TILE_SPEAKER
@3:     cmp #'B'
        bne @4
        ldx #TILE_BAR
@4:     txa
        sta tile, y
        lda #0
        sta memb, y
        sta gmap, y
        iny
        cpy #CELLS
        bne @t
        lda #1
        sta length
        lda #START_CELL
        sta body
        tax
        lda #1
        sta memb, x
        lda #0
        sta look
        sta moving
        sta queue_n
        sta step_timer
        sta combo
        sta combo_timer
        sta song_crashes
        lda #DIR_RIGHT
        sta dir
        ldx #MAX_GUESTS - 1
        lda #0
        sta g_top
@g:     sta g_active, x
        dex
        bpl @g
        lda #<STAR_EVERY
        sta star_timer
        lda #>STAR_EVERY
        sta star_timer + 1
        jsr fill_guests
        lda #PHASE_INTRO
        jsr set_phase
        lda song
        sta ev_c
        lda #EV_SONG_START
        jmp event_head

; The line is long enough: the bonus is added and the summary screen begins.
finish_song:
        lda length
        sec
        sbc #1
        sta bonus_followers
        ; song bonus = 10 * song
        lda song
        sta bonus_song
        lda #0
        sta bonus_song + 1
        asl bonus_song
        rol bonus_song + 1
        lda bonus_song
        ldx bonus_song + 1
        asl bonus_song
        rol bonus_song + 1
        asl bonus_song
        rol bonus_song + 1
        clc
        adc bonus_song
        sta bonus_song
        txa
        adc bonus_song + 1
        sta bonus_song + 1
        lda #0
        ldx song_crashes
        bne @p
        lda #POINTS_PERFECT
@p:     sta bonus_perfect
        clc
        adc bonus_followers
        sta bonus_total
        lda #0
        adc #0
        sta bonus_total + 1
        clc
        lda bonus_total
        adc bonus_song
        sta bonus_total
        sta gt_pts
        lda bonus_total + 1
        adc bonus_song + 1
        sta bonus_total + 1
        sta gt_pts + 1
        jsr add_score
        lda #0
        sta moving
        lda #PHASE_CLEARED
        jsr set_phase
        lda bonus_followers
        sta ev_c
        lda bonus_total
        sta gt_pts
        lda bonus_total + 1
        sta gt_pts + 1
        lda #EV_CLEARED
        jmp event_head

; The leader ran into something: a life and the back half of the line are lost.
crash:
        ; drop = (followers + 1) / 2 = length / 2
        lda length
        lsr
        sta dropped
        lda #0
        sta gt_k
@d:     lda gt_k
        cmp dropped
        bcs @dd
        ; i = length - 1 - k
        lda length
        clc
        sbc gt_k
        tax
        lda look, x
        sta gt_look
        lda body, x
        tay
        lda #0
        sta memb, y
        lda #GUEST_DANCER
        sta gt_type
        tya
        jsr add_guest
        inc gt_k
        bne @d
@dd:    lda length
        sec
        sbc dropped
        sta length
        dec lives
        inc song_crashes
        lda #0
        sta moving
        sta queue_n
        sta grace
        sta combo
        sta combo_timer
        lda dropped
        sta ev_c
        lda lives
        sta ev_i
        lda #EV_CRASH
        jsr event_head
        lda lives
        bne @alive
        lda #PHASE_GAME_OVER
        jsr set_phase
        lda #EV_GAME_OVER
        jmp event_head
@alive: lda #PHASE_CRASH
        jmp set_phase

; The leader touched the guest X: points (times the combo) and a longer combo.
catch_guest:
        stx gt_slot
        lda g_type, x
        sta ev_i
        ldy #POINTS_DANCER
        cmp #GUEST_SHY
        bne @s
        ldy #POINTS_SHY
@s:     cmp #GUEST_STAR
        bne @t
        ldy #POINTS_STAR
@t:     sty cg_base
        lda combo_timer
        beq @one
        lda combo
        cmp #COMBO_MAX
        bcs @c
        inc combo
        bne @c
@one:   lda #1
        sta combo
@c:     lda #COMBO_TICKS
        sta combo_timer
        ; points = base * combo
        lda #0
        ldx combo
@m:     clc
        adc cg_base
        dex
        bne @m
        sta gt_pts
        sta cg_pts
        lda #0
        sta gt_pts + 1
        ldx gt_slot
        jsr remove_guest
        ldx gt_slot
        lda g_cell, x
        sta gt_e
        lda combo
        sta ev_c
        lda #EV_CATCH
        jsr event
        lda cg_pts
        sta gt_pts
        lda #0
        sta gt_pts + 1
        jmp add_score

.segment "BSS"
cg_base:    .res 1
cg_pts:     .res 1
.segment "CODE"

; Carry set if the leader's next step onto cell A is blocked. The end of the line moves
; on, so it does not count (unless the line is so short that the leader would turn around).
step_blocked:
        cmp #NO_CELL
        beq @yes
        tax
        lda tile, x
        bne @yes
        lda memb, x
        beq @no
        ldy length
        cpy #1
        beq @yes
        txa
        cmp body + 1
        beq @yes
        ldy length
        cmp body - 1, y
        bne @yes
@no:    clc
        rts
@yes:   sec
        rts

; One step of the line in its direction (after a buffered turn).
step:
        lda queue_n
        beq @nq
        lda queue
        sta gt_d
        lda queue + 1
        sta queue
        dec queue_n
        lda gt_d
        cmp dir
        beq @same
        sta ev_i
        lda #EV_TURN
        jsr event_head
@same:  lda gt_d
        sta dir
@nq:    lda body
        ldx dir
        jsr next_cell
        sta gt_target
        jsr step_blocked
        bcc @free
        ; one step of grace: the line stands still and a turn can still save it
        lda grace
        beq @g
        jmp crash
@g:     lda #1
        sta grace
        lda dir
        sta ev_i
        lda #EV_GRACE
        jmp event_head
@free:  lda #0
        sta grace
        ldx gt_target
        lda gmap, x
        sec
        sbc #1
        sta gt_slot             ; $ff: no guest
        ldy length
        cmp #$ff
        beq @nc
        ; the new member appears at the end of the line, where the last one stood
        lda body - 1, y
        sta body, y
        ldx gt_slot
        lda g_look, x
        sta look, y
        jmp @shift
@nc:    ; the end of the line leaves its cell
        ldy length
        ldx body - 1, y
        lda #0
        sta memb, x
@shift: ldy length
        dey
        beq @head
@sh:    lda body - 1, y
        sta body, y
        dey
        bne @sh
@head:  lda gt_target
        sta body
        tax
        lda #1
        sta memb, x
        inc steps
        lda gt_slot
        cmp #$ff
        bne @catch
        rts
@catch: inc length
        ldx gt_slot
        jsr catch_guest
        lda length
        sec
        sbc #1
        cmp song_target
        bcc @fill
        jmp finish_song
@fill:  jmp fill_guests

; Shy guests close to the leader step to the free neighbour farthest from it (at half
; the leader's speed); among equally far ones, to the one with the most free neighbours.
flee:
        lda song_step
        asl
        sta fl_min
        lda body
        sta gt_head
        lda #0
        sta gt_i
@guest: ldx gt_i
        lda g_active, x
        beq @skip
        lda g_type, x
        cmp #GUEST_SHY
        bne @skip
        lda g_moved, x
        cmp fl_min
        bcc @skip
        ldy gt_head
        lda g_cell, x
        tax
        jsr distance
        cmp #FLEE_DISTANCE + 1
        bcc @near
@skip:  jmp @next
@near:
        sta gt_bestd
        lda #NO_CELL
        sta gt_best
        lda #$ff
        sta gt_bestf
        lda #0
        sta gt_k
@d:     ldx gt_i
        lda g_cell, x
        ldx gt_k
        jsr next_cell
        sta gt_c
        jsr cell_free
        bcc @nd
        ldx gt_c
        ldy gt_head
        jsr distance
        sta gt_dist
        ; free neighbours of the candidate
        lda #0
        sta gt_nfree
        sta gt_e
@e:     lda gt_c
        ldx gt_e
        jsr next_cell
        jsr cell_free
        bcc @ne
        inc gt_nfree
@ne:    inc gt_e
        lda gt_e
        cmp #4
        bne @e
        lda gt_dist
        cmp gt_bestd
        beq @eq
        bcs @take
        bcc @nd
@eq:    lda gt_best
        cmp #NO_CELL
        beq @nd
        lda gt_nfree
        cmp gt_bestf
        beq @nd
        bcc @nd
        ; nfree > bestFree (bestFree may be -1 only while best < 0)
@take:  lda gt_c
        sta gt_best
        lda gt_dist
        sta gt_bestd
        lda gt_nfree
        sta gt_bestf
@nd:    inc gt_k
        lda gt_k
        cmp #4
        bne @d
        lda gt_best
        cmp #NO_CELL
        beq @next
        ; the step
        ldx gt_i
        ldy g_cell, x
        lda #0
        sta gmap, y
        tya
        sta g_from, x
        lda gt_best
        sta g_cell, x
        tay
        txa
        clc
        adc #1
        sta gmap, y
        lda #0
        sta g_moved, x
        sty gt_e
        stx ev_i
        lda #EV_FLEE
        jsr event
@next:  inc gt_i
        lda gt_i
        cmp g_top
        bcs @done
        jmp @guest
@done:  rts

.segment "BSS"
fl_min:     .res 1
.segment "CODE"

; Old stars leave; from song 2 a new one appears now and then while the line moves.
stars:
        ldx #0
@s:     lda g_active, x
        beq @ns
        lda g_type, x
        cmp #GUEST_STAR
        bne @ns
        lda g_age_hi, x
        cmp #>STAR_TICKS
        bcc @ns
        bne @gone
        lda g_age_lo, x
        cmp #<STAR_TICKS
        bcc @ns
@gone:  stx gt_i
        jsr remove_guest
        ldx gt_i
        lda g_cell, x
        sta gt_e
        stx ev_i
        lda #EV_STAR_GONE
        jsr event
        ldx gt_i
@ns:    inx
        cpx g_top
        bcc @s
        lda song
        cmp #2
        bcc @done
        lda moving
        beq @done
        ; --starTimer > 0
        lda star_timer
        bne @dl
        dec star_timer + 1
@dl:    dec star_timer
        lda star_timer
        ora star_timer + 1
        bne @done
        lda #<STAR_EVERY
        sta star_timer
        lda #>STAR_EVERY
        sta star_timer + 1
        ldx #0
@a:     lda g_active, x
        beq @na
        lda g_type, x
        cmp #GUEST_STAR
        beq @done
@na:    inx
        cpx g_top
        bcc @a
        jsr spawn_cell
        ldx #GUEST_STAR
        stx gt_type
        ldx #0
        stx gt_look
        jsr add_guest
        cmp #$ff
        beq @done
        tax
        stx ev_i
        lda g_cell, x
        sta gt_e
        lda #EV_STAR
        jmp event
@done:  rts

; The line waits: a free direction A starts it, a blocked one is refused.
go:
        sta gt_d
        lda body
        ldx gt_d
        jsr next_cell
        sta gt_target
        jsr step_blocked
        bcs @deny
        lda length
        cmp #2
        bcc @ok
        lda gt_target
        cmp body + 1
        bne @ok
@deny:  lda gt_d
        sta ev_i
        lda #EV_DENY
        jmp event_head
@ok:    lda gt_d
        sta dir
        lda #0
        sta queue_n
        sta grace
        sta step_timer
        lda #1
        sta moving
        lda gt_d
        sta ev_i
        lda #EV_GO
        jsr event_head
        jmp step

; While moving, direction changes are queued for the next steps; a reversal is ignored.
turn:
        sta gt_d
        ldx queue_n
        cpx #TURN_QUEUE
        bcs @no
        lda dir
        cpx #0
        beq @l
        lda queue - 1, x
@l:     cmp gt_d
        beq @no
        ldy length
        cpy #2
        bcc @push
        clc
        adc #2
        and #3
        cmp gt_d
        beq @no
@push:  lda gt_d
        sta queue, x
        inc queue_n
@no:    rts

; A tick of the PLAY phase with the direction gt_a.
play:
        ldx g_top
        beq @gd
        dex
@g:     lda g_active, x
        beq @ng
        lda g_moved, x
        cmp #255
        beq @m
        inc g_moved, x
@m:     inc g_age_lo, x
        bne @ng
        inc g_age_hi, x
@ng:    dex
        bpl @g
@gd:    lda moving
        bne @moving
        lda gt_a
        cmp #DIR_NONE
        beq @st
        jsr go
        lda phase
        cmp #PHASE_PLAY
        bne @done
@st:    jmp stars
@moving:
        lda gt_a
        cmp #DIR_NONE
        beq @nt
        jsr turn
@nt:    lda combo_timer
        beq @ct
        dec combo_timer
@ct:    inc step_timer
        lda step_timer
        cmp song_step
        bcc @fl
        lda #0
        sta step_timer
        jsr step
        lda phase
        cmp #PHASE_PLAY
        bne @done
@fl:    jsr flee
        jmp stars
@done:  rts

; Advances the game by one tick: A = the direction pressed (DIR_NONE), X = 1 if A (fire) was pressed.
game_tick:
        sta gt_a
        stx gt_fire
        lda #0
        sta ev_n
        inc timer
        bne @t
        inc timer + 1
@t:     lda phase
        cmp #PHASE_INTRO
        bne @nintro
        ; intro: its time is up, or A or a direction after SKIP_TICKS
        lda timer + 1
        ldx song
        cpx #1
        bne @short
        cmp #>FIRST_INTRO_TICKS
        bcc @skip
        bne @go
        lda timer
        cmp #<FIRST_INTRO_TICKS
        bcs @go
        bcc @skip
@short: cmp #0
        bne @go
        lda timer
        cmp #INTRO_TICKS
        bcs @go
@skip:  lda timer + 1
        bne @sk
        lda timer
        cmp #SKIP_TICKS
        bcc @r
@sk:    lda gt_fire
        bne @go
        lda gt_a
        cmp #DIR_NONE
        beq @r
@go:    lda #PHASE_PLAY
        jsr set_phase
        lda #EV_PLAY
        jsr event_head
        lda gt_a
        cmp #DIR_NONE
        beq @r
        jmp go
@r:     rts
@nintro:
        cmp #PHASE_PLAY
        bne @nplay
        jmp play
@nplay: cmp #PHASE_CRASH
        bne @ncrash
        ldx g_top
        beq @cd
        dex
@cg:    lda g_active, x
        beq @cn
        lda g_moved, x
        cmp #255
        beq @cn
        inc g_moved, x
@cn:    dex
        bpl @cg
@cd:    lda timer
        cmp #CRASH_TICKS
        bcc @r
        lda #PHASE_PLAY
        jmp set_phase
@ncrash:
        cmp #PHASE_CLEARED
        bne @nclr
        lda timer + 1
        cmp #>CLEARED_TICKS
        bcc @c1
        bne @next
        lda timer
        cmp #<CLEARED_TICKS
        bcs @next
@c1:    lda timer + 1
        bne @c2
        lda timer
        cmp #SKIP_TICKS
        bcc @r
@c2:    lda gt_fire
        beq @r
@next:  inc song
        bne @ns
        dec song                ; song 255 is the last one
@ns:    jmp start_song
@nclr:  ; game over
        lda timer + 1
        cmp #>GAME_OVER_TICKS
        bcc @r
        bne @dn
        lda timer
        cmp #<GAME_OVER_TICKS
        bcc @r
@dn:    lda #1
        sta done
        rts

.segment "BSS"
gt_fire:    .res 1
.segment "CODE"

; The number of guests in the line.
followers:
        lda length
        sec
        sbc #1
        rts
