; screens.s - the flow of the game, a port of app.ts and the screen parts of draw.ts:
; the title screen with the demo floor and the best scores, a game with its status
; bar and info panels, the pause, the name entry for a new high score.

M_TITLE = 0
M_GAME  = 1
M_ENTRY = 2

P_NONE     = 0
P_INTRO1   = 1
P_INTRO    = 2
P_CRASH    = 3
P_CLEARED  = 4
P_GAMEOVER = 5
P_PAUSE    = 6

KEY_QUEUE = 4
LONG_PRESS = 35             ; frames of fire to end the game in the pause
MAX_SCORES = 10
NAME_LEN = 10

; colours of draw.ts
C_TEXT  = WHITE
C_LABEL = LGREY
C_DIM   = DGREY
C_PINK  = PURPLE

.segment "BSS"
mode:       .res 1
paused:     .res 1
pause_armed: .res 1
keys:       .res KEY_QUEUE
keys_n:     .res 1
confirm:    .res 1
panel_cur:  .res 1
panel_rows: .res 1          ; CLEARED: rows shown so far
blink_shown: .res 1
; the high score list
hs_count:   .res 1
hs_name:    .res MAX_SCORES * NAME_LEN
hs_score:   .res MAX_SCORES * 3
hs_song:    .res MAX_SCORES
last_name:  .res NAME_LEN
; the result of the last game for the title screen
last_valid: .res 1
last_rank:  .res 1          ; 1.. in the list, 0 not in it
last_score: .res 3
; the name entry
entry_name: .res NAME_LEN
entry_pos:  .res 1
entry_rank: .res 1
entry_rep:  .res 1
sc_t:       .res 4
seed_mix:   .res 1

.segment "RODATA"
; the panels: first and last character row, frame colour
panel_top:    .byte 0, 1, 9, 9, 3, 7, 9
panel_bottom: .byte 0, 22, 16, 16, 20, 14, 16
panel_color:  .byte 0, C_PINK, C_PINK, RED, GREEN, RED, YELLOW
; characters of the name entry, in the order of the joystick
name_chars:
        .byte C_SPACE
        .byte 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26
        .byte C_AE, C_OE, C_UE
        .byte C_ZERO, C_ZERO + 1, C_ZERO + 2, C_ZERO + 3, C_ZERO + 4, C_ZERO + 5, C_ZERO + 6, C_ZERO + 7
        .byte C_ZERO + 8, C_ZERO + 9
        .byte C_DOT, C_MINUS, C_EXCL, C_QUESTION
NAME_CHARS = * - name_chars

.segment "CODE"

; ---------------------------------------------------------------- the main loop

main_loop:
        jsr wait_frame
.ifdef TEST
        jsr autopilot
.endif
        jsr handle_input
        ; the logic ticks due (60 per second)
@tick:  lda ticks_due
        beq @draw
        sei
        dec ticks_due
        cli
        lda paused
        bne @tick
        jsr app_tick
        jmp @tick
@draw:  jsr app_draw
        jmp main_loop

; One logic tick of what is on screen.
app_tick:
        lda mode
        cmp #M_GAME
        beq @game
        jmp render_tick
@game:  ; one direction press per tick
        lda #DIR_NONE
        ldx keys_n
        beq @k
        lda keys
        ldx keys + 1
        stx keys
        ldx keys + 2
        stx keys + 1
        ldx keys + 3
        stx keys + 2
        dec keys_n
@k:     ldx confirm
        jsr game_tick
        lda #0
        sta confirm
        jsr play_events
        jsr render_tick
        jsr fx_tick
        lda done
        beq @r
        jmp end_game
@r:     rts

; The sounds and effects of the events of the last tick.
play_events:
        ldx #0
@e:     cpx ev_n
        beq @done
        stx pe_i
        jsr sound_event
        ldx pe_i
        jsr render_event
        ldx pe_i
        jsr fx_event
        ldx pe_i
        lda ev_type, x
        cmp #EV_SONG_START
        bne @ns
        ; a new floor
        jsr song_screen
@ns:    ldx pe_i
        ldy ev_type, x
        lda ev_hud, y
        ora hud_dirty
        sta hud_dirty
        inx
        bne @e
@done:  rts

.segment "BSS"
pe_i:       .res 1
.segment "RODATA"
; the parts of the status bar each event changes
ev_hud:     .byte 0, 0, 0, 0, HUD_SCORE | HUD_DANCERS | HUD_COMBO, 0, 0, 0
            .byte HUD_DANCERS | HUD_COMBO | HUD_LIVES, HUD_LIVES | HUD_SCORE, $ff, 0, HUD_SCORE | HUD_DANCERS, 0
.segment "CODE"

; Draws the frame of the current mode.
app_draw:
        lda mode
        cmp #M_GAME
        beq @game
        jsr render_field
        jsr title_conga
        lda mode
        cmp #M_ENTRY
        beq @entry
        jmp title_update
@entry: jmp entry_update
@game:  jsr update_panel
        jsr render_field
        jsr draw_hud
        jsr fx_draw
        ; the crash flash: the black of the outlines turns red
        lda screen_flash
        beq @nf
        ldx #RED
        cmp #FLASH_TICKS / 2
        bcs @f
        ldx #BROWN
        cmp #FLASH_TICKS / 4
        bcs @f
        ldx #BLACK
@f:     stx bgcolor
        rts
@nf:    sta bgcolor
        rts

; ---------------------------------------------------------------- input

handle_input:
@next:  jsr pop_input
        bcc @got
        ; the pause: a long press on fire ends the game
        lda mode
        cmp #M_GAME
        bne @r
        lda paused
        beq @r
        lda pause_armed
        beq @r
        lda fire_held
        cmp #LONG_PRESS
        bcc @rel
        jmp end_game
@rel:   lda joy_now
        and #$10
        bne @r
        ; released after a short press: continue
        jmp unpause
