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

; Mappings for push buttons.
;
; P1.6	SHIFT modifier
; PB0	Unassigned
; PB1	Unassigned
; PB2	Unassigned
; PB3	Start/stop oven
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
TIMER0_RELOAD_1MS EQU (0x10000-(CLK/1000))
TIMER1_RELOAD EQU (0x100-(CLK/(16*BAUD)))

; Shift button.
S_BUTTON EQU P1.6

; LCD I/O pins.
LCD_RS EQU P1.3
LCD_E EQU P1.4
LCD_D4 EQU P0.0
LCD_D5 EQU P0.1
LCD_D6 EQU P0.2
LCD_D7 EQU P0.3

; FSM states.
STATE_INIT EQU 0b00000001
STATE_IDLE EQU 0b00000010
STATE_PREHEAT EQU 0b00000100
STATE_SOAK EQU 0b00001000
STATE_RAMP EQU 0b00010000
STATE_REFLOW EQU 0b00100000
STATE_COOLING EQU 0b01000000
STATE_EMERGENCY EQU 0b10000000

; FSM state transition conditions.
; [Temporary] Represent values in hex.
; Preheat to soak condition is set by user (default: 150 deg C, X s).
; Reflow to cooling condition is set by user (default: Y deg C, 60 s).
COND_SOAK_TO_RAMP EQU 0x60 ; 60 s - 120 s.
COND_RAMP_TO_REFLOW EQU 0x217 ; 217 deg C.

ORG 0x0000
	LJMP main

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

x:   ds 4
y:   ds 4
z:   ds 4

VAL_LM4040: ds 2
VAL_LM335: ds 2

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

; code for reading adc
Read_ADC:
	clr ADCF
	setb ADCS ;  ADC start trigger signal
    jnb ADCF, $ ; Wait for conversion complete
    
    ; Read the ADC result and store in [R1, R0]
    mov a, ADCRL
    anl a, #0x0f
    mov R0, a
    mov a, ADCRH   
    swap a
    push acc
    anl a, #0x0f
    mov R1, a
    pop acc
    anl a, #0xf0
    orl a, R0
    mov R0, A
	ret





Wait_1_Millisecond:
	CLR TR0 ; Stop timer 0.
	CLR TF0 ; Clear overflow flag.
	MOV TH0, #high(TIMER0_RELOAD_1MS)
	MOV TL0, #low(TIMER0_RELOAD_1MS)
	SETB TR0
	JNB TF0, $ ; Wait for overflow.
	RET

; Wait the number of milliseconds in R2.
Wait_Milliseconds:
	LCALL Wait_1_Millisecond
	DJNZ R2, Wait_Milliseconds
	RET

; Initialisation-related subroutines.

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

	; Configure AIN0 (P1.7 and 1.1) as input.
	ORL P1M1, #0b1000_0010
	ANL P1M2, #0b0111_1101

	; Configure AIN1 (P3.0) as input.
	ORL P3M1, #0b0000_0001
	ANL P3M2, #0b1111_1110

	; Configure AIN4 (P0.5) as input.
	ORL P0M1, #0b0010_0000
	ANL P0M2, #0b1101_1111

	; Switch to ADC and use channel 0.
	;ORL ADCCON1, #0b0000_0001
	;LCALL Switch_to_AIN0
	mov AINDIDS, #0x00 ; Disable all analog inputs
	orl AINDIDS, #0b10010011 ; Activate AIN0 and AIN7 and AIN1 and AIN4 analog inputs
	orl ADCCON1, #0x01 ; Enable ADC

	RET

ADC_to_PB:
	; Initialize and start the ADC.
	;ANL ADCCON0, #0b11110000
	;ORL ADCCON0, #0b00000000 ; Select channel 7.
	; AINDIDS select if some pins are analog inputs or digital I/O.
	;MOV AINDIDS, #0b00000000 ; Disable all analog inputs.
	;ORL AINDIDS, #0b00000010 ; P1.7 is analog input.
	;ORL ADCCON1, #0b00000001 ; Enable ADC.
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x04 ; Select channel 4

	CLR ADCF
	SETB ADCS ; ADC start trigger signal.
	JNB ADCF, $ ; Wait for conversion complete.

	SETB PB0
	SETB PB1
	SETB PB2
	SETB PB3
	SETB PB4
	SETB PB5
	SETB PB6
	SETB PB7

	; Initilize shift button.
	SETB S_BUTTON

	; Check push buttons (order from 7 to 0).

Check_Push_Button MAC
Check_%0:
	CLR C
	MOV A, ADCRH
	SUBB A, %2
	JC Check_%1
	CLR %0
	RET
ENDMAC

