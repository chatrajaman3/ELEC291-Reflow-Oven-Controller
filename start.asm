; 76E003 ADC_Pushbuttons.asm: Reads push buttons using the ADC, AIN0 in P1.7
; can work from push buttons asm and build functionality for oven 
$NOLIST
$MODN76E003
$LIST

;  N76E003 pinout:
;                               -------
;       PWM2/IC6/T0/AIN4/P0.5 -|1    20|- P0.4/AIN5/STADC/PWM3/IC3
;               TXD/AIN3/P0.6 -|2    19|- P0.3/PWM5/IC5/AIN6
;               RXD/AIN2/P0.7 -|3    18|- P0.2/ICPCK/OCDCK/RXD_1/[SCL]
;                    RST/P2.0 -|4    17|- P0.1/PWM4/IC4/MISO
;        INT0/OSCIN/AIN1/P3.0 -|5    16|- P0.0/PWM3/IC3/MOSI/T1
;              INT1/AIN0/P1.7 -|6    15|- P1.0/PWM2/IC2/SPCLK
;                         GND -|7    14|- P1.1/PWM1/IC1/AIN7/CLO
;[SDA]/TXD_1/ICPDA/OCDDA/P1.6 -|8    13|- P1.2/PWM0/IC0
;                         VDD -|9    12|- P1.3/SCL/[STADC]
;            PWM5/IC7/SS/P1.5 -|10   11|- P1.4/SDA/FB/PWM1
;                               -------
;

CLK               EQU 16600000 ; Microcontroller system frequency in Hz
BAUD              EQU 115200 ; Baud rate of UART in bps
TIMER1_RELOAD     EQU (0x100-(CLK/(16*BAUD)))
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))


;shift button 
S_BUTTON    equ P1.6

ORG 0x0000
	ljmp main

;              1234567890123456    <- This helps determine the location of the counter
title:     db 'ADC PUSH BUTTONS', 0
blank:     db '                ', 0
temp:      db 'To=   C  Tj=  C ', 0
parameters:db 's   ,   r   ,   ', 0
on:        db 'Oven on ', 0
off:       db 'Oven off', 0




cseg
; These 'equ' must match the hardware wiring
LCD_RS equ P1.3
LCD_E  equ P1.4
LCD_D4 equ P0.0
LCD_D5 equ P0.1
LCD_D6 equ P0.2
LCD_D7 equ P0.3

$NOLIST
$include(LCD_4bit.inc) ; A library of LCD related functions and utility macros
$LIST


dseg at 0x30
s_temp: ds 1
s_time: ds 1
r_temp: ds 1
r_time: ds 1


BSEG
; These eight bit variables store the value of the pushbuttons after calling 'ADC_to_PB' below
PB0: dbit 1
PB1: dbit 1
PB2: dbit 1
PB3: dbit 1
PB4: dbit 1
PB5: dbit 1
PB6: dbit 1
PB7: dbit 1

process_start: dbit 1

CSEG
Init_All:
	; Configure all the pins for biderectional I/O
	mov	P3M1, #0x00
	mov	P3M2, #0x00
	mov	P1M1, #0x00
	mov	P1M2, #0x00
	mov	P0M1, #0x00
	mov	P0M2, #0x00
	
	orl	CKCON, #0x10 ; CLK is the input for timer 1
	orl	PCON, #0x80 ; Bit SMOD=1, double baud rate
	mov	SCON, #0x52
	anl	T3CON, #0b11011111
	anl	TMOD, #0x0F ; Clear the configuration bits for timer 1
	orl	TMOD, #0x20 ; Timer 1 Mode 2
	mov	TH1, #TIMER1_RELOAD ; TH1=TIMER1_RELOAD;
	setb TR1
	  

	
	;initialize temperatures/times for now 
	mov s_time, #0x05
	mov s_temp, #0x05
	mov r_time, #0x05
	mov r_temp, #0x05
	

	
	; Using timer 0 for delay functions.  Initialize here:
	clr	TR0 ; Stop timer 0
	orl	CKCON,#0x08 ; CLK is the input for timer 0
	anl	TMOD,#0xF0 ; Clear the configuration bits for timer 0
	orl	TMOD,#0x01 ; Timer 0 in Mode 1: 16-bit timer
	
	; Initialize and start the ADC:
	
	; AIN0 is connected to P1.7.  Configure P1.7 as input.
	orl	P1M1, #0b10000000
	anl	P1M2, #0b01111111
	
	; AINDIDS select if some pins are analog inputs or digital I/O:
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b00000001 ; Using AIN0
	orl ADCCON1, #0x01 ; Enable ADC
	
	ret
	