@r:     rts
@got:   sta hi_in
        stx hi_key
        ; mix the input into the seed of the next game
        lda frame
        eor seed_mix
        adc hi_in
        sta seed_mix
        lda mode
        cmp #M_TITLE
        bne @nt
        jsr title_input
        jmp @next
@nt:    cmp #M_ENTRY
        bne @ng
        jsr entry_input
        jmp @next
@ng:    jsr game_input
        jmp @next

.segment "BSS"
hi_in:      .res 1
hi_key:     .res 1
.segment "CODE"

; Input in a game.
game_input:
        lda hi_in
        cmp #IN_KEY
        bne @nk
        lda hi_key
        cmp #KEY_STOP
        beq @pause
        cmp #'P'
        beq @pause
        cmp #'Q'
        bne @r
        lda paused
        beq @r
        jmp end_game
@pause: lda paused
        beq @p
        jmp unpause
@p:     jmp pause
@nk:    cmp #IN_FIRE
        bne @dir
        lda paused
        beq @nfp
        lda #1
        sta pause_armed
        rts
@nfp:   lda phase
        cmp #PHASE_PLAY
        beq @p
        lda #1
        sta confirm
@r:     rts
@dir:   lda paused
        bne @r
        ldx keys_n
        cpx #KEY_QUEUE
        bcs @r
        lda hi_in
        sta keys, x
        inc keys_n
        rts

pause:
        lda #1
        sta paused
        lda #0
        sta pause_armed
        sta keys_n
        lda #SFX_PAUSE
        jsr sfx_play
        jmp sound_pause

unpause:
        lda #0
        sta paused
        sta keys_n
        jsr clear_input
        jmp sound_resume

; ---------------------------------------------------------------- a game

; Starts a game (from the title screen).
start_game:
        ; the seed: frame counter, raster, CIA timer, the inputs so far
        lda frame
        sta rng
        lda $d012
        eor seed_mix
        sta rng + 1
        lda CIA1 + 4
        sta rng + 2
        lda CIA1 + 6
        eor r_ticks
        sta rng + 3
        jsr game_new
.ifdef TEST_SONG
        lda #TEST_SONG
        jsr game_start_at
.endif
        lda #M_GAME
        sta mode
        lda #0
        sta paused
        sta keys_n
        sta confirm
        sta last_valid
        lda #1
        sta show_arrows
        jsr clear_input
        jsr music_start
        jsr fx_reset
        jmp play_events         ; the start of song 1 sets up the screen

; The screen of a new song: the field, the status bar, no panel.
song_screen:
        lda #P_NONE
        sta panel_cur
        lda #0
        ldx #0
        ldy #RM_TEXT
        jsr set_rows
        lda #1
        ldx #24
        ldy #RM_BLANK
        jsr set_rows
        jsr update_vis
        jsr wait_frame
        jsr big_reset
        lda #0
        ldx #0
        jsr clear_rows
        jsr field_setup
        jsr redraw_field
        jsr place_dj
        lda #1
        ldx #24
        ldy #RM_BITMAP
        jsr set_rows
        jsr update_vis
        lda #$ff
        sta hud_dirty
        rts

; Back to the title screen; a score good enough for the list asks for the name first.
end_game:
        lda #0
        sta paused
        jsr sound_resume
        jsr fx_reset
        lda score
        sta last_score
        lda score + 1
        sta last_score + 1
        lda score + 2
        sta last_score + 2
        lda song
        sta entry_song
        jsr qualifies
        bcc @title
        jmp start_entry
@title: lda #0
        sta last_rank
        lda last_score
        ora last_score + 1
        ora last_score + 2
        beq @nv
        lda #1
@nv:    sta last_valid
        jmp start_title

.segment "BSS"
entry_song: .res 1
.segment "CODE"

; ---------------------------------------------------------------- panels

; Opens and closes the info panels with the phases of the game.
update_panel:
        lda #P_PAUSE
        ldx paused
        bne @want
        lda phase
        cmp #PHASE_INTRO
        bne @n1
        lda #P_INTRO1
        ldx song
        cpx #1
        beq @want
        lda #P_INTRO
        bne @want
@n1:    cmp #PHASE_CRASH
        bne @n2
        lda timer
        cmp #10
        lda #P_CRASH
        bcs @want
        lda #P_NONE
        beq @want
@n2:    cmp #PHASE_CLEARED
        bne @n3
        lda timer + 1
        bne @cl
        lda timer
        cmp #40
        lda #P_NONE
        bcc @want
@cl:    lda #P_CLEARED
        bne @want
@n3:    cmp #PHASE_GAME_OVER
        bne @none
        lda timer + 1
        bne @go
        lda timer
        cmp #70
        lda #P_NONE
        bcc @want
@go:    lda #P_GAMEOVER
        bne @want
@none:  lda #P_NONE
@want:  cmp panel_cur
        beq @same
        sta up_want
        jsr close_panel
        lda up_want
        jsr open_panel
@same:  jmp panel_refresh

.segment "BSS"
up_want:    .res 1
.segment "CODE"

; Closes the current panel: its rows show the field again.
close_panel:
        ldx panel_cur
        beq @r
        lda panel_top, x
        sta cp_top
        lda panel_bottom, x
        sta cp_bot
        tax
        lda cp_top
        ldy #RM_BLANK
        jsr set_rows
        jsr update_vis
        jsr wait_frame
        ; cell rows (top - 1) / 2 .. (bottom - 2) / 2
        lda cp_bot
        sec
        sbc #2
        lsr
        tax
        lda cp_top
        sec
        sbc #1
        lsr
        jsr redraw_rows
        lda cp_top
        ldx cp_bot
        ldy #RM_BITMAP
        jsr set_rows
        jsr update_vis
        lda #P_NONE
        sta panel_cur
@r:     rts

.segment "BSS"
cp_top:     .res 1
cp_bot:     .res 1
.segment "CODE"

