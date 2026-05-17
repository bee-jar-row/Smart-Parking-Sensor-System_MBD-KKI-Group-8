#include <avr/io.h>

; Pin & LCD Definitions
.equ BTN_WARN,  2        ; PB2 = D10
.equ BTN_DANG,  3        ; PB3 = D11
.equ LED_SAFE,  2        ; PD2 = Green
.equ LED_WARN,  3        ; PD3 = Blue/Yellow
.equ LED_DANG,  4        ; PD4 = Red
.equ BUZ_BIT,   5        ; PD5 = Buzzer
.equ LCD_WR,    0x7C     ; JHD-2X16-I2C write address
.equ SIM_SAFE,  26       ; no button → SAFE (> 25)
.equ SIM_WARN,  15       ; BTN_WARN  → CAUTION (10–25)
.equ SIM_DANG,  9        ; BTN_DANG  → WARNING (< 10)

.section .bss
buz_phase: .byte 1
beep_acc:  .byte 1

.section .text
.global main

; Initialize stack, GPIO, peripherals, and show splash screen
main:
    ldi   r16, hi8(RAMEND)
    out   _SFR_IO_ADDR(SPH), r16
    ldi   r16, lo8(RAMEND)
    out   _SFR_IO_ADDR(SPL), r16

    in    r16, _SFR_IO_ADDR(DDRD)
    ori   r16, (1<<LED_SAFE)|(1<<LED_WARN)|(1<<LED_DANG)|(1<<BUZ_BIT)
    out   _SFR_IO_ADDR(DDRD), r16

    in    r16, _SFR_IO_ADDR(DDRB)
    andi  r16, ~((1<<BTN_WARN)|(1<<BTN_DANG))
    out   _SFR_IO_ADDR(DDRB), r16
    in    r16, _SFR_IO_ADDR(PORTB)
    ori   r16, (1<<BTN_WARN)|(1<<BTN_DANG)
    out   _SFR_IO_ADDR(PORTB), r16

    rcall twi_init
    rcall lcd_init

    rcall lcd_clear
    ldi   r24, 0x80
    rcall lcd_cmd
    ldi   ZL, lo8(msg_splash1)
    ldi   ZH, hi8(msg_splash1)
    rcall lcd_puts
    ldi   r24, 0xC0
    rcall lcd_cmd
    ldi   ZL, lo8(msg_splash2)
    ldi   ZH, hi8(msg_splash2)
    rcall lcd_puts
    ldi   r24, 150
    rcall delay_10ms_x
    rcall lcd_clear

    clr   r16
    sts   buz_phase, r16
    sts   beep_acc, r16

; Main loop: read buttons, classify zone, update outputs
loop:
    rcall read_distance

    mov   r24, r6
    cpi   r24, 10
    brlo  l_warning
    cpi   r24, 26
    brlo  l_caution
    rjmp  l_safe

; WARNING zone (<10cm): red LED, fast beep
l_warning:
    ldi   r16, 2
    mov   r9, r16
    in    r16, _SFR_IO_ADDR(PORTD)
    andi  r16, ~((1<<LED_SAFE)|(1<<LED_WARN)|(1<<LED_DANG))
    ori   r16, (1<<LED_DANG)
    out   _SFR_IO_ADDR(PORTD), r16
    ldi   r18, 1
    rcall buzzer_service
    rjmp  l_display

; CAUTION zone (10-25cm): blue LED, slow beep
l_caution:
    ldi   r16, 1
    mov   r9, r16
    in    r16, _SFR_IO_ADDR(PORTD)
    andi  r16, ~((1<<LED_SAFE)|(1<<LED_WARN)|(1<<LED_DANG))
    ori   r16, (1<<LED_WARN)
    out   _SFR_IO_ADDR(PORTD), r16
    ldi   r18, 4
    rcall buzzer_service
    rjmp  l_display

; SAFE zone (>25cm): green LED, buzzer off
l_safe:
    clr   r9
    in    r16, _SFR_IO_ADDR(PORTD)
    andi  r16, ~((1<<LED_SAFE)|(1<<LED_WARN)|(1<<LED_DANG))
    ori   r16, (1<<LED_SAFE)
    out   _SFR_IO_ADDR(PORTD), r16
    rcall buzzer_off
    rjmp  l_display

; Update LCD with distance and zone name
l_display:
    ldi   r24, 0x80
    rcall lcd_cmd
    ldi   ZL, lo8(msg_dist)
    ldi   ZH, hi8(msg_dist)
    rcall lcd_puts
    mov   r24, r6
    rcall lcd_print_u8
    ldi   ZL, lo8(msg_cm)
    ldi   ZH, hi8(msg_cm)
    rcall lcd_puts

    ldi   r24, 0xC0
    rcall lcd_cmd
    ldi   ZL, lo8(msg_zone)
    ldi   ZH, hi8(msg_zone)
    rcall lcd_puts
    mov   r20, r9
    cpi   r20, 0
    breq  z_safe
    cpi   r20, 1
    breq  z_caution
    ldi   ZL, lo8(msg_warning)
    ldi   ZH, hi8(msg_warning)
    rjmp  z_print
z_safe:
    ldi   ZL, lo8(msg_safe)
    ldi   ZH, hi8(msg_safe)
    rjmp  z_print
z_caution:
    ldi   ZL, lo8(msg_caution)
    ldi   ZH, hi8(msg_caution)
z_print:
    rcall lcd_puts

    ldi   r24, 12
    rcall delay_10ms_x
    rjmp  loop

