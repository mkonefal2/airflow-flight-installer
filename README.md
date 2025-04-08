
# Airflow Flight Installer

A bash script for automatically installing and configuring Apache Airflow from the `epwa-flight-etl` project ZIP archive.

## Usage

1. Download the `epwa-flight-etl-main.zip` archive and place it in the same directory as this script.
2. Run the installer:

```bash
chmod +x install_epwa_flight_etl.sh
sudo ./install_epwa_flight_etl.sh
```

## Features

- Creates an `airflow` user
- Sets up a virtual environment
- Installs all required Python dependencies
- Initializes Airflow and creates an admin user
- Configures Airflow as a systemd service
- Automatically starts Airflow webserver and scheduler

After successful installation, access the Airflow web UI at:  
**http://<your_vm_ip>:8080**