; Opens the panel A.
open_panel:
        sta panel_cur
        tax
        beq @r
        lda panel_top, x
        sta pf_top
        lda panel_bottom, x
        sta pf_bottom
        tax
        lda pf_top
        ldy #RM_BLANK
        jsr set_rows
        jsr update_vis
        jsr wait_frame
        jsr big_reset
        ldx panel_cur
        lda panel_color, x
        jsr panel
        lda #0
        sta panel_rows
        lda #$ff
        sta blink_shown
        jsr panel_content
        lda pf_top
        ldx pf_bottom
        ldy #RM_TEXT
        jsr set_rows
@r:     rts

; The texts of the panel that do not change.
panel_content:
        lda panel_cur
        cmp #P_INTRO1
        bne @n1
        jmp intro1_content
@n1:    cmp #P_INTRO
        bne @n2
        jmp intro_content
@n2:    cmp #P_CRASH
        bne @n3
        jmp crash_content
@n3:    cmp #P_CLEARED
        bne @n4
        jmp cleared_content
@n4:    cmp #P_GAMEOVER
        bne @n5
        jmp gameover_content
@n5:    jmp pause_content

; The parts of the panel that change.
panel_refresh:
        lda panel_cur
        cmp #P_INTRO1
        bne @n1
        lda #21
        jmp intro_start
@n1:    cmp #P_INTRO
        bne @n2
        lda #15
        jmp intro_start
@n2:    cmp #P_CLEARED
        bne @r
        jmp cleared_rows
@r:     rts

; Prints the text A centred in row X in colour Y.
say:
        stx t_row
        sty t_color
        jmp print_center

; Prints the text A in large letters at row X in colour Y.
say_big:
        stx t_row
        sty t_color
        jmp print_big

; Clears the inside of the panel row X.
clear_inner:
        lda row_scr_lo, x
        sta scr
        lda row_scr_hi, x
        clc
        adc #>SCREEN
        sta scr + 1
        ldy #38
        lda #C_SPACE
@l:     sta (scr), y
        dey
        bne @l
        rts

; The song number and the target of the current song for the texts.
song_args:
        lda song
        sta t_song
        lda #0
        sta t_song + 1
        sta t_target + 1
        lda song_target
        sta t_target
        rts

intro1_content:
        jsr song_args
        lda #T_INTRO_TITLE
        ldx #2
        ldy #YELLOW
        jsr say_big
        lda #T_INTRO_GOAL
        ldx #5
        ldy #C_TEXT
        jsr say
        lda #T_HELP_TITLE
        ldx #7
        ldy #CYAN
        jsr say
        lda #T_HELP_STEER
        ldx #9
        ldy #C_TEXT
        jsr say
        lda #T_HELP_PAUSE
        ldx #10
        ldy #C_TEXT
        jsr say
        lda #T_HELP_CATCH
        ldx #12
        ldy #C_TEXT
        jsr say
        lda #T_HELP_COMBO
        ldx #13
        ldy #C_TEXT
        jsr say
        lda #T_HELP_SHY
        ldx #14
        ldy #C_TEXT
        jsr say
        lda #T_HELP_STAR
        ldx #15
        ldy #C_TEXT
        jsr say
        lda #T_HELP_CRASH1
        ldx #17
        ldy #C_TEXT
        jsr say
        lda #T_HELP_CRASH2
        ldx #18
        ldy #C_TEXT
        jsr say
        lda #T_HELP_CRASH3
        ldx #19
        ldy #C_TEXT
        jmp say

intro_content:
        jsr song_args
        lda #T_INTRO_TITLE
        ldx #10
        ldy #YELLOW
        jsr say_big
        lda #T_INTRO_GOAL
        ldx #12
        ldy #C_TEXT
        jsr say
        lda #T_INTRO_FASTER
        ldx #13
        ldy #CYAN
        jmp say

; The blinking start prompt in row A (after SKIP_TICKS).
intro_start:
        sta is_row
        lda #0
        ldx timer + 1
        bne @t
        ldx timer
        cpx #SKIP_TICKS
        bcc @s
@t:     lda r_t20
        and #1
@s:     cmp blink_shown
        beq @r
        sta blink_shown
        ldx is_row
        cmp #0
        beq @clr
        lda #T_INTRO_START
        ldy #YELLOW
        jmp say
@clr:   jmp clear_inner
@r:     rts

.segment "BSS"
is_row:     .res 1
.segment "CODE"

crash_content:
        lda #T_CRASH_TITLE
        ldx #10
        ldy #LRED
        jsr say_big
        lda lives
        sta t_count
        lda #0
        sta t_count + 1
        lda #T_CRASH_LIVES_ONE
        ldx lives
        cpx #1
        beq @one
        lda #T_CRASH_LIVES_OTHER
@one:   ldx #12
        ldy #C_TEXT
        jsr say_big
        lda dropped
        beq @r
        sta t_count
        lda #T_CRASH_DROPPED_ONE
        ldx dropped
        cpx #1
        beq @d1
        lda #T_CRASH_DROPPED_OTHER
@d1:    ldx #14
        ldy #C_LABEL
        jmp say
@r:     rts

gameover_content:
        lda #T_GAMEOVER_TITLE
        ldx #8
        ldy #LRED
        jsr say_big
        lda score
        sta t_score
        lda score + 1
        sta t_score + 1
        lda score + 2
        sta t_score + 2
        lda #T_GAMEOVER_SCORE
        ldx #11
        ldy #C_TEXT
        jsr say
        jsr song_args
        lda #T_GAMEOVER_SONG
        ldx #12
        ldy #C_LABEL
        jmp say

pause_content:
        lda #T_PAUSE_TITLE
        ldx #10
        ldy #YELLOW
        jsr say_big
        lda #T_PAUSE_RESUME
        ldx #13
        ldy #C_TEXT
        jsr say
        lda #T_PAUSE_QUIT
        ldx #14
        ldy #C_LABEL
        jmp say

cleared_content:
        jsr song_args
        lda #T_CLEARED_TITLE
        ldx #4
        ldy #LGREEN
        jmp say_big