; Read simulated distance from buttons into r6
read_distance:
    in    r16, _SFR_IO_ADDR(PINB)
    sbrs  r16, BTN_DANG
    rjmp  rd_dang
    sbrs  r16, BTN_WARN
    rjmp  rd_warn
    ldi   r16, SIM_SAFE
    mov   r6, r16
    ret
rd_dang:
    ldi   r16, SIM_DANG
    mov   r6, r16
    ret
rd_warn:
    ldi   r16, SIM_WARN
    mov   r6, r16
    ret

; Toggle buzzer at rate r18 (1=fast, 4=slow)
buzzer_service:
    lds   r19, beep_acc
    inc   r19
    cp    r19, r18
    brlo  bs_store
    clr   r19
    lds   r20, buz_phase
    ldi   r21, 1
    eor   r20, r21
    sts   buz_phase, r20
    in    r16, _SFR_IO_ADDR(PORTD)
    sbrc  r20, 0
    rjmp  bs_on
    andi  r16, ~(1<<BUZ_BIT)
    out   _SFR_IO_ADDR(PORTD), r16
    rjmp  bs_store
bs_on:
    ori   r16, (1<<BUZ_BIT)
    out   _SFR_IO_ADDR(PORTD), r16
bs_store:
    sts   beep_acc, r19
    ret

; Turn buzzer off and reset phase
buzzer_off:
    clr   r16
    sts   buz_phase, r16
    sts   beep_acc, r16
    in    r16, _SFR_IO_ADDR(PORTD)
    andi  r16, ~(1<<BUZ_BIT)
    out   _SFR_IO_ADDR(PORTD), r16
    ret

; Initialize TWI/I2C at ~100kHz
twi_init:
    clr   r16
    sts   TWSR, r16
    ldi   r16, 72
    sts   TWBR, r16
    ldi   r16, (1<<TWEN)
    sts   TWCR, r16
    ret

; Send I2C START condition
twi_start:
    ldi   r16, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
    sts   TWCR, r16
ts_w:
    lds   r16, TWCR
    sbrs  r16, TWINT
    rjmp  ts_w
    ret

; Send I2C STOP condition
twi_stop:
    ldi   r16, (1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
    sts   TWCR, r16
    ldi   r24, 10
    rcall delay_us_x
    ret

; Write byte r24 to I2C bus
twi_write:
    sts   TWDR, r24
    ldi   r16, (1<<TWINT)|(1<<TWEN)
    sts   TWCR, r16
tw_w:
    lds   r16, TWCR
    sbrs  r16, TWINT
    rjmp  tw_w
    ret

; Send command byte to LCD (control byte 0x00)
lcd_cmd:
    push  r24
    rcall twi_start
    ldi   r24, LCD_WR
    rcall twi_write
    ldi   r24, 0x00
    rcall twi_write
    pop   r24
    rcall twi_write
    rcall twi_stop
    ldi   r24, 2
    rcall delay_ms_x
    ret

; Send data byte to LCD (control byte 0x40)
lcd_data:
    push  r24
    rcall twi_start
    ldi   r24, LCD_WR
    rcall twi_write
    ldi   r24, 0x40
    rcall twi_write
    pop   r24
    rcall twi_write
    rcall twi_stop
    ldi   r24, 1
    rcall delay_ms_x
    ret

; Initialize LCD in 8-bit mode, 2 lines, display on
lcd_init:
    ldi   r24, 50
    rcall delay_ms_x
    ldi   r24, 0x38
    rcall lcd_cmd
    ldi   r24, 0x0C
    rcall lcd_cmd
    ldi   r24, 0x06
    rcall lcd_cmd
    rcall lcd_clear
    ret

; Clear LCD display
lcd_clear:
    ldi   r24, 0x01
    rcall lcd_cmd
    ldi   r24, 5
    rcall delay_ms_x
    ret

; Print null-terminated string from program memory (Z pointer)
lcd_puts:
    lpm   r24, Z+
    cpi   r24, 0
    breq  lp_done
    push  ZL
    push  ZH
    rcall lcd_data
    pop   ZH
    pop   ZL
    rjmp  lcd_puts
lp_done:
    ret

; Print unsigned 8-bit number (r24) as 3-digit decimal
lcd_print_u8:
    ldi   r22, 100
    rcall lp_digit
    ldi   r22, 10
    rcall lp_digit
    subi  r24, -48
    rcall lcd_data
    ret
lp_digit:
    clr   r18
lpd_lp:
    cp    r24, r22
    brlo  lpd_dn
    sub   r24, r22
    inc   r18
    rjmp  lpd_lp
lpd_dn:
    push  r24
    ldi   r24, 48
    add   r24, r18
    rcall lcd_data
    pop   r24
    ret

; Delay r24 * ~4us
delay_us_x:
du_outer:
    ldi   r25, 3
du_inner:
    nop
    dec   r25
    brne  du_inner
    dec   r24
    brne  du_outer
    ret

; Delay r24 * 1ms
delay_ms_x:
dm_o:
    ldi   r26, lo8(1600)
    ldi   r27, hi8(1600)
dm_i:
    sbiw  r26, 1
    brne  dm_i
    dec   r24
    brne  dm_o
    ret

; Delay r24 * 10ms
delay_10ms_x:
dt_o:
    push  r24
    ldi   r24, 10
    rcall delay_ms_x
    pop   r24
    dec   r24
    brne  dt_o
    ret

; String constants
.section .text
msg_splash1: .asciz "Smart Parking"
msg_splash2: .asciz "Sensor  Group 8"
msg_dist:    .asciz "Dist: "
msg_cm:      .asciz " cm   "
msg_zone:    .asciz "Zone: "
msg_safe:    .asciz "SAFE      "
msg_caution: .asciz "CAUTION   "
msg_warning: .asciz "WARNING   "