Check_Push_Button(PB7, PB6, #0xF0)
Check_Push_Button(PB6, PB5, #0xD0)
Check_Push_Button(PB5, PB4, #0xB0)
Check_Push_Button(PB4, PB3, #0x90)
Check_Push_Button(PB3, PB2, #0x70)
Check_Push_Button(PB2, PB1, #0x50)
Check_Push_Button(PB1, PB0, #0x30)
Check_Push_Button(PB0, PB_End, #0x10)
Check_PB_End:
	RET

; ADC_to_PB_L7:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0xF0
; 	JC ADC_to_PB_L6
; 	CLR PB7
; 	RET
; ADC_to_PB_L6:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0xD0
; 	JC ADC_to_PB_L5
; 	CLR PB6
; 	RET
; ADC_to_PB_L5:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0xB0
; 	JC ADC_to_PB_L4
; 	CLR PB5
; 	RET
; ADC_to_PB_L4:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0x90
; 	JC ADC_to_PB_L3
; 	CLR PB4
; 	RET
; ADC_to_PB_L3:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0x70
; 	JC ADC_to_PB_L2
; 	CLR PB3
; 	RET
; ADC_to_PB_L2:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0x50
; 	JC ADC_to_PB_L1
; 	CLR PB2
; 	RET
; ADC_to_PB_L1:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0x30
; 	JC ADC_to_PB_L0
; 	CLR PB1
; 	RET
; ADC_to_PB_L0:
; 	CLR C
; 	MOV A, ADCRH
; 	SUBB A, #0x10
; 	JC ADC_to_PB_End
; 	CLR PB0
; ADC_to_PB_End:
; 	RET

Change_Value MAC
Change_%0:
	JNB S_BUTTON, Decrement_%0
Increment_%0:
	Wait_Milli_Seconds(#75)
	JB %1, Forever_Interim
	JB %1, $

	MOV A, %0
	ADD A, #1
	DA A
	MOV %0, A
	LJMP FOREVER
Decrement_%0:
	JB %1, Forever_Interim
	Wait_Milli_Seconds(#75)
	JB %1, Forever_Interim
	JB %1, $

	MOV A, %0
	ADD A, #0x99
	DA A
	MOV %0, A
	LJMP FOREVER
ENDMAC

Change_Value(Reflow_Temp, PB4)
Change_Value(Reflow_Time, PB5)

Forever_Interim:
	LJMP FOREVER

Change_Value(Soak_Temp, PB6)
Change_Value(Soak_Time, PB7)

MAIN:
	MOV SP, #0x7F
	LCALL INIT
	LCALL LCD_4BIT

	; [TEMPORARY?] Initialize oven_on_flag.
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
	MOV R2, #50
	LCALL Wait_Milliseconds

	; Check if oven on/off button is pressed.
	JNB PB3, Oven_Button_Check

Process_Start_Check:
	; Check process flag. If not set, keep checking for button presses.
	JB process_start, Process_Continue

	; Select push buttons as input for ADC.

	anl ADCCON0, #0xF0
	orl ADCCON0, #0x04 ; Select channel 4

	JNB PB4, Change_Reflow_Temp_Interim
	JNB PB5, Change_Reflow_Time_Interim
	JNB PB6, Change_Soak_Temp_Interim
	JNB PB7, Change_Soak_Time_Interim

	LJMP FOREVER

; Activated on PB3 (oven toggle button) press.
Oven_Button_Check:
	Wait_Milli_Seconds(#75)
	JB PB3, Process_Start_Check
	JB PB3, $
	CPL process_start
	LJMP Process_Start_Check

Change_Reflow_Temp_Interim:
	LJMP Change_Reflow_Temp
Change_Reflow_Time_Interim:
	LJMP Change_Reflow_Time
Change_Soak_Temp_Interim:
	LJMP Change_Soak_Temp
Change_Soak_Time_Interim:
	LJMP Change_Soak_Time

Process_Continue:
	; Read the 2.08V LM4040 voltage connected to AIN0 on pin 6
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x00 ; Select channel 0

	lcall Read_ADC
	; Save result for later use
	mov VAL_LM4040+0, R0
	mov VAL_LM4040+1, R1

;lm 335
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x01 ; Select channel 1
	
	lcall Read_ADC
	mov VAL_LM335+0, R0
	mov VAL_LM335+1, R1

	; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	; Pad other bits with zero
	mov x+2, #0
	mov x+3, #0
	;Load_y(40959) ; The MEASURED voltage reference: 4.0959V, with 4 decimal places
	Load_y(40959)
	lcall mul32
	
	
	; Retrive the ADC LM4040 value
	mov y+0, VAL_LM4040+0
	mov y+1, VAL_LM4040+1
	; Pad other bits with zero
	mov y+2, #0
	mov y+3, #0
	lcall div32
	
	;convert to temp, for lm 335
	Load_y(27300)
	lcall sub32
	Load_y(100)
	lcall mul32
	
	mov z+0, x+0         ; Store LM335 temperature result in z
	mov z+1, x+1
	mov z+2, x+2
	mov z+3, x+3
	
	
	lcall hex2bcd
	; display ambient temp on top right
	Set_Cursor(1, 13)
	Display_BCD(bcd+2)

	;Display_char(#'.')
	;Display_BCD(bcd+1)
	;Display_BCD(bcd+0)
	

	; Read the signal connected to AIN7, op amp
	anl ADCCON0, #0xF0
	orl ADCCON0, #0x07 ; Select channel 7
	lcall Read_ADC
    
    ; Convert to voltage
	mov x+0, R0
	mov x+1, R1
	; Pad other bits with zero
	mov x+2, #0
	mov x+3, #0
	;Load_y(40959) ; The MEASURED voltage reference: 4.0959V, with 4 decimal places
	Load_y(40959)
	lcall mul32

	
	; Retrive the ADC LM4040 value
	mov y+0, VAL_LM4040+0
	mov y+1, VAL_LM4040+1
	; Pad other bits with zero
	mov y+2, #0
	mov y+3, #0
	lcall div32
	

	Load_y(1474)
	lcall mul32
	Load_y(464200)
	lcall div32
	Load_y(1000)
	lcall mul32
	lcall mul32
	Load_y(41)
	lcall div32
	
	mov y+0, z+0         ; y = LM335 temperature (stored in z)
	mov y+1, z+1
	mov y+2, z+2
	mov y+3, z+3

	lcall add32
	

	

	; Convert to BCD and display
	lcall hex2bcd
	; display manually
	Set_Cursor(1, 3)
	Display_BCD(bcd+3)
	Display_BCD(bcd+2)


	; Wait 500 ms between conversions.
	MOV R2, #250
	LCALL Wait_Milliseconds
	MOV R2, #250
	LCALL Wait_Milliseconds

	LJMP FOREVER

; Increment/decrement temperatures and times.
;
; General algorithm:
;	- Check if SHIFT button is pressed. If pressed:
;		- Wait for software debounce;
;		- Add 1 to soak/reflow temperature/time;
;		- Convert to a BCD number;
;		- Jump to start of program loop.
;	- Otherwise (SHIFT is not pressed):
;		- Wait for software debounce;
;		- Add 99 to soak/reflow temperature/time;
;		- Convert to a BCD number. Adding 99 is subtracting 1 with BCDs;
;		- Jump to start of program loop.

; check_S_button_7:
; 	jnb S_BUTTON, Decrement_Soak_Time
; Increment_Soak_Time:
; 	Wait_Milli_Seconds(#75)
; 	jb PB7, Forever_Interim
; 	jb PB7, $

; 	mov a, soak_time
; 	add a, #1
; 	da a
; 	mov soak_time, a
; 	LJMP Forever
; Decrement_Soak_Time:
; 	jb PB7, Forever_Interim
; 	Wait_Milli_Seconds(#75)
; 	jb PB7, Forever_Interim
; 	jb PB7, $

; 	mov a, soak_time
; 	add a, #0x99
; 	da a
; 	mov soak_time, a
; 	ljmp Forever

; check_S_button_6:
; 	jnb S_BUTTON, Decrement_Soak_Temp
; Increment_Soak_Temp:
; 	Wait_Milli_Seconds(#75)
; 	jb PB6, Forever_Interim
; 	jb PB6, $

; 	mov a, soak_temp
; 	add a, #1
; 	da a
; 	mov soak_temp, a
; 	LJMP Forever
; Decrement_Soak_Temp:
; 	jb PB6, Forever_Interim
; 	Wait_Milli_Seconds(#75)
; 	jb PB6, Forever_Interim
; 	jb PB6, $

; 	mov a, soak_temp
; 	add a, #0x99
; 	da a
; 	mov soak_temp, a
; 	; ljmp Forever

; Forever_Interim:
; 	LJMP Forever

; check_S_button_5:
; 	jnb S_BUTTON, Decrement_Reflow_Time
; Increment_Reflow_Time:
; 	Wait_Milli_Seconds(#75)
; 	jb PB5, Forever_Interim
; 	jb PB5, $

; 	mov a, reflow_time
; 	add a, #1
; 	da a
; 	mov reflow_time, a
; 	LJMP Forever
; Decrement_Reflow_Time:
; 	jb PB5, Forever_Interim
; 	Wait_Milli_Seconds(#75)
; 	jb PB5, Forever_Interim
; 	jb PB5, $

; 	mov a, reflow_time
; 	add a, #0x99
; 	da a
; 	mov reflow_time, a
; 	ljmp Forever

; check_S_button_4:
; 	jnb S_BUTTON, Decrement_Reflow_Temp
; Increment_Reflow_Temp:
; 	Wait_Milli_Seconds(#75)
; 	jb PB4, Forever_Interim
; 	jb PB4, $

; 	mov a, reflow_temp
; 	add a, #1
; 	da a
; 	mov reflow_temp, a
; 	LJMP Forever
; Decrement_Reflow_Temp:
; 	jb PB4, Forever_Interim
; 	;Debounce delay
; 	Wait_Milli_Seconds(#75)
; 	jb PB4, Forever_Interim
; 	jb PB4, $

; 	mov a, reflow_temp
; 	add a, #0x99
; 	da a
; 	mov reflow_temp, a
; 	ljmp Forever

END
