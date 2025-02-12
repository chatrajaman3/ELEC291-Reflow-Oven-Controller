import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, serial
from matplotlib.collections import LineCollection

xsize = 50  # Initial range for the x-axis

# Temperature thresholds for different states
state1_val = 50
state2_val = 100
state3_val = 150
state4_val = 170
state5_val = 210

# Configure the serial port
ser = serial.Serial(
    port='COM7',
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
    if value >= state5_val:
        return 'r'  # Red 
    elif value >= state4_val:
        return 'm'  # Magenta
    elif value >= state3_val:
        return 'g'  # Green
    elif value >= state2_val:
        return 'b'  # Blue
    elif value >= state1_val:
        return 'c'  # Cyan
    else:
        return 'k'  # Black for any temp that isn't a state

# Function to update the graph
def run(data):
    t, y = data
    xdata.append(t)
    ydata.append(y)

    # Shift x-axis dynamically while keeping left at 0
    ax.set_xlim(0, max(t, xsize))  

    

    # Create segments with colors
    points = np.array([xdata, ydata]).T.reshape(-1, 1, 2)
    segments = np.concatenate([points[:-1], points[1:]], axis=1)
    colors = [get_color(val) for val in ydata[:-1]]

    # Update line collection instead of redrawing everything
    line_collection.set_segments(segments)
    line_collection.set_color(colors)

    return line_collection, 

# Event handler for closing the figure
def on_close_figure(event):
    sys.exit(0)

# Initialize variables
data_gen.t = -1
fig, ax = plt.subplots()
fig.canvas.mpl_connect('close_event', on_close_figure)

ax.set_ylim(0, 300)
ax.set_xlim(0, xsize)  # Fixed left boundary
ax.grid()
xdata, ydata = [], []

# Initialize line collection
line_collection = LineCollection([], linewidth=2)
ax.add_collection(line_collection)


# Animation
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
