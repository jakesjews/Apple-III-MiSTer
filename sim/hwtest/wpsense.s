; Apple /// write-protect sense test: a boot block, no SOS.
;
; Reads the Disk /// write-protect sense (Q6H, then Q7L) of the internal drive
; in six drive states and shows each byte in hex: bit 7 set means protected.
; With a writable disk in drive 1 the expected readings are
;   A  motor on, selected, 1.3 s      00
;   B  0.3 s after motor off          00   the drive is still enabled
;   C  1.6 s after motor off          FF   enable has timed out
;   D  motor on, drive deselected     FF   no drive drives the sense line
;   E  reselected, read at once       00
;   F  0.3 s later                    00
;   G  right after a ROM block read   00   as the Confidence Program senses it
;   H  0.3 s after that               00
; and with a write-protected disk A, B, E, F, G and H read FF as well.

        .setcpu "6502"

ENV     = $FFDF
PTR     = $D0

        .segment "CODE"

start:  sei
        cld
        ldx #$FF
        txs
        lda #$F7                ; 1 MHz, screen, I/O, ROM: the disk routines' speed
        sta ENV
        lda $C050               ; 40-column text, page 1
        lda $C052
        lda $C054
        lda $C056
        lda #$7F
        sta $FFDE
        sta $FFEE
        lda #$A0
        ldx #0
clear:  sta $0400,x
        sta $0500,x
        sta $0600,x
        sta $0700,x
        inx
        bne clear
        ldx #0
title:  lda text,x
        beq loop
        ora #$80
        sta $0480,x
        inx
        bne title

loop:   lda $C0D4               ; A: internal drive selected, motor on
        lda $C0EA
        lda $C0E9
        ldy #4
        jsr delay
        jsr sense
        ldx #0
        jsr show
        lda $C0E8               ; B: shortly after motor off
        ldy #1
        jsr delay
        jsr sense
        ldx #3
        jsr show
        ldy #4                  ; C: after the motor-off timeout
        jsr delay
        jsr sense
        ldx #6
        jsr show
        lda $C0E9               ; D: motor on, internal drive deselected
        ldy #4
        jsr delay
        lda $C0D5
        jsr sense
        ldx #9
        jsr show
        lda $C0D4               ; E: reselected, read at once
        jsr sense
        ldx #12
        jsr show
        ldy #1                  ; F: a little later
        jsr delay
        jsr sense
        ldx #15
        jsr show
        lda #1                  ; G: the ROM reads block 0, which ends with motor off
        sta $87
        lda #0
        sta $85
        lda #$B0
        sta $86
        lda #0
        tax
        jsr $F479               ; BLOCKIO
        jsr sense
        ldx #18
        jsr show
        ldy #1                  ; H: a little later
        jsr delay
        jsr sense
        ldx #21
        jsr show
        lda $C0E8
        inc $0600 + 39          ; pass indicator
        ldy #6
        jsr delay
        jmp loop

; A = the sense byte; the controller is left in read mode.
sense:  lda $C0ED
        lda $C0EE
        pha
        lda $C0EC
        pla
        rts

; A as two hex digits at column X of the results line.
show:   pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr digit
        pla
        and #$0F
digit:  cmp #10
        bcc :+
        adc #6
:       adc #$B0
        sta $0580,x
        inx
        rts

; About Y * 0.33 s at 1 MHz.
delay:  ldx #0
        lda #0
:       dex
        bne :-
        sec
        sbc #1
        bne :-
        dey
        bne delay
        rts

text:   .byte "WP SENSE A B C D E F G H (HEX BELOW)", 0
