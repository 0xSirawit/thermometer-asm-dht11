.include "m328pdef.inc"

.def temp = r16
.dseg
mode_var:    .byte 1			; store mode 0-3 (C, F, K, R)
dht_counter: .byte 1			; store counter
temp_stored: .byte 1			; store stable temperature shown on display

.cseg
.org 0x0000
	rjmp start
.org 0x0008
	rjmp button_isr

start:
	rcall seg_setup
	rcall mode_display_setup
	rcall button_setup
	rcall dht11_read			; reads temp sensor and saves result to temp_stored

	ldi   temp, 6			; number of loop to read temp sensor (around every 2 seconds)
	sts   dht_counter, temp

loop:
	lds   r18, temp_stored		; load temp_stored for display
	rcall mode_display
	rcall seg_show_temp

	lds   temp, dht_counter
	dec   temp
	sts   dht_counter, temp
	brne  loop

	rcall dht11_read
	ldi   temp, 6
	sts   dht_counter, temp
	rjmp  loop

; ============================================================================
; 7 SEGMENT FUNCTIONS
; ============================================================================
; segment pattern table (active LOW, bit0=A .. bit6=G, 0=ON 1=OFF)
seg_tbl:
.db 0b1000000, 0b1111001  ; 0, 1
.db 0b0100100, 0b0110000  ; 2, 3
.db 0b0011001, 0b0010010  ; 4, 5
.db 0b0000010, 0b1111000  ; 6, 7
.db 0b0000000, 0b0010000  ; 8, 9

seg_setup:
	; PD2-PD7 = seg A-F output, PD1 = DHT11 input
	ldi  temp, 0b11111100
	out  DDRD, temp

	; PB0=segG  PB1=ones  PB2=tens  PB3=hundreds  output
	in   temp, DDRB
	ori  temp, 0b00001111
	out  DDRB, temp
	ret

; show value in r18 on 3-digit 7-segment display
; call this repeatedly for multiplexing
seg_show_temp:
	push r19
	push r20
	push r21

	; convert r18 to C/F/K/R based on mode
	mov  r20, r18				; r20 = working value (Celsius)

	lds  temp, mode_var
	cpi  temp, 1
	breq seg_calc_F
	lds  temp, mode_var
	cpi  temp, 2
	breq seg_calc_K
	lds  temp, mode_var
	cpi  temp, 3
	breq seg_calc_R
	rjmp seg_split				; mode 0: show C directly

seg_calc_F:						; F = C*9/5 + 32
	; --- C * 9 using add loop ---
	clr  r24
	clr  r25
	mov  r20, r18
	tst  r20
	breq seg_F_add_done
seg_F_add:
	ldi  r21, 9
	add  r24, r21
	adc  r25, r1
	dec  r20
	brne seg_F_add
seg_F_add_done:					; r25:r24 = C*9

	; --- / 5 using subtract loop ---
	clr  r19
seg_F_div:
	cpi  r25, 0
	brne seg_F_div_hi
	cpi  r24, 5
	brlo seg_F_div_done
seg_F_div_hi:
	subi r24, 5
	sbci r25, 0
	inc  r19
	rjmp seg_F_div
seg_F_div_done:					; r19 = C*9/5

	; --- + 32 ---
	ldi  r20, 32
	add  r19, r20
	clr  r21
	mov  r20, r19
	rcall seg_display_16
	rjmp seg_show_done

seg_calc_K:						; K = C + 273
	clr  r24
	clr  r25
	mov  r24, r18
	ldi  r20, low(273)
	ldi  r21, high(273)
	add  r24, r20
	adc  r25, r21				; r25:r24 = C+273
	mov  r20, r24
	mov  r21, r25
	rcall seg_display_16
	rjmp seg_show_done

seg_calc_R:						; Rankine = (C+273)*9/5
	; --- r24 = C+273 (fits in 16-bit) ---
	mov  r24, r18
	clr  r25
	ldi  r20, low(273)
	ldi  r21, high(273)
	add  r24, r20
	adc  r25, r21				; r25:r24 = C+273

	; --- save base, clear accumulator, add base 9 times ---
	push r24					; save low(C+273)
	push r25					; save high(C+273)
	clr  r24
	clr  r25
	ldi  r20, 9
