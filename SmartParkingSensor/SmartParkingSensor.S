#include <avr/io.h>

; Pin & LCD Definitions
.equ TRIG_BIT,  0
.equ ECHO_BIT,  1
.equ LED_SAFE,  2
.equ LED_CAUT,  3
.equ LED_WARN,  4
.equ BUZ_BIT,   5
.equ LCD_I2C_ADDR, 0x4E
.equ LCD_RS,    0x01
.equ LCD_E,     0x04
.equ LCD_BL,    0x08

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
    ori   r16, (1<<LED_SAFE)|(1<<LED_CAUT)|(1<<LED_WARN)|(1<<BUZ_BIT)
    out   _SFR_IO_ADDR(DDRD), r16

    in    r16, _SFR_IO_ADDR(DDRB)
    ori   r16, (1<<TRIG_BIT)
    andi  r16, ~(1<<ECHO_BIT)
    out   _SFR_IO_ADDR(DDRB), r16
    in    r16, _SFR_IO_ADDR(PORTB)
    andi  r16, ~((1<<TRIG_BIT)|(1<<ECHO_BIT))
    out   _SFR_IO_ADDR(PORTB), r16

    clr   r16
    sts   TCCR1A, r16
    sts   TCCR1B, r16

    rcall twi_init
    rcall lcd_init

    ldi   r24, 0x80
    rcall lcd_command
    ldi   ZL, lo8(msg_splash1)
    ldi   ZH, hi8(msg_splash1)
    rcall lcd_print_string
    ldi   r24, 0xC0
    rcall lcd_command
    ldi   ZL, lo8(msg_splash2)
    ldi   ZH, hi8(msg_splash2)
    rcall lcd_print_string
    ldi   r24, 150
    rcall delay_10ms_x
    ldi   r24, 0x01
    rcall lcd_command
    rcall delay_long

    clr   r16
    sts   buz_phase, r16
    sts   beep_acc, r16

; Main loop: read sensor, update LEDs/buzzer/LCD
loop:
    rcall read_distance

    mov   r24, r6
    cpi   r24, 0xFF
    breq  l_safe
    cpi   r24, 11
    brlo  l_warning
    cpi   r24, 26
    brlo  l_caution
    rjmp  l_safe

; WARNING zone (<10cm): red LED, fast beep
l_warning:
    ldi   r16, 2
    mov   r9, r16
    in    r16, _SFR_IO_ADDR(PORTD)
    andi  r16, ~((1<<LED_SAFE)|(1<<LED_CAUT)|(1<<LED_WARN))
    ori   r16, (1<<LED_WARN)
    out   _SFR_IO_ADDR(PORTD), r16
    ldi   r18, 1
    rcall buzzer_service
    rjmp  l_display

; CAUTION zone (10-25cm): blue LED, slow beep
l_caution:
    ldi   r16, 1
    mov   r9, r16
    in    r16, _SFR_IO_ADDR(PORTD)
    andi  r16, ~((1<<LED_SAFE)|(1<<LED_CAUT)|(1<<LED_WARN))
    ori   r16, (1<<LED_CAUT)
    out   _SFR_IO_ADDR(PORTD), r16
    ldi   r18, 4
    rcall buzzer_service
    rjmp  l_display

; SAFE zone (>25cm or timeout): green LED, buzzer off
l_safe:
    clr   r9
    in    r16, _SFR_IO_ADDR(PORTD)
    andi  r16, ~((1<<LED_SAFE)|(1<<LED_CAUT)|(1<<LED_WARN))
    ori   r16, (1<<LED_SAFE)
    out   _SFR_IO_ADDR(PORTD), r16
    rcall buzzer_off
    rjmp  l_display

; Update LCD with distance and zone name
l_display:
    ldi   r24, 0x80
    rcall lcd_command
    ldi   ZL, lo8(msg_dist)
    ldi   ZH, hi8(msg_dist)
    rcall lcd_print_string
    mov   r24, r6
    cpi   r24, 0xFF
    brne  ld_num
    ldi   ZL, lo8(msg_na)
    ldi   ZH, hi8(msg_na)
    rcall lcd_print_string
    rjmp  ld_line2
ld_num:
    rcall lcd_print_u8
    ldi   ZL, lo8(msg_cm)
    ldi   ZH, hi8(msg_cm)
    rcall lcd_print_string