; The parts of the bonus appear one after the other (every 20 ticks).
cleared_rows:
        ; rows = (timer - 40) / 20
        lda timer
        sec
        sbc #40
        sta sc_t
        lda timer + 1
        sbc #0
        bne @max
        lda sc_t
        ldx #0
@d:     cmp #20
        bcc @dd
        sbc #20
        inx
        cpx #5
        bne @d
@dd:    txa
        jmp @have
@max:   lda #5
@have:  cmp panel_rows
        beq @r
        bcc @r
        inc panel_rows
        lda panel_rows
        cmp #1
        bne @n2
        ; the line
        lda bonus_followers
        sta t_count
        lda #0
        sta t_count + 1
        lda #T_CLEARED_LINE_ONE
        ldx bonus_followers
        cpx #1
        beq @l1
        lda #T_CLEARED_LINE_OTHER
@l1:    ldx #7
        jsr bonus_label
        lda bonus_followers
        ldx #0
        jmp bonus_value
@r:     rts
@n2:    cmp #2
        bne @n3
        jsr song_args
        lda #T_CLEARED_SONG
        ldx #9
        jsr bonus_label
        lda bonus_song
        ldx bonus_song + 1
        jmp bonus_value
@n3:    cmp #3
        bne @n4
        lda #T_CLEARED_PERFECT
        ldx #11
        jsr bonus_label
        lda bonus_perfect
        ldx #0
        jmp bonus_value
@n4:    cmp #4
        bne @n5
        ldx #13
        ldy #3
        lda #C_DIM
        sta pf_color
@line:  lda #CH_LINE
        jsr panel_put
        iny
        cpy #37
        bne @line
        lda #T_CLEARED_TOTAL
        ldx #14
        jsr bonus_label
        lda score
        sta t_score
        lda score + 1
        sta t_score + 1
        lda score + 2
        sta t_score + 2
        lda #0
        sta tlen
        jsr append_score
        lda #YELLOW
        sta t_color
        lda #37
        sta t_col
        jmp right_buf
@n5:    lda song
        clc
        adc #1
        sta t_song
        jsr song_target_of
        sta t_target
        lda #0
        sta t_target + 1
        lda #T_CLEARED_NEXT
        ldx #16
        ldy #CYAN
        jsr say
        lda #T_CLEARED_NEXTINFO
        ldx #17
        ldy #C_LABEL
        jsr say
        lda #T_CLEARED_CONTINUE
        ldx #19
        ldy #YELLOW
        jmp say

; The label A of a bonus row X.
bonus_label:
        stx t_row
        stx bl_row
        pha
        lda #3
        sta t_col
        lda #C_TEXT
        sta t_color
        pla
        jmp print_left

; "+value" (A lo, X hi, units of 100) right aligned in the bonus row; dim if 0.
bonus_value:
        sta t_score
        stx t_score + 1
        lda #0
        sta t_score + 2
        lda #C_PLUS
        sta tbuf
        lda #1
        sta tlen
        jsr append_score
        lda bl_row
        sta t_row
        ldx #WHITE
        lda t_score
        ora t_score + 1
        bne @c
        ldx #C_DIM
@c:     stx t_color
        lda #37
        sta t_col
        jmp right_buf

.segment "BSS"
bl_row:     .res 1
.segment "CODE"

; ---------------------------------------------------------------- the status bar

; Score, the line against the song's target, the combo, the song and the lives. Each part
; is drawn again only when its bit in hud_dirty is set, without clearing it first.
HUD_SCORE   = 1
HUD_DANCERS = 2
HUD_COMBO   = 4
HUD_SONG    = 8
HUD_LIVES   = 16

draw_hud:
        lda hud_dirty
        bne @go
        rts
@go:    sta hd_d
        lda #0
        sta hud_dirty
        sta t_row
        lsr hd_d
        bcc @nsc
        ; score in columns 1..8
        lda score
        sta t_score
        lda score + 1
        sta t_score + 1
        lda score + 2
        sta t_score + 2
        lda #0
        sta tlen
        jsr append_score
        lda #1
        sta t_col
        lda #WHITE
        sta t_color
        lda #9
        jsr hud_print
@nsc:   lsr hd_d
        bcc @nda
        ; dancers: followers / target in columns 9..14, a bar of 24 pixels in 15..17
        jsr followers
        sta hd_f
        ldx #CYAN
        cmp song_target
        bcc @c
        ldx #LGREEN
@c:     stx t_color
        lda #CH_PERSON
        sta tbuf
        lda #1
        sta tlen
        lda hd_f
        jsr append_byte
        ldx tlen
        lda #C_SLASH
        sta tbuf, x
        inc tlen
        lda song_target
        jsr append_byte
        lda #9
        sta t_col
        lda #15
        jsr hud_print
        lda hd_f
        cmp song_target
        bcc @p
        lda song_target
@p:     ldx #24
        jsr mul8
        ldx song_target
        jsr div16
        ldx #15
        ldy #3
        jsr draw_bar
@nda:   lsr hd_d
        bcc @nco
        ; combo in columns 22..23, its time (16 pixels) in 24..25
        ldx #C_DIM
        lda combo
        beq @cc
        ldx #PURPLE
        cmp #4
        bcc @cc
        ldx #YELLOW
@cc:    lda combo_flash
        beq @cf
        and #4
        beq @cf
        ldx #WHITE
@cf:    lda combo
        bne @c1
        ldx #C_DIM
@c1:    stx hd_cc
        stx t_color
        lda #C_X
        sta tbuf
        lda #1
        sta tlen
        lda combo
        bne @c2
        lda #1
@c2:    jsr append_byte
        lda #22
        sta t_col
        jsr print_buf
        lda combo_timer
        ldx #16
        jsr mul8
        ldx #COMBO_TICKS
        jsr div16
        ldx #24
        ldy #2
        lda hd_cc
        sta t_color
        lda hd_bar
        jsr draw_bar_n
