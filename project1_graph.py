import numpy as np
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, serial, smtplib, threading
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from matplotlib.collections import LineCollection

xsize = 150  # Initial range for the x-axis
log_file = "temperature_log.txt"  # Log file name

# Temperature thresholds
state1_val = 50
state2_val = 100
state3_val = 150
state4_val = 170
state5_val = 210
email_trigger_temp = 217 # Email trigger threshold, change based on what value want to email at

# Email Configuration, adjust this based on your mailtrap host info
smtp_server = "bulk.smtp.mailtrap.io"
port = 587
login = "api"  # Mailtrap login
password = "91f13d766ef5fe08540e0ec581c2c181"  # Mailtrap password
sender_email = "hello@demomailtrap.com"
#adjust who will recieve email here
receiver_email = "santoneyyan3@gmail.com"


email_sent = False  # Flag to ensure only one email is sent

#email sending function
def send_email():
    """Send an email when the temperature exceeds 217°C and attach the log file."""
    global email_sent
    if email_sent:
        return

    email_sent = True  # Set flag before sending to avoid duplicates

    # Create an email message with proper UTF-8 encoding
    msg = MIMEMultipart()
    msg["From"] = sender_email
    msg["To"] = receiver_email
    msg["Subject"] = "🔥 Temperature Alert! Oven Over 217°C! Reflow has occurred🔥"

    # Email body, adjust as necessary
    body = "Alert. Oven Temperature has reached 217°C. Cooling will begin soon and board is fully cooked. See the attached log file for more info on temperature readings."
    msg.attach(MIMEText(body, "plain", "utf-8"))  # Set encoding to UTF-8

    # Attach the log file
    try:
        with open(log_file, "rb") as attachment:
            part = MIMEBase("application", "octet-stream")
            part.set_payload(attachment.read())

        encoders.encode_base64(part)
        part.add_header("Content-Disposition", f"attachment; filename={log_file}")
        msg.attach(part)

        # Send the email
        with smtplib.SMTP(smtp_server, port) as server:
            server.starttls()
            server.login(login, password)
            server.sendmail(sender_email, receiver_email, msg.as_string())

#check message to see if email was sent or if error
        print("✅ Email with log file sent successfully.")
    except Exception as e:
        print(f"❌ Email failed: {e}")

# Configure serial port
ser = serial.Serial(
    port='COM8',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)
ser.isOpen()

# Ensure log file is cleared at the start
open(log_file, "w").close()

# Data generator
def data_gen():
    global email_sent
    #actual decoding of serial port and printing 
    t = data_gen.t
    while True:
        try:
            strin = ser.readline()
            decoded_string = strin.decode('utf-8').strip()  # Remove newline characters
            val = float(decoded_string)  # Convert to float
            print(f"Received: {val}°C")  # Debug print

            # Save to log file, inputs readings into the text file
            with open(log_file, "a") as f:
                f.write(f"{t}, {val}\n")

            # If temp exceeds 217°C for the first time, send email with log file
            if val > email_trigger_temp and not email_sent:
                threading.Thread(target=send_email, daemon=True).start()

            yield t, val
            t += 1
            #error check 
        except ValueError:
            print("⚠️ Warning: Invalid data received. Skipping.")

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
        return 'k'  # Black for lower temps

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
#everything below is for graph
data_gen.t = -1
fig, ax = plt.subplots()
fig.canvas.mpl_connect('close_event', on_close_figure)

ax.set_ylim(0, 300)
ax.set_xlim(0, xsize)  # Fixed left boundary
ax.grid()
ax.set_title("Oven Temperature vs. Time")
ax.set_xlabel("Time (t/500 ms)")
ax.set_ylabel("Temperature (°C)")
xdata, ydata = [], []

# Initialize line collection
line_collection = LineCollection([], linewidth=2)
ax.add_collection(line_collection)

# Animation
ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()
