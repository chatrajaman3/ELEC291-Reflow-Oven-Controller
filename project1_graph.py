import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, serial
from matplotlib.collections import LineCollection


xsize = 200  # Set a fixed range for the x-axis

#temp values that need to be reached for diff states
state1_val = 23 #state 1 - ramp-to-soak -....
state2_val = 25 #state 2 - soak - ....
state3_val = 27 #state 3 - ramp-to-peak - ....
state4_val = 29 #state 4 - reflow - ....
state5_val = 31 #state 5 - cool - ....


# Configure the serial port
ser = serial.Serial(
    port='COM8',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)
ser.isOpen()

# Data generator
def data_gen():
    t = data_gen.t
    while True:
        t += 1
        ser_read = ser.readline()
        ser_decode = ser_read.decode('utf-8').strip()
        val = float(ser_decode)
        yield t, val

# Function to determine segment colors
def get_color(value):

    #important to write in decreasing order of temp for each state -> checks largest temp first then goes down
    #adjust to temp of states as necessary
    if value >= state5_val:
        return 'r'  # Red 
    elif value >= state4_val:
        return 'm'  # magenta
    elif value >= state3_val:
        return 'g'  # green
    elif value >= state2_val:
        return 'b'  # blue
    elif value >= state1_val:
        return 'c'  # cyan
    else:
        return 'k'  # Black for any temp that isnt a state 

# Function to update the graph
def run(data):
    t, y = data
    if t > -1:
        xdata.append(t)
        ydata.append(y)

        # Update text only for the current state
        if y >= state5_val:
            state5_text.set_text(f"State 5: {y:.2f}")
            state5_text.set_position((t - 5, y + 2))
            state1_text.set_text("")
            state2_text.set_text("")
            state3_text.set_text("")
            state4_text.set_text("")   

        elif y >= state4_val:
            state4_text.set_text(f"State 4: {y:.2f}")
            state4_text.set_position((t - 5, y + 2))
            state1_text.set_text("")
            state2_text.set_text("")
            state3_text.set_text("") 
            state5_text.set_text("")  
        elif y >= state3_val:
            state3_text.set_text(f"State 3: {y:.2f}")
            state3_text.set_position((t - 5, y + 2))
            state1_text.set_text("")
            state2_text.set_text("")
            state4_text.set_text("")  
            state5_text.set_text("")  
        elif y >= state2_val:
            state2_text.set_text(f"State 2: {y:.2f}")
            state2_text.set_position((t - 5, y + 2))
            state1_text.set_text("")
            state3_text.set_text("")
            state4_text.set_text("")  
            state5_text.set_text("")  
        elif y >= state1_val:
            state1_text.set_text(f"State 1: {y:.2f}")
            state1_text.set_position((t - 5, y + 2))
            state2_text.set_text("")
            state3_text.set_text("")
            state4_text.set_text("")  
            state5_text.set_text("")  
        else:
            # Clear all state texts if below State 1
            state1_text.set_text("")
            state2_text.set_text("")
            state3_text.set_text("")
            state4_text.set_text("")  
            state5_text.set_text("")  


        # Create segments with colors
        points = np.array([xdata, ydata]).T.reshape(-1, 1, 2)
        segments = np.concatenate([points[:-1], points[1:]], axis=1)
        colors = [get_color(val) for val in ydata[:-1]]

        # Clear and update the line collection
        ax.clear()
        ax.set_ylim(0, 300)
        ax.set_xlim(0, xsize)  # Fixed starting range
        ax.grid()

        # Add updated plot elements
        lc = LineCollection(segments, colors=colors, linewidth=2)
        ax.add_collection(lc)
        ax.set_xlabel("Time (s)")
        ax.set_ylabel("Temperature (°C)")
        ax.set_title("Temperature in Oven")

        # Re-add the active text objects
        ax.add_artist(state1_text)
        ax.add_artist(state2_text)
        ax.add_artist(state3_text)
        ax.add_artist(state4_text)
        ax.add_artist(state5_text)
        

    return ax,

# Event handler for closing the figure
def on_close_figure(event):
    sys.exit(0)

# Initialize variables
data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
ax.set_ylim(0, 300)
ax.set_xlim(0, xsize)  # Fixed starting range
ax.grid()
xdata, ydata = [], []

# Create text objects at a fixed position initially
state1_text = ax.text(5, 80, "", fontsize=10, color="red")
state2_text = ax.text(5, 70, "", fontsize=10, color="magenta", ha="left")
state3_text = ax.text(5, 60, "", fontsize=10, color="green", ha="left")
state4_text = ax.text(5, 80, "", fontsize=10, color="blue")
state5_text = ax.text(5, 70, "", fontsize=10, color="cyan", ha="left")


# Animation
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()