@nco:   lsr hd_d
        bcc @nso
        ; the song in columns 28..31
        lda #CH_NOTE
        sta tbuf
        lda #1
        sta tlen
        lda song
        jsr append_byte
        lda #28
        sta t_col
        lda #C_LABEL
        sta t_color
        lda #32
        jsr hud_print
@nso:   lsr hd_d
        bcc @r
        ; the lives: max(lives, 3) hearts, ending in column 38 (spaces before them)
        lda lives
        cmp #LIVES_START
        bcs @s
        lda #LIVES_START
@s:     sta hd_slots
        lda #39
        sec
        sbc hd_slots
        sta t_col
        tax
        lda #33
        jsr hud_clear
        lda #0
        sta hd_i
@h:     ldx #C_DIM
        lda hd_i
        cmp lives
        bcs @hc
        ldx #LRED
        ; the last one blinks after a crash or an extra life
        clc
        adc #1
        cmp lives
        bne @hc
        lda lives_flash
        beq @hc
        and #8
        beq @hc
        ldx #WHITE
@hc:    stx t_color
        lda #CH_HEART
        sta tbuf
        lda #1
        sta tlen
        jsr print_buf
        inc t_col
        inc hd_i
        lda hd_i
        cmp hd_slots
        bne @h
@r:     rts

; Prints tbuf at t_col in the status bar, padded with spaces up to column A (exclusive):
; every character is written once with its final value, so nothing flickers when the
; beam passes while the bar changes.
hud_print:
        sta hd_end
@pad:   lda t_col
        clc
        adc tlen
        cmp hd_end
        bcs @p
        ldx tlen
        lda #C_SPACE
        sta tbuf, x
        inc tlen
        bne @pad
@p:     jmp print_buf

; Clears the status bar from column A to X (exclusive).
hud_clear:
        stx hd_end
        tax
        lda #C_SPACE
@l:     sta SCREEN, x
        inx
        cpx hd_end
        bne @l
        rts

.segment "BSS"
hd_f:       .res 1
hd_d:       .res 1
hd_end:     .res 1
hd_cc:      .res 1
hd_slots:   .res 1
hd_i:       .res 1
hd_bar:     .res 1
md_a:       .res 2
.segment "CODE"

; Appends the number A (0..255) to tbuf.
append_byte:
        sta num
        lda #0
        sta num + 1
        sta num + 2
        jmp append_num

; md_a = A * X.
mul8:
        sta md_b
        stx md_c
        lda #0
        ldx #8
        lsr md_c
@l:     bcc @n
        clc
        adc md_b
@n:     ror
        ror md_c
        dex
        bne @l
        sta md_a + 1
        lda md_c
        sta md_a
        rts

; A = md_a / X (the result fits in 8 bits).
div16:
        stx md_b
        lda #0
        sta md_q
        ; repeated subtraction (small results)
@l:     lda md_a
        sec
        sbc md_b
        tay
        lda md_a + 1
        sbc #0
        bcc @done
        sta md_a + 1
        sty md_a
        inc md_q
        bne @l
@done:  lda md_q
        sta hd_bar
        rts

.segment "BSS"
md_b:       .res 1
md_c:       .res 1
md_d:       .res 1
md_q:       .res 1
.segment "CODE"

; A bar of hd_bar pixels in Y characters from column X of row 0, in t_color.
draw_bar:
        lda hd_bar
draw_bar_n:
        sta db_n
        stx t_col
        sty db_w
        lda #0
        sta tlen
@l:     lda db_n
        cmp #8
        bcc @part
        sbc #8
        sta db_n
        lda #8
        bne @put
@part:  ldx #0
        stx db_n
@put:   clc
        adc #CH_BAR0
        ldx tlen
        sta tbuf, x
        inc tlen
        dec db_w
        bne @l
        jmp print_buf

.segment "BSS"
db_n:       .res 1
db_w:       .res 1
.segment "CODE"

; ---------------------------------------------------------------- the title screen

; The title screen with a new demo floor.
start_title:
        lda #M_TITLE
        sta mode
        lda #0
        sta show_arrows
        sta spr_en
        jsr music_start
        jsr clear_input
        ; the demo: a floor of song 2..8 with its guests, never ticked
        jsr random
        lda frame
        eor r_ticks
        sta rng
        lda #7
        jsr rand_mod
        clc
        adc #2
        pha
        jsr game_new
        pla
        jsr game_start_at
        jsr render_reset
        ; all rows black, the field drawn, then the bands of the title
        lda #0
        ldx #24
        ldy #RM_BLANK
        jsr set_rows
        jsr update_vis
        jsr wait_frame
        jsr field_setup
        jsr redraw_field
        jsr title_texts
        jmp title_rows

; The bands of the title screen: logo, the floor, the list, the start prompt.
title_rows:
        lda #0
        ldx #0
        ldy #RM_TEXT
        jsr set_rows
        lda #1
        ldx #3
        ldy #RM_LOGO
        jsr set_rows
        lda #4
        ldx #4
        ldy #RM_TEXT
        jsr set_rows
        lda #5
        ldx #8
        ldy #RM_BITMAP
        jsr set_rows
        lda #9
        ldx #24
        ldy #RM_TEXT
        jsr set_rows
        jmp update_vis

; The texts of the title screen (again after a change of the language).
title_texts:
        jsr big_reset
        lda #0
        ldx #4
        jsr clear_rows
        lda #9
        ldx #24
        jsr clear_rows
        jsr draw_logo
        lda #T_TITLE_TAGLINE
        ldx #4
        ldy #CYAN
        jsr say
        lda #9
        sta pf_top
        lda #20
        sta pf_bottom
        lda #CYAN
        jsr panel
        lda #T_TITLE_SCORES
        ldx #10
        ldy #YELLOW
        jsr say_big
        lda hs_count
        bne @list
        lda #T_TITLE_NOSCORES
        ldx #15
        ldy #C_LABEL
        jsr say
        jmp @last
@list:  lda #0
        sta tt_i
@e:     jsr score_row
        inc tt_i
        lda tt_i
        cmp hs_count
        beq @last
        cmp #5
        bne @e
