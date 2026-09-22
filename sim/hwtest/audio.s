; Apple /// audio test: a boot block, no SOS.
;
; Plays the three sound sources in turn, forever, and shows which one is
; playing as an inverse bar on the screen:
;   1  the speaker toggle at $C030, three notes (C5, E5, G5)
;   2  the hardware bell at $C040, three 1 kHz beeps of 0.1 s
;   3  the six-bit DAC on the E VIA's port B, the same three notes as a
;      full-scale square wave, so louder than the speaker
;   4  the DAC again, a triangle wave of about 260 Hz
;   5  the DAC one bit at a time: bit 0 up to bit 5, six bursts at the same
;      pitch, each twice as loud as the last
; The CPU runs at 1 MHz so the note periods are counted in even cycles;
; durations are counted in vertical blanking flags on the E VIA's CB2.
; The program is two blocks long: the ROM loads block 0, which reads block 1
; through the ROM's BLOCKIO before it changes anything.

        .setcpu "6502"

BLOCKIO = $F479         ; boot ROM: read block A/X to (IBBUFP)
IBBUFP  = $85           ; the boot ROM's zero page
IBCMD   = $87
ENV     = $FFDF         ; D VIA port A: environment register
DAC     = $FFE0         ; E VIA port B: bits 5-0 are the DAC
E_DDRB  = $FFE2
E_PCR   = $FFEC         ; E VIA peripheral control
E_IFR   = $FFED         ; E VIA interrupt flags, bit 3 = CB2 (vertical blanking)
SPKR    = $C030
BELL    = $C040

PTR     = $D0
MODE    = $D2           ; 0 = speaker, 1 = DAC
VAL     = $D3           ; last DAC value
MASK    = $D4           ; bits the square wave toggles
PERIOD  = $D5           ; half-period delay count
FRAMES  = $D6           ; frames left to play
NOTE    = $D7
TEST    = $D8

NOTE_LEN = 20           ; frames per note (0.33 s)
BELL_GAP = 18           ; frames from one bell to the next
TRI_LEN  = 45
BIT_LEN  = 12
BIT_GAP  = 6
GAP      = 30           ; frames of silence between tests

ROW1    = $0480
ROW3    = $0580
ROW5    = $0680
ROW7    = $0780
ROW9    = $04A8
ROW11   = $05A8
ROW14   = $0728
ROW16   = $0450
PASSCHR = ROW16 + 5

        .segment "CODE"

start:  lda #1
        sta IBCMD
        lda #0
        sta IBBUFP
        lda #$A2
        sta IBBUFP+1
        lda #1
        ldx #0
        jsr BLOCKIO

        sei
        cld
        ldx #$FF
        txs
        lda #$F7                ; the ROM's $77 plus bit 7: 1 MHz
        sta ENV
        lda $C050               ; 40-column text, page 1
        lda $C052
        lda $C054
        lda $C056
        lda #$7F                ; no VIA interrupts
        sta $FFDE
        sta $FFEE
        lda E_PCR
        and #$1F
        ora #$60                ; CB2: independent input, positive edge (start of VBL)
        sta E_PCR
        lda #$3F                ; PB5..0 out to the DAC; PB6, PB7 stay inputs
        sta E_DDRB
        lda #$20                ; mid-scale: silence
        sta DAC

        lda #$A0
        ldx #0
clear:  sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne clear

        ldx #0
label:  lda labels,x
        sta PTR
        lda labels+1,x
        beq main
        sta PTR+1
        inx
        inx
        ldy #0
:       lda labels,x
        beq :+
        ora #$80
        sta (PTR),y
        inx
        iny
        bne :-
:       inx
        bne label

main:   ldx #0
next:   lda rows,x
        sta PTR
        lda rows+1,x
        sta PTR+1
        jsr flip
        lda tests,x
        sta call+1
        lda tests+1,x
        sta call+2
        stx TEST
call:   jsr $0000
        lda #$20
        sta DAC
        jsr flip
        lda #GAP
        jsr wait
        ldx TEST
        inx
        inx
        cpx #10
        bne next
        inc PASSCHR
        jmp main

; Invert the 40 characters of the row at (PTR).
flip:   ldy #39
:       lda (PTR),y
        eor #$80
        sta (PTR),y
        dey
        bpl :-
        rts

; Wait A frames.
wait:   sta FRAMES
:       lda E_IFR
        and #$08
        beq :-
        sta E_IFR
        dec FRAMES
        bne :-
        rts

; Square wave for FRAMES frames: the speaker (MODE 0) or MASK's bits of the
; DAC.  A half period is 21 + 5 * PERIOD cycles on the speaker, 11 more on
; the DAC.
square: lda MODE
        beq :+
        lda VAL
        eor MASK
        sta VAL
        sta DAC
        bpl :++                 ; VAL is at most $3F
:       bit SPKR
:       ldy PERIOD
:       dey
        bne :-
        lda E_IFR
        and #$08
        beq square
        sta E_IFR
        dec FRAMES
        bne square
        rts

; 1: the speaker.
t_spk:  lda #0
        sta MODE
        beq three
; 3: the DAC, full scale.
t_dac:  lda #1
        sta MODE
        lda #$3F
        sta MASK
        lda #0
        sta VAL
three:  lda #0
        sta NOTE
:       ldx NOTE
        lda periods,x
        sta PERIOD
        lda #NOTE_LEN
        sta FRAMES
        jsr square
        inc NOTE
        lda NOTE
        cmp #3
        bne :-
        rts

; 2: the bell, three times.
t_bell: lda #3
        sta NOTE
:       bit BELL
        lda #BELL_GAP
        jsr wait
        dec NOTE
        bne :-
        rts

; 4: a triangle wave on the DAC: 63 steps up of 32 cycles, 63 down of 30,
; 3906 cycles a period (261 Hz).
t_tri:  lda #TRI_LEN
        sta FRAMES
tri:    ldx #0
:       stx DAC
        jsr step
        inx
        cpx #63
        bne :-
:       stx DAC
        jsr step
        dex
        bne :-
        lda FRAMES
        bne tri
        rts
step:   lda E_IFR
        and #$08
        beq :+
        sta E_IFR
        dec FRAMES
:       rts

; 5: each DAC bit alone, around mid-scale.
t_bits: lda #1
        sta MODE
        sta MASK
:       lda #$20
        sta VAL
        lda periods
        sta PERIOD
        lda #BIT_LEN
        sta FRAMES
        jsr square
        lda #$20
        sta DAC
        lda #BIT_GAP
        jsr wait
        asl MASK
        lda MASK
        cmp #$40
        bne :-
        rts

; Half-period delay counts: C5 (523 Hz), E5 (659 Hz), G5 (784 Hz).
periods: .byte 191, 151, 126

rows:   .word ROW3, ROW5, ROW7, ROW9, ROW11
tests:  .word t_spk, t_bell, t_dac, t_tri, t_bits

; Screen address, text, 0; a zero high byte ends the list.
labels: .word ROW1 + 10
        .byte "APPLE /// AUDIO TEST", 0
        .word ROW3
        .byte "1 SPEAKER $C030  3 NOTES", 0
        .word ROW5
        .byte "2 BELL $C040  3 BEEPS", 0
        .word ROW7
        .byte "3 DAC SQUARE  FULL SCALE", 0
        .word ROW9
        .byte "4 DAC TRIANGLE  260 HZ", 0
        .word ROW11
        .byte "5 DAC BITS 0-5  6 STEPS", 0
        .word ROW14
        .byte "INVERSE = PLAYING", 0
        .word ROW16
        .byte "PASS", 0
        .word 0
