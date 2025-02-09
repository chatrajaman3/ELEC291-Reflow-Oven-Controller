; main.asm
;
; Assembly code for reflow oven controller.
; Written for N76E003 (8051 derivative).
;
; Authored by Eric Feng, Warrick Lo, Santo Neyyan,
; Chathil Rajamanthree, Rishi Upath, Colin Yeung.

; N76E003 pinout
; ------------------------------------------------------------------------------
; PWM2/IC6/T0/AIN4/P0.5		-|1  20|-	P0.4/AIN5/STADC/PWM3/IC3
; TXD/AIN3/P0.6			-|2  19|-	P0.3/PWM5/IC5/AIN6
; RXD/AIN2/P0.7			-|3  18|-	P0.2/ICPCK/OCDCK/RXD_1/[SCL]
; RST/P2.0			-|4  17|-	P0.1/PWM4/IC4/MISO
; INT0/OSCIN/AIN1/P3.0		-|5  16|-	P0.0/PWM3/IC3/MOSI/T1
; INT1/AIN0/P1.7		-|6  15|-	P1.0/PWM2/IC2/SPCLK
; GND				-|7  14|-	P1.1/PWM1/IC1/AIN7/CLO
; [SDA]/TXD_1/ICPDA/OCDDA/P1.6	-|8  13|-	P1.2/PWM0/IC0
; VDD				-|9  12|-	P1.3/SCL/[STADC]
; PWM5/IC7/SS/P1.5		-|10 11|-	P1.4/SDA/FB/PWM1
; ------------------------------------------------------------------------------

; ADC channel mappings.
;
; AIN1	P3.0	Ambient temperature
; AIN4	P0.5	Push button

; Mappings for push buttons.
;
; P1.5	SHIFT modifier
; P1.6	Start/stop oven
;
; PB0	Unassigned
; PB1	Unassigned
; PB2	Unassigned
; PB3	Unassigned
; PB4	Reflow temperature
; PB5	Reflow time
; PB6	Soak temperature
; PB7	Soak time

$NOLIST
$MODN76E003
$LIST

; Microcontroller system frequency in Hz.
CLK EQU 16600000
; Baud rate of UART in bit/s.
BAUD EQU 115200
; Timer 0 and 1 reload values.
TIMER0_RELOAD EQU (0x10000-(CLK/1000))
TIMER1_RELOAD EQU (0x100-(CLK/(16*BAUD)))

; Start/stop oven.
OVEN_BUTTON EQU P1.5
; Shift button.
S_BUTTON EQU P1.6

; LCD I/O pins.
LCD_E EQU P1.4
LCD_RS EQU P1.3
LCD_D4 EQU P0.0
LCD_D5 EQU P0.1
LCD_D6 EQU P0.2
LCD_D7 EQU P0.3

; State machine states representations.
STATE_INIT EQU 0b00000001
STATE_IDLE EQU 0b00000010
STATE_PREHEAT EQU 0b00000100
STATE_SOAK EQU 0b00001000
STATE_RAMP EQU 0b00010000
STATE_REFLOW EQU 0b00100000
STATE_COOLING EQU 0b01000000
STATE_EMERGENCY EQU 0b10000000

; State machine transition conditions.
; [Temporary] Represent values in hex.
; Preheat to soak condition is set by user (default: 150 deg C, X s).
; Reflow to cooling condition is set by user (default: Y deg C, 60 s).
COND_SOAK_TO_RAMP EQU 0x60 ; 60 s - 120 s.
COND_RAMP_TO_REFLOW EQU 0x217 ; 217 deg C.

ORG 0x0000
	LJMP MAIN

$NOLIST
$include(LCD_4bit.inc)
$include(math32.inc)
$LIST

; Bit-addressable memory space.
DSEG at 0x20

; State machine related variables. Refer to defined macros.

state: DS 1

DSEG at 0x30

; Variables for 32-bit integer arithmetic.

x: DS 4
y: DS 4

; User-controlled variables.

soak_temp: DS 1
soak_time: DS 1
reflow_temp: DS 1
reflow_time: DS 1

; BCD numbers for LCD.

bcd: DS 5

BSEG

mf: DBIT 1

; These eight bit variables store the value of the pushbuttons after
; calling "ADC_to_PB" below.
PB0: DBIT 1
PB1: DBIT 1
PB2: DBIT 1
PB3: DBIT 1
PB4: DBIT 1
PB5: DBIT 1
PB6: DBIT 1
PB7: DBIT 1

process_start: DBIT 1

CSEG

; LCD display strings.

blank:
	DB '                ', 0
temp:
	DB 'To=   C  Tj=  C ', 0
parameters:
	DB 's   ,   r   ,   ', 0
on:
	DB 'Oven on ', 0
off:
	DB 'Oven off', 0

; Utility subroutines.

DELAY MAC MS
	PUSH AR2
	MOV R2, %0
	LCALL Wait_Milliseconds
	POP AR2
ENDMAC

Wait_1_Millisecond:
	CLR TR0 ; Stop timer 0.
	CLR TF0 ; Clear overflow flag.
	MOV TH0, #high(TIMER0_RELOAD)
	MOV TL0, #low(TIMER0_RELOAD)
	SETB TR0
	JNB TF0, $ ; Wait for overflow.
	RET

; Wait the number of milliseconds in R2.
Wait_Milliseconds:
	LCALL Wait_1_Millisecond
	DJNZ R2, Wait_Milliseconds
	RET

; Initialisation subroutine.

INIT:
	; Configure all the pins for biderectional I/O.
	MOV P3M1, #0x00
	MOV P3M2, #0x00
	MOV P1M1, #0x00
	MOV P1M2, #0x00
	MOV P0M1, #0x00
	MOV P0M2, #0x00

	ORL CKCON, #0b00010000 ; CLK is the input for timer 1.
	ORL PCON, #0b00001000 ; Bit SMOD=1, double baud rate.
	MOV SCON, #0b01010010
	ANL T3CON, #0b11011111
	ANL TMOD, #0b00001111 ; Clear the configuration bits for timer 1.
	ORL TMOD, #0b00100000 ; Timer 1 Mode 2.
	MOV TH1, #TIMER1_RELOAD ; TH1 = TIMER1_RELOAD.
	SETB TR1

	; [TEMPORARY] Initialise temperatures/times.
	MOV soak_time, #0x05
	MOV soak_temp, #0x05
	MOV reflow_time, #0x05
	MOV reflow_temp, #0x05

	; Using timer 0 for delay functions.
	CLR TR0 ; Stop timer 0.
	ORL CKCON, #0b00001000 ; CLK is the input for timer 0.
	ANL TMOD, #0b11110000 ; Clear the configuration bits for timer 0.
	ORL TMOD, #0b00000001 ; Timer 0 in Mode 1: 16-bit timer.

	; Initialize and start the ADC.

	; Configure AIN0 (P1.7) as input.
	ORL P1M1, #0b10000000
	ANL P1M2, #0b01111111

	; Configure AIN1 (P3.0) as input.
	ORL P3M1, #0b00000001
	ANL P3M2, #0b11111110

	; Switch to ADC and use channel 0.
	ORL ADCCON1, #0b00000001
	LCALL Switch_to_AIN0

	RET

; ADC channel switching subroutines.

Switch_to_AIN0:
	; Select ADC channel 0.
	ANL ADCCON0, #0b1111_0000
	ORL ADCCON0, #0b0000_0000
	; Enable P1.7 as analog and everything else as digital.
	MOV AINDIDS, #0b0000_0001
	RET

Switch_to_AIN1:
	; Select ADC channel 1.
	ANL ADCCON0, #0b1111_0000
	ORL ADCCON0, #0b0000_0001
	; Enable P3.0 as analog and everything else as digital.
	MOV AINDIDS, #0b0000_0010
	RET

Switch_to_AIN4:
	; Select ADC channel 4.
	ANL ADCCON0, #0b1111_0000
	ORL ADCCON0, #0b0000_0100
	; Enable P0.5 as analog and everything else as digital.
	MOV AINDIDS, #0b0001_0000
	RET

; Check push buttons.

CHECK_PUSH_BUTTON MAC PB, NEXT, HEX
Check_%0:
	CLR C
	MOV A, ADCRH
	SUBB A, %2
	JC Check_%1
	CLR %0
	RET
ENDMAC