@last:  ; the result of the last game
        lda last_valid
        beq @nl
        lda last_score
        sta t_score
        lda last_score + 1
        sta t_score + 1
        lda last_score + 2
        sta t_score + 2
        lda #T_TITLE_YOURSCORE
        ldy #C_TEXT
        ldx last_rank
        cpx #1
        bne @y
        lda #T_TITLE_RECORD
        ldy #YELLOW
@y:     ldx #19
        jsr say
@nl:    lda #T_TITLE_LANG
        ldx #24
        ldy #C_LABEL
        jsr say
        lda #$ff
        sta blink_shown
        rts

.segment "BSS"
tt_i:       .res 1
.segment "CODE"

; Row tt_i of the high score list (rows 13..17): rank, name, score, song.
score_row:
        lda tt_i
        clc
        adc #13
        sta t_row
        ldx #C_TEXT
        lda last_rank
        beq @c
        sec
        sbc #1
        cmp tt_i
        bne @c
        ldx #YELLOW
@c:     stx t_color
        lda tt_i
        clc
        adc #1
        sta tbuf + 1
        lda #0
        sta tlen
        lda tbuf + 1
        jsr append_byte
        ldx tlen
        lda #C_DOT
        sta tbuf, x
        inc tlen
        lda #5
        sta t_col
        jsr right_buf
        ; the name (or ???)
        lda tt_i
        jsr name_ptr
        ldy #0
        ldx #0
        stx tlen
@n:     lda (ptr2), y
        sta tbuf, y
        beq @sp
        sty tlen
        inc tlen
@sp:    iny
        cpy #NAME_LEN
        bne @n
        lda tlen
        bne @named
        lda #T_ENTRY_ANONYMOUS
        jsr expand
@named: lda #6
        sta t_col
        jsr print_buf
        ; the score
        lda tt_i
        asl
        adc tt_i
        tax
        lda hs_score, x
        sta t_score
        lda hs_score + 1, x
        sta t_score + 1
        lda hs_score + 2, x
        sta t_score + 2
        lda #0
        sta tlen
        jsr append_score
        lda #28
        sta t_col
        jsr right_buf
        ; the song
        ldx tt_i
        lda hs_song, x
        sta t_song
        lda #0
        sta t_song + 1
        lda #38
        sta t_col
        lda t_color
        pha
        lda #C_LABEL
        ldx last_rank
        beq @sc
        dex
        cpx tt_i
        bne @sc
        lda #YELLOW
@sc:    sta t_color
        lda #T_TITLE_SONG
        jsr print_right
        pla
        sta t_color
        rts

; ptr2 = the name of entry A.
name_ptr:
        ldx #0
        stx ptr2 + 1
        sta ptr2
        asl
        asl
        adc ptr2                ; * 5
        asl                     ; * 10
        clc
        adc #<hs_name
        sta ptr2
        lda #>hs_name
        adc #0
        sta ptr2 + 1
        rts

; The logo in rows 1..3 (multicolor characters of the charset).
draw_logo:
        lda #<(SCREEN + 40 + 6)
        sta scr
        sta col
        lda #>(SCREEN + 40 + 6)
        sta scr + 1
        lda #>(COLRAM + 40 + 6)
        sta col + 1
        ldx #0
@r:     ldy #0
@c:     lda logo_map, x
        sta (scr), y
        lda #8 + C_PINK         ; multicolor: 11 is unused, 01 and 10 are the band colours
        sta (col), y
        inx
        iny
        cpy #27
        bne @c
        lda scr
        clc
        adc #40
        sta scr
        sta col
        bcc @n
        inc scr + 1
        inc col + 1
@n:     cpx #81
        bne @r
        rts

; The parts of the title screen that change: the start prompt blinks, the last entry too.
title_update:
        lda r_t20
        and #1
        cmp blink_shown
        beq @r
        sta blink_shown
        ldx #21
        cmp #0
        beq @off
        lda #T_TITLE_START
        ldy #YELLOW
        jsr say_big
        jmp @mark
@off:   jsr clear_inner
        ldx #22
        jsr clear_inner
@mark:  ; the entry of the last game blinks white
        lda last_rank
        beq @r
        cmp #6
        bcs @r
        clc
        adc #12
        sta t_row
        lda #2
        sta t_col
        lda #27
        sta tlen
        lda #YELLOW
        ldx blink_shown
        beq @c
        lda #WHITE
@c:     jmp color_span
@r:     rts

; Input on the title screen: fire starts, left / right switch the language.
title_input:
        lda hi_in
        cmp #IN_FIRE
        bne @nf
        jmp start_game
@nf:    cmp #DIR_LEFT
        beq @lang
        cmp #DIR_RIGHT
        beq @lang
        cmp #IN_KEY
        bne @r
        lda hi_key
        cmp #KEY_RETURN
        beq @start
        cmp #' '
        beq @start
        cmp #KEY_F1
        bne @r
@lang:  lda lang
        eor #1
        sta lang
        jmp title_texts
@start: jmp start_game
@r:     rts

; The conga line of 7 dancers over the title (hardware sprites 0..6).
title_conga:
        lda #$7f
        sta spr_en
        sta spr_mc
        lda #0
        sta spr_xe
        sta spr_ye
        sta spr_pri
        lda #BLACK
        sta spr_mc1
        lda #LRED
        sta spr_mc2
        ldx #0
@s:     ; x = 160 - 16 (i - 3) + sin((t - 8 i) * 0.05) * 3 - 8
        txa
        asl
        asl
        asl
        sta tc_t
        lda r_ticks
        sec
        sbc tc_t
        and #127
        tay
        lda conga_sin, y
        sta tc_t
        txa
        asl
        asl
        asl
        asl
        sta tc_x
        lda #24 + 160 + 48 - 8 - 4
        sec
        sbc tc_x
        clc
        adc tc_t
        sta spr_x, x
        lda #0
        sta spr_xhi, x
        ; y bobs: (t / 8 + i) % 2
        txa
        clc
        adc r_t8
        and #1
        sta tc_l
        clc
        adc #50 + 42
        sta spr_y, x
        ; arms up on (t / 15 + i) % 2 (not the leader)
        txa
        clc
        adc r_t15
        and #1
        asl
        cpx #0
        bne @a
        lda #0
