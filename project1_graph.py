import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math

import serial


# configure the serial port
ser = serial.Serial(
port='COM5',
baudrate=115200,
parity=serial.PARITY_NONE,
stopbits=serial.STOPBITS_TWO,
bytesize=serial.EIGHTBITS
)
ser.isOpen()

arr = []
xdata, ydata = [], []
xsize=100
max_val = float('-inf')
min_val = float('inf')


def data_gen():
    t = 0
    while True:
        strin = ser.readline()
        decoded_string = strin.decode('utf-8') # Remove newline characters
        print("Received:", decoded_string)
        val = float(decoded_string)  # Parse to float
        
        arr.append(val)  # Store the received value
        yield t, val
        t += 1

# Update function for the animation
def run(data):
    global max_val
    global min_val
    t,y = data
    if t>-1:
        xdata.append(t)
        ydata.append(y)

        if y > max_val:
            max_val = y
            max_text.set_text(f"Max: {max_val:.2f}")  # Update text
            max_text.set_position((t, y))  # Move the text to the new max point
        
        if y < min_val:
            min_val = y
            min_text.set_text(f"Min: {min_val:.2f}")  # Update text
            min_text.set_position((t, y))  # Move the text to the new min point


        if t>xsize: # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        line.set_data(xdata, ydata)

    return line, max_text, min_text

def on_close_figure(event):
    sys.exit(0)




   


# Set up the plot
data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
line, = ax.plot([], [], lw=2, color='red')
ax.set_ylim(0, 280)  # Adjust Y-axis range as needed
ax.set_xlim(0, xsize)  # Initial X-axis range
ax.grid()

ax.set_title("Temperature vs. Time")  # Title of the plot
ax.set_xlabel("Time (t/500 ms)")           # Label for the X-axis
ax.set_ylabel("Temperature (\N{DEGREE SIGN}C)")              # Label for the Y-axis



max_text = ax.text(0, 0, "", fontsize=10, color="red")

min_text = ax.text(0, 0, "", fontsize=10, color="blue")


# Animation setup
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)

# Display the plot
plt.show()