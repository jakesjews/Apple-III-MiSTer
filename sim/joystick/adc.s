; Apple /// joystick timing test, assembled into a 4 KiB boot ROM.
;
; Reads the A/D converter and the switches the way shipped software does and
; stores the results for sim/joystick/main.cpp, which sets the joystick for
; each batch and checks the results:
;
;   SOS 1.3 GET_ANALOG ($64): D VIA timer 2, a 500-tick charge, a 360-tick
;   offset and 8 ticks per step, measured by the boot ROM's ANALOG routine.
;   Emulation-mode PREAD: a 1 MHz polling loop, 800 us charge, 370 us offset,
;   16 us per two steps (Service Reference Manual listing, section 10).
;   Atomic Defense: its own 1 MHz loop, 17 cycles per step, with the IRQ check
;   copied from ANALOG.
;   Boot ROM self-test: ground, a short charge, a 2 MHz count that must stay
;   below 32.
;
; Routine bodies and their addresses follow the originals so that their cycle
; counts, including branches across pages, are the same.

.setcpu "6502"

ENV     = $FFDF         ; D VIA port A: environment register
ZPREG   = $FFD0         ; D VIA port B: zero page register
D_DDRB  = $FFD2
D_DDRA  = $FFD3
D_T2L   = $FFD8         ; D VIA timer 2
D_T2H   = $FFD9
D_ACR   = $FFDB
D_PCR   = $FFDC
D_IFR   = $FFDD
D_IER   = $FFDE
E_ORB   = $FFE0
E_DDRB  = $FFE2
E_DDRA  = $FFE3
E_IER   = $FFEE
BANK    = $FFEF         ; E VIA port A: bank register, IRQ line in bit 7

AD_SEL0 = $C058
AD_SEL2 = $C05A
AD_CHRG = $C05C
AD_STRT = $C05D
AD_SEL1 = $C05E
AD_FLAG = $C066

; Environments: I/O, reset key, ROM (both ROM bits, as the stock ROM sets them).
FAST_OFF = $53          ; 2 MHz, screen off
FAST_ON  = $73          ; 2 MHz, screen on
SLOW_OFF = $D3          ; 1 MHz, screen off

TEMP    = $D1           ; AD.TEMP in SOS
SWITCH  = $D2
SAVEX   = $D3
RAW     = $D4           ; timer 2 as ANALOG read it

; Results, read by the harness through the RAM probe.
SEQ     = $0300         ; incremented after each batch
R_SOS   = $0301         ; GET_ANALOG, 2 MHz screen off: channels 1-4
R_SOSON = $0305         ; GET_ANALOG port B X, 2 MHz screen on
R_SOS1M = $0306         ; GET_ANALOG port B X, 1 MHz
R_PREAD = $0307         ; PREAD port B X and Y
R_ATOM  = $0309         ; Atomic Defense port B X
R_SW    = $030A         ; $C060-$C063 bit 7 in bits 0-3
R_IFR   = $030B         ; D VIA flags: CA2 (port A button) and CB1 (port A switch)
R_RAW   = $0320         ; timer 2 after each GET_ANALOG above, 6 words
R_SELF  = $0310         ; boot ROM self-test count
R_FIXED = $0311         ; GET_ANALOG ground, reference, battery, unconnected

.segment "CODE"

reset:  sei
        cld
        lda #FAST_OFF           ; the stock ROM's first environment
        sta ENV
        ldx #$00
        stx E_ORB
        stx BANK
        stx ZPREG
        dex
        stx D_DDRB
        stx D_DDRA
        txs
        lda #$0F
        sta E_DDRA
        lda #$3F
        sta E_DDRB
        lda #$7F
        sta D_IER
        sta E_IER
        lda D_ACR               ; SOS AD.SETUP: timer 2 one-shot, ENSEL off,
        and #$DF                ; ENSIO input
        sta D_ACR
        bit $C0DC
        bit $C0DE

        jsr selftest
        sty R_SELF
        ldx #0
fixed:  lda fixed_channels,x
        jsr ad_read
        sta R_FIXED,x
        inx
        cpx #4
        bne fixed
        lda #0
        sta SEQ
        lda #$7F
        sta D_IFR

batch:  ldx #1
chan:   txa
        jsr ad_read
        sta R_SOS-1,x
        jsr keep_raw
        inx
        cpx #5
        bne chan
        lda #FAST_ON
        sta ENV
        lda #1
        jsr ad_read
        sta R_SOSON
        ldx #5
        jsr keep_raw
        lda #SLOW_OFF
        sta ENV
        lda #1
        jsr ad_read
        sta R_SOS1M
        ldx #6
        jsr keep_raw
        ldx #1                  ; PREAD 1 = port B X, 3 = port B Y
        jsr PREAD
        sty R_PREAD
        ldx #3
        jsr PREAD
        sty R_PREAD+1
        lda #FAST_OFF
        sta ENV
        jsr atomic
        stx R_ATOM

        lda #0
        sta SWITCH
        ldx #3
sw:     lda $C060,x
        asl a
        rol SWITCH
        dex
        bpl sw
        lda SWITCH
        sta R_SW
        lda D_IFR
        and #$11
        sta R_IFR
        sta D_IFR
        inc SEQ
        jmp batch