@a:     ora tc_l
        cpx #0
        bne @d
        ora #4                  ; the leader's frames
@d:     clc
        adc #SPRSTAT_PTR + SPR_DANCER0
        sta spr_ptr, x
        lda conga_color, x
        sta spr_col, x
        inx
        cpx #7
        bne @s
        rts

.segment "BSS"
tc_t:       .res 1
tc_x:       .res 1
tc_l:       .res 1
.segment "RODATA"
conga_color: .byte WHITE, CYAN, YELLOW, LGREEN, LBLUE, ORANGE, PURPLE
.segment "CODE"

; ---------------------------------------------------------------- the high score list

; Carry set if the last score (last_score) makes it into the list.
qualifies:
        lda last_score
        ora last_score + 1
        ora last_score + 2
        beq @no
        lda hs_count
        cmp #MAX_SCORES
        bcc @yes
        ; better than the last entry
        ldx #(MAX_SCORES - 1) * 3
        jsr cmp_last
        beq @no
        bcs @yes
@no:    clc
        rts
@yes:   sec
        rts

; Compares last_score with hs_score + X: carry set if >=, Z set if equal.
cmp_last:
        lda last_score + 2
        cmp hs_score + 2, x
        bne @r
        lda last_score + 1
        cmp hs_score + 1, x
        bne @r
        lda last_score
        cmp hs_score, x
@r:     rts

; The rank of last_score (after the equal scores) into A (1..).
rank_for:
        ldy #0
        ldx #0
@l:     cpy hs_count
        beq @done
        jsr cmp_last
        beq @ge                 ; equal: the new one comes after
        bcs @done               ; greater: here
@ge:    inx
        inx
        inx
        iny
        bne @l
@done:  iny
        tya
        rts

; Inserts last_score with entry_name and entry_song at rank entry_rank.
insert_score:
        ; move the entries from rank - 1 down by one (the last one drops out)
        ldx #MAX_SCORES - 1
@m:     txa
        clc
        adc #1
        cmp entry_rank
        beq @put
        bcc @put
        ; entry x = entry x - 1
        stx is_i
        dex
        txa
        jsr name_ptr
        lda ptr2
        sta src
        lda ptr2 + 1
        sta src + 1
        lda is_i
        jsr name_ptr
        ldy #NAME_LEN - 1
@n:     lda (src), y
        sta (ptr2), y
        dey
        bpl @n
        ldx is_i
        lda hs_song - 1, x
        sta hs_song, x
        txa
        asl
        adc is_i
        tay
        lda hs_score - 3, y
        sta hs_score, y
        lda hs_score - 2, y
        sta hs_score + 1, y
        lda hs_score - 1, y
        sta hs_score + 2, y
        ldx is_i
        dex
        bpl @m
@put:   ldx entry_rank
        dex
        stx is_i
        txa
        jsr name_ptr
        ldy #NAME_LEN - 1
@nn:    lda entry_name, y
        sta (ptr2), y
        sta last_name, y
        dey
        bpl @nn
        ldx is_i
        lda entry_song
        sta hs_song, x
        txa
        asl
        adc is_i
        tay
        lda last_score
        sta hs_score, y
        lda last_score + 1
        sta hs_score + 1, y
        lda last_score + 2
        sta hs_score + 2, y
        lda hs_count
        cmp #MAX_SCORES
        bcs @r
        inc hs_count
@r:     rts

.segment "BSS"
is_i:       .res 1
.segment "CODE"

; ---------------------------------------------------------------- the name entry

start_entry:
        jsr rank_for
        sta entry_rank
        lda #M_ENTRY
        sta mode
        ; the last name entered is suggested
        ldx #NAME_LEN - 1
@n:     lda last_name, x
        sta entry_name, x
        dex
        bpl @n
        ; the cursor after the name
        ldx #NAME_LEN - 1
@e:     lda entry_name, x
        bne @f
        dex
        bpl @e
@f:     inx
        cpx #NAME_LEN
        bcc @p
        ldx #NAME_LEN - 1
@p:     stx entry_pos
        lda #0
        sta entry_rep
        sta show_arrows
        jsr clear_input
        jsr music_start
        ; the demo floor behind it, as on the title screen
        lda #0
        ldx #24
        ldy #RM_BLANK
        jsr set_rows
        jsr update_vis
        jsr wait_frame
        lda #7
        jsr rand_mod
        clc
        adc #2
        jsr game_start_at
        jsr render_reset
        jsr field_setup
        jsr redraw_field
        jsr entry_texts
        jmp title_rows

entry_texts:
        jsr big_reset
        lda #0
        ldx #4
        jsr clear_rows
        lda #9
        ldx #24
        jsr clear_rows
        jsr draw_logo
        lda #T_TITLE_TAGLINE
        ldx #4
        ldy #CYAN
        jsr say
        lda #9
        sta pf_top
        lda #20
        sta pf_bottom
        lda #YELLOW
        jsr panel
        lda #T_ENTRY_TITLE
        ldx #10
        ldy #YELLOW
        jsr say_big
        lda entry_rank
        sta t_rank
        lda #0
        sta t_rank + 1
        lda last_score
        sta t_score
        lda last_score + 1
        sta t_score + 1
        lda last_score + 2
        sta t_score + 2
        lda #T_ENTRY_RANK
        ldx #13
        ldy #C_TEXT
        jsr say
        lda #T_ENTRY_PROMPT
        ldx #15
        ldy #CYAN
        jsr say
        lda #T_ENTRY_HINT1
        ldx #22
        ldy #C_LABEL
        jsr say
        lda #T_ENTRY_HINT2
        ldx #23
        ldy #C_LABEL
        jsr say
        jmp entry_name_row