ld_line2:
    ldi   r24, 0xC0
    rcall lcd_command
    ldi   ZL, lo8(msg_zone)
    ldi   ZH, hi8(msg_zone)
    rcall lcd_print_string
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
    rcall lcd_print_string

    ldi   r24, 12
    rcall delay_10ms_x
    rjmp  loop

; Take 3 HC-SR04 readings and return the median in r6
read_distance:
    rcall read_once
    mov   r10, r24
    ldi   r24, 20
    rcall delay_ms_x
    rcall read_once
    mov   r11, r24
    ldi   r24, 20
    rcall delay_ms_x
    rcall read_once
    mov   r12, r24

    cp    r10, r11
    brlo  rd_s1
    mov   r16, r10
    mov   r10, r11
    mov   r11, r16
rd_s1:
    cp    r11, r12
    brlo  rd_s2
    mov   r16, r11
    mov   r11, r12
    mov   r12, r16
rd_s2:
    cp    r10, r11
    brlo  rd_s3
    mov   r16, r10
    mov   r10, r11
    mov   r11, r16
rd_s3:
    mov   r6, r11
    ret

; Single HC-SR04 measurement, returns distance in r24 (0xFF = timeout)
read_once:
    cbi   _SFR_IO_ADDR(PORTB), TRIG_BIT
    ldi   r24, 4
    rcall delay_us_x
    sbi   _SFR_IO_ADDR(PORTB), TRIG_BIT
    ldi   r24, 12
    rcall delay_us_x
    cbi   _SFR_IO_ADDR(PORTB), TRIG_BIT

    ldi   r24, 0
    ldi   r25, 0
    ldi   r19, 200
ro_wh:
    sbic  _SFR_IO_ADDR(PINB), ECHO_BIT
    rjmp  ro_started
    nop
    nop
    dec   r24
    brne  ro_wh
    dec   r19
    brne  ro_wh
    rjmp  ro_timeout

ro_started:
    clr   r16
    sts   TCNT1H, r16
    sts   TCNT1L, r16
    ldi   r16, (1<<CS11)
    sts   TCCR1B, r16

    ldi   r24, 0
    ldi   r19, 200
ro_wl:
    sbis  _SFR_IO_ADDR(PINB), ECHO_BIT
    rjmp  ro_done
    nop
    nop
    dec   r24
    brne  ro_wl
    dec   r19
    brne  ro_wl
    clr   r16
    sts   TCCR1B, r16
    rjmp  ro_timeout

ro_done:
    clr   r16
    sts   TCCR1B, r16
    lds   r24, TCNT1L
    lds   r25, TCNT1H

    ldi   r22, 116
    rcall div16_8
    cpi   r24, 201
    brlo  ro_ok
    ldi   r24, 200
ro_ok:
    tst   r24
    breq  ro_timeout
    ret

ro_timeout:
    ldi   r24, 0xFF
    ret

; Unsigned 16-bit / 8-bit division (r25:r24 / r22 -> r24)
div16_8:
    clr   r18
    ldi   r23, 16
dv_lp:
    lsl   r24
    rol   r25
    rol   r18
    cp    r18, r22
    brlo  dv_sk
    sub   r18, r22
    ori   r24, 1
dv_sk:
    dec   r23
    brne  dv_lp
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

; Initialize TWI/I2C at ~308kHz
twi_init:
    clr   r21
    sts   TWSR, r21
    ldi   r21, 12
    sts   TWBR, r21
    ldi   r21, (1<<TWEN)
    sts   TWCR, r21
    ret

; Send I2C START condition
I2C_start:
    ldi   r21, (1<<TWINT)|(1<<TWSTA)|(1<<TWEN)
    sts   TWCR, r21
s1: lds   r21, TWCR
    sbrs  r21, TWINT
    rjmp  s1
    ret

; Send I2C STOP condition
I2C_stop:
    ldi   r21, (1<<TWINT)|(1<<TWSTO)|(1<<TWEN)
    sts   TWCR, r21
    ret

; Write byte r27 to I2C bus
I2C_write:
    sts   TWDR, r27
    ldi   r21, (1<<TWINT)|(1<<TWEN)
    sts   TWCR, r21