fixed_channels:
        .byte 0, 7, 5, 6

; Store RAW in word X-1 of R_RAW.
keep_raw:
        txa
        asl a
        tay
        lda RAW
        sta R_RAW-2,y
        lda RAW+1
        sta R_RAW-1,y
        rts

; Boot ROM A/D self-test (ATD): ground, about 80 us of charge, then count.
selftest:
        lda AD_SEL2
        lda AD_SEL1
        lda AD_CHRG
        ldy #$20
:       dey
        bne :-
        lda AD_STRT
:       iny
        beq :+
        lda AD_FLAG
        bmi :-
:       rts

; SOS 1.3 AD.READ: A = channel 0-7; returns 0-255 in A.
ad_read:
        stx SAVEX
        lsr a
        bit AD_SEL0
        bcc :+
        bit AD_SEL0+1
:       lsr a
        bit AD_SEL1
        bcc :+
        bit AD_SEL1+1
:       lsr a
        bit AD_SEL2
        bcc :+
        bit AD_SEL2+1
:       php
adr040: cli
        bit AD_CHRG             ; charge the capacitor for 500 ticks
        lda #<500
        sta D_T2L
        lda #>500
        sta D_T2H
        lda #$20
adr050: bit D_IFR
        beq adr050
        sei
        sec
        lda #<360               ; skip 360 ticks
        sta D_T2L
        lda #>360
        bit AD_STRT
        jsr ANALOG
        bcc adr070
adr060: cli
        sei
        bit AD_FLAG
        bpl adr040
        jsr ANLOG1
        bcs adr060
adr070: plp
        sta RAW+1
        sty RAW
        eor #$FF
        bmi adr080
        sta TEMP
        tya
        eor #$FF
        lsr TEMP
        ror a
        lsr TEMP
        ror a
        lsr TEMP
        bne adr090
        ror a
        adc #0
        ldx SAVEX
        rts
adr080: lda #0
        ldx SAVEX
        rts
adr090: lda #$FF
        ldx SAVEX
        rts

; Atomic Defense: port B X at 1 MHz, 800 us charge, 160 us offset, 17 cycles
; per step.  Returns the count in X, $80 past full scale.
        .align 256
atomic: lda #1
        jsr select
atomic_retry:
        sta AD_CHRG
        php
        sei
        nop
        lda ENV
        ora #$80
        sta ENV
        plp
        ldx #$A0
:       dex
        bne :-
        php
        sei
        nop
        lda ENV
        ora #$80
        sta ENV
        lda AD_STRT
        ldx #$20
:       dex
        bne :-
atomic_count:
        inx
        bmi :+
        lda BANK
        and AD_FLAG
        nop
        bmi atomic_count
:       lda ENV
        and #$7F
        sta ENV
        txa
        bmi :+
        lda AD_FLAG
        bpl :+
        plp
        nop
        nop
        jmp atomic_retry
:       plp
        rts

; Select channel A with the A/D select switches.
select: lsr a
        bit AD_SEL0
        bcc :+
        bit AD_SEL0+1
:       lsr a
        bit AD_SEL1
        bcc :+
        bit AD_SEL1+1
:       lsr a
        bit AD_SEL2
        bcc :+
        bit AD_SEL2+1
:       rts

irq:    rti

; Boot ROM ANALOG ($F4A8): time the ramp with timer 2 and watch the IRQ line.
.segment "ANALOG"
ANALOG: sta D_T2H               ; start the timer
ANLOG1: lda BANK
        and AD_FLAG             ; wait for the ramp or an interrupt
        bmi ANLOG1
        lda AD_FLAG
        bmi goodtime            ; an interrupt: carry still set
        clc
        lda D_T2H
        ldy D_T2L
        bpl goodtime
        lda D_T2H               ; the high byte may have moved
goodtime:
        rts

; Emulation-mode monitor PREAD ($FB1E), JOY2 ($FCC9) and WAIT ($FCA8).
.segment "PREAD"
PREAD:  txa
        pha
        eor #$01
        tax
        lda $C059
        lda $C05E
        lda $C05A
        jmp JOY2

.segment "WAIT"
WAIT:   sec
@wait2: pha
@wait3: sbc #$01
        bne @wait3
        pla
        sbc #$01
        bne @wait2
        rts

.segment "JOY2"
JOY2:   inx
        dex
        beq @joy3               ; port B X
        lda $C05F
        dex
        beq @joy3               ; port A X
        lda $C058
        dex
        beq @joy3               ; port B Y
        lda $C05E
        lda $C05B               ; port A Y
@joy3:  lda $C05C               ; charge the capacitor
        lda #$0F
        jsr WAIT                ; 800 us
        ldy #$80
        lda $C05D               ; start the timeout
        ldx #$48
@joy4:  dex                     ; 370 us
        bpl @joy4
@joy5:  inx
        lda $BFE6,y             ; page-crossing read
        rol a
        lda $C066
        bmi @joy5
        txa
        bpl @joy6
        lda #$FF
        bne @joy7
@joy6:  rol a                   ; double the count
@joy7:  tay
        pla
        tax
        rts

.segment "VECTORS"
        .word irq, reset, irq
