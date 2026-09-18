; Apple /// joystick test: a boot block, no SOS.
;
; Reads both joystick ports continuously with SOS 1.3's GET_ANALOG timing (a
; 500-tick charge, then the boot ROM's ANALOG routine timing the ramp with the
; D VIA's timer 2 from a 360-tick offset, 8 ticks per step) and shows the
; readings in hex with the buttons and switches.  Ground and the 2.26 V
; reference are read the same way: ground is below the window and reads 00,
; the reference is above it and reads FF.

        .setcpu "6502"

ENV     = $FFDF         ; D VIA port A: environment register
D_T2L   = $FFD8         ; D VIA timer 2
D_T2H   = $FFD9
D_ACR   = $FFDB
D_IFR   = $FFDD
ANALOG  = $F4A8         ; boot ROM: start timer 2, wait for the ramp

PTR     = $D0
TEMP    = $D2
SLOT    = $D3

        .segment "CODE"

start:  sei
        cld
        ldx #$FF
        txs
        lda #$77                ; the ROM's environment: 2 MHz, screen, I/O, ROM
        sta ENV
        lda $C050               ; 40-column text, page 1
        lda $C052
        lda $C054
        lda $C056
        lda #$7F                ; no VIA interrupts; an ACIA programmed reset
        sta $FFDE               ; disables its interrupts.  ANALOG stops early
        sta $FFEE               ; when the IRQ line is low.
        sta $C0F1
        lda D_ACR               ; timer 2 one-shot, as SOS sets it up
        and #$DF
        sta D_ACR
        bit $C0DC               ; ENSEL off, ENSIO input: port A is a joystick port
        bit $C0DE

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
        beq loop
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

loop:   ldx #0
reading:
        lda slots+1,x
        sta PTR
        lda slots+2,x
        sta PTR+1
        stx SLOT
        lda slots,x
        jsr ad_read
        jsr hex
        ldx SLOT
        inx
        inx
        inx
        cpx #18
        bne reading
        lda $C062               ; port B button (SW2) and switch (SW0)
        jsr closed
        sta $0789
        lda $C060
        jsr closed
        sta $0431
        lda $C061               ; port A button (SW1) and switch (SW3)
        jsr closed
        sta $0792
        lda $C063
        jsr closed
        sta $043A
        jmp loop

; Bit 7 as "0" or "1".
closed: asl a
        lda #$B0
        adc #0
        rts

; A as two hex digits at (PTR).
hex:    ldy #0
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr nibble
        pla
        and #$0F
nibble: cmp #10
        bcc :+
        adc #6
:       adc #$B0
        sta (PTR),y
        iny
        rts

; SOS 1.3 AD.READ, interrupts off: A = channel 0-7, returns 0-255.
ad_read:
        lsr a
        bit $C058
        bcc :+
        bit $C059
:       lsr a
        bit $C05E
        bcc :+
        bit $C05F
:       lsr a
        bit $C05A
        bcc :+
        bit $C05B
:       bit $C05C               ; charge the capacitor for 500 ticks
        lda #<500
        sta D_T2L
        lda #>500
        sta D_T2H
        lda #$20
:       bit D_IFR
        beq :-
        sec
        lda #<360               ; skip 360 ticks
        sta D_T2L
        lda #>360
        bit $C05D
        jsr ANALOG
        eor #$FF
        bmi below
        sta TEMP
        tya
        eor #$FF
        lsr TEMP
        ror a
        lsr TEMP
        ror a
        lsr TEMP
        bne above
        ror a
        adc #0
        rts
below:  lda #0
        rts
above:  lda #$FF
        rts

; Channel and screen position of each reading.
slots:  .byte 1, <$0689, >$0689 ; port B X
        .byte 2, <$0709, >$0709 ; port B Y
        .byte 3, <$0692, >$0692 ; port A X
        .byte 4, <$0712, >$0712 ; port A Y
        .byte 0, <$052F, >$052F ; ground
        .byte 7, <$053E, >$053E ; reference

; Screen address, text, 0; a zero high byte ends the list.
labels: .word $0480 + 8
        .byte "APPLE /// JOYSTICK TEST", 0
        .word $0580 + 9
        .byte "PORT B   PORT A", 0
        .word $0680
        .byte "X", 0
        .word $0700
        .byte "Y", 0
        .word $0780
        .byte "BUTTON", 0
        .word $0428
        .byte "SWITCH", 0
        .word $0528
        .byte "GROUND", 0
        .word $0528 + 12
        .byte "REFERENCE", 0
        .word $0628
        .byte "SOS JOYSTICK TIMING, HEX; 1 = CLOSED", 0
        .word 0