; The name with the cursor in row 17, columns 15..24.
entry_name_row:
        lda #<(SCREEN + 17 * 40 + 15)
        sta scr
        sta col
        lda #>(SCREEN + 17 * 40 + 15)
        sta scr + 1
        lda #>(COLRAM + 17 * 40 + 15)
        sta col + 1
        ldy #0
@l:     lda entry_name, y
        cpy entry_pos
        bne @nc
        ; the cursor: an underline when the position is empty, blinking
        cmp #C_SPACE
        bne @nc
        lda r_t15
        and #1
        beq @nc
        lda #CH_CURSOR
@nc:    sta (scr), y
        lda #WHITE
        cpy entry_pos
        bne @c
        lda r_t15
        and #1
        beq @y
        lda #WHITE
        bne @c
@y:     lda #YELLOW
@c:     sta (col), y
        iny
        cpy #NAME_LEN
        bne @l
        ; a frame line below
        ldy #NAME_LEN - 1
        lda #CH_HZ
@u:     sta SCREEN + 18 * 40 + 15, y
        dey
        bpl @u
        ldy #NAME_LEN - 1
        lda #CYAN
@uc:    sta COLRAM + 18 * 40 + 15, y
        dey
        bpl @uc
        rts

entry_update:
        ; up / down held: the letter repeats
        lda joy_now
        and #3
        beq @nr
        inc entry_rep
        lda entry_rep
        cmp #20
        bcc @blink
        lda #16
        sta entry_rep
        lda joy_now
        lsr
        bcc @dn
        jsr letter_next
        jmp @blink
@dn:    jsr letter_prev
        jmp @blink
@nr:    lda #0
        sta entry_rep
@blink: ; the title blinks white and yellow
        lda r_t20
        and #1
        cmp blink_shown
        beq @name
        sta blink_shown
        lda #10
        sta t_row
        lda #1
        sta t_col
        lda #38
        sta tlen
        lda #YELLOW
        ldx blink_shown
        beq @c
        lda #WHITE
@c:     jsr color_span
        lda #11
        sta t_row
        lda #YELLOW
        ldx blink_shown
        beq @c2
        lda #WHITE
@c2:    jsr color_span
@name:  jmp entry_name_row

letter_next:
        jsr letter_index
        inx
        cpx #NAME_CHARS
        bcc letter_set
        ldx #0
        beq letter_set
letter_prev:
        jsr letter_index
        dex
        bpl letter_set
        ldx #NAME_CHARS - 1
letter_set:
        lda name_chars, x
        ldx entry_pos
        sta entry_name, x
        rts

; X = the index of the letter at the cursor in name_chars.
letter_index:
        ldy entry_pos
        lda entry_name, y
        ldx #NAME_CHARS - 1
@l:     cmp name_chars, x
        beq @r
        dex
        bpl @l
        ldx #0
@r:     rts

entry_input:
        lda hi_in
        cmp #IN_FIRE
        bne @n1
        jmp save_entry
@n1:    cmp #DIR_UP
        bne @n2
        lda #0
        sta entry_rep
        jmp letter_next
@n2:    cmp #DIR_DOWN
        bne @n3
        lda #0
        sta entry_rep
        jmp letter_prev
@n3:    cmp #DIR_LEFT
        bne @n4
        ldx entry_pos
        beq @r
        dec entry_pos
@r:     rts
@n4:    cmp #DIR_RIGHT
        bne @n5
        ldx entry_pos
        cpx #NAME_LEN - 1
        bcs @r
        inc entry_pos
        rts
@n5:    ; the keyboard
        lda hi_key
        cmp #KEY_RETURN
        bne @k1
        jmp save_entry
@k1:    cmp #KEY_DEL
        bne @k2
        ldx entry_pos
        lda entry_name, x
        bne @del
        dex
        bmi @r
        stx entry_pos
@del:   lda #C_SPACE
        sta entry_name, x
        rts
@k2:    cmp #KEY_LEFT
        beq @n3
        cmp #KEY_RIGHT
        beq @n4
        ; a letter, digit or sign
        jsr ascii_code
        bcc @r
        ldx entry_pos
        sta entry_name, x
        cpx #NAME_LEN - 1
        bcs @r
        inc entry_pos
        rts

; The character code of the key A (ASCII): carry set if it can be in a name.
ascii_code:
        cmp #'A'
        bcc @d
        cmp #'Z' + 1
        bcs @no
        sbc #'A' - 2            ; carry clear: - ('A' - 1)
        sec
        rts
@d:     cmp #'0'
        bcc @s
        cmp #'9' + 1
        bcs @no
        sbc #'0' - 1
        clc
        adc #C_ZERO
        sec
        rts
@s:     ldx #C_SPACE
        cmp #' '
        beq @ok
        ldx #C_DOT
        cmp #'.'
        beq @ok
        ldx #C_MINUS
        cmp #'-'
        beq @ok
        ldx #C_PLUS
        cmp #'+'
        beq @ok
@no:    clc
        rts
@ok:    txa
        sec
        rts

; The name is entered: the score goes into the list, the list onto the disk.
save_entry:
.if .defined(TEST) .and (.not .defined(TEST_SCRIPT))
        ; a name, typed by the test
        ldx #NAME_LEN - 1
@tn:    lda test_name, x
        sta entry_name, x
        dex
        bpl @tn
.endif
        jsr insert_score
        lda entry_rank
        sta last_rank
        lda #1
        sta last_valid
        jsr save_scores
.ifdef TEST
        ; the round trip: the list again from the disk (a wrong list shows on the title)
        jsr scores_clear
        lda #$ff
        sta lang
        jsr kernal_on
        jsr load_scores
        jsr kernal_off
.endif
        jmp start_title

.ifdef TEST
.segment "RODATA"
test_name: .byte 20, 5, 19, 20, 0, 27, 28, 29, 0, 0   ; "TEST ÄÖÜ"
.segment "CODE"
.endif