wait_1ms:
	clr	TR0 ; Stop timer 0
	clr	TF0 ; Clear overflow flag
	mov	TH0, #high(TIMER0_RELOAD_1MS)
	mov	TL0,#low(TIMER0_RELOAD_1MS)
	setb TR0
	jnb	TF0, $ ; Wait for overflow
	ret

; Wait the number of miliseconds in R2
waitms:
	lcall wait_1ms
	djnz R2, waitms
	ret

ADC_to_PB:
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x00 ; Select AIN0
	
	clr ADCF
	setb ADCS   ; ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete

	setb PB7
	setb PB6
	setb PB5
	setb PB4
	setb PB3
	setb PB2
	setb PB1
	setb PB0
	
	setb S_BUTTON ; initilize shift button
	
	; Check PB7
ADC_to_PB_L7:
	clr c
	mov a, ADCRH
	subb a, #0xf0
	jc ADC_to_PB_L6
	clr PB7
	ret

	; Check PB6
ADC_to_PB_L6:
	clr c
	mov a, ADCRH
	subb a, #0xd0
	jc ADC_to_PB_L5
	clr PB6
	ret

	; Check PB5
ADC_to_PB_L5:
	clr c
	mov a, ADCRH
	subb a, #0xb0
	jc ADC_to_PB_L4
	clr PB5
	ret

	; Check PB4
ADC_to_PB_L4:
	clr c
	mov a, ADCRH
	subb a, #0x90
	jc ADC_to_PB_L3
	clr PB4
	ret

	; Check PB3
ADC_to_PB_L3:
	clr c
	mov a, ADCRH
	subb a, #0x70
	jc ADC_to_PB_L2
	clr PB3
	ret

	; Check PB2
ADC_to_PB_L2:
	clr c
	mov a, ADCRH
	subb a, #0x50
	jc ADC_to_PB_L1
	clr PB2
	ret

	; Check PB1
ADC_to_PB_L1:
	clr c
	mov a, ADCRH
	subb a, #0x30
	jc ADC_to_PB_L0
	clr PB1
	ret

	; Check PB0
ADC_to_PB_L0:
	clr c
	mov a, ADCRH
	subb a, #0x10
	jc ADC_to_PB_Done
	clr PB0
	ret
	
ADC_to_PB_Done:
	; No pusbutton pressed	
	ret

Display_PushButtons_ADC:
	Set_Cursor(2, 1)
	mov a, #'0'
	mov c, PB7
	addc a, #0
    lcall ?WriteData	
	mov a, #'0'
	mov c, PB6
	addc a, #0
    lcall ?WriteData	
	mov a, #'0'
	mov c, PB5
	addc a, #0
    lcall ?WriteData	
	mov a, #'0'
	mov c, PB4
	addc a, #0
    lcall ?WriteData	
	mov a, #'0'
	mov c, PB3
	addc a, #0
    lcall ?WriteData	
	mov a, #'0'
	mov c, PB2
	addc a, #0
    lcall ?WriteData	
	mov a, #'0'
	mov c, PB1
	addc a, #0
    lcall ?WriteData	
	mov a, #'0'
	mov c, PB0
	addc a, #0
    lcall ?WriteData	
	ret
	
