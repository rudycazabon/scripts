# Suspending Your Workstation
You can suspend a Linux workstation on a schedule using rtcwake with a cron job or systemd timer. To suspend, use sudo rtcwake -m [suspend_type] -s [seconds] to schedule a wake-up time. For a specific time, create a script and use crontab -e to run it.  

## Method 1: Using cron and rtcwake

This is a good option for simple, time-based schedules and works on most Linux systems. 
Create a script for a specific time:
Open a new file, for example, ~/suspend_at_time.sh, with a text editor.
Add the following script, replacing HH:MM with your desired suspend time (e.g., 23:00 for 11 PM):
Code

    #!/bin/bash
    # Suspend and wake at a specific time
    # Usage: suspend_at_time.sh HH:MM

    if [ $# -lt 1 ]; then
      echo "Usage: $(basename "$0") HH:MM"
      exit 1
    fi

    # Get the desired time in seconds from now
    DESIRED_TIMESTAMP=$(date +%s -d "$1")
    CURRENT_TIMESTAMP=$(date +%s)

    # If the time is in the past, schedule it for the next day
    if [ "$DESIRED_TIMESTAMP" -lt "$CURRENT_TIMESTAMP" ]; then
      DESIRED_TIMESTAMP=$((DESIRED_TIMESTAMP + 24 * 60 * 60))
    fi

    # Suspend using rtcwake (suspend-to-RAM)
    # Use -m 'standby' for less power saving but faster wake-up, or 'mem' for suspend-to-RAM
    sudo rtcwake -l -m mem -t "$DESIRED_TIMESTAMP" &
    echo "System will suspend. Wake up time set for $(date -d "@$DESIRED_TIMESTAMP")"

Make the script executable: chmod +x ~/suspend_at_time.sh. 
Schedule the script with cron:
Open the root user's crontab: sudo crontab -e. 
Add a line to run your script at your desired wake-up time. For example, to wake up at 7:30 AM:

```30 7 * * * /path/to/your/suspend_at_time.sh 07:30```

## Method 2: Using systemd timers
This is the modern way to handle scheduled tasks on systemd-based systems and is very powerful.

Create the service file:

```sudo systemctl edit --force --full suspend.service```

In the new file, add this content to create a service that will **WAKE** the system:

**Code**

    [Unit]
    Description=Wake from suspend

    [Service]
    Type=oneshot
    # Wake from suspend-then-hibernate (requires configuration in systemd-sleep.conf)
    ExecStart=/usr/bin/systemctl hibernate
    # You can also use systemctl suspend or systemctl hybrid-sleep

    [Install]
    WantedBy=multi-user.target

Create the timer file:

```sudo systemctl edit --force --full suspend.timer```

Add this content to schedule the service to run at a specific time (e.g., 7:30 AM daily):

**Code**

    [Unit]
    Description=Run suspend service every morning

    [Timer]
    # Wake up at 7:30 AM
    OnCalendar=*-*-* 07:30:00
    Persistent=true

    [Install]
    WantedBy=timers.target

Save and exit. This will create two new files: ```suspend.service``` and ```suspend.timer```.