ADC_to_PB:
	LCALL Switch_to_AIN4

	; Wait for ADC to finish A/D conversion.
	CLR ADCF
	SETB ADCS
	JNB ADCF, $

	; Initialise buttons.
	SETB OVEN_BUTTON
	SETB S_BUTTON
	SETB PB0
	SETB PB1
	SETB PB2
	SETB PB3
	SETB PB4
	SETB PB5
	SETB PB6
	SETB PB7

	CHECK_PUSH_BUTTON(PB7, PB6, #0xF0)
	CHECK_PUSH_BUTTON(PB6, PB5, #0xD0)
	CHECK_PUSH_BUTTON(PB5, PB4, #0xB0)
	CHECK_PUSH_BUTTON(PB4, PB3, #0x90)
	CHECK_PUSH_BUTTON(PB3, PB2, #0x70)
	CHECK_PUSH_BUTTON(PB2, PB1, #0x50)
	CHECK_PUSH_BUTTON(PB1, PB0, #0x30)
	CHECK_PUSH_BUTTON(PB0, PB_End, #0x10)
Check_PB_End:
	RET

CHANGE_VALUE MAC VALUE, PB
Change_%0:
	DELAY(#125)
	JB %1, Change_%0_End
	JB %1, $

	MOV A, %0
	JNB S_BUTTON, Decrement_%0
Increment_%0:
	ADD A, #1
	LJMP Change_%0_End
Decrement_%0:
	ADD A, #0x99
Change_%0_End:
	DA A
	MOV %0, A
	LJMP FOREVER
ENDMAC

CHANGE_VALUE(Reflow_Temp, PB4)
CHANGE_VALUE(Reflow_Time, PB5)
CHANGE_VALUE(Soak_Temp, PB6)
CHANGE_VALUE(Soak_Time, PB7)

MAIN:
	MOV SP, #0x7F
	LCALL INIT
	LCALL LCD_4BIT

	; [TEMPORARY?] Initialise oven_on_flag.
	CLR process_start

	; Display logic.
	Set_Cursor(1, 1)
	Send_Constant_String(#temp)
	Set_Cursor(2, 1)
	Send_Constant_String(#parameters)

	Set_Cursor(1,2)

FOREVER:
	; Convert ADC signal to push button bitfield.
	LCALL ADC_to_PB

	; Display variables.
	Set_Cursor(2, 2)
	Display_BCD(soak_time)
	Set_Cursor(2, 6)
	Display_BCD(soak_temp)
	Set_Cursor(2, 10)
	Display_BCD(reflow_time)
	Set_Cursor(2, 14)
	Display_BCD(reflow_temp)

	; Wait 50 ms between readings.
	DELAY(#50)

	; Check if oven on/off button is pressed.
	JB OVEN_BUTTON, FOREVER_L0
	DELAY(#100)
	JB OVEN_BUTTON, FOREVER_L0
	JNB OVEN_BUTTON, $
	CPL process_start
FOREVER_L0:
	JB process_start, Oven_On

Idle:
	JNB PB4, Change_Reflow_Temp_Interim
	JNB PB5, Change_Reflow_Time_Interim
	JNB PB6, Change_Soak_Temp_Interim
	JNB PB7, Change_Soak_Time_Interim

	LJMP FOREVER

Change_Reflow_Temp_Interim:
	LJMP Change_Reflow_Temp
Change_Reflow_Time_Interim:
	LJMP Change_Reflow_Time
Change_Soak_Temp_Interim:
	LJMP Change_Soak_Temp
Change_Soak_Time_Interim:
	LJMP Change_Soak_Time

Oven_On:
	LCALL Switch_to_AIN1

	; Wait for ADC to finish A/D conversion.
	CLR ADCF
	SETB ADCS
	JNB ADCF, $

	; Read the ADC result and store in [R1, R0].
	MOV A, ADCRH
	SWAP A
	PUSH ACC
	ANL A, #0b00001111
	MOV R1, A
	POP ACC
	ANL A, #0b11110000
	ORL A, ADCRL
	MOV R0, A

	; Convert to voltage.
	MOV x+0, R0
	MOV x+1, R1
	MOV x+2, #0
	MOV x+3, #0
	Load_y(50300) ; VCC voltage (5.03 V).
	LCALL mul32
	Load_y(4095) ; 2^12 - 1.
	LCALL div32

	; Convert to temperature.
	load_y(27300)
	LCALL sub32
	load_y(100)
	LCALL mul32

	; Convert to BCD and display.
	LCALL hex2bcd

	Set_Cursor(1, 13)
	Display_BCD(bcd+2)

	; Wait 500 ms between conversions.
	DELAY(#250)
	DELAY(#250)

	LJMP FOREVER

END
