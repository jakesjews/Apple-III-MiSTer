; Standalone Apple /// 6551 diagnostic, assembled into a 4 KiB boot ROM.
; Configure 19200 8N1. A received byte interrupts the real T65 and is echoed
; through a 256-byte RAM queue. TX interrupts drain a queue stalled by CTS.
.setcpu "6502"
.segment "CODE"
.org $F000
reset:
    sei
    cld
    ldx #$ff
    txs
    lda #$f7                  ; slow CPU, I/O, video, ROM, ordinary stack
    sta $ffd1                 ; preload environment before enabling outputs
    lda #$ff
    sta $ffd3                 ; VIA D PA direction: environment register
    lda #$00
    sta $ffd0                 ; zero page 0
    lda #$ff
    sta $ffd2                 ; VIA D PB direction: zero-page register
    lda #$7f
    sta $ffde                 ; disable VIA D IRQs
    sta $ffee                 ; disable VIA E IRQs
    lda #0
    sta $00                   ; received-byte queue head
    sta $01                   ; transmitted-byte queue tail
    sta $02                   ; errors accumulated by handler
    sta $c0f1                 ; programmed reset
    lda #$1f
    sta $c0f3                 ; 19200, internal receive clock, 8N1
    lda #$09
    sta $c0f2                 ; DTR/RTS asserted, RX IRQ enabled
    lda $c0f1                 ; clear startup modem status
    cli
loop:
    ; Only the IRQ handler reads status: mainline polling can acknowledge
    ; a receive interrupt before the CPU takes it, losing the notification.
    jmp loop
irq:
    pha
    txa
    pha
    lda $c0f1                 ; acknowledge IRQ before reading received data
    sta $03                   ; retain the TX-empty state from this snapshot
    and #$07
    ora $02
    sta $02
    lda $03
    and #$08
    beq transmit
    lda $c0f0
    ldx $00
    sta $0200,x
    inc $00
transmit:
    ldx $01
    cpx $00
    beq queue_empty
    lda $03
    and #$10
    beq queue_pending
    lda $0200,x
    sta $c0f0
    inc $01
    ldx $01
    cpx $00
    beq queue_empty
queue_pending:
    lda #$05                  ; RX + TX IRQ; CTS masks TX-empty requests
    bne set_command
queue_empty:
    lda #$09                  ; RX IRQ only; avoid idle TX IRQ storms
set_command:
    sta $c0f2
done:
    pla
    tax
    pla
    rti
nmi:
    rti
.res $fffa-*, $ea
.word nmi,reset,irq