main:
	mov sp, #0x7f
	lcall Init_All
    lcall LCD_4BIT
    
    ; initialize oven_on_flag
    clr process_start 
	
	; display logic
	Set_Cursor(1, 1)
    Send_Constant_String(#temp)
    
    Set_Cursor(2, 1)
    Send_Constant_String(#parameters)
    
    Set_Cursor(1,2)

	
Forever:
	lcall ADC_to_PB
	;lcall Display_PushButtons_ADC
	
	; Display variables 
	Set_Cursor(2, 2)
	Display_BCD(s_time) 
	Set_Cursor(2, 6)
	Display_BCD(s_temp) 
	Set_Cursor(2, 10)
	Display_BCD(r_time) 
	Set_Cursor(2, 14)
	Display_BCD(r_temp) 
	
	; Wait 50 ms between readings
	mov R2, #50
	lcall waitms

	; check if oven on/off button pressed
	jnb PB3, oven_button_check 
	
process_start_check:
	; check process flag, if passes, keep checking for button presses
	jb process_start,  process_continue
	
	jnb PB7, check_S_button_7
	jnb PB6, check_S_button_6
	jnb PB5, check_S_button_5_temp
	jnb PB4, check_S_button_4_temp

process_continue:

	Set_Cursor(1,1)
	Send_Constant_String(#on)
	ljmp Forever
	
check_S_button_4_temp:
	ljmp check_S_button_4

check_S_button_5_temp:
	ljmp check_S_button_5

oven_button_check:
	Wait_Milli_Seconds(#75)
	jb PB3, process_start_check  ; if not still pressed then skip 
	jb PB3, $
	
	cpl process_start
	
	sjmp process_start_check
	

;PB7 CHECK
check_S_button_7:

	
	jnb S_BUTTON, change_timeT_dec_7

	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB7, timeT_done_7 ; if not still pressed then skip 
	jb PB7, $

	mov a, s_time
	add a, #1
	da a
	mov s_time, a
	
timeT_done_7:
	ljmp Forever

change_timeT_dec_7:
	jb PB7, timeT_done_7
	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB7, timeT_done_7 ; if not still pressed then skip 
	jb PB7, $
	
	mov a, s_time
	add a, #0x99
	da a 
	mov s_time, a
	
	ljmp Forever


;PB6 CHECK
check_S_button_6:

	
	jnb S_BUTTON, change_timeT_dec_6

	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB6, timeT_done_6 ; if not still pressed then skip 
	jb PB6, $

	mov a, s_temp
	add a, #1
	da a
	mov s_temp, a
	
timeT_done_6:
	ljmp Forever

change_timeT_dec_6:
	jb PB6, timeT_done_6
	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB6, timeT_done_6 ; if not still pressed then skip 
	jb PB6, $
	
	mov a, s_temp
	add a, #0x99
	da a 
	mov s_temp, a
	
	ljmp Forever
	
;PB5 CHECK
check_S_button_5:

	
	jnb S_BUTTON, change_timeT_dec_5

	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB5, timeT_done_5 ; if not still pressed then skip 
	jb PB5, $

	mov a, r_time
	add a, #1
	da a
	mov r_time, a
	
timeT_done_5:
	ljmp Forever

change_timeT_dec_5:
	jb PB5, timeT_done_5
	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB5, timeT_done_5 ; if not still pressed then skip 
	jb PB5, $
	
	mov a, r_time
	add a, #0x99
	da a 
	mov r_time, a
	
	ljmp Forever
	
;PB4 CHECK
check_S_button_4:

	
	jnb S_BUTTON, change_timeT_dec_4

	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB4, timeT_done_4 ; if not still pressed then skip 
	jb PB4, $

	mov a, r_temp
	add a, #1
	da a
	mov r_temp, a
	
timeT_done_4:
	ljmp Forever

change_timeT_dec_4:
	jb PB4, timeT_done_4
	;Debounce delay 
	Wait_Milli_Seconds(#75)
	jb PB4, timeT_done_4 ; if not still pressed then skip 
	jb PB4, $
	
	mov a, r_temp
	add a, #0x99
	da a 
	mov r_temp, a
	
	ljmp Forever
	
END
	