seg_Ra_mul:
	pop  r21					; high base
	pop  r19					; low base
	push r19
	push r21
	add  r24, r19
	adc  r25, r21
	dec  r20
	brne seg_Ra_mul
	pop  r21					; clean stack
	pop  r19
	; r25:r24 = (C+273)*9

	; --- / 5, result in r21:r20 ---
	clr  r20
	clr  r21
seg_Ra_div:
	cpi  r25, 0
	brne seg_Ra_div_hi
	cpi  r24, 5
	brlo seg_Ra_div_done
seg_Ra_div_hi:
	subi r24, 5
	sbci r25, 0
	ldi  r19, 1
	add  r20, r19
	adc  r21, r1
	rjmp seg_Ra_div
seg_Ra_div_done:				; r21:r20 = result
	rcall seg_display_16
	rjmp seg_show_done

seg_split:
	; r20 = 8-bit value (Celsius or Fahrenheit, <256)
	clr  r21
	rcall seg_display_16

seg_show_done:
	pop  r21
	pop  r20
	pop  r19
	ret

; seg_display_16: display r21:r20 on 3 digits, multiplex 80 times (~160ms)
seg_display_16:
	push r22
	ldi  r22, 80
seg_mux_loop:
	rcall seg_multiplex
	dec  r22
	brne seg_mux_loop
	pop  r22
	ret

; seg_multiplex: show one full refresh (hundreds, tens, ones)
seg_multiplex:
	push r20
	push r21
	push r22
	push r23

	; --- count hundreds ---
	clr  r22					; hundreds
sub100:
	cpi  r21, 0
	brne sub100_hi
	cpi  r20, 100
	brlo sub100_done
sub100_hi:
	subi r20, 100
	sbci r21, 0
	inc  r22
	rjmp sub100
sub100_done:

	; --- count tens ---
	clr  r23					; tens
sub10:
	cpi  r20, 10
	brlo sub10_done
	subi r20, 10
	inc  r23
	rjmp sub10
sub10_done:					; r22=hundreds r23=tens r20=ones
	; show each digit (ones=PB1, tens=PB2, hundreds=PB3)
	mov  r16, r20
	ldi  r17, (1<<1)
	rcall seg_digit

	mov  r16, r23
	ldi  r17, (1<<2)
	rcall seg_digit

	mov  r16, r22
	ldi  r17, (1<<3)
	rcall seg_digit

	pop  r23
	pop  r22
	pop  r21
	pop  r20
	ret

; seg_digit: r16=digit(0-9)  r17=digit-select bit mask for PORTB
seg_digit:
	push r17

	; lookup pattern
	ldi  ZL, low(seg_tbl*2)
	ldi  ZH, high(seg_tbl*2)
	add  ZL, r16
	clr  r16
	adc  ZH, r16
	lpm  r16, Z					; r16 = pattern

	; activate digit
	pop  r17
	in   r18, PORTB
	andi r18, 0b11110001
	or   r18, r17
	out  PORTB, r18

	; seg A-F -> PD2-PD7
	mov  r17, r16
	andi r17, 0b00111111
	lsl  r17
	lsl  r17
	in   r18, PORTD
	andi r18, 0b00000011
	or   r18, r17
	out  PORTD, r18

	; seg G -> PB0
	in   r17, PORTB
	andi r17, 0b11111110
	sbrc r16, 6
	ori  r17, 1
	out  PORTB, r17

	rcall delay_1ms
	rcall delay_1ms
	rcall delay_1ms

	; blank
	in   r17, PORTB
	andi r17, 0b11110001
	ori  r17, 1
	out  PORTB, r17
	in   r17, PORTD
	ori  r17, 0b11111100
	out  PORTD, r17

	ret


; ============================================================================
; MODE DISPLAY FUNCTIONS
; ============================================================================
mode_display_setup:
	ldi  temp, 0
	sts  mode_var, temp
	sbi DDRB, 5
	sbi DDRB, 4
	ret

mode_display:
	push temp
	push r20

	lds  temp, mode_var
	andi temp, 0x03

	in   r20, PORTB
	andi r20, 0b11001111
	lsl  temp
	lsl  temp
	lsl  temp
	lsl  temp
	or   r20, temp
	out  PORTB, r20

	pop  r20
	pop  temp
	ret