s2: lds   r21, TWCR
    sbrs  r21, TWINT
    rjmp  s2
    ret

; Write one byte to PCF8574 (separate I2C transaction)
expander_write:
    push  r22
    ori   r22, LCD_BL
    rcall I2C_start
    ldi   r27, LCD_I2C_ADDR
    rcall I2C_write
    mov   r27, r22
    rcall I2C_write
    rcall I2C_stop
    pop   r22
    ret

; Pulse the LCD Enable pin (high then low)
pulse_enable:
    mov   r24, r22
    ori   r24, LCD_E
    mov   r22, r24
    rcall expander_write
    ldi   r24, 2
    rcall delay_us_x
    mov   r24, r22
    andi  r24, ~(LCD_E)
    mov   r22, r24
    rcall expander_write
    ldi   r24, 50
    rcall delay_us_x
    ret

; Send 4-bit nibble to LCD
lcd_write4bits:
    rcall expander_write
    rcall pulse_enable
    ret

; Send full byte to LCD (high nibble then low nibble)
lcd_send_byte:
    push  r24
    mov   r24, r22
    andi  r24, 0xF0
    or    r24, r23
    mov   r22, r24
    rcall expander_write
    rcall pulse_enable
    pop   r24
    swap  r24
    andi  r24, 0xF0
    or    r24, r23
    mov   r22, r24
    rcall expander_write
    rcall pulse_enable
    ret

; Send command byte to LCD (RS=0)
lcd_command:
    mov   r22, r24
    ldi   r23, 0
    rcall lcd_send_byte
    ret

; Send data byte to LCD (RS=1)
lcd_data:
    mov   r22, r24
    ldi   r23, LCD_RS
    rcall lcd_send_byte
    ret

; Initialize LCD in 4-bit mode, 2 lines, display on
lcd_init:
    rcall delay_long
    ldi   r22, LCD_BL
    rcall expander_write
    rcall delay_long
    ldi   r22, 0x30
    rcall lcd_write4bits
    ldi   r24, 250
    rcall delay_us_x
    ldi   r24, 250
    rcall delay_us_x
    ldi   r22, 0x30
    rcall lcd_write4bits
    ldi   r24, 250
    rcall delay_us_x
    ldi   r22, 0x30
    rcall lcd_write4bits
    ldi   r24, 250
    rcall delay_us_x
    ldi   r22, 0x20
    rcall lcd_write4bits
    rcall delay_long
    ldi   r24, 0x28
    rcall lcd_command
    ldi   r24, 0x0C
    rcall lcd_command
    ldi   r24, 0x01
    rcall lcd_command
    rcall delay_long
    ldi   r24, 0x06
    rcall lcd_command
    ret

; Print null-terminated string from program memory (Z pointer)
lcd_print_string:
    lpm   r24, Z+
    tst   r24
    breq  lcd_str_done
    push  ZL
    push  ZH
    rcall lcd_data
    pop   ZH
    pop   ZL
    rjmp  lcd_print_string
lcd_str_done:
    ret

; Print unsigned 8-bit number (r24) as 3-digit decimal
lcd_print_u8:
    mov   r18, r24
    ldi   r19, 100
    rcall lcd_digit
    ldi   r19, 10
    rcall lcd_digit
    mov   r24, r18
    subi  r24, -'0'
    rcall lcd_data
    ret
lcd_digit:
    clr   r20
lcd_dg_lp:
    cp    r18, r19
    brlo  lcd_dg_dn
    sub   r18, r19
    inc   r20
    rjmp  lcd_dg_lp
lcd_dg_dn:
    push  r18
    mov   r24, r20
    subi  r24, -'0'
    rcall lcd_data
    pop   r18
    ret

; Delay ~34us
delay_short:
    ldi   r24, 180
ds_l:
    dec   r24
    brne  ds_l
    ret

; Delay ~12ms
delay_long:
    ldi   r24, 0xFF
dl_o:
    ldi   r22, 0xFF
dl_i:
    dec   r22
    brne  dl_i
    dec   r24
    brne  dl_o
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
msg_na:      .asciz "---  cm   "
msg_cm:      .asciz " cm   "
msg_zone:    .asciz "Zone: "
msg_safe:    .asciz "SAFE      "
msg_caution: .asciz "CAUTION   "
msg_warning: .asciz "WARNING   "