; ============================================================================
; BUTTON FUNCTIONS
; ============================================================================
button_setup:
	cbi  DDRC, 0
	cbi  DDRC, 1
	cbi  DDRC, 2
	cbi  DDRC, 3

	ldi  temp, (1<<PCINT8)|(1<<PCINT9)|(1<<PCINT10)|(1<<PCINT11)
	sts  PCMSK1, temp

	ldi  temp, (1<<PCIE1)
	sts  PCICR, temp

	sei
	ret

button_isr:
	rcall delay_10ms

	sbis PINC, 0
	rjmp bisr_b1
	sbis PINC, 1
	rjmp bisr_b2
	sbis PINC, 2
	rjmp bisr_b3
	sbis PINC, 3
	rjmp bisr_b4
	rjmp bisr_exit

bisr_b1: ldi  temp, 0
	sts  mode_var, temp
bisr_w1: sbis PINC, 0
	rjmp bisr_w1
	rjmp bisr_exit

bisr_b2: ldi  temp, 1
	sts  mode_var, temp
bisr_w2: sbis PINC, 1
	rjmp bisr_w2
	rjmp bisr_exit

bisr_b3: ldi  temp, 2
	sts  mode_var, temp
bisr_w3: sbis PINC, 2
	rjmp bisr_w3
	rjmp bisr_exit

bisr_b4: ldi  temp, 3
	sts  mode_var, temp
bisr_w4: sbis PINC, 3
	rjmp bisr_w4

bisr_exit:
	rcall delay_10ms
	reti


; ============================================================================
; DHT11 FUNCTIONS
; ============================================================================
dht11_read:
	sbi  DDRD, 1
	cbi  PORTD, 1
	rcall delay_10ms
	rcall delay_10ms
	sbi  PORTD, 1

	cbi  DDRD, 1
w1: sbic PIND, 1
	rjmp w1
w2: sbis PIND, 1
	rjmp w2
w3: sbic PIND, 1
	rjmp w3

	push r20
	rcall dht11_reading			; byte 1 humidity int
	rcall dht11_reading			; byte 2 humidity dec
	rcall dht11_reading			; byte 3 temperature int -> r18
	mov  r20, r18
	rcall dht11_reading			; byte 4 temperature dec
	rcall dht11_reading			; byte 5 checksum
	sts  temp_stored, r20		; save stable value directly
	pop  r20
	ret

dht11_reading:
	push r19
	ldi  r19, 8
	clr  r18					; working byte

w4: sbis PIND, 1
	rjmp w4
	rcall delay_50us

	sbis PIND, 1
	rjmp skp
	sec
	rol  r18
	rjmp w5
skp: lsl  r18

w5: sbic PIND, 1
	rjmp w5

	dec  r19
	brne w4

	pop  r19
	ret




; ============================================================================
; DELAY FUNCTIONS (at 16MHz clock)
; ============================================================================
delay_10us:
	push r18
	ldi  r18, 49
delay_10us_loop:
	dec  r18
	brne delay_10us_loop
	nop
	nop
	pop  r18
	ret

delay_50us:
	rcall delay_10us
	rcall delay_10us
	rcall delay_10us
	rcall delay_10us
	rcall delay_10us
	ret

delay_1ms:
	push r16
	push r17
	ldi  r16, 21
	ldi  r17, 199
delay_1ms_loop:
	dec  r17
	brne delay_1ms_loop
	dec  r16
	brne delay_1ms_loop
	pop  r17
	pop  r16
	ret

delay_5ms:
	rcall delay_1ms
	rcall delay_1ms
	rcall delay_1ms
	rcall delay_1ms
	rcall delay_1ms
	ret

delay_10ms:
	rcall delay_5ms
	rcall delay_5ms
	ret

delay_50ms:
	rcall delay_10ms
	rcall delay_10ms
	rcall delay_10ms
	rcall delay_10ms
	rcall delay_10ms
	ret

delay_100ms:
	rcall delay_50ms
	rcall delay_50ms
	ret

delay_250ms:
	rcall delay_100ms
	rcall delay_100ms
	rcall delay_50ms
	ret

delay_500ms:
	rcall delay_250ms
	rcall delay_250ms
	ret

delay_1000ms:
	rcall delay_500ms
	rcall delay_500ms
	ret